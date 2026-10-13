# Loaded only by the host UI. All state, configuration, timers and native adapters are independent.
. (Join-Path $PSScriptRoot 'autoFight.Engine.ps1')
if (-not ('WowAutoFight.Native' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'autoFight.Native.cs') }

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
        foreach ($button in @($row.MoveButtons)) {$button.Enabled=$null -ne $row.Session -and -not $busy -and -not $script:autoFight.Editing}
        if ($row.Start.Enabled) { $runnable=$true }; if ($null -ne $row.Session) { $running=$true }
    }
    $script:autoFight.StartAll.Enabled=$runnable
    $script:autoFight.StopAll.Enabled=$running -or $busy
}
function Release-AutoFightHold {
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
        if (-not (Test-AutoFightLoginPoint $row)) {throw '插件常驻登录白点不存在，已停止战斗任务。'}
        $packet=[WowAutoFight.Native]::Read($row.Client)
        if ($null -eq $packet) { throw '保持期间检测关闭或协议不可读，已释放移动键。' }
        if ($packet.ClassId -ne $hold.Session.ClassId) { throw '职业发生变化，已释放移动键。' }
        if ($Now -ge $hold.Until -or $packet.Action -ne $hold.State -or $packet.Recovery -ne 'none' -or
            ($hold.Movement -and $packet.Busy)) { [void](Release-AutoFightHold) }
    }
    catch {
        $message=$_.Exception.Message
        [void](Release-AutoFightHold)
        $row.CanStart=$false
        Stop-AutoFightRow $row $message
    }
}
function Stop-AutoFightRow($Row,[string]$Reason='已停止，战斗任务已取消。') {
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
    if ($UiTest) {return $true}
    return [WowAutoRotation.Native]::LoginPoint($Row.Client.ProcessId,$Row.Client.StartTicks,$Row.Client.Path)
}
function Start-AutoFightRow($Row) {
    if (-not $Row.CanStart -or $script:autoFight.Scan -or -not $script:autoFight.ConfigReady -or $Row.Session) { return }
    if (-not [WowAutoFight.Native]::IsAlive($Row.Client)) {
        $Row.CanStart=$false; Set-AutoFightStatus $Row '进程已退出或身份改变，请刷新。'; Update-AutoFightControls; return
    }
    $Row.Session=New-AutoFightSession $script:autoFight.Clock.ElapsedMilliseconds $Row.ClassId
    Set-AutoFightJumpInterval $Row.Session $script:autoFight.Common.JumpIntervalSeconds $script:autoFight.Clock.ElapsedMilliseconds
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
    $panel.Width=1215; $panel.Height=148; $panel.Margin=New-Object System.Windows.Forms.Padding(0,0,0,8)
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
    $row | Add-Member NoteProperty MoveButtons @()
    foreach ($entry in @(@('forward','前'),@('backward','后'),@('left','左'),@('right','右'))) {
        $button=New-Object WowAuto.DimButton
        $button.Text=$entry[1]; $button.SetBounds((395+$row.MoveButtons.Count*48),106,44,28)
        Set-AutoFightButtonStyle $button
        $button.Tag=[pscustomobject]@{Row=$row;Direction=$entry[0]}
        $button.Add_Click({param($sender,$eventArgs)
            $r=$sender.Tag.Row
            if (-not $r.Session -or $script:autoFight.Editing -or $script:autoFight.Scan -or $script:autoFight.ActiveHold) {return}
            $r.Session.MovementRequest=$sender.Tag.Direction
            $r.Session.Due=$script:autoFight.Clock.ElapsedMilliseconds
            if ($r.Session.State.StartsWith('move-')) {
                $r.Session.EntryPending=$true; $r.Session.NextActionAt=$r.Session.Due
            }
            Set-AutoFightStatus $r '已请求一次移动；仅在待机、无需恢复及非忙碌时执行。'
        })
        $row.MoveButtons+=,$button; $panel.Controls.Add($button)
    }
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
        $pending.Session.Due=[Math]::Max($pending.Session.Due,($Now+250))
    }
}
function Invoke-AutoFightTick([bool]$AllowInput=$true) {
    $now=$script:autoFight.Clock.ElapsedMilliseconds
    if ($now -ge $script:autoFight.PositionAt) {
        foreach ($positionRow in @($script:autoFight.Rows.Values)) {Update-AutoFightRowName $positionRow}
        $script:autoFight.PositionAt=$now+1000
    }
    if ($script:autoFight.ActiveHold) { Invoke-AutoFightHold $now; return }
    if ([WowAutoFight.Native]::IsHolding) { [void](Release-AutoFightHold); return }
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
        if (-not (Test-AutoFightLoginPoint $row)) {throw '插件常驻登录白点不存在，已停止战斗任务。'}
        $packet=[WowAutoFight.Native]::Read($row.Client)
        if ($null -eq $packet) {
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
        $previous=$session.State
        if (Update-AutoFightState $session $packet $now) {
            $before=if ($previous) { $script:autoFightStates[$previous].Label } else { '初始' }
            Set-AutoFightStatus $row ("状态切换：$before → "+$script:autoFightStates[$session.State].Label)
        }
        $action=Get-AutoFightAction $session $packet $profile $now
        if ($action -eq 'identity-changed') { $row.CanStart=$false; Stop-AutoFightRow $row '角色职业或协议状态改变，请刷新。'; return }
        if ($action -eq 'wait') {
            $detail=if ($session.State -eq 'waiting') { '不下发按键，等待进入攻击距离' }
                elseif ($packet.Busy) { '施法 / 交互中，等待' } else { '等待下一次状态处理' }
            Set-AutoFightStatus $row ($script:autoFightStates[$session.State].Label+" · $detail · $combatText")
            Finish-AutoFightPending $now; return
        }
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
        $handler=$script:autoFightStates[$action]
        $keyField=$handler.Key
        $binding=ConvertFrom-AutoFightBinding $profile.$keyField
        # Re-read the main color immediately before input.
        $latest=[WowAutoFight.Native]::Read($row.Client)
        if ($null -eq $latest -or $latest.ClassId -ne $packet.ClassId -or $latest.Action -ne $packet.Action -or
            $latest.Recovery -ne $packet.Recovery -or $latest.Combat -ne $packet.Combat -or $latest.Busy -ne $packet.Busy -or
            $latest.EncounterId -ne $packet.EncounterId) {
            Set-AutoFightStatus $row '状态变化，等待重新探测。'; Finish-AutoFightPending $now; return
        }
        $movement=$action.StartsWith('move-')
        # All combat windows and states share this gate. Releases always remain immediate.
        if (-not (Test-AutoFightCommandReady $script:autoFight.CommandGate $script:autoFight.Clock.ElapsedMilliseconds)) {
            Set-AutoFightStatus $row ('等待公共最小按键间隔：'+$script:autoFight.CommandGate.IntervalMs+' ms。')
            Finish-AutoFightPending $now; return
        }
        if ($movement) { $sent=[WowAutoFight.Native]::BeginHold($row.Client,[uint16]$binding.Code,$binding.Ctrl,$binding.Shift,$binding.Alt) }
        else { $sent=[WowAutoFight.Native]::Press($row.Client,[uint16]$binding.Code,$binding.Ctrl,$binding.Shift,$binding.Alt) }
        if (-not $sent) { throw '发键前失去前台。' }
        $completed=$script:autoFight.Clock.ElapsedMilliseconds
        Complete-AutoFightCommand $script:autoFight.CommandGate $completed $true
        Complete-AutoFightAction $session $profile $action $completed
        if ($movement -or $action -in @('skin','loot')) {
            $duration=if ($movement) { $profile.MovementHoldMs } else { $profile.InteractionHoldMs }
            $script:autoFight.ActiveHold=[pscustomobject]@{Row=$row; Session=$session; State=$packet.Action;
                Until=($completed+$duration); Movement=$movement}
            Set-AutoFightStatus $row ("已执行"+$handler.Label+" $($binding.Text) · 最长保持 $duration ms，状态改变时结束。")
        }
        else { Set-AutoFightStatus $row ("已执行"+$handler.Label+"键 $($binding.Text) · $combatText") }
        Finish-AutoFightPending $completed
    }
    catch {
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
        $profile.CombatIntervalMs=[int]$page.CombatInterval.Value
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
    $editor.Numbers.CombatIntervalMs=$page.CombatInterval
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
    $page.CombatInterval.Value=$profile.CombatIntervalMs
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
    $body.Dock='Fill'; $body.AutoScroll=$true; $body.AutoScrollMinSize=New-Object Drawing.Size(840,716)
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
    $profileTabs.SetBounds(16,12,808,214); $editor.Tabs=$profileTabs; $body.Controls.Add($profileTabs)
    foreach ($flavor in @('titan','forerver')) {
        $tab=New-Object System.Windows.Forms.TabPage
        $tab.Text=if ($flavor -eq 'titan') {'时光服'} else {'无限服'}
        $tab.Tag=$flavor; $tab.BackColor=[Drawing.Color]::FromArgb(58,58,58); $tab.ForeColor=[Drawing.Color]::White
        $tab.AutoScroll=$true; $tab.AutoScrollMinSize=New-Object Drawing.Size(790,160)
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
        $page=[pscustomobject]@{Tab=$tab;Class=$combo;ClassIds=$ids;CurrentKey='';Bindings=@{};CombatInterval=$null}
        $editor.Pages[$flavor]=$page
        $labels=@('开怪战斗键','正常战斗键','非战斗恢复键','战斗紧急恢复键')
        for ($i=0;$i -lt 4;$i++) {
            $field=$script:autoFightKeyFields[$i]; $x=8+($i%2)*400; $y=44+[Math]::Floor($i/2)*42
            $label=New-Object System.Windows.Forms.Label; $label.Text=$labels[$i]; $label.SetBounds($x,($y+4),212,32)
            $box=New-AutoFightKeyBox; $box.SetBounds(($x+212),$y,168,32)
            $page.Bindings[$field]=$box; $tab.Controls.Add($label); $tab.Controls.Add($box)
        }
        $label=New-Object System.Windows.Forms.Label; $label.Text='正常战斗间隔 (ms)'; $label.SetBounds(8,132,216,32); $tab.Controls.Add($label)
        $number=New-Object System.Windows.Forms.NumericUpDown
        $number.Minimum=100; $number.Maximum=10000; $number.Increment=100
        $number.BackColor=[Drawing.Color]::FromArgb(50,50,50); $number.ForeColor=[Drawing.Color]::White
        $number.SetBounds(232,128,168,32); $tab.Controls.Add($number); $page.CombatInterval=$number
        $combo.SelectedIndex=0
    }
    $profileTabs.Add_SelectedIndexChanged({if (-not $script:autoFight.Editor.Loading) {Set-AutoFightEditorAliases}})
    $heading=New-Object System.Windows.Forms.Label; $heading.Text='通用设置：全部服务器与职业'; $heading.SetBounds(16,230,810,26); $body.Controls.Add($heading)
    $keyLabels=@('开怪战斗键','正常战斗键','非战斗恢复键','战斗紧急恢复键','向前移动键','向后移动键','向左移动键','向右移动键','拾取 / 剥皮交互键','选中 / 锁定目标键')
    $allKeyFields=$script:autoFightKeyFields+$script:autoFightCommonKeyFields
    for ($i=4;$i -lt $allKeyFields.Count;$i++) {
        $field=$allKeyFields[$i]
        $j=if ($i -lt 4) {$i} else {$i-4}
        $x=16+($j%2)*420; $y=if ($i -lt 4) {82+[Math]::Floor($j/2)*44} else {258+[Math]::Floor($j/2)*44}
        $label=New-Object System.Windows.Forms.Label; $label.Text=$keyLabels[$i]; $label.SetBounds($x,($y+4),220,32)
        $box=New-AutoFightKeyBox; $box.SetBounds(($x+224),$y,168,32)
        $box.Text=$editor.Common.$field
        $editor.CommonBindings[$field]=$box; $body.Controls.Add($label); $body.Controls.Add($box)
    }
    $numbers=@(@('CombatIntervalMs','正常战斗间隔 (ms)',100,10000),
        @('MovementHoldMs','移动按住时长 (ms)',100,2000),
        @('InteractionHoldMs','交互前台保持 (ms)',1000,60000))
    for ($i=1;$i -lt $numbers.Count;$i++) {
        $entry=$numbers[$i]; $x=if ($i -eq 2) {436} else {16}; $y=if ($i -eq 0) {174} else {394}
        $label=New-Object System.Windows.Forms.Label; $label.Text=$entry[1]; $label.SetBounds($x,($y+4),220,32)
        $number=New-Object System.Windows.Forms.NumericUpDown
        $number.Minimum=$entry[2]; $number.Maximum=$entry[3]; $number.Increment=100
        $number.BackColor=[Drawing.Color]::FromArgb(50,50,50); $number.ForeColor=[Drawing.Color]::White
        $number.SetBounds(($x+224),$y,168,32)
        $number.Value=$editor.Common.($entry[0]); $editor.CommonNumbers[$entry[0]]=$number; $body.Controls.Add($label); $body.Controls.Add($number)
    }
    $editor.SkinEnabled=New-Object WowAuto.DimCheckBox
    $editor.SkinEnabled.Text='启用自动拾取 / 剥皮交互'; $editor.SkinEnabled.SetBounds(16,440,600,32)
    $editor.SkinEnabled.Checked=$editor.Common.SkinEnabled
    $body.Controls.Add($editor.SkinEnabled)
    $commonLabel=New-Object System.Windows.Forms.Label
    $commonLabel.Text='公共最小按键间隔 (ms)'; $commonLabel.SetBounds(16,484,340,32); $body.Controls.Add($commonLabel)
    $editor.CommandInterval=New-Object System.Windows.Forms.NumericUpDown
    $editor.CommandInterval.Minimum=100; $editor.CommandInterval.Maximum=60000; $editor.CommandInterval.Increment=100
    $editor.CommandInterval.Value=$script:autoFight.CommandGate.IntervalMs
    $editor.CommandInterval.BackColor=[Drawing.Color]::FromArgb(50,50,50); $editor.CommandInterval.ForeColor=[Drawing.Color]::White
    $editor.CommandInterval.SetBounds(360,480,168,32); $body.Controls.Add($editor.CommandInterval)
    $jumpLabel=New-Object System.Windows.Forms.Label
    $jumpLabel.Text='自动跳跃间隔 (秒，0 关闭)'; $jumpLabel.SetBounds(16,526,340,32); $body.Controls.Add($jumpLabel)
    $jump=New-Object System.Windows.Forms.NumericUpDown
    $jump.Minimum=0; $jump.Maximum=3600; $jump.Increment=1; $jump.Value=$editor.Common.JumpIntervalSeconds
    $jump.BackColor=[Drawing.Color]::FromArgb(50,50,50); $jump.ForeColor=[Drawing.Color]::White
    $jump.SetBounds(360,522,168,32); $body.Controls.Add($jump); $editor.CommonNumbers.JumpIntervalSeconds=$jump
    $hint=New-Object System.Windows.Forms.Label
    $hint.Text="选目标键默认 Tab；须与游戏插件面板的全局选目标键一致。`r`n确认后每只怪开怪一次，战斗通过焦点锁定；检测支持后台窗口。`r`n检测 / 攻击距离在插件面板设置；等待接近期间不发攻击键。`r`n公共间隔约束所有战斗指令；普通 / 紧急恢复每次进入只执行一次。`r`n移动由方向按钮请求；跳跃按各进程计时，忙碌或恢复时延后。"
    $hint.SetBounds(16,568,812,144); $body.Controls.Add($hint)
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
    $script:autoFight.Timer.Add_Tick({ Invoke-AutoFightTick })
    if ($Unified) {$script:autoFight.Tab=$Tabs.TabPages[0]}
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
