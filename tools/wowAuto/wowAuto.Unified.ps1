# Shared process UI and foreground scheduling; detector engines retain their own state.
$script:detectorCommands=@()
$script:detectorSamples=@()
function Add-ProcessModeControl($Row) {
    $Row.Panel.Height=148
    $label=New-Object System.Windows.Forms.Label
    $label.Text='模式'; $label.SetBounds(6,106,50,28); $Row.Panel.Controls.Add($label)
    $combo=New-Object System.Windows.Forms.ComboBox
    $combo.DropDownStyle='DropDownList'; $combo.FlatStyle='Flat'
    $combo.BackColor=$script:uiColors.Input; $combo.ForeColor=$script:uiColors.Text
    $combo.DrawMode='OwnerDrawFixed'; $combo.ItemHeight=26
    $combo.Add_DrawItem({param($sender,$e)
        if ($e.Index -lt 0) {return}
        $brush=New-Object Drawing.SolidBrush($sender.BackColor)
        try {$e.Graphics.FillRectangle($brush,$e.Bounds)} finally {$brush.Dispose()}
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics,[string]$sender.Items[$e.Index],$sender.Font,$e.Bounds,[Drawing.Color]::White)
    })
    $combo.Items.AddRange([object[]]@('钓鱼','战斗')); $combo.SetBounds(62,102,180,32)
    $mode=if ($script:processModePreferences.ContainsKey($Row.Key)) {$script:processModePreferences[$Row.Key]} else {'fish'}
    $Row | Add-Member NoteProperty TaskMode $mode
    $Row | Add-Member NoteProperty ModeBox $combo
    $Row | Add-Member NoteProperty FightRow $null
    $combo.SelectedIndex=if ($mode -eq 'fight') {1} else {0}
    $combo.Tag=$Row; $Row.Panel.Controls.Add($combo)
    $combo.Add_SelectedIndexChanged({param($sender,$e)
        $row=$sender.Tag; $mode=if ($sender.SelectedIndex -eq 1) {'fight'} else {'fish'}
        if ($script:updatingPreferenceControls -or $row.TaskMode -eq $mode) {return}
        try {
            if ($script:scanning -or $script:editingSettings) {throw '刷新或设置期间不能切换模式。'}
            if ($mode -eq 'fight' -and (-not $script:autoFight -or -not $script:autoFight.Unified)) {throw '战斗模块未加载。'}
            $nextModes=$script:processModePreferences.Clone(); $nextModes[$row.Key]=$mode
            Save-PreferenceSwitches -ProcessModePreferences $nextModes
            Stop-Row $row '模式已切换，请刷新验证后开始。' -CancelExit
            $row.TaskMode=$mode; $row.Validated=$false; $row.State=$null; $row.StatusSnapshot=$null
            if ($row.FightRow) {$row.FightRow.CanStart=$false}
            if ($mode -eq 'fight') {Ensure-UnifiedFightRow $row}
            Set-RowStatusText $row '模式已切换，请刷新开启对应检测并验证。'
        }
        catch {
            $script:updatingPreferenceControls=$true
            try {$sender.SelectedIndex=if ($row.TaskMode -eq 'fight') {1} else {0}} finally {$script:updatingPreferenceControls=$false}
            Set-RowStatusText $row ('模式未改变：'+$_.Exception.Message)
        }
        Set-RowControls $row; Update-BatchControls
    })
    if ($mode -eq 'fight' -and $script:autoFight -and $script:autoFight.Unified) {Ensure-UnifiedFightRow $Row}
    Add-RotationRow $Row
}
function Ensure-UnifiedFightRow($Row) {
    if ($Row.FightRow) {return}
    $client=if ($UiTest) {[pscustomobject]@{}} else {New-Object WowAutoFight.Client}
    foreach ($entry in @{ProcessId=$Row.Process.Id;StartTicks=$Row.StartTime.Ticks;Path=$Row.Client.ExecutablePath;
        Flavor=$Row.Client.Flavor;Title=$Row.Caption}.GetEnumerator()) {
        if ($UiTest) {$client | Add-Member NoteProperty $entry.Key $entry.Value} else {$client.($entry.Key)=$entry.Value}
    }
    if ($UiTest) {$client | Add-Member NoteProperty Key $Row.Key}
    $fight=New-AutoFightRow $client $Row.Process.Id
    foreach ($button in $fight.MoveButtons) {$Row.Panel.Controls.Add($button)}
    $oldPanel=$fight.Panel
    $fight.Panel=$Row.Panel; $fight.Name=$Row.Name; $fight.Start=$Row.Start; $fight.Stop=$Row.Stop; $fight.Status=$Row.Status
    $fight | Add-Member NoteProperty ParentRow $Row
    $Row.FightRow=$fight; $script:autoFight.Rows[$Row.Key]=$fight
    $oldPanel.Dispose()
    $Row.Status.SetStatusText(($fight.History -join [Environment]::NewLine))
}
function Test-UnifiedTaskRunning($Row) {
    if ($Row.TaskMode -eq 'fight') {return $Row.FightRow -and $null -ne $Row.FightRow.Session}
    return $null -ne $Row.State -and $Row.State.Running
}
function Test-UnifiedRowRunning($Row) {
    return ($script:rotation -and $script:rotation.Active.ContainsKey($Row.Key)) -or (Test-UnifiedTaskRunning $Row)
}
function Test-RowLoginPoint($Row) {
    if ($UiTest) {
        if ($Row.Process.PSObject.Properties['LoginPointPresent']) {return [bool]$Row.Process.LoginPointPresent}
        return $true
    }
    return [WowAutoRotation.Native]::LoginPoint($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath)
}
function Send-ScanDetectorCommand($Row) {
    Assert-GameActionContext
    $Row.Process.Refresh()
    if ($Row.Process.HasExited -or -not (Test-RowProcessIdentity $Row) -or -not (Test-WorkerForeground $Row)) {return $false}
    if (-not (Test-RowLoginPoint $Row)) {throw '未检测到插件左下角常驻白点，未开启钓鱼 / 战斗监控。'}
    $command=[WowAuto.NativeInput]::DetectorCommand($Row.TaskMode)
    if ($UiTest) {
        if ($Row.Process.PSObject.Properties['CommandAllowed'] -and -not $Row.Process.CommandAllowed) {return $false}
        $script:detectorCommands+=,[pscustomobject]@{Key=$Row.Key;Mode=$Row.TaskMode;Command=$command}
        return $true
    }
    return [WowAuto.NativeInput]::SendDetectorCommand($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath,$Row.TaskMode)
}
function Read-ScanFightPacket($Row) {
    if (-not (Test-RowProcessIdentity $Row) -or $Row.Process.HasExited) {throw '战斗进程身份已变化。'}
    if (-not (Test-RowLoginPoint $Row)) {return $null}
    Ensure-UnifiedFightRow $Row
    if ($UiTest) {$script:detectorSamples+=,$Row.Key}
    return [WowAutoFight.Native]::Read($Row.FightRow.Client)
}
function Invoke-UnifiedTick([long]$Now) {
    Submit-HoldAction $Now
    Submit-GameExitActions $Now
    if (-not $script:editingSettings) {
        if ($script:scanning) {Submit-RefreshAction $Now}
        else {
            Submit-RotationAction $Now
            if ($script:autoFight -and $script:autoFight.Unified -and -not $script:autoFight.ActiveHold) {
                # Observe every due combat row before choosing any foreground action.
                $count=[Math]::Max(1,$script:autoFight.Rows.Count)
                for ($i=0;$i -lt $count;$i++) {Invoke-AutoFightTick -PlanOnly}
            }
            Submit-FishingActions $Now
        }
    }
    Invoke-GameActionQueue $Now
}
function New-UnifiedSettingsDialog {
    if (-not $script:autoFight) {throw '战斗设置模块未加载。'}
    if (-not (Release-AutoFightHold)) {throw '移动键未能释放，请停止任务后重试设置。'}
    $script:autoFight.Editing=$true
    $hostDialog=New-Object WowAuto.DimForm
    $hostDialog.Text='wowAuto · 设置'; $hostDialog.StartPosition='CenterParent'; $hostDialog.AutoScaleMode='Dpi'
    $hostDialog.Font=$form.Font; $hostDialog.BackColor=$script:uiColors.Background
    $hostDialog.ClientSize=New-Object Drawing.Size(1000,934); $hostDialog.MinimumSize=New-Object Drawing.Size(700,500)
    $area=[System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $hostDialog.Size=New-Object Drawing.Size([Math]::Min($hostDialog.Width,$area.Width),[Math]::Min($hostDialog.Height,$area.Height))
    $settingTabs=New-Object WowAuto.DimTabControl
    $settingTabs.Dock='Fill'; $settingTabs.HeaderBackground=[Drawing.Color]::Black; $settingTabs.HeaderSurface=$script:uiColors.Tab
    $settingTabs.ForeColor=[Drawing.Color]::White; $settingTabs.SizeMode='Fixed'; $settingTabs.ItemSize=New-Object Drawing.Size(150,32)
    $hostDialog.Controls.Add($settingTabs)
    $fish=New-WaitSettingsDialog -Embedded; $fight=New-AutoFightSettingsDialog -Embedded
    foreach ($entry in @(@('自动钓鱼',$fish),@('自动战斗',$fight))) {
        $page=New-Object System.Windows.Forms.TabPage
        $page.Text=$entry[0]; $page.BackColor=$script:uiColors.Background; $page.AutoScroll=$true
        $settingTabs.TabPages.Add($page)
        $child=$entry[1]; $child.TopLevel=$false; $child.FormBorderStyle='None'; $child.Location=New-Object Drawing.Point(0,0)
        $child.Dock='Fill'; $child.AutoScroll=$true
        if ($child -eq $fish) {$child.AutoScrollMinSize=New-Object Drawing.Size(960,770)}
        $page.Controls.Add($child); $child.Show()
    }
    $fish.Tag.Apply.Text='保存钓鱼设置'; $fish.Tag.Apply.Width=150
    $fish.Tag.Cancel.Left=700
    $fight.Tag.Save.Text='保存战斗设置'; $fight.Tag.Save.Width=130
    $fish.Tag.Cancel.Add_Click({param($sender,$e) $sender.Tag.Parent.Parent.FindForm().Close()})
    $fight.Tag.Cancel.Tag=$hostDialog; $fight.Tag.Cancel.Add_Click({param($sender,$e) $sender.Tag.Close()})
    $settingTabs.Add_SelectedIndexChanged({if ($script:unifiedSettingsHost) {Stop-AudioPreview $script:unifiedSettingsHost.Tag.Fish}})
    $hostDialog.Tag=[pscustomobject]@{Tabs=$settingTabs;Fish=$fish;Fight=$fight}
    $hostDialog.Tag | Add-Member NoteProperty Rotation (New-RotationIntervalControls $hostDialog)
    $script:unifiedSettingsHost=$hostDialog
    $hostDialog.Add_FormClosed({
        $script:unifiedSettingsHost=$null; $script:autoFight.Editor=$null; $script:autoFight.Editing=$false
    })
    $hostDialog.Add_Disposed({
        $script:unifiedSettingsHost=$null
        if ($script:autoFight) {$script:autoFight.Editor=$null; $script:autoFight.Editing=$false}
    })
    return $hostDialog
}
