# Shared process UI and foreground scheduling; detector engines retain their own state.
$script:detectorCommands=@()
$script:detectorSamples=@()
function Set-RowTaskMode($Row,[string]$Mode) {
    if ($Mode -cnotin @('fish','fight')) {throw '任务须为钓鱼或战斗。'}
    if ($Row.TaskMode -ne $Mode) {
        if (Test-UnifiedTaskRunning $Row) {Stop-Row $Row '任务已切换，停止原任务并等待重新验证。' -CancelExit}
        $Row.TaskMode=$Mode;$Row.Validated=$false;$Row.State=$null;$Row.StatusSnapshot=$null
        if ($Row.FightRow) {$Row.FightRow.CanStart=$false}
    }
    if ($Mode -eq 'fight' -and $script:autoFight -and $script:autoFight.Unified) {Ensure-UnifiedFightRow $Row}
    Set-RowControls $Row
}
function Add-ProcessTaskControls($Row) {
    $Row | Add-Member NoteProperty TaskMode 'fish'
    $Row | Add-Member NoteProperty FightRow $null
    $Row | Add-Member NoteProperty SlotUseItem $false
    $plan=Get-RowRotationPlan $Row;$index=Get-RotationNextSlot $plan -1
    if ($index -ge 0) {Set-RowSlotTask $Row $plan.Slots[$index]}
    Add-RotationRow $Row
    Add-RowAccountControls $Row
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
    if (-not (Test-RowLoginPoint $Row)) {throw '未检测到插件右下角常驻白点，未开启钓鱼 / 战斗监控。'}
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
function Invoke-FishingDeathChecks([long]$Now) {
    foreach ($row in @($script:rows.Values)) {
        $state=$row.State
        if ($row.TaskMode -ne 'fish' -or -not $state -or -not $state.Running -or $Now -lt $state.DeathCheckAt) {continue}
        $state.DeathCheckAt=$Now+1000
        try {
            # Independent background sampling also runs while waiting for a bite,
            # item confirmation or a reel cooldown. Unknown pixels never exclude a role.
            if (-not (Test-RowLoginPoint $row)) {continue}
            $color=Read-ScanColor $row
        } catch {
            # Regular task reads own capture/identity error reporting and retry policy.
            continue
        }
        if ($color -eq 'dead') {Close-WorkerGame $row '角色死亡'}
    }
}
function Invoke-UnifiedTick([long]$Now) {
    Submit-HoldAction $Now
    Submit-GameExitActions $Now
    if (-not $script:editingSettings) {
        if ($script:scanning) {Submit-RefreshAction $Now}
        else {
            Invoke-FishingDeathChecks $Now
            Submit-RotationAction $Now
            if ($script:autoFight -and $script:autoFight.Unified -and -not $script:autoFight.ActiveHold) {
                # Observe every due combat row before choosing any foreground action.
                $count=[Math]::Max(1,$script:autoFight.Rows.Count)
                for ($i=0;$i -lt $count;$i++) {Invoke-AutoFightTick -PlanOnly}
            }
            Submit-FishingActions $Now
        }
    }
    Submit-WindowCaptureActions $Now
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
    $directories=New-GameDirectorySettingsPage;$settingTabs.TabPages.Add($directories)
    $hostDialog.Tag=[pscustomobject]@{Tabs=$settingTabs;Fish=$fish;Fight=$fight;Directories=$directories}
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
