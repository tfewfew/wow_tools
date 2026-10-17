# Uses the combat native substitute installed by AutoFight.UiTests.ps1 and mock fishing adapters.
Stop-AllRows
foreach ($page in @($tabs.TabPages)) {if ($page -ne $tab) {$tabs.TabPages.Remove($page); $page.Dispose()}}
$tabs.SelectedTab=$tab
Initialize-AutoFightTab $tabs $form -Unified
$fightConfigPath=Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-unified-'+[Guid]::NewGuid()+'.json')
$script:autoFight.ConfigPath=$fightConfigPath
$sourceIni=Join-Path (Split-Path $PSScriptRoot -Parent) 'config.ini'
$savedRotationPath=$script:rotation.Path;$savedRotationPlans=$script:rotation.Plans;$savedRotationHistory=$script:rotation.NameHistory
$script:rotation.Path=Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-unified-roles-'+[Guid]::NewGuid()+'.json')
$script:rotation.Plans=@{};$script:rotation.NameHistory=@()
$sourceFight=Join-Path (Split-Path $PSScriptRoot -Parent) 'autoFight.config.json'
$iniHash=(Get-FileHash $sourceIni).Hash; $fightHash=(Get-FileHash $sourceFight).Hash
try {
    Assert-Ui ([WowAuto.NativeInput]::DetectorCommand('fish') -eq '/wowdetector on' -and [WowAuto.NativeInput]::DetectorCommand('fight') -eq '/fightdetector on') 'Native command routing changed.'
    $rejected=$false;try {$null=[WowAuto.NativeInput]::DetectorCommand('arbitrary chat')} catch {$rejected=$true}
    Assert-Ui $rejected 'Native command sender accepts arbitrary text.'
    $script:scheduler=New-WowAutoScheduler
    $script:schedulerClock=[pscustomobject]@{ElapsedMilliseconds=0L}
    $script:autoFight.Clock=$script:schedulerClock
    $script:processModePreferences=@{}
    $script:mockProcesses=@()
    foreach ($spec in @(@(701,'titan'),@(702,'forerver'))) {
        $forever=$spec[1] -eq 'forerver'
        $mock=[pscustomobject]@{Id=$spec[0];StartTime=[datetime]'2026-10-13';
            ProcessName=$(if ($forever) {'Wow'} else {'WowClassic'});
            ExecutablePath=$(if ($forever) {'C:\games\_cn_beta_\Wow.exe'} else {'C:\games\_classic_titan_\WowClassic.exe'});
            FileVersion=$(if ($forever) {'1.60.1.70338'} else {'3.80.2.70177'});
            MainWindowTitle='Unified mock';HasExited=$false;FocusAllowed=$true;CommandAllowed=$true;
            ScanColor='red';LureColor='present';WindowBounds=@(20,20,820,520);ScreenBounds=@(0,0,1920,1080);Minimized=$false}
        $mock | Add-Member ScriptMethod Refresh {}
        $script:mockProcesses+=,$mock
    }
    $null=Refresh-ProcessRows
    $combat=@($script:rows.Values | Where-Object {$_.Process.Id -eq 701})[0]
    $fishing=@($script:rows.Values | Where-Object {$_.Process.Id -eq 702})[0]
    Assert-Ui ($tabs.TabPages.Count -eq 1 -and -not $combat.PSObject.Properties['ModeBox'] -and @($combat.Panel.Controls | Where-Object {$_ -is [System.Windows.Forms.ComboBox]}).Count -eq 1) 'Main UI still has two task tabs or incorrect default.'
    Set-RowTaskMode $combat fight
    Assert-Ui ($combat.TaskMode -eq 'fight' -and $combat.FightRow -and -not $combat.Validated) 'Mode selector failed to attach combat engine.'
    Assert-Ui (-not $combat.FightRow.PSObject.Properties['MoveButtons'] -and
        -not @($combat.Panel.Controls | Where-Object {$_ -is [System.Windows.Forms.Button] -and $_.Text -in @('前','后','左','右')}).Count) 'Unified combat row still exposes manual movement buttons.'
    [WowAutoFight.Native]::Current.Flavor='titan'; [WowAutoFight.Native]::Current.Action='idle'
    [WowAutoFight.Native]::Current.Recovery='none'; [WowAutoFight.Native]::Current.ClassId=1
    [WowAutoFight.Native]::IsForeground=$true; [WowAutoFight.Native]::FailSend=$false
    [WowAutoFight.Native]::MissingReads=0
    $script:detectorCommands=@(); $script:detectorSamples=@()
    $sends=[WowAutoFight.Native]::Sends; $keys=$script:workerKeys.Count
    Begin-RefreshScan
    Invoke-RefreshScan 0
    Assert-Ui ($script:detectorCommands.Count -eq 0 -and $script:detectorSamples.Count -eq 0) 'Command/sample preceded activation.'
    Invoke-RefreshScan 200
    Assert-Ui ($script:detectorCommands.Count -eq 0 -and $script:detectorSamples.Count -eq 0) 'Command/sample preceded foreground settling.'
    Invoke-RefreshScan 400
    Assert-Ui ($script:detectorCommands.Count -eq 1 -and $script:detectorCommands[0].Command -eq '/fightdetector on' -and $script:detectorSamples.Count -eq 0) 'Combat detector not enabled before sampling.'
    Invoke-UnifiedTick 450
    Assert-Ui ([WowAutoFight.Native]::Sends -eq $sends -and $script:workerKeys.Count -eq $keys) 'Refresh ran an attack or fishing action.'
    Invoke-RefreshScan 600
    Complete-TestScan
    Assert-Ui ($combat.Validated -and $combat.FightRow.CanStart -and $fishing.Validated -and $script:restored) 'Mixed-mode refresh/foreground restoration failed.'
    Assert-Ui ($script:detectorCommands.Count -eq 2 -and $script:detectorCommands[1].Command -eq '/wowdetector on') 'Fishing refresh sent incorrect command.'
    Assert-Ui ($script:detectorSamples.Count -eq 2 -and [WowAutoFight.Native]::Sends -eq $sends -and $script:workerKeys.Count -eq $keys) 'Refresh performed unexpected actions.'
    $startAllButton.PerformClick()
    Assert-Ui ($combat.FightRow.Session -and $fishing.State.Running) 'Start All failed to dispatch both modes.'
    Set-RowTaskMode $combat fish
    Assert-Ui (-not $combat.FightRow.Session -and $fishing.State.Running -and -not $combat.Validated) 'Switching mode stopped another row or retained combat task.'
    Set-RowTaskMode $combat fight
    Stop-AllRows
    $combat.Process.CommandAllowed=$false; $script:detectorSamples=@()
    Begin-RefreshScan; Complete-TestScan
    Assert-Ui (-not $combat.Validated -and $combat.Key -notin $script:detectorSamples -and $fishing.Validated) 'Failed command still sampled/validated combat.'
    $combat.Process.CommandAllowed=$true; $combat.Process.FocusAllowed=$false
    $script:detectorCommands=@(); Begin-RefreshScan; Complete-TestScan
    Assert-Ui (-not $combat.Validated -and -not @($script:detectorCommands | Where-Object {$_.Key -eq $combat.Key}).Count) 'Focus failure still sent command.'
    $combat.Process.FocusAllowed=$true
    Begin-RefreshScan; Complete-TestScan
    # Due combat precedes a fishing reel; activation settling and post-reel holds still apply.
    Stop-AllRows; $audioCheck.Checked=$false
    $script:scheduler=New-WowAutoScheduler
    $script:autoFight.CommandGate=New-AutoFightCommandGate
    $combat.FightRow.CanStart=$true; $combat.Validated=$true; Start-Row $combat
    $combat.FightRow.CanStart=$false;$combat.Validated=$false;Set-RowControls $combat
    Assert-Ui (-not $combat.Start.Enabled -and $combat.Stop.Enabled) 'Running row lost stop control when readiness became invalid.'
    $combat.FightRow.CanStart=$true;$combat.Validated=$true;Set-RowControls $combat
    $fishing.State=Add-WowAutoTask $script:scheduler $fishing.Key 1000 1000 0 -UseItem $false -UseAudio $false
    $null=Complete-WowAutoPoll $script:scheduler $fishing.Key 0 'green'
    $fishing.Process.ScanColor='green'; $script:workerFocus=$fishing.Process.Id
    [WowAutoFight.Native]::Current.Action='combat'; [WowAutoFight.Native]::Current.Combat=$true
    $script:schedulerClock.ElapsedMilliseconds=1000
    $sends=[WowAutoFight.Native]::Sends; $keys=$script:workerKeys.Count
    Invoke-UnifiedTick 1000
    Assert-Ui ([WowAutoFight.Native]::Sends -eq $sends -and $script:workerKeys.Count -eq $keys -and $script:workerFocus -eq $combat.Process.Id) 'Due combat did not take priority over reel or skipped activation settling.'
    $script:schedulerClock.ElapsedMilliseconds=1199; Invoke-UnifiedTick 1199
    Assert-Ui ([WowAutoFight.Native]::Sends -eq $sends -and $script:workerKeys.Count -eq $keys) 'Input preceded activation settling.'
    $script:schedulerClock.ElapsedMilliseconds=1200; Invoke-UnifiedTick 1200
    Assert-Ui ([WowAutoFight.Native]::Sends -eq $sends+1 -and $script:workerKeys.Count -eq $keys) 'Combat did not execute before due reel.'
    $script:schedulerClock.ElapsedMilliseconds=1225; Invoke-UnifiedTick 1225
    $script:schedulerClock.ElapsedMilliseconds=1399; Invoke-UnifiedTick 1399
    Assert-Ui ($script:workerKeys.Count -eq $keys) 'Reel skipped its resumed activation settling.'
    $script:schedulerClock.ElapsedMilliseconds=1400; Invoke-UnifiedTick 1400
    Assert-Ui ($script:workerKeys.Count -eq $keys+1 -and $script:workerKeys[-1] -eq "$($fishing.Process.Id):$($script:keyBindings.Reel.Code)" -and (Get-WowAutoCycleCount $script:scheduler $fishing.Key) -eq 1) 'Due reel was lost after combat or cycle state changed.'
    $script:schedulerClock.ElapsedMilliseconds=1401; Invoke-UnifiedTick 1401
    Assert-Ui ([WowAutoFight.Native]::Sends -eq $sends+1 -and $script:workerFocus -eq $fishing.Process.Id) 'Combat stole post-reel foreground hold.'
    Stop-AllRows
    $script:editingSettings=$true
    $dialog=New-UnifiedSettingsDialog
    try {
        $dialog.Show($form); [System.Windows.Forms.Application]::DoEvents()
        Assert-Ui ($dialog.Tag.Tabs.TabPages.Count -eq 3 -and $dialog.Tag.Tabs.TabPages[0].Text -eq '自动钓鱼' -and $dialog.Tag.Tabs.TabPages[1].Text -eq '自动战斗') 'Settings pages not combined.'
        $savedTarget=$script:autoFight.Common.TargetKey
        $dialog.Tag.Fight.Tag.CommonBindings.TargetKey.Text='Ctrl+Tab'
        $before=$script:versionRanges.titan.MinimumMs
        $dialog.Tag.Fish.Tag.Inputs.titan.Minimum.Value=$before+100
        $dialog.Tag.Fish.Tag.Inputs.titan.Maximum.Value=$before+200
        Assert-Ui ($script:versionRanges.titan.MinimumMs -eq $before -and $script:autoFight.Common.TargetKey -eq $savedTarget) 'Embedded drafts applied before save.'
        $dialog.Tag.Tabs.SelectedIndex=1; $dialog.Tag.Fight.Tag.Save.PerformClick()
        Assert-Ui ($script:autoFight.Common.TargetKey -eq 'Ctrl+Tab' -and $script:versionRanges.titan.MinimumMs -eq $before -and $dialog.Visible) 'Saving combat changed fishing or closed embedded page.'
        $dialog.Tag.Tabs.SelectedIndex=0; $dialog.Tag.Fish.Tag.Apply.PerformClick()
        Assert-Ui ($script:versionRanges.titan.MinimumMs -eq $before+100 -and $dialog.Visible) ('Embedded fishing save failed: '+$dialog.Tag.Fish.Tag.Error.Text+'; actual='+$script:versionRanges.titan.MinimumMs+'; before='+$before+'; visible='+$dialog.Visible)
        if ($env:WOWAUTO_UNIFIED_PREVIEW_DIRECTORY) {
            foreach ($preview in @(@('unified-main.png',$form),@('unified-settings-fish.png',$dialog))) {
                $bitmap=New-Object Drawing.Bitmap($preview[1].Width,$preview[1].Height)
                try {$preview[1].DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$bitmap.Width,$bitmap.Height))); $bitmap.Save((Join-Path $env:WOWAUTO_UNIFIED_PREVIEW_DIRECTORY $preview[0]),[Drawing.Imaging.ImageFormat]::Png)} finally {$bitmap.Dispose()}
            }
            $dialog.Tag.Tabs.SelectedIndex=1; [System.Windows.Forms.Application]::DoEvents()
            $bitmap=New-Object Drawing.Bitmap($dialog.Width,$dialog.Height)
            try {$dialog.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$bitmap.Width,$bitmap.Height))); $bitmap.Save((Join-Path $env:WOWAUTO_UNIFIED_PREVIEW_DIRECTORY 'unified-settings-fight.png'),[Drawing.Imaging.ImageFormat]::Png)} finally {$bitmap.Dispose()}
        }
    } finally {$dialog.Dispose(); $script:editingSettings=$false}
    $dialog=New-UnifiedSettingsDialog
    try {
        $dialog.Show($form)
        $before=$script:versionRanges.titan.MinimumMs; $target=$script:autoFight.Common.TargetKey
        $dialog.Tag.Fish.Tag.Inputs.titan.Minimum.Value=500
        $dialog.Tag.Fight.Tag.CommonBindings.TargetKey.Text='F11'
        $dialog.Tag.Tabs.SelectedIndex=1; $dialog.Tag.Fight.Tag.Cancel.PerformClick()
        Assert-Ui (-not $dialog.Visible -and $script:versionRanges.titan.MinimumMs -eq $before -and $script:autoFight.Common.TargetKey -eq $target -and -not $script:autoFight.Editing) 'Unified cancel applied draft or left scheduler paused.'
    } finally {$dialog.Dispose()}
    # Mode records obey the same all-or-nothing INI validation as other preferences.
    $validIni=[IO.File]::ReadAllText($script:settingsPath)
    try {
        foreach ($invalidMode in @('Mode_901_1=attack','Mode_901_1=FISH','Mode_2147483648_1=fish',
            'Mode_901_3155378976000000000=fish',"Mode_901_1=fish`r`nmode_901_1=fight")) {
            [IO.File]::WriteAllText($script:settingsPath,$validIni+"`r`n"+$invalidMode)
            $rejected=$false
            try {$null=Read-WowAutoSettingsIni $script:settingsPath} catch {$rejected=$true}
            Assert-Ui $rejected ('Invalid mode record accepted: '+$invalidMode)
        }
        $withoutModes=($validIni -split '\r?\n' | Where-Object {$_ -notmatch '^Mode_'}) -join "`r`n"
        [IO.File]::WriteAllText($script:settingsPath,$withoutModes)
        $oldHash=(Get-FileHash $script:settingsPath).Hash
        $legacy=Read-WowAutoSettingsIni $script:settingsPath
        Assert-Ui ($legacy.ProcessModePreferences.Count -eq 0 -and (Get-FileHash $script:settingsPath).Hash -eq $oldHash) 'Legacy mode-free INI was rejected or rewritten.'
    } finally {[IO.File]::WriteAllText($script:settingsPath,$validIni)}
    $plan=New-RotationPlan;$plan.Slots[0].Name='测试角色';$plan.Slots[0].Mode='fight'
    $plans=@{};$plans[$combat.Key]=$plan;Save-RotationConfiguration -Plans $plans
    $combat.Validated=$true;$combat.FightRow.CanStart=$true;Set-RowControls $combat
    Stop-Row $fishing;$fishing.Validated=$true;Set-RowControls $fishing
    $fishingStatus=$fishing.StatusMessage
    Finish-RefreshScan
    $scanRestore=@($script:gameActions.Events | Where-Object {$_.Id -eq 'restore'})[0]
    $script:restored=$false
    Add-GameAction -Id direct-isolation-restore -Kind Scan.Restore -Domain Restore -Key $fishing.Key -Row $fishing -Owner $script:scanGeneration -Due 999999 -Execute {param($event,$now)}
    $otherRestore=@($script:gameActions.Events | Where-Object {$_.Id -eq 'direct-isolation-restore'})[0]
    Assert-Ui ($combat.DirectStart.Enabled) 'Validated combat row cannot start directly with a saved role plan.'
    $combat.DirectStart.PerformClick()
    Assert-Ui ($combat.FightRow.Session -and -not $script:rotation.Active.ContainsKey($combat.Key) -and
        $script:rotation.LogoutQueue.Count -eq 0) 'Direct combat start entered role rotation.'
    Assert-Ui ($fishing.DirectStart.Enabled) 'Direct combat start disabled a different fishing process.'
    Assert-Ui ($script:gameActions.Events.Contains($otherRestore) -and -not $otherRestore.Cancelled -and
        $fishing.StatusMessage -eq $fishingStatus -and $fishing.Validated) 'Direct start removed another process restore or changed its validation/status.'
    Assert-Ui ($script:gameActions.Events.Contains($scanRestore)) 'Direct start cancelled the shared scan restore.'
    $null=Invoke-QueuedGameAction $scanRestore $script:schedulerClock.ElapsedMilliseconds
    Assert-Ui (-not $script:restored -and $combat.FightRow.Session -and $fishing.DirectStart.Enabled) 'A delayed scan restore changed foreground or controls after direct start.'
    $otherSession=$combat.FightRow.Session
    $otherSession.RecoveryReadyAt=98765L;$otherSession.BuffRemaining=2;$otherSession.NextJumpAt=123456L
    $otherPending=New-AutoFightPending $combat.FightRow $otherSession $false $script:schedulerClock.ElapsedMilliseconds
    $script:autoFight.Pending=$otherPending
    Add-GameAction -Id direct-isolation-combat -Kind Fight.Combat -Domain Fight -Key $combat.Key -Row $combat -Owner $otherSession -Due 999999 -Data ([pscustomobject]@{Row=$combat.FightRow;Action='combat'}) -Execute {param($event,$now)}
    $otherInput=@($script:gameActions.Events | Where-Object {$_.Id -eq 'direct-isolation-combat'})[0]
    $script:gameActions.Focus=$otherInput;$otherInput.ReadyAt=777L;$otherInput.FocusUntil=888L
    $sendsBeforeDirect=[WowAutoFight.Native]::Sends;$keysBeforeDirect=$script:workerKeys.Count
    $fishing.DirectStart.PerformClick()
    Assert-Ui ((Test-UnifiedTaskRunning $combat) -and (Test-UnifiedTaskRunning $fishing) -and
        $script:rotation.Active.Count -eq 0) 'Mixed-mode direct starts did not keep both tasks running without rotation.'
    Assert-Ui ([object]::ReferenceEquals($combat.FightRow.Session,$otherSession) -and
        [object]::ReferenceEquals($script:autoFight.Pending,$otherPending) -and
        [object]::ReferenceEquals($script:gameActions.Focus,$otherInput) -and $script:gameActions.Events.Contains($otherInput) -and
        $otherInput.ReadyAt -eq 777 -and $otherInput.FocusUntil -eq 888 -and
        $otherSession.RecoveryReadyAt -eq 98765 -and $otherSession.BuffRemaining -eq 2 -and $otherSession.NextJumpAt -eq 123456 -and
        [WowAutoFight.Native]::Sends -eq $sendsBeforeDirect -and $script:workerKeys.Count -eq $keysBeforeDirect) 'Direct fishing start changed another process pending input, focus, cooldown/buff/jump timers, or sent input.'
    $fishingSession=$fishing.State
    $fishing.Process | Add-Member NoteProperty LoginPointPresent $false -Force
    Start-RowDirect $fishing
    Assert-Ui ([object]::ReferenceEquals($fishing.State,$fishingSession) -and $fishingSession.Running -and
        [object]::ReferenceEquals($combat.FightRow.Session,$otherSession)) 'Repeated direct start restarted a running row or affected another process.'
    Stop-Row $fishing
    Start-RowDirect $fishing
    Assert-Ui (-not (Test-UnifiedTaskRunning $fishing) -and
        [object]::ReferenceEquals($combat.FightRow.Session,$otherSession) -and
        [object]::ReferenceEquals($script:autoFight.Pending,$otherPending) -and
        [object]::ReferenceEquals($script:gameActions.Focus,$otherInput) -and $script:gameActions.Events.Contains($otherInput) -and
        $otherSession.RecoveryReadyAt -eq 98765 -and -not $combat.DirectStart.Enabled -and $combat.Stop.Enabled) 'A failed direct start changed another process task, pending input, timers or buttons.'
    $fishing.Process.PSObject.Properties.Remove('LoginPointPresent')
    Stop-Row $combat
    # Same-process refresh/reconstruction remembers mode; PID reuse inherits neither mode nor task.
    $null=Refresh-ProcessRows
    Assert-Ui ($script:rows[$combat.Key].TaskMode -eq 'fight') 'Refresh lost process mode.'
    $script:autoFight.Rows.Remove($combat.Key); $script:rows.Remove($combat.Key); $combat.Panel.Dispose()
    $script:processModePreferences=@{}; Import-VersionWaitSettings; $null=Refresh-ProcessRows
    $combat=@($script:rows.Values | Where-Object {$_.Process.Id -eq 701})[0]
    Assert-Ui ($combat.TaskMode -eq 'fight' -and -not $combat.PSObject.Properties['ModeBox']) 'Restart did not restore persisted mode.'
    $oldKey=$combat.Key
    $combat.Process.StartTime=$combat.Process.StartTime.AddSeconds(1)
    $null=Refresh-ProcessRows
    $replacement=@($script:rows.Values | Where-Object {$_.Process.Id -eq 701})[0]
    Assert-Ui ($replacement.TaskMode -eq 'fish' -and -not $replacement.FightRow -and -not $script:autoFight.Rows.ContainsKey($oldKey)) 'Reused PID inherited mode/combat adapter.'
    Assert-Ui ((Get-FileHash $sourceIni).Hash -eq $iniHash -and (Get-FileHash $sourceFight).Hash -eq $fightHash) 'Unified tests changed user source configuration.'
    Write-Output 'PASS: unified process selector/settings tabs, mixed command-before-sample refresh, focus/command failure, independent direct-start buttons/tasks/queues/timers including repeated clicks and failed starts, delayed scan restore suppression, slot-mode refresh/reconstruction/PID reuse without a process mode selector and mixed-mode foreground/reel priority. All game input, pixels and audio mocked.'
} finally {
    Stop-AllRows; Close-AutoFightTab
    if ([IO.File]::Exists($script:rotation.Path)) {[IO.File]::Delete($script:rotation.Path)}
    $script:rotation.Path=$savedRotationPath;$script:rotation.Plans=$savedRotationPlans;$script:rotation.NameHistory=$savedRotationHistory
    if ([IO.File]::Exists($fightConfigPath)) {[IO.File]::Delete($fightConfigPath)}
}
