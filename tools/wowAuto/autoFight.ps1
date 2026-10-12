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
function Stop-AutoFightRow($Row,[string]$Reason='已停止，战斗任务已取消。') {
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
    $script:autoFight.HoldUntil=0L
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
    if ($script:autoFight.Editing -or $script:autoFight.Tabs.SelectedTab -ne $script:autoFight.Tab) { return }
    $now=$script:autoFight.Clock.ElapsedMilliseconds
    if ($now -lt $script:autoFight.HoldUntil) { return }
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
        $action=Get-AutoFightAction $session $packet $profile $now
        if ($action -eq 'identity-changed') { $row.CanStart=$false; Stop-AutoFightRow $row '角色职业改变，请刷新重新识别。'; return }
        if ($action -eq 'wait') {
            $text=switch ($packet.Action) { 'busy' {'施法 / 拾取 / 剥皮中'}; 'idle' {'等待范围内目标'};
                'skin' {'可剥皮，当前配置未启用交互或仍在冷却'}; 'loot' {'可拾取，当前配置未启用交互或仍在冷却'}; default {'等待下一次战斗按键'} }
            Set-AutoFightStatus $row "$text · $combatText"
            Finish-AutoFightPending $now; return
        }
        $binding=ConvertFrom-AutoFightBinding $(if ($action -eq 'attack') { $profile.AttackKey } else { $profile.SkinKey })
        # Read again immediately before input; reject any action/class/combat transition.
        $latest=[WowAutoFight.Native]::Read($row.Client)
        if ($null -eq $latest -or $latest.ClassId -ne $packet.ClassId -or
            $latest.Action -ne $packet.Action -or $latest.Combat -ne $packet.Combat) {
            Set-AutoFightStatus $row '状态变化，等待重新探测。'; Finish-AutoFightPending $now; return
        }
        if (-not [WowAutoFight.Native]::Press($row.Client,[uint16]$binding.Code,$binding.Ctrl,$binding.Shift,$binding.Alt)) {
            throw '发键前失去前台。'
        }
        $completed=$script:autoFight.Clock.ElapsedMilliseconds
        if ($action -eq 'attack') {
            $session.NextAttackAt=$completed+$profile.AttackIntervalMs
            $session.Due=$session.NextAttackAt
            Set-AutoFightStatus $row "已发送战斗键 $($binding.Text) · $combatText"
        }
        else {
            $session.NextInteractionAt=$completed+$profile.InteractionHoldMs
            $session.Due=$session.NextInteractionAt
            $script:autoFight.HoldUntil=$session.NextInteractionAt
            $verb=if ($packet.Action -eq 'skin') { '剥皮' } else { '拾取' }
            Set-AutoFightStatus $row "已发送$verb 交互键 $($binding.Text)，前台保持 $($profile.InteractionHoldMs) ms。"
        }
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
    $p.AttackKey=$editor.Attack.Text; $p.SkinKey=$editor.Skin.Text
    $p.AttackIntervalMs=[int]$editor.Interval.Value; $p.InteractionHoldMs=[int]$editor.Hold.Value
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
    $editor.Attack.Text=$p.AttackKey; $editor.Skin.Text=$p.SkinKey
    $editor.Interval.Value=$p.AttackIntervalMs; $editor.Hold.Value=$p.InteractionHoldMs
    $editor.SkinEnabled.Checked=$p.SkinEnabled
}
function Show-AutoFightSettings {
    if ($script:autoFight.Editing -or $script:autoFight.Scan) { return }
    $script:autoFight.Editing=$true
    $dialog=New-Object WowAuto.DimForm
    $dialog.Text='autoFight · 按服务器及职业配置'; $dialog.StartPosition='CenterParent'
    $dialog.ClientSize=New-Object Drawing.Size(720,475); $dialog.MinimumSize=$dialog.Size
    $dialog.Font=$script:autoFight.Owner.Font; $dialog.BackColor=[Drawing.Color]::FromArgb(58,58,58)
    $dialog.ForeColor=[Drawing.Color]::White
    $editor=[pscustomobject]@{Draft=(Copy-AutoFightProfiles $script:autoFight.Profiles); CurrentKey=''; Loading=$true;
        Flavor=$null; Class=$null; Attack=$null; Skin=$null; Interval=$null; Hold=$null; SkinEnabled=$null}
    $script:autoFight.Editor=$editor
    $labels=@('服务器','职业','一键战斗快捷键','拾取 / 剥皮交互快捷键','战斗按键间隔 (ms)','交互后前台保持 (ms)')
    for ($i=0;$i -lt $labels.Count;$i++) {
        $label=New-Object System.Windows.Forms.Label; $label.Text=$labels[$i]; $label.SetBounds(24,(22+44*$i),280,32)
        $dialog.Controls.Add($label)
    }
    $editor.Flavor=New-Object System.Windows.Forms.ComboBox
    $editor.Class=New-Object System.Windows.Forms.ComboBox
    foreach ($combo in @($editor.Flavor,$editor.Class)) {
        $combo.DropDownStyle='DropDownList'; $combo.FlatStyle='Flat'
        $combo.BackColor=[Drawing.Color]::FromArgb(50,50,50); $combo.ForeColor=[Drawing.Color]::White
        $combo.Add_SelectedIndexChanged({ Select-AutoFightDraftProfile })
        $dialog.Controls.Add($combo)
    }
    $editor.Flavor.SetBounds(330,18,345,32); $editor.Class.SetBounds(330,62,345,32)
    $editor.Flavor.Items.AddRange([object[]]@('时光服 (titan)','永恒服 / 无限服 (forerver)'))
    $editor.Class.Items.AddRange([object[]]@($script:autoFightClasses.Values))
    foreach ($field in @('Attack','Skin')) {
        $box=New-Object System.Windows.Forms.TextBox; $box.ReadOnly=$true
        $box.BackColor=[Drawing.Color]::FromArgb(50,50,50); $box.ForeColor=[Drawing.Color]::White
        $box.Add_KeyDown({param($sender,$eventArgs)
            $binding=New-AutoFightBinding ([int]$eventArgs.KeyCode) $eventArgs.Control $eventArgs.Shift $eventArgs.Alt
            if ($null -ne $binding) { $sender.Text=$binding.Text }
            $eventArgs.SuppressKeyPress=$true; $eventArgs.Handled=$true
        })
        $editor.$field=$box; $dialog.Controls.Add($box)
    }
    $editor.Attack.SetBounds(330,106,345,32); $editor.Skin.SetBounds(330,150,345,32)
    foreach ($field in @('Interval','Hold')) {
        $number=New-Object System.Windows.Forms.NumericUpDown
        $number.Minimum=if ($field -eq 'Interval') { 100 } else { 1000 }
        $number.Maximum=if ($field -eq 'Interval') { 10000 } else { 60000 }
        $number.Increment=100; $number.BackColor=[Drawing.Color]::FromArgb(50,50,50); $number.ForeColor=[Drawing.Color]::White
        $editor.$field=$number; $dialog.Controls.Add($number)
    }
    $editor.Interval.SetBounds(330,194,345,32); $editor.Hold.SetBounds(330,238,345,32)
    $editor.SkinEnabled=New-Object WowAuto.DimCheckBox
    $editor.SkinEnabled.Text='启用拾取及剥皮交互'; $editor.SkinEnabled.SetBounds(24,290,600,32)
    $dialog.Controls.Add($editor.SkinEnabled)
    $hint=New-Object System.Windows.Forms.Label
    $hint.Text="点击快捷键输入框后按键录入。游戏内须绑定对应战斗宏 / 交互键。`r`n切换服务器或职业可分别编辑；保存写入独立 autoFight.config.json。"
    $hint.SetBounds(24,330,650,56); $dialog.Controls.Add($hint)
    $errorLabel=New-Object System.Windows.Forms.Label
    $errorLabel.SetBounds(24,390,650,30); $errorLabel.AutoEllipsis=$true; $dialog.Controls.Add($errorLabel)
    $save=New-Object WowAuto.DimButton
    $save.Text='保存'; $save.SetBounds(460,430,100,32); Set-AutoFightButtonStyle $save $true
    $cancel=New-Object WowAuto.DimButton
    $cancel.Text='取消'; $cancel.SetBounds(575,430,100,32); Set-AutoFightButtonStyle $cancel
    $cancel.Add_Click({param($sender,$eventArgs) $sender.FindForm().Close()})
    $save.Tag=$errorLabel
    $save.Add_Click({param($sender,$eventArgs)
        try {
            Save-AutoFightDraftSelection
            $valid=Save-AutoFightProfiles $script:autoFight.ConfigPath $script:autoFight.Editor.Draft
            $script:autoFight.Profiles=$valid; $script:autoFight.ConfigReady=$true
            $script:autoFight.Summary.Text='autoFight 设置已保存；运行中的截止时间保留，下次操作使用新配置。'
            $sender.FindForm().Close()
        }
        catch { $sender.Tag.Text=$_.Exception.Message }
    })
    $dialog.Controls.AddRange([System.Windows.Forms.Control[]]@($save,$cancel))
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
    foreach ($entry in @(@('Refresh','刷新进程'),@('StartAll','全部开始'),@('StopAll','全部停止'),@('Settings','职业设置'))) {
        $button=New-Object WowAuto.DimButton; $button.Text=$entry[1]; $button.Width=120; $button.Height=36
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
    $script:autoFight=[pscustomobject]@{Rows=@{}; Pending=$null; Scan=$null; HoldUntil=0L; Editing=$false; Editor=$null;
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
