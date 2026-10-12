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
        if (-not [WowAutoFight.Native]::IsAlive($row.Client) -or -not [WowAutoFight.Native]::Foreground($row.Client)) {
            throw '保持期间进程身份或前台发生变化，已释放移动键。'
        }
        $packet=[WowAutoFight.Native]::Read($row.Client)
        if ($null -eq $packet) { throw '保持期间检测关闭或协议不可读，已释放移动键。' }
        if ($packet.ClassId -ne $hold.Session.ClassId) { throw '职业发生变化，已释放移动键。' }
        if ($packet.Heartbeat -ne $hold.Beat) { $hold.Beat=$packet.Heartbeat; $hold.LastBeatAt=$Now }
        elseif ($Now-$hold.LastBeatAt -ge 1500) { throw '保持期间插件心跳停止，已释放移动键。' }
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
    $scan=$script:autoFight.Scan
    $script:autoFight.Scan=$null
    $script:autoFight.Pending=$null
    if ($scan) { [WowAutoFight.Native]::Restore($scan.OriginalWindow) }
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
function Start-AutoFightRow($Row) {
    if (-not $Row.CanStart -or $script:autoFight.Scan -or -not $script:autoFight.ConfigReady -or $Row.Session) { return }
    if (-not [WowAutoFight.Native]::IsAlive($Row.Client)) {
        $Row.CanStart=$false; Set-AutoFightStatus $Row '进程已退出或身份改变，请刷新。'; Update-AutoFightControls; return
    }
    $Row.Session=New-AutoFightSession $script:autoFight.Clock.ElapsedMilliseconds $Row.ClassId
    Set-AutoFightStatus $Row '开始监测，等待前台及新心跳。'
    Update-AutoFightControls
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
        Status=$status; CanStart=$false; ClassId=0; Session=$null; Message=''; History=(New-Object 'Collections.Generic.List[string]')}
    $start.Tag=$row; $stop.Tag=$row
    $start.Add_Click({param($sender,$eventArgs) Start-AutoFightRow $sender.Tag})
    $stop.Add_Click({param($sender,$eventArgs) Stop-AutoFightRow $sender.Tag})
    $panel.Controls.AddRange([System.Windows.Forms.Control[]]@($name,$start,$stop,$status))
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
        Index=0; OriginalWindow=[WowAutoFight.Native]::CurrentWindow()}
    $script:autoFight.Summary.Text='正在逐个切换窗口读取战斗协议，不发送按键。'
    Update-AutoFightControls
}
function New-AutoFightPending($Row,$Session,[bool]$Scanning,[long]$Now) {
    return [pscustomobject]@{Row=$Row; Session=$Session; Scanning=$Scanning; Activated=$false;
        Since=$Now; SampleAt=($Now+200); FirstBeat=-1; FirstClass=0; FirstAction=''}
}
function Finish-AutoFightPending([long]$Now) {
    $pending=$script:autoFight.Pending
    $script:autoFight.Pending=$null
    if ($pending.Scanning) { $script:autoFight.Scan.Index++ }
    elseif ($pending.Row.Session -eq $pending.Session) {
        $pending.Session.Due=[Math]::Max($pending.Session.Due,($Now+250))
    }
}
function Invoke-AutoFightTick {
    $now=$script:autoFight.Clock.ElapsedMilliseconds
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
        if (-not $pending.Activated) {
            $pending.Activated=$true
            if (-not [WowAutoFight.Native]::Activate($row.Client)) { throw '无法切换到目标窗口。' }
            return
        }
        if ($now -lt $pending.SampleAt) { return }
        if (-not [WowAutoFight.Native]::Foreground($row.Client)) {
            if ($now-$pending.Since -lt 800) { return }
            throw '窗口未取得前台，暂停该行。'
        }
        $packet=[WowAutoFight.Native]::Read($row.Client)
        if ($null -eq $packet) {
            if ($pending.Scanning -and $now-$pending.Since -lt 800) { return }
            $row.CanStart=$false
            if ($pending.Scanning) { Set-AutoFightStatus $row '战斗协议不可读，请启动 fight_detector 后刷新。'; Finish-AutoFightPending $now }
            else { Stop-AutoFightRow $row '检测关闭、死亡或数据未知，请恢复插件后刷新。' }
            Update-AutoFightControls; return
        }
        # Every focus acquisition requires two different fresh heartbeat samples, even after a restart.
        if ($pending.FirstBeat -lt 0) {
            $pending.FirstBeat=$packet.Heartbeat; $pending.FirstClass=$packet.ClassId; $pending.FirstAction=$packet.Action
            return
        }
        if ($packet.Heartbeat -eq $pending.FirstBeat) {
            if ($now-$pending.Since -lt 1500) { return }
            throw '插件心跳未更新，停止该行。'
        }
        if ($packet.ClassId -ne $pending.FirstClass) { throw '采样期间职业发生变化，请刷新。' }
        $combatText=if ($packet.Combat) { '战斗中' } else { '非战斗' }
        if ($pending.Scanning) {
            $row.ClassId=$packet.ClassId; $row.CanStart=$true
            $label=if ($row.Client.Flavor -eq 'titan') { '时光服' } else { '永恒服 / 无限服' }
            $row.Name.Text="PID $($row.Client.ProcessId) · $label`r`n$($row.Client.Title)`r`n职业：$($script:autoFightClasses[[string]$row.ClassId])"
            Set-AutoFightStatus $row "已识别职业及新心跳 · $combatText · 点击开始。"
            Finish-AutoFightPending $now; Update-AutoFightControls; return
        }
        $session=$pending.Session
        $profile=$script:autoFight.Profiles["$($row.Client.Flavor):$($session.ClassId)"]
        $previous=$session.State
        if (Update-AutoFightState $session $packet $now) {
            $before=if ($previous) { $script:autoFightStates[$previous].Label } else { '初始' }
            Set-AutoFightStatus $row ("状态切换：$before → "+$script:autoFightStates[$session.State].Label)
        }
        $action=Get-AutoFightAction $session $packet $profile $now
        if ($action -eq 'identity-changed') { $row.CanStart=$false; Stop-AutoFightRow $row '角色职业或协议状态改变，请刷新。'; return }
        if ($action -eq 'wait') {
            $detail=if ($packet.Busy) { '施法 / 交互中，等待' } else { '等待下一次状态处理' }
            Set-AutoFightStatus $row ($script:autoFightStates[$session.State].Label+" · $detail · $combatText")
            Finish-AutoFightPending $now; return
        }
        $handler=$script:autoFightStates[$action]
        $keyField=$handler.Key
        $binding=ConvertFrom-AutoFightBinding $profile.$keyField
        # Re-read both independent state and recovery signals immediately before input.
        $latest=[WowAutoFight.Native]::Read($row.Client)
        if ($null -eq $latest -or $latest.ClassId -ne $packet.ClassId -or $latest.Action -ne $packet.Action -or
            $latest.Recovery -ne $packet.Recovery -or $latest.Combat -ne $packet.Combat -or $latest.Busy -ne $packet.Busy) {
            Set-AutoFightStatus $row '状态变化，等待重新探测。'; Finish-AutoFightPending $now; return
        }
        $movement=$action.StartsWith('move-')
        if ($movement) { $sent=[WowAutoFight.Native]::BeginHold($row.Client,[uint16]$binding.Code,$binding.Ctrl,$binding.Shift,$binding.Alt) }
        else { $sent=[WowAutoFight.Native]::Press($row.Client,[uint16]$binding.Code,$binding.Ctrl,$binding.Shift,$binding.Alt) }
        if (-not $sent) { throw '发键前失去前台。' }
        $completed=$script:autoFight.Clock.ElapsedMilliseconds
        Complete-AutoFightAction $session $profile $action $completed
        if ($movement -or $action -in @('skin','loot')) {
            $duration=if ($movement) { $profile.MovementHoldMs } else { $profile.InteractionHoldMs }
            $script:autoFight.ActiveHold=[pscustomobject]@{Row=$row; Session=$session; State=$packet.Action;
                Until=($completed+$duration); Movement=$movement; Beat=$latest.Heartbeat; LastBeatAt=$completed}
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
    if (-not $editor.CurrentKey) { return }
    $p=$editor.Draft[$editor.CurrentKey]
    foreach ($field in $editor.Bindings.Keys) { $p.$field=$editor.Bindings[$field].Text }
    foreach ($field in $editor.Numbers.Keys) { $p.$field=[int]$editor.Numbers[$field].Value }
    $p.SkinEnabled=$editor.SkinEnabled.Checked
}
function Select-AutoFightDraftProfile {
    $editor=$script:autoFight.Editor
    if ($editor.Loading -or $editor.Flavor.SelectedIndex -lt 0 -or $editor.Class.SelectedIndex -lt 0) { return }
    Save-AutoFightDraftSelection
    $flavor=if ($editor.Flavor.SelectedIndex -eq 0) { 'titan' } else { 'forerver' }
    $id=$editor.Class.SelectedIndex+1
    $editor.CurrentKey="${flavor}:$id"
    $p=$editor.Draft[$editor.CurrentKey]
    foreach ($field in $editor.Bindings.Keys) { $editor.Bindings[$field].Text=$p.$field }
    foreach ($field in $editor.Numbers.Keys) { $editor.Numbers[$field].Value=$p.$field }
    $editor.SkinEnabled.Checked=$p.SkinEnabled
}
function Show-AutoFightSettings {
    if ($script:autoFight.Editing -or $script:autoFight.Scan) { return }
    if (-not (Release-AutoFightHold)) { return }
    $script:autoFight.Pending=$null
    $script:autoFight.Editing=$true
    $dialog=New-Object WowAuto.DimForm
    $dialog.Text='autoFight · 状态按键 / 服务器及职业'; $dialog.StartPosition='CenterParent'
    $area=[System.Windows.Forms.Screen]::FromControl($script:autoFight.Owner).WorkingArea
    $dialog.ClientSize=New-Object Drawing.Size([Math]::Min(860,$area.Width-80),[Math]::Min(720,$area.Height-100))
    $dialog.MinimumSize=New-Object Drawing.Size(600,450)
    $dialog.Font=$script:autoFight.Owner.Font; $dialog.BackColor=[Drawing.Color]::FromArgb(58,58,58)
    $dialog.ForeColor=[Drawing.Color]::White
    $body=New-Object System.Windows.Forms.Panel
    $body.Dock='Fill'; $body.AutoScroll=$true; $body.AutoScrollMinSize=New-Object Drawing.Size(840,590)
    $footer=New-Object System.Windows.Forms.Panel
    $footer.Dock='Bottom'; $footer.Height=100
    $dialog.Controls.Add($body); $dialog.Controls.Add($footer)
    $editor=[pscustomobject]@{Draft=(Copy-AutoFightProfiles $script:autoFight.Profiles); CurrentKey=''; Loading=$true;
        Flavor=$null; Class=$null; Bindings=@{}; Numbers=@{}; SkinEnabled=$null}
    $script:autoFight.Editor=$editor
    foreach ($entry in @(@('Flavor','服务器'),@('Class','职业'))) {
        $x=if ($entry[0] -eq 'Flavor') { 16 } else { 436 }
        $label=New-Object System.Windows.Forms.Label; $label.Text=$entry[1]; $label.SetBounds($x,22,220,32)
        $combo=New-Object System.Windows.Forms.ComboBox
        $combo.DropDownStyle='DropDownList'; $combo.FlatStyle='Flat'
        $combo.BackColor=[Drawing.Color]::FromArgb(50,50,50); $combo.ForeColor=[Drawing.Color]::White
        $combo.SetBounds(($x+224),18,168,32)
        $combo.Add_SelectedIndexChanged({ Select-AutoFightDraftProfile })
        $editor.($entry[0])=$combo; $body.Controls.Add($label); $body.Controls.Add($combo)
    }
    $editor.Flavor.Items.AddRange([object[]]@('时光服 (titan)','永恒服 / 无限服 (forerver)'))
    $editor.Class.Items.AddRange([object[]]@($script:autoFightClasses.Values))
    $keyLabels=@('开怪战斗键','正常战斗键','非战斗恢复键','战斗紧急恢复键','向前移动键','向后移动键','向左移动键','向右移动键','拾取 / 剥皮交互键')
    for ($i=0;$i -lt $script:autoFightKeyFields.Count;$i++) {
        $field=$script:autoFightKeyFields[$i]
        $x=16+($i%2)*420; $y=66+[Math]::Floor($i/2)*44
        $label=New-Object System.Windows.Forms.Label; $label.Text=$keyLabels[$i]; $label.SetBounds($x,($y+4),220,32)
        $box=New-Object System.Windows.Forms.TextBox; $box.ReadOnly=$true
        $box.BackColor=[Drawing.Color]::FromArgb(50,50,50); $box.ForeColor=[Drawing.Color]::White
        $box.SetBounds(($x+224),$y,168,32)
        $box.Add_KeyDown({param($sender,$eventArgs)
            $binding=New-AutoFightBinding ([int]$eventArgs.KeyCode) $eventArgs.Control $eventArgs.Shift $eventArgs.Alt
            if ($null -ne $binding) { $sender.Text=$binding.Text }
            $eventArgs.SuppressKeyPress=$true; $eventArgs.Handled=$true
        })
        $editor.Bindings[$field]=$box; $body.Controls.Add($label); $body.Controls.Add($box)
    }
    $numbers=@(@('OpeningIntervalMs','开怪重试间隔 (ms)',100,60000),@('CombatIntervalMs','正常战斗间隔 (ms)',100,10000),
        @('EmergencyIntervalMs','紧急恢复重试间隔 (ms)',100,60000),@('MovementHoldMs','移动按住时长 (ms)',100,2000),
        @('InteractionHoldMs','交互前台保持 (ms)',1000,60000))
    for ($i=0;$i -lt $numbers.Count;$i++) {
        $entry=$numbers[$i]; $x=16+($i%2)*420; $y=302+[Math]::Floor($i/2)*44
        $label=New-Object System.Windows.Forms.Label; $label.Text=$entry[1]; $label.SetBounds($x,($y+4),220,32)
        $number=New-Object System.Windows.Forms.NumericUpDown
        $number.Minimum=$entry[2]; $number.Maximum=$entry[3]; $number.Increment=100
        $number.BackColor=[Drawing.Color]::FromArgb(50,50,50); $number.ForeColor=[Drawing.Color]::White
        $number.SetBounds(($x+224),$y,168,32)
        $editor.Numbers[$entry[0]]=$number; $body.Controls.Add($label); $body.Controls.Add($number)
    }
    $editor.SkinEnabled=New-Object WowAuto.DimCheckBox
    $editor.SkinEnabled.Text='启用自动拾取 / 剥皮交互'; $editor.SkinEnabled.SetBounds(16,440,600,32)
    $body.Controls.Add($editor.SkinEnabled)
    $hint=New-Object System.Windows.Forms.Label
    $hint.Text="插件主色驱动开怪 / 战斗，独立恢复色块优先驱动恢复。阈值在插件面板配置。`r`n非战斗恢复仅在进入状态时按一次；开怪 / 战斗 / 紧急恢复按各自间隔重试。`r`n四向移动规则待定，暂仅响应插件面板手动请求；按住至时限或状态改变。`r`n拾取后检测到可剥皮会再次按交互键；请在游戏中启用自动拾取。`r`n点击输入框按键录入；游戏内绑定对应宏 / 技能 / 交互 / 移动键。"
    $hint.SetBounds(16,484,812,128); $body.Controls.Add($hint)
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
            $valid=Save-AutoFightProfiles $script:autoFight.ConfigPath $script:autoFight.Editor.Draft
            $script:autoFight.Profiles=$valid; $script:autoFight.ConfigReady=$true
            $script:autoFight.Summary.Text='状态按键已保存；下次执行使用新配置，已有截止时间保留。'
            $sender.FindForm().Close()
        }
        catch { $sender.Tag.Text=$_.Exception.Message }
    })
    $footer.Controls.AddRange([System.Windows.Forms.Control[]]@($save,$cancel))
    $editor.Flavor.SelectedIndex=0; $editor.Class.SelectedIndex=0; $editor.Loading=$false
    Select-AutoFightDraftProfile
    try { [void]$dialog.ShowDialog($script:autoFight.Owner) }
    finally { $script:autoFight.Editor=$null; $script:autoFight.Editing=$false; $dialog.Dispose(); Update-AutoFightControls }
}
function Initialize-AutoFightTab($Tabs,$Owner) {
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
    $script:autoFight=[pscustomobject]@{Rows=@{}; Pending=$null; Scan=$null; ActiveHold=$null; Editing=$false; Editor=$null;
        ConfigPath=(Join-Path $PSScriptRoot 'autoFight.config.json'); Profiles=(New-AutoFightProfiles); ConfigReady=$true;
        Tab=$tab; Tabs=$Tabs; Owner=$Owner; List=$list; Refresh=$buttons.Refresh; StartAll=$buttons.StartAll;
        StopAll=$buttons.StopAll; Settings=$buttons.Settings; Summary=$summary;
        Clock=[Diagnostics.Stopwatch]::StartNew(); Timer=(New-Object System.Windows.Forms.Timer)}
    try { $script:autoFight.Profiles=Read-AutoFightProfiles $script:autoFight.ConfigPath }
    catch { $script:autoFight.ConfigReady=$false; $summary.Text='配置读取失败，请在职业设置中修正并保存：'+$_.Exception.Message }
    $buttons.Refresh.Add_Click({ Begin-AutoFightRefresh })
    $buttons.Settings.Add_Click({ Show-AutoFightSettings })
    $buttons.StartAll.Add_Click({ foreach ($row in @($script:autoFight.Rows.Values | Sort-Object Order)) { Start-AutoFightRow $row } })
    $buttons.StopAll.Add_Click({ Stop-AutoFightAll })
    $script:autoFight.Timer.Interval=50
    $script:autoFight.Timer.Add_Tick({ Invoke-AutoFightTick })
    $Tabs.TabPages.Add($tab)
    $script:autoFight.Timer.Start()
    Update-AutoFightControls
}
function Close-AutoFightTab {
    if ($null -eq $script:autoFight) { return }
    $script:autoFight.Timer.Stop()
    Stop-AutoFightAll
    $script:autoFight.Timer.Dispose()
    $script:autoFight=$null
}
