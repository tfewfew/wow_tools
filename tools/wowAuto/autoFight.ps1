# Combat state and configuration are independent; game input uses the host action queue.
. (Join-Path $PSScriptRoot 'autoFight.Engine.ps1')
if (-not ('WowAutoFight.Native' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'autoFight.Native.cs') -ReferencedAssemblies System.Drawing }
if (-not $UiTest) {
    [WowAutoFight.Native]::FrameReader=[WowAutoCapture.Native]::FrameReader
    [WowAutoFight.Native]::CapturePending=[WowAutoCapture.Native]::PendingReader
}

function Set-AutoFightButtonStyle($Button,[bool]$Accent=$false) {
    $Button.UseVisualStyleBackColor=$false
    $Button.BackColor=if ($Accent) { [Drawing.Color]::FromArgb(88,100,112) } else { [Drawing.Color]::FromArgb(86,86,86) }
    $Button.ForeColor=[Drawing.Color]::White
    $Button.FlatStyle='Flat'
    $Button.FlatAppearance.BorderColor=[Drawing.Color]::FromArgb(116,116,116)
}
function Set-AutoFightStatus($Row,[string]$Message) {
    if ($Row.Message -eq $Message) { return }
    $Row.Message=$Message
    $Row.History.Insert(0,('['+[datetime]::Now.ToString('HH:mm:ss')+'] '+$Message))
    while ($Row.History.Count -gt 50) { $Row.History.RemoveAt($Row.History.Count-1) }
    $Row.Status.SetStatusText(($Row.History -join [Environment]::NewLine))
}
function Update-AutoFightControls {
    if ($script:autoFight.Unified) {
        foreach ($parentRow in @($script:rows.Values)) {Set-RowControls $parentRow}
        Update-BatchControls
        return
    }
    $busy=$null -ne $script:autoFight.Scan
    $script:autoFight.Refresh.Enabled=-not $busy -and -not $script:autoFight.Editing
    $script:autoFight.Settings.Enabled=-not $busy -and -not $script:autoFight.Editing
    $runnable=$false; $running=$false
    foreach ($row in @($script:autoFight.Rows.Values)) {
        $row.Start.Enabled=$row.CanStart -and $null -eq $row.Session -and -not $busy -and $script:autoFight.ConfigReady
        $row.Stop.Enabled=$null -ne $row.Session
        if ($row.Start.Enabled) { $runnable=$true }; if ($null -ne $row.Session) { $running=$true }
    }
    $script:autoFight.StartAll.Enabled=$runnable
    $script:autoFight.StopAll.Enabled=$running -or $busy
}
function Release-AutoFightHold {
    if (-not $script:gameActions.Current -or $script:gameActions.Current.Kind -ne 'Safety.Release') {
        $result=[pscustomobject]@{Success=$false}
        Add-GameAction -Id release -Kind Safety.Release -Domain Safety -Due 0 -Data $result -Execute {
            param($event,$now) $event.Data.Success=Release-AutoFightHold
        }
        # Safety releases use the same executor, including synchronous Stop/settings/close paths.
        Invoke-GameActionQueue $script:autoFight.Clock.ElapsedMilliseconds -SafetyOnly
        return $result.Success
    }
    Assert-GameActionContext
    $hold=$script:autoFight.ActiveHold
    try { [WowAutoFight.Native]::ReleaseHold() }
    catch { $script:autoFight.Summary.Text='释放移动键失败，暂停调度并继续重试：'+$_.Exception.Message; return $false }
    $script:autoFight.ActiveHold=$null
    if ($hold -and $hold.Row.Session -eq $hold.Session) { $hold.Session.Due=$script:autoFight.Clock.ElapsedMilliseconds }
    return $true
}
function Invoke-AutoFightHold([long]$Now) {
    $hold=$script:autoFight.ActiveHold
    if (-not $hold) { return }
    $row=$hold.Row
    try {
        if ($row.Session -ne $hold.Session) { [void](Release-AutoFightHold); return }
        if (-not [WowAutoFight.Native]::IsAlive($row.Client)) {
            throw '保持期间进程身份发生变化，已释放移动键。'
        }
        if ($hold.Movement -and -not [WowAutoFight.Native]::Foreground($row.Client)) {
            [void](Release-AutoFightHold)
            Set-AutoFightStatus $row '失去前台，释放移动键并继续后台监测。'
            return
        }
        $packet=[WowAutoFight.Native]::Read($row.Client)
        if ($null -eq $packet) {
            if ([WowAutoFight.Native]::LastReadPending) {[void](Release-AutoFightHold);return}
            throw '保持期间检测关闭或协议不可读，已释放移动键。'
        }
        if ($packet.ClassId -ne $hold.Session.ClassId -or $packet.Flavor -ne $row.Client.Flavor) { throw '职业或客户端发生变化，已释放移动键。' }
        if (($Now -ge $hold.Session.RecoveryReadyAt -and $packet.Recovery -in @('unknown','recover')) -or
            (Test-AutoFightHoldFinished $hold $packet $Now)) { [void](Release-AutoFightHold) }
    }
    catch {
        $message=$_.Exception.Message
        [void](Release-AutoFightHold)
        $row.CanStart=$false
        Stop-AutoFightRow $row $message
    }
}
function Stop-AutoFightRow($Row,[string]$Reason='已停止，战斗任务已取消。') {
    Remove-GameActions -Key $Row.Client.Key -Domain Fight
    if (-not $UiTest) {[WowAutoCapture.Native]::CancelRestore($Row.Client.ProcessId,$Row.Client.StartTicks,$Row.Client.Path)}
    if (($script:autoFight.ActiveHold -and $script:autoFight.ActiveHold.Row -eq $Row) -or
        (-not $script:autoFight.ActiveHold -and [WowAutoFight.Native]::IsHolding)) { [void](Release-AutoFightHold) }
    $Row.Session=$null
    if ($script:autoFight.Pending -and $script:autoFight.Pending.Row -eq $Row) { $script:autoFight.Pending=$null }
    Set-AutoFightStatus $Row $Reason
    Update-AutoFightControls
}
function Complete-AutoFightScan {
    $script:autoFight.Scan=$null
    $script:autoFight.Pending=$null
    $script:autoFight.Summary.Text='检测到 '+$script:autoFight.Rows.Count+' 个进程；有效行需手动开始。'
    Update-AutoFightControls
}
function Stop-AutoFightAll {
    if ($null -eq $script:autoFight) { return }
    [void](Release-AutoFightHold)
    $script:autoFight.Pending=$null
    if ($script:autoFight.Scan) { Complete-AutoFightScan }
    foreach ($row in @($script:autoFight.Rows.Values)) { Stop-AutoFightRow $row }
    Update-AutoFightControls
}
function Test-AutoFightLoginPoint($Row) {
    if ($Row.PSObject.Properties['ParentRow']) {return Test-RowLoginPoint $Row.ParentRow}
    if ($UiTest) {
        if ($Row.Client.PSObject.Properties['LoginPointPresent']) {return [bool]$Row.Client.LoginPointPresent}
        return $true
    }
    return [WowAutoRotation.Native]::LoginPoint($Row.Client.ProcessId,$Row.Client.StartTicks,$Row.Client.Path)
}
function Start-AutoFightRow($Row) {
    if (-not $Row.CanStart -or $script:autoFight.Scan -or -not $script:autoFight.ConfigReady -or $Row.Session) { return }
    if (-not [WowAutoFight.Native]::IsAlive($Row.Client)) {
        $Row.CanStart=$false; Set-AutoFightStatus $Row '进程已退出或身份改变，请刷新。'; Update-AutoFightControls; return
    }
    $now=$script:autoFight.Clock.ElapsedMilliseconds
    $Row.Session=New-AutoFightSession $now $Row.ClassId
    $profile=Get-AutoFightEffectiveProfile $script:autoFight.Profiles["$($Row.Client.Flavor):$($Row.ClassId)"] $script:autoFight.Common
    Set-AutoFightJumpInterval $Row.Session $script:autoFight.Common.JumpIntervalSeconds $now
    Set-AutoFightBuffSchedule $Row.Session $profile $now -AfterLogin
    Set-AutoFightStatus $Row '开始后台监测主色块；需要发键时切换窗口。'
    Update-AutoFightControls
}
function Update-AutoFightRowName($Row) {
    try {$Row.Position=[WowAutoFight.Native]::ReadWindowPosition($Row.Client)} catch {$Row.Position='位置未知'}
    $label=if ($Row.Client.Flavor -eq 'titan') {'时光服'} else {'无限服'}
    $class=if ($Row.ClassId) {$script:autoFightClasses[[string]$Row.ClassId]} else {'等待插件识别'}
    $Row.Name.Text="PID $($Row.Client.ProcessId) · $label · $($Row.Position)`r`n$($Row.Client.Title)`r`n职业：$class"
}
function New-AutoFightRow($Client,[int]$Order) {
    $panel=New-Object System.Windows.Forms.Panel
    $panel.Width=1215; $panel.Height=110; $panel.Margin=New-Object System.Windows.Forms.Padding(0,0,0,8)
    $panel.BackColor=[Drawing.Color]::FromArgb(72,72,72)
    $name=New-Object System.Windows.Forms.Label
    $name.SetBounds(12,12,370,86); $name.AutoEllipsis=$true
    $label=if ($Client.Flavor -eq 'titan') { '时光服' } else { '永恒服 / 无限服' }
    $name.Text="PID $($Client.ProcessId) · $label`r`n$($Client.Title)`r`n职业：等待插件识别"
    $start=New-Object WowAuto.DimButton
    $start.Text='开始'; $start.SetBounds(395,33,90,36); Set-AutoFightButtonStyle $start $true
    $stop=New-Object WowAuto.DimButton
    $stop.Text='停止'; $stop.SetBounds(495,33,90,36); Set-AutoFightButtonStyle $stop
    $status=New-Object WowAuto.DimStatusLog
    $status.SetBounds(600,12,600,86); $status.Anchor='Top, Left, Right'
    $status.Multiline=$true; $status.ReadOnly=$true; $status.ScrollBars='Vertical'; $status.MaxLength=0
    $status.BackColor=[Drawing.Color]::FromArgb(50,50,50); $status.ForeColor=[Drawing.Color]::White
    $row=[pscustomobject]@{Client=$Client; Order=$Order; Panel=$panel; Name=$name; Start=$start; Stop=$stop;
        Status=$status; Position='位置未知'; CanStart=$false; ClassId=0; Session=$null; Message=''; History=(New-Object 'Collections.Generic.List[string]')}
    $start.Tag=$row; $stop.Tag=$row
    $start.Add_Click({param($sender,$eventArgs) Start-AutoFightRow $sender.Tag})
    $stop.Add_Click({param($sender,$eventArgs) Stop-AutoFightRow $sender.Tag})
    $panel.Controls.AddRange([System.Windows.Forms.Control[]]@($name,$start,$stop,$status))
    Update-AutoFightRowName $row
    Set-AutoFightStatus $row '尚未读取 fight_detector，开始按钮锁定。'
    return $row
}
function Begin-AutoFightRefresh {
    if ($script:autoFight.Editing -or $script:autoFight.Scan) { return }
    Stop-AutoFightAll
    foreach ($row in @($script:autoFight.Rows.Values)) { $row.Panel.Dispose() }
    $script:autoFight.List.Controls.Clear()
    $script:autoFight.Rows=@{}
    try { $clients=@([WowAutoFight.Native]::FindClients() | Sort-Object ProcessId) }
    catch { $script:autoFight.Summary.Text='无法枚举进程：'+$_.Exception.Message; return }
    $order=0
    foreach ($client in $clients) {
        $row=New-AutoFightRow $client $order; $order++
        $script:autoFight.Rows[$client.Key]=$row
        $script:autoFight.List.Controls.Add($row.Panel)
    }
    if ($clients.Count -eq 0) { $script:autoFight.Summary.Text='未发现时光服 / 永恒服游戏进程。'; Update-AutoFightControls; return }
    $script:autoFight.Scan=[pscustomobject]@{Order=@($script:autoFight.Rows.Values | Sort-Object Order);
        Index=0}
    $script:autoFight.Summary.Text='正在后台读取各窗口战斗协议，不发送按键。'
    Update-AutoFightControls
}
function New-AutoFightPending($Row,$Session,[bool]$Scanning,[long]$Now) {
    return [pscustomobject]@{Row=$Row; Session=$Session; Scanning=$Scanning; Activated=$false;
        Since=$Now; SampleAt=($Now+200); ReadFailureSince=-1L}
}
function Finish-AutoFightPending([long]$Now) {
    $pending=$script:autoFight.Pending
    $script:autoFight.Pending=$null
    if ($pending.Scanning) { $script:autoFight.Scan.Index++ }
    elseif ($pending.Row.Session -eq $pending.Session) {
        $next=$Now+1000
        $pending.Session.Due=[Math]::Max($pending.Session.Due,$next)
    }
}
function Invoke-AutoFightTick([bool]$AllowInput=$true,[switch]$PlanOnly,[string]$ExpectedAction='') {
    if (-not $PlanOnly -and -not $script:gameActions.Current) {
        Invoke-AutoFightTick -PlanOnly
        if ($UiTest) {
            Submit-HoldAction $script:autoFight.Clock.ElapsedMilliseconds
            Invoke-GameActionQueue $script:autoFight.Clock.ElapsedMilliseconds
        }
        return
    }
    $now=$script:autoFight.Clock.ElapsedMilliseconds
    if ($now -ge $script:autoFight.PositionAt) {
        foreach ($positionRow in @($script:autoFight.Rows.Values)) {Update-AutoFightRowName $positionRow}
        $script:autoFight.PositionAt=$now+1000
    }
    if ($script:autoFight.ActiveHold) {if (-not $PlanOnly) {Invoke-AutoFightHold $now};return}
    if ([WowAutoFight.Native]::IsHolding) {if (-not $PlanOnly) {[void](Release-AutoFightHold)};return}
    if ($script:autoFight.Editing -or $script:autoFight.Tabs.SelectedTab -ne $script:autoFight.Tab) { return }
    if (-not $script:autoFight.Pending) {
        if ($script:autoFight.Scan) {
            if ($script:autoFight.Scan.Index -ge $script:autoFight.Scan.Order.Count) { Complete-AutoFightScan; return }
            $row=$script:autoFight.Scan.Order[$script:autoFight.Scan.Index]
            $script:autoFight.Pending=New-AutoFightPending $row $null $true $now
        }
        else {
            $due=@($script:autoFight.Rows.Values | Where-Object { $null -ne $_.Session -and $_.Session.Due -le $now } |
                Sort-Object @{Expression={$_.Session.Due}},Order | Select-Object -First 1)
            if ($due.Count -eq 0) { return }
            $row=$due[0]
            $script:autoFight.Pending=New-AutoFightPending $row $row.Session $false $now
        }
    }
    $pending=$script:autoFight.Pending; $row=$pending.Row
    if (-not $pending.Scanning -and $row.Session -ne $pending.Session) { $script:autoFight.Pending=$null; return }
    try {
        if (-not [WowAutoFight.Native]::IsAlive($row.Client)) {
            $row.CanStart=$false
            if ($pending.Scanning) { Set-AutoFightStatus $row '进程已退出或身份改变。'; Finish-AutoFightPending $now }
            else { Stop-AutoFightRow $row '进程已退出或身份改变。' }
            Update-AutoFightControls; return
        }
        $packet=[WowAutoFight.Native]::Read($row.Client)
        if ($null -eq $packet) {
            if ([WowAutoFight.Native]::LastReadPending) {
                $pending.ReadFailureSince=-1L
                Set-AutoFightStatus $row ([WowAutoFight.Native]::LastReadError)
                if (-not $pending.Scanning) {Finish-AutoFightPending $now}
                return
            }
            if ($pending.ReadFailureSince -lt 0) {$pending.ReadFailureSince=$now}
            $reason=[WowAutoFight.Native]::LastReadError
            if (-not $reason) {$reason='色块暂时不可读'}
            if ($now-$pending.ReadFailureSince -lt 800) {
                Set-AutoFightStatus $row ('暂停发键，重新读取战斗色块：'+$reason)
                return
            }
            $row.CanStart=$false
            $message='战斗色块连续800ms不可读：'+$reason+'。请保持插件面板可见，恢复后刷新。'
            if ($pending.Scanning) { Set-AutoFightStatus $row $message; Finish-AutoFightPending $now }
            else { Stop-AutoFightRow $row $message }
            Update-AutoFightControls; return
        }
        $pending.ReadFailureSince=-1L
        $combatText=if ($packet.Combat) { '战斗中' } else { '非战斗' }
        if ($pending.Scanning) {
            $row.ClassId=$packet.ClassId; $row.CanStart=$true
            Update-AutoFightRowName $row
            Set-AutoFightStatus $row "已识别职业及主色块 · $combatText · 点击开始。"
            Finish-AutoFightPending $now; Update-AutoFightControls; return
        }
        $session=$pending.Session
        $profile=Get-AutoFightEffectiveProfile $script:autoFight.Profiles["$($row.Client.Flavor):$($session.ClassId)"] $script:autoFight.Common
        $action=Get-AutoFightAction $session $packet $profile $now
        if ($action -eq 'identity-changed') { $row.CanStart=$false; Stop-AutoFightRow $row '角色职业或协议状态改变，请刷新。'; return }
        if ($ExpectedAction -and $action -ne $ExpectedAction) {Finish-AutoFightPending $now;return}
        if ($action -eq 'wait') {
            if ($PlanOnly) {Remove-GameActions -Key $row.Client.Key -Domain Fight}
            $detail=if ($packet.Action -eq 'waiting') { '不下发按键，等待进入攻击距离' }
                elseif ($packet.Busy) { '施法 / 交互中，等待' } else { '等待下一次状态处理' }
            Set-AutoFightStatus $row ($script:autoFightStates[$packet.Action].Label+" · $detail · $combatText")
            Finish-AutoFightPending $now; return
        }
        if ($PlanOnly) {
            Submit-CombatAction $row $session $action $now
            Finish-AutoFightPending $now;return
        }
        Assert-GameActionContext
        # Detection never requires focus. Activate only when an input is actually due.
        if (-not $AllowInput) {Finish-AutoFightPending $now; return}
        if (-not (Test-AutoFightCommandReady $script:autoFight.CommandGate $now)) {Finish-AutoFightPending $now; return}
        if (-not [WowAutoFight.Native]::Foreground($row.Client)) {
            if (-not $pending.Activated) {
                if (-not [WowAutoFight.Native]::Activate($row.Client)) {throw '无法切换到目标窗口。'}
                $pending.Activated=$true; $pending.Since=$now; $pending.SampleAt=$now+200
            }
            elseif ($now-$pending.Since -ge 800) {throw '发键窗口未取得前台。'}
            return
        }
        if ($pending.Activated -and $now -lt $pending.SampleAt) {return}
        # Background monitoring cannot call the foreground-only login-point reader.
        # Check only after activation has settled and before any actual command is sent.
        if (-not (Test-AutoFightLoginPoint $row)) {throw '插件常驻登录白点不存在，已停止战斗任务。'}
        $handler=$script:autoFightStates[$action]
        $keyField=$handler.Key
        $binding=ConvertFrom-AutoFightBinding $profile.$keyField
        # Re-read both cells immediately before input; an auxiliary change can supersede the main action.
        $latest=[WowAutoFight.Native]::Read($row.Client)
        if ($null -eq $latest -or $latest.ClassId -ne $packet.ClassId -or $latest.Action -ne $packet.Action -or
            $latest.Combat -ne $packet.Combat -or $latest.Busy -ne $packet.Busy -or
            $latest.EncounterId -ne $packet.EncounterId -or $latest.Recovery -ne $packet.Recovery) {
            if ($latest) {
                Set-AutoFightStatus $row '颜色已变化，旧按键已取消；按插件新主状态继续。'
                Finish-AutoFightPending $script:autoFight.Clock.ElapsedMilliseconds
            } else {
                Set-AutoFightStatus $row '颜色暂时不可读，旧按键已取消。'
                Finish-AutoFightPending $now
            }
            return
        }
        $movement=$action.StartsWith('move-')
        # All combat windows and states share this gate. Releases always remain immediate.
        if (-not (Test-AutoFightCommandReady $script:autoFight.CommandGate $script:autoFight.Clock.ElapsedMilliseconds)) {
            Set-AutoFightStatus $row ('等待公共最小按键间隔：'+$script:autoFight.CommandGate.IntervalMs+' ms。')
            Finish-AutoFightPending $now; return
        }
        if ($action -eq 'opening') {
            $targetBinding=ConvertFrom-AutoFightBinding $profile.TargetKey
            $sent=[WowAutoFight.Native]::Press($row.Client,[uint16]$targetBinding.Code,$targetBinding.Ctrl,$targetBinding.Shift,$targetBinding.Alt)
            if (-not $sent) {throw '选目标前失去前台。'}
            Complete-AutoFightCommand $script:autoFight.CommandGate $script:autoFight.Clock.ElapsedMilliseconds $true
            # Target selection and opener are one transaction. Recheck the plugin
            # before the second key; a changed main state cancels the opener.
            $afterTarget=[WowAutoFight.Native]::Read($row.Client)
            if (-not $afterTarget -or $afterTarget.Action -ne 'opening' -or $afterTarget.ClassId -ne $packet.ClassId -or
                $afterTarget.Flavor -ne $row.Client.Flavor -or $afterTarget.EncounterId -ne $packet.EncounterId -or
                $afterTarget.Busy -or $afterTarget.Recovery -ne $packet.Recovery -or
                -not [WowAutoFight.Native]::Foreground($row.Client)) {
                Set-AutoFightStatus $row '已选中目标；插件状态变化，取消本次开怪键。'
                Finish-AutoFightPending $script:autoFight.Clock.ElapsedMilliseconds
                return
            }
            $sent=[WowAutoFight.Native]::Press($row.Client,[uint16]$binding.Code,$binding.Ctrl,$binding.Shift,$binding.Alt)
        }
        elseif ($movement) { $sent=[WowAutoFight.Native]::BeginHold($row.Client,[uint16]$binding.Code,$binding.Ctrl,$binding.Shift,$binding.Alt) }
        else { $sent=[WowAutoFight.Native]::Press($row.Client,[uint16]$binding.Code,$binding.Ctrl,$binding.Shift,$binding.Alt) }
        if (-not $sent) { throw '发键前失去前台。' }
        $completed=$script:autoFight.Clock.ElapsedMilliseconds
        Complete-AutoFightCommand $script:autoFight.CommandGate $completed $true
        Complete-AutoFightAction $session $profile $action $completed
        if ($movement -or $action -in @('skin','loot')) {
            $duration=Get-AutoFightHoldDuration $profile $action
            $script:autoFight.ActiveHold=[pscustomobject]@{Row=$row; Session=$session; State=$packet.Action;
                Until=($completed+$duration); Movement=$movement}
            $holdDescription=if ($action -eq 'skin') {"固定保持 $duration ms"} else {"最长保持 $duration ms，状态改变时结束"}
            Set-AutoFightStatus $row ("已执行"+$handler.Label+" $($binding.Text) · $holdDescription。")
        }
        elseif ($action -eq 'opening') {Set-AutoFightStatus $row ("已执行选目标键 $($targetBinding.Text) 和开怪键 $($binding.Text) · $combatText")}
        else { Set-AutoFightStatus $row ("已执行"+$handler.Label+"键 $($binding.Text) · $combatText") }
        Finish-AutoFightPending $completed
    }
    catch {
        if (Test-WindowCapturePending $_) {if (-not $pending.Scanning) {Finish-AutoFightPending $now};return}
        $message=$_.Exception.Message
        $row.CanStart=$false
        if ($pending.Scanning) { Set-AutoFightStatus $row $message; Finish-AutoFightPending $now }
        else { Stop-AutoFightRow $row $message }
        Update-AutoFightControls
    }
}
function Save-AutoFightDraftSelection {
    $editor=$script:autoFight.Editor
    foreach ($page in $editor.Pages.Values) {
        if (-not $page.CurrentKey) {continue}
        $profile=$editor.Draft[$page.CurrentKey]
        foreach ($field in $page.Bindings.Keys) {$profile.$field=$page.Bindings[$field].Text}
        $profile.RecoveryCooldownSeconds=[int]$page.RecoveryCooldown.Value
        $profile.BuffIntervalSeconds=[int]$page.BuffInterval.Value
        $profile.BuffCount=[int]$page.BuffCount.Value
    }
    foreach ($field in $editor.CommonBindings.Keys) {$editor.Common.$field=$editor.CommonBindings[$field].Text}
    foreach ($field in $editor.CommonNumbers.Keys) {$editor.Common.$field=[int]$editor.CommonNumbers[$field].Value}
    $editor.Common.SkinEnabled=$editor.SkinEnabled.Checked
}
function Set-AutoFightEditorAliases {
    $editor=$script:autoFight.Editor
    if (-not $editor.Tabs.SelectedTab) {return}
    $page=$editor.Pages[[string]$editor.Tabs.SelectedTab.Tag]
    $editor.Class=$page.Class
    $editor.Bindings=@{}; $editor.Numbers=@{}
    foreach ($field in $editor.CommonBindings.Keys) {$editor.Bindings[$field]=$editor.CommonBindings[$field]}
    foreach ($field in $page.Bindings.Keys) {$editor.Bindings[$field]=$page.Bindings[$field]}
    foreach ($field in $editor.CommonNumbers.Keys) {$editor.Numbers[$field]=$editor.CommonNumbers[$field]}
    $editor.Numbers.RecoveryCooldownSeconds=$page.RecoveryCooldown
    $editor.Numbers.BuffIntervalSeconds=$page.BuffInterval
    $editor.Numbers.BuffCount=$page.BuffCount
}
function Select-AutoFightDraftProfile([string]$Flavor) {
    $editor=$script:autoFight.Editor
    if ($editor.Loading) {return}
    $page=$editor.Pages[$Flavor]
    if ($page.Class.SelectedIndex -lt 0) {return}
    Save-AutoFightDraftSelection
    $id=$page.ClassIds[$page.Class.SelectedIndex]
    $page.CurrentKey="${Flavor}:$id"
    $profile=$editor.Draft[$page.CurrentKey]
    foreach ($field in $page.Bindings.Keys) {$page.Bindings[$field].Text=$profile.$field}
    $page.RecoveryCooldown.Value=$profile.RecoveryCooldownSeconds
    $page.BuffInterval.Value=$profile.BuffIntervalSeconds
    $page.BuffCount.Value=$profile.BuffCount
    Set-AutoFightEditorAliases
}
function New-AutoFightKeyBox {
    $box=New-Object System.Windows.Forms.TextBox; $box.ReadOnly=$true
    $box.BackColor=[Drawing.Color]::FromArgb(50,50,50); $box.ForeColor=[Drawing.Color]::White
    $box.Add_PreviewKeyDown({param($sender,$eventArgs) $eventArgs.IsInputKey=$true})
    $box.Add_KeyDown({param($sender,$eventArgs)
        $binding=New-AutoFightBinding ([int]$eventArgs.KeyCode) $eventArgs.Control $eventArgs.Shift $eventArgs.Alt
        if ($null -ne $binding) {$sender.Text=$binding.Text}
        $eventArgs.SuppressKeyPress=$true; $eventArgs.Handled=$true
    })
    return $box
}
function New-AutoFightSettingsDialog([switch]$Embedded) {
    $dialog=New-Object WowAuto.DimForm
    $dialog.AutoScaleMode='Dpi'
    $dialog.Text='autoFight · 通用设置 / 职业攻击与恢复'; $dialog.StartPosition='CenterParent'
    $area=[System.Windows.Forms.Screen]::FromControl($script:autoFight.Owner).WorkingArea
    $dialog.ClientSize=New-Object Drawing.Size([Math]::Min(860,$area.Width-80),[Math]::Min(770,$area.Height-100))
    $dialog.MinimumSize=New-Object Drawing.Size(600,450)
    $dialog.Font=$script:autoFight.Owner.Font; $dialog.BackColor=[Drawing.Color]::FromArgb(58,58,58)
    $dialog.ForeColor=[Drawing.Color]::White
    $body=New-Object System.Windows.Forms.Panel
    $body.Dock='Fill'; $body.AutoScroll=$true; $body.AutoScrollMinSize=New-Object Drawing.Size(840,780)
    $footer=New-Object System.Windows.Forms.Panel
    $footer.Dock='Bottom'; $footer.Height=100
    $dialog.Controls.Add($body); $dialog.Controls.Add($footer)
    $editor=[pscustomobject]@{Draft=(Copy-AutoFightProfiles $script:autoFight.Profiles); Common=(Copy-AutoFightCommon $script:autoFight.Common); Loading=$true;
        Pages=@{};Tabs=$null;Class=$null;CommonBindings=@{};CommonNumbers=@{};Bindings=@{};Numbers=@{};
        SkinEnabled=$null;CommandInterval=$null;Save=$null;Cancel=$null;Error=$null;Embedded=[bool]$Embedded;Saved=$false}
    $script:autoFight.Editor=$editor
    $profileTabs=New-Object WowAuto.DimTabControl
    $profileTabs.HeaderBackground=[Drawing.Color]::Black
    $profileTabs.HeaderSurface=[Drawing.Color]::FromArgb(54,78,98)
    $profileTabs.ForeColor=[Drawing.Color]::White
    $profileTabs.SizeMode='Fixed'; $profileTabs.ItemSize=New-Object Drawing.Size(140,32)
    $profileTabs.SetBounds(16,12,808,260); $editor.Tabs=$profileTabs; $body.Controls.Add($profileTabs)
    foreach ($flavor in @('titan','forerver')) {
        $tab=New-Object System.Windows.Forms.TabPage
        $tab.Text=if ($flavor -eq 'titan') {'时光服'} else {'无限服'}
        $tab.Tag=$flavor; $tab.BackColor=[Drawing.Color]::FromArgb(58,58,58); $tab.ForeColor=[Drawing.Color]::White
        $tab.AutoScroll=$true; $tab.AutoScrollMinSize=New-Object Drawing.Size(790,216)
        $profileTabs.TabPages.Add($tab)
        $label=New-Object System.Windows.Forms.Label; $label.Text='职业'; $label.SetBounds(8,10,216,28); $tab.Controls.Add($label)
        $combo=New-Object System.Windows.Forms.ComboBox
        $combo.DropDownStyle='DropDownList'; $combo.FlatStyle='Flat'
        $combo.DrawMode='OwnerDrawFixed'; $combo.ItemHeight=26
        $combo.BackColor=[Drawing.Color]::FromArgb(50,50,50); $combo.ForeColor=[Drawing.Color]::White
        $combo.Add_DrawItem({param($sender,$eventArgs)
            if ($eventArgs.Index -lt 0) {return}
            $brush=New-Object Drawing.SolidBrush($sender.BackColor)
            try {$eventArgs.Graphics.FillRectangle($brush,$eventArgs.Bounds)} finally {$brush.Dispose()}
            [System.Windows.Forms.TextRenderer]::DrawText($eventArgs.Graphics,[string]$sender.Items[$eventArgs.Index],
                $sender.Font,$eventArgs.Bounds,[Drawing.Color]::White,
                ([System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter))
            $eventArgs.DrawFocusRectangle()
        })
        $combo.SetBounds(232,6,168,32); $combo.Tag=$flavor
        $ids=Get-AutoFightClassIds $flavor
        $combo.Items.AddRange([object[]]@($ids | ForEach-Object {$script:autoFightClasses[[string]$_]}))
        $combo.Add_SelectedIndexChanged({param($sender,$eventArgs) Select-AutoFightDraftProfile $sender.Tag})
        $tab.Controls.Add($combo)
        $page=[pscustomobject]@{Tab=$tab;Class=$combo;ClassIds=$ids;CurrentKey='';Bindings=@{};RecoveryCooldown=$null;BuffInterval=$null;BuffCount=$null}
        $editor.Pages[$flavor]=$page
        $labels=@('开怪战斗键','正常战斗键','恢复键','补 Buff 快捷键')
        for ($i=0;$i -lt $labels.Count;$i++) {
            $field=$script:autoFightKeyFields[$i]; $x=8+($i%2)*400; $y=44+[Math]::Floor($i/2)*42
            $label=New-Object System.Windows.Forms.Label; $label.Text=$labels[$i]; $label.SetBounds($x,($y+4),212,32)
            $box=New-AutoFightKeyBox; $box.SetBounds(($x+212),$y,168,32)
            $page.Bindings[$field]=$box; $tab.Controls.Add($label); $tab.Controls.Add($box)
        }
        $recoveryLabel=New-Object System.Windows.Forms.Label
        $recoveryLabel.Text='恢复键冷却 (秒)'; $recoveryLabel.SetBounds(408,132,212,32); $tab.Controls.Add($recoveryLabel)
        $recoveryNumber=New-Object System.Windows.Forms.NumericUpDown
        $recoveryNumber.Minimum=1; $recoveryNumber.Maximum=3600; $recoveryNumber.Increment=1
        $recoveryNumber.BackColor=[Drawing.Color]::FromArgb(50,50,50); $recoveryNumber.ForeColor=[Drawing.Color]::White
        $recoveryNumber.SetBounds(620,128,168,32); $tab.Controls.Add($recoveryNumber); $page.RecoveryCooldown=$recoveryNumber
        foreach ($entry in @(@('BuffInterval','补 Buff 间隔 (秒，0关闭)',0,86400,8),@('BuffCount','每轮补 Buff 次数',1,20,408))) {
            $buffLabel=New-Object System.Windows.Forms.Label;$buffLabel.Text=$entry[1];$buffLabel.SetBounds([int]$entry[4],178,212,32);$tab.Controls.Add($buffLabel)
            $buffNumber=New-Object System.Windows.Forms.NumericUpDown
            $buffNumber.Minimum=[int]$entry[2];$buffNumber.Maximum=[int]$entry[3];$buffNumber.Increment=1
            $buffNumber.BackColor=[Drawing.Color]::FromArgb(50,50,50);$buffNumber.ForeColor=[Drawing.Color]::White
            $buffNumber.SetBounds(([int]$entry[4]+212),174,168,32);$tab.Controls.Add($buffNumber)
            $page.($entry[0])=$buffNumber
        }
        $combo.SelectedIndex=0
    }
    $profileTabs.Add_SelectedIndexChanged({if (-not $script:autoFight.Editor.Loading) {Set-AutoFightEditorAliases}})
    $heading=New-Object System.Windows.Forms.Label; $heading.Text='通用设置：全部服务器与职业'; $heading.SetBounds(16,278,810,26); $body.Controls.Add($heading)
    $keyLabels=@('向前移动键','向后移动键','向左移动键','向右移动键','拾取 / 剥皮交互键','选中目标键')
    for ($j=0;$j -lt $script:autoFightCommonKeyFields.Count;$j++) {
        $field=$script:autoFightCommonKeyFields[$j]
        $x=16+($j%2)*420; $y=306+[Math]::Floor($j/2)*44
        $label=New-Object System.Windows.Forms.Label; $label.Text=$keyLabels[$j]; $label.SetBounds($x,($y+4),220,32)
        $box=New-AutoFightKeyBox; $box.SetBounds(($x+224),$y,168,32)
        $box.Text=$editor.Common.$field
        $editor.CommonBindings[$field]=$box; $body.Controls.Add($label); $body.Controls.Add($box)
    }
    $numbers=@(@('MovementHoldMs','移动按住时长 (ms)',100,2000),
        @('InteractionHoldMs','拾取前台保持 (ms)',1000,60000))
    for ($i=0;$i -lt $numbers.Count;$i++) {
        $entry=$numbers[$i]; $x=if ($i -eq 1) {436} else {16}; $y=442
        $label=New-Object System.Windows.Forms.Label; $label.Text=$entry[1]; $label.SetBounds($x,($y+4),220,32)
        $number=New-Object System.Windows.Forms.NumericUpDown
        $number.Minimum=$entry[2]; $number.Maximum=$entry[3]; $number.Increment=100
        $number.BackColor=[Drawing.Color]::FromArgb(50,50,50); $number.ForeColor=[Drawing.Color]::White
        $number.SetBounds(($x+224),$y,168,32)
        $number.Value=$editor.Common.($entry[0]); $editor.CommonNumbers[$entry[0]]=$number; $body.Controls.Add($label); $body.Controls.Add($number)
    }
    $editor.SkinEnabled=New-Object WowAuto.DimCheckBox
    $editor.SkinEnabled.Text='启用自动拾取 / 剥皮交互'; $editor.SkinEnabled.SetBounds(16,488,600,32)
    $editor.SkinEnabled.Checked=$editor.Common.SkinEnabled
    $body.Controls.Add($editor.SkinEnabled)
    $commonLabel=New-Object System.Windows.Forms.Label
    $commonLabel.Text='公共最小按键间隔 (ms)'; $commonLabel.SetBounds(16,532,340,32); $body.Controls.Add($commonLabel)
    $editor.CommandInterval=New-Object System.Windows.Forms.NumericUpDown
    $editor.CommandInterval.Minimum=100; $editor.CommandInterval.Maximum=60000; $editor.CommandInterval.Increment=100
    $editor.CommandInterval.Value=$script:autoFight.CommandGate.IntervalMs
    $editor.CommandInterval.BackColor=[Drawing.Color]::FromArgb(50,50,50); $editor.CommandInterval.ForeColor=[Drawing.Color]::White
    $editor.CommandInterval.SetBounds(360,528,168,32); $body.Controls.Add($editor.CommandInterval)
    $jumpLabel=New-Object System.Windows.Forms.Label
    $jumpLabel.Text='自动跳跃间隔 (秒，0 关闭)'; $jumpLabel.SetBounds(16,574,340,32); $body.Controls.Add($jumpLabel)
    $jump=New-Object System.Windows.Forms.NumericUpDown
    $jump.Minimum=0; $jump.Maximum=3600; $jump.Increment=1; $jump.Value=$editor.Common.JumpIntervalSeconds
    $jump.BackColor=[Drawing.Color]::FromArgb(50,50,50); $jump.ForeColor=[Drawing.Color]::White
    $jump.SetBounds(360,570,168,32); $body.Controls.Add($jump); $editor.CommonNumbers.JumpIntervalSeconds=$jump
    $hint=New-Object System.Windows.Forms.Label
    $hint.Text="选目标键默认 Tab；须与游戏内选目标按键一致。`r`n每个战斗进程每秒采样色块一次，每次采样最多执行一个逻辑动作。`r`n恢复键成功发送后按职业冷却；冷却期间忽略副色块恢复提示，主状态继续运行。`r`n补 Buff 间隔为 0 时关闭；进入游戏和到期后各执行一轮，轮内成功按键相隔至少 1 秒。`r`n检测 / 攻击距离在插件面板设置；等待接近期间不发攻击键。"
    $hint.SetBounds(16,616,812,144); $body.Controls.Add($hint)
    $errorLabel=New-Object System.Windows.Forms.Label
    $errorLabel.SetBounds(16,4,($footer.ClientSize.Width-32),30); $errorLabel.Anchor='Top, Left, Right'; $errorLabel.AutoEllipsis=$true
    $footer.Controls.Add($errorLabel)
    $save=New-Object WowAuto.DimButton
    $save.Text='保存'; $save.SetBounds(($footer.ClientSize.Width-236),50,100,32); $save.Anchor='Top, Right'; Set-AutoFightButtonStyle $save $true
    $cancel=New-Object WowAuto.DimButton
    $cancel.Text='取消'; $cancel.SetBounds(($footer.ClientSize.Width-116),50,100,32); $cancel.Anchor='Top, Right'; Set-AutoFightButtonStyle $cancel
    $cancel.Add_Click({param($sender,$eventArgs) $sender.FindForm().Close()})
    $save.Tag=$errorLabel
    $save.Add_Click({param($sender,$eventArgs)
        try {
            Save-AutoFightDraftSelection
            $interval=[int]$script:autoFight.Editor.CommandInterval.Value
            $valid=Save-AutoFightProfiles $script:autoFight.ConfigPath $script:autoFight.Editor.Draft $interval $script:autoFight.Editor.Common
            $script:autoFight.Profiles=$valid; $script:autoFight.Common=ConvertTo-AutoFightCommon $script:autoFight.Editor.Common; $script:autoFight.ConfigReady=$true
            $script:autoFight.CommandGate.IntervalMs=$interval
            foreach ($row in @($script:autoFight.Rows.Values)) {
                if ($row.Session) {Set-AutoFightJumpInterval $row.Session $script:autoFight.Common.JumpIntervalSeconds $script:autoFight.Clock.ElapsedMilliseconds}
            }
            $script:autoFight.Summary.Text='状态按键已保存；下次执行使用新配置，已有截止时间保留。'
            $script:autoFight.Editor.Saved=$true
            if (-not $script:autoFight.Editor.Embedded) {$sender.FindForm().Close()}
            else {$sender.Tag.Text='战斗设置已保存。'}
        }
        catch { $sender.Tag.Text=$_.Exception.Message }
    })
    $footer.Controls.AddRange([System.Windows.Forms.Control[]]@($save,$cancel))
    $editor.Save=$save; $editor.Cancel=$cancel; $editor.Error=$errorLabel; $dialog.Tag=$editor
    $profileTabs.SelectedIndex=0
    $editor.Loading=$false
    Select-AutoFightDraftProfile 'titan'
    Select-AutoFightDraftProfile 'forerver'
    Set-AutoFightEditorAliases
    return $dialog
}
function Show-AutoFightSettings {
    if ($script:autoFight.Editing -or $script:autoFight.Scan) { return }
    if (-not (Release-AutoFightHold)) { return }
    $script:autoFight.Pending=$null
    $script:autoFight.Editing=$true
    $dialog=New-AutoFightSettingsDialog
    try { [void]$dialog.ShowDialog($script:autoFight.Owner) }
    finally { $script:autoFight.Editor=$null; $script:autoFight.Editing=$false; $dialog.Dispose(); Update-AutoFightControls }
}
function Initialize-AutoFightTab($Tabs,$Owner,[switch]$Unified) {
    $tab=New-Object System.Windows.Forms.TabPage
    $tab.Text='autoFight'; $tab.BackColor=[Drawing.Color]::FromArgb(58,58,58); $tab.ForeColor=[Drawing.Color]::White
    $toolbar=New-Object System.Windows.Forms.FlowLayoutPanel
    $toolbar.Dock='Top'; $toolbar.Height=60; $toolbar.AutoScroll=$true
    $toolbar.Padding=New-Object System.Windows.Forms.Padding(8); $toolbar.BackColor=[Drawing.Color]::FromArgb(72,72,72)
    $buttons=@{}
    foreach ($entry in @(@('Refresh','刷新进程'),@('StartAll','全部开始'),@('StopAll','全部停止'),@('Settings','状态 / 职业设置'))) {
        $button=New-Object WowAuto.DimButton; $button.Text=$entry[1]; $button.Width=if ($entry[0] -eq 'Settings') { 160 } else { 120 }; $button.Height=36
        Set-AutoFightButtonStyle $button ($entry[0] -eq 'StartAll')
        $buttons[$entry[0]]=$button; $toolbar.Controls.Add($button)
    }
    $summary=New-Object System.Windows.Forms.Label
    $summary.Width=650; $summary.Height=40; $summary.Padding=New-Object System.Windows.Forms.Padding(8,7,0,0)
    $summary.Text='先启动游戏 fight_detector，再刷新进程并点击开始。'; $toolbar.Controls.Add($summary)
    $hint=New-Object System.Windows.Forms.Label
    $hint.Dock='Top'; $hint.Height=58; $hint.Padding=New-Object System.Windows.Forms.Padding(12,8,12,0)
    $hint.Text="自动识别服务器和职业；仅向前台窗口发送已配置快捷键。`r`n切换标签会停止上一页任务。插件关闭、死亡、职业改变或协议失效时停止该行。"
    $list=New-Object System.Windows.Forms.FlowLayoutPanel
    $list.Dock='Fill'; $list.FlowDirection='TopDown'; $list.WrapContents=$false; $list.AutoScroll=$true
    $list.Padding=New-Object System.Windows.Forms.Padding(12)
    $tab.Controls.Add($list); $tab.Controls.Add($hint); $tab.Controls.Add($toolbar)
    $script:autoFight=[pscustomobject]@{Rows=@{}; PositionAt=0L; Pending=$null; Scan=$null; ActiveHold=$null; Editing=$false; Editor=$null;
        ConfigPath=(Join-Path $PSScriptRoot 'autoFight.config.json'); Profiles=(New-AutoFightProfiles); Common=(New-AutoFightCommon); ConfigReady=$true;
        Tab=$tab; Tabs=$Tabs; Owner=$Owner; List=$list; Refresh=$buttons.Refresh; StartAll=$buttons.StartAll;
        StopAll=$buttons.StopAll; Settings=$buttons.Settings; Summary=$summary;
        Unified=[bool]$Unified; DetachedTab=$tab;
        CommandGate=(New-AutoFightCommandGate); Clock=[Diagnostics.Stopwatch]::StartNew(); Timer=(New-Object System.Windows.Forms.Timer)}
    try {
        $config=Read-AutoFightConfiguration $script:autoFight.ConfigPath
        $script:autoFight.Profiles=$config.Profiles; $script:autoFight.Common=$config.Common; $script:autoFight.CommandGate.IntervalMs=$config.CommandIntervalMs
    }
    catch { $script:autoFight.ConfigReady=$false; $summary.Text='配置读取失败，请在职业设置中修正并保存：'+$_.Exception.Message }
    $buttons.Refresh.Add_Click({ Begin-AutoFightRefresh })
    $buttons.Settings.Add_Click({ Show-AutoFightSettings })
    $buttons.StartAll.Add_Click({ foreach ($row in @($script:autoFight.Rows.Values | Sort-Object Order)) { Start-AutoFightRow $row } })
    $buttons.StopAll.Add_Click({ Stop-AutoFightAll })
    $script:autoFight.Timer.Interval=50
    $script:autoFight.Timer.Add_Tick({
        Submit-HoldAction $script:autoFight.Clock.ElapsedMilliseconds
        Invoke-AutoFightTick -PlanOnly
        Submit-WindowCaptureActions $script:autoFight.Clock.ElapsedMilliseconds
        Invoke-GameActionQueue $script:autoFight.Clock.ElapsedMilliseconds
    })
    if ($Unified) {$script:autoFight.Tab=$Tabs.TabPages[0];$script:autoFight.Clock=$script:schedulerClock}
    else {$Tabs.TabPages.Add($tab); $script:autoFight.Timer.Start()}
    Update-AutoFightControls
}
function Close-AutoFightTab {
    if ($null -eq $script:autoFight) { return }
    $script:autoFight.Timer.Stop()
    Stop-AutoFightAll
    $script:autoFight.Timer.Dispose()
    if ($script:autoFight.Unified) {$script:autoFight.DetachedTab.Dispose()}
    $script:autoFight=$null
}
