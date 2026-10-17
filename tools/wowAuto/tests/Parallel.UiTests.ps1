function Assert-Parallel($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Pump-Parallel([scriptblock]$Until,[int]$Timeout=6000) {
    $deadline=$script:parallelHub.Now+$Timeout
    do {
        [Windows.Forms.Application]::DoEvents();Update-ParallelMessages
        if(& $Until){return};[Threading.Thread]::Sleep(10)
    }while($script:parallelHub.Now -lt $deadline)
    throw ('Parallel UI timed out; '+(($script:rows.Values | ForEach-Object {$_.Process.Id.ToString()+': '+$_.StatusMessage}) -join '; '))
}
$rows=@($script:rows.Values | Sort-Object {$_.Process.Id});$a=$rows[0];$b=$rows[1];$c=$rows[2]
$script:autoFight.Profiles['forerver:1'].BuffIntervalSeconds=0;$script:autoFight.Common.JumpIntervalSeconds=0
Assert-Parallel ($rows.Count -eq 3 -and $script:parallelWorkers.Count -eq 3) 'Each process must have one detector runspace.'
foreach($row in $rows) {
    Assert-Parallel ($row.AccountBox.Parent -eq $row.Panel -and -not $row.PSObject.Properties['RotationButton'] -and @(Get-AccountTaskRoles $row).Count -eq 4) 'Account binding missing or process slots still limit roles.'
    Assert-Parallel ($row.Status.Bottom -eq $row.Panel.ClientSize.Height) 'Status lost bottom alignment.'
}
$dialog=New-UnifiedSettingsDialog
try {
    $dialog.Show($form);$dialog.Tag.Tabs.SelectedTab=$dialog.Tag.Accounts;[Windows.Forms.Application]::DoEvents()
    Assert-Parallel ($dialog.Tag.Tabs.TabPages.Count -eq 4 -and $dialog.Tag.Accounts.Tag.Grid.Rows.Count -eq 4 -and $script:parallelHub.Paused) 'Account settings tab or runtime pause is missing.'
    $editor=$dialog.Tag.Accounts.Tag;$before=(Get-FileHash $script:accountTasks.Path).Hash
    $editor.Grid.Rows[0].Cells['Enabled'].Value=$false
    Assert-Parallel ($script:accountTasks.Config.Accounts[$editor.Selected][0].Enabled) 'Role draft applied before save.'
    if($env:WOWAUTO_PARALLEL_PREVIEW){$bitmap=New-Object Drawing.Bitmap($dialog.Width,$dialog.Height);try{$dialog.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$bitmap.Width,$bitmap.Height)));$bitmap.Save((Join-Path $env:WOWAUTO_PARALLEL_PREVIEW 'account-settings.png'))}finally{$bitmap.Dispose()}}
}finally{$dialog.Dispose()}
Assert-Parallel ((Get-FileHash $script:accountTasks.Path).Hash -eq $before -and -not $script:parallelHub.Paused) 'Cancel changed account tasks or left workers paused.'
$dialog=New-UnifiedSettingsDialog
try {
    $dialog.Show($form);$dialog.Tag.Tabs.SelectedTab=$dialog.Tag.Accounts;[Windows.Forms.Application]::DoEvents()
    $editor=$dialog.Tag.Accounts.Tag;$editor.Accounts.SelectedItem='titan:ACCOUNT-A'
    $editor.Grid.Rows[3].Cells['Enabled'].Value=$false;$editor.Periods.OcrMs.Value=50
    $locked=[IO.File]::Open($script:accountTasks.Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try{$editor.Save.PerformClick()}finally{$locked.Dispose()}
    Assert-Parallel ($script:accountTasks.Config.Accounts['titan:ACCOUNT-A'][3].Enabled -and $script:accountTasks.Config.Periods.OcrMs -eq 25 -and (Get-FileHash $script:accountTasks.Path).Hash -eq $before) 'Locked save partly applied account tasks or periods.'
    $editor.Save.PerformClick()
    Assert-Parallel (-not $script:accountTasks.Config.Accounts['titan:ACCOUNT-A'][3].Enabled -and $script:accountTasks.Config.Periods.OcrMs -eq 50) 'Account tasks/periods did not save together.'
    $editor.Grid.Rows[3].Cells['Enabled'].Value=$true;$editor.Accounts.SelectedItem='titan:ACCOUNT-B'
    Assert-Parallel (-not $script:accountTasks.Config.Accounts['titan:ACCOUNT-A'][3].Enabled) 'Further edits after Save shared the active configuration object.'
    $editor.Accounts.SelectedItem='titan:ACCOUNT-A';$editor.Periods.OcrMs.Value=25;$editor.Save.PerformClick()
}finally{$dialog.Dispose()}
$refreshButton.PerformClick();Pump-Parallel {-not $script:scanning}
Assert-Parallel (@($rows | Where-Object Validated).Count -eq 3) 'Independent scan/operation acknowledgements did not validate every row.'
$startAllButton.PerformClick()
Pump-Parallel {[ParallelFixture]::Ocr[101] -eq 1 -and [ParallelFixture]::Ocr[202] -gt 0} 2000
Assert-Parallel ([ParallelFixture]::Clicks -eq 0) 'A process clicked before all OCR positions were ready.'
Pump-Parallel {@($rows | Where-Object {$_.CurrentRole -eq '角色甲'}).Count -eq 3}
Assert-Parallel ([ParallelFixture]::EarlyOcr -eq 0 -and [ParallelFixture]::EarlyClicks -eq 0) 'Logout/position barriers were broken.'
Assert-Parallel (@([ParallelFixture]::ReadThread.Values | Sort-Object -Unique).Count -eq 3 -and @([ParallelFixture]::OpThread.Values | Sort-Object -Unique).Count -eq 1) 'Detection is not per-process or operations are not serialized.'
foreach($id in @(101,202,303)){Assert-Parallel ([ParallelFixture]::ReadThread[$id] -eq [ParallelFixture]::OcrThread[$id]) 'OCR ran outside its detector thread.'}
Assert-Parallel (-not ([Threading.Thread]::CurrentThread.ManagedThreadId -in [ParallelFixture]::ReadThread.Values)) 'UI thread performed detection.'
[ParallelFixture]::BlockPid=101;[ParallelFixture]::Release.Reset()
Pump-Parallel {[ParallelFixture]::BlockedPid -eq 101}
$readsA=[ParallelFixture]::Reads[101];$readsB=[ParallelFixture]::Reads[202]
[Threading.Thread]::Sleep(160);Update-ParallelMessages
Assert-Parallel ([ParallelFixture]::Reads[101] -eq $readsA -and [ParallelFixture]::Reads[202] -gt $readsB) 'A waiting operation did not pause only its own detector.'
$actionsA=[ParallelFixture]::Actions[101];$a.Stop.PerformClick();[Threading.Thread]::Sleep(80);[ParallelFixture]::Release.Set();[ParallelFixture]::BlockPid=0
Pump-Parallel {-not $a.RuntimeRunning}
Assert-Parallel ([ParallelFixture]::Actions[101] -eq $actionsA -and $b.RuntimeRunning -and $c.RuntimeRunning) 'Stop allowed a stale operation or stopped another process.'
$a.Validated=$true;Set-RowControls $a;[ParallelFixture]::FailFocusPid=101;$a.DirectStart.PerformClick()
Pump-Parallel {$a.Status.Text -match '继续后台检测'}
$reads=[ParallelFixture]::Reads[101];[Threading.Thread]::Sleep(180);Update-ParallelMessages
Assert-Parallel ([ParallelFixture]::Reads[101] -gt $reads -and $a.RuntimeRunning) 'Focus retry paused detection/death checks instead of only input.'
Stop-AllRows;Pump-Parallel {@($rows | Where-Object RuntimeRunning).Count -eq 0}
$startAllButton.PerformClick();Pump-Parallel {@($rows | Where-Object {$_.CurrentRole -eq '角色甲'}).Count -eq 3}
foreach($expected in @('角色乙','角色丙','角色丁','角色甲')) {
    $script:parallelNextAt=$script:parallelHub.Now
    Pump-Parallel {@($rows | Where-Object {$_.CurrentRole -eq $expected}).Count -eq 3}
}
Assert-Parallel ($a.RotationSwitchCount -ge 4 -and $b.RotationSwitchCount -ge 4) 'Main-thread global rotation did not cycle through all four account roles.'
Stop-AllRows;Pump-Parallel {@($rows | Where-Object RuntimeRunning).Count -eq 0}
$beforeA=$a.ExecutionRound;$beforeB=$b.ExecutionRound
$a.Validated=$true;$b.Validated=$true;Set-RowControls $a;Set-RowControls $b;$a.DirectStart.PerformClick();$b.DirectStart.PerformClick()
Pump-Parallel {$a.ExecutionRound -gt $beforeA -and $b.ExecutionRound -gt $beforeB}
Assert-Parallel ($a.RuntimeDirect -and $b.RuntimeDirect) 'Direct start did not remain independent.'
if($env:WOWAUTO_PARALLEL_PREVIEW){$bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height);try{$form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$bitmap.Width,$bitmap.Height)));$bitmap.Save((Join-Path $env:WOWAUTO_PARALLEL_PREVIEW 'parallel-main.png'))}finally{$bitmap.Dispose()}}
Stop-AllRows;Set-VersionWaitRanges 25 25 25 25 -Persist $false -JumpEveryCycles 1
[ParallelFixture]::AutoFish=$true;$a.Validated=$true;Set-RowControls $a;$a.DirectStart.PerformClick()
Pump-Parallel {[ParallelFixture]::Reels -eq 1 -and $a.CycleCount -eq 1}
$a.Stop.PerformClick();Assert-Parallel ([ParallelFixture]::Jumps -eq 0) 'Jump interrupted the first reel cooldown.'
$a.DirectStart.PerformClick();Pump-Parallel {[ParallelFixture]::Reels -ge 2}
Assert-Parallel ([ParallelFixture]::Jumps -eq 0) 'Inherited jump request executed before the new successful reel finished its cooldown.'
Pump-Parallel {[ParallelFixture]::Jumps -eq 1}
Assert-Parallel ([ParallelFixture]::EarlyJumps -eq 0 -and [ParallelFixture]::Reels -ge 2) 'Cycle jump did not wait for a successful reel and full cooldown.'
[ParallelFixture]::AutoFish=$false;[ParallelFixture]::Colors[101]='red'
Stop-AllRows;$startAllButton.PerformClick();Pump-Parallel {@($rows | Where-Object {$_.CurrentRole -eq '角色甲'}).Count -eq 3}
$configurationHash=(Get-FileHash $script:accountTasks.Path).Hash
[ParallelFixture]::Colors[101]='dead'
Pump-Parallel {$a.Exited} 10000
Assert-Parallel ($a.ExcludedNames.Count -eq 4 -and [ParallelFixture]::ExitRequests -eq 1 -and $b.RuntimeRunning -and $c.RuntimeRunning -and (Get-FileHash $script:accountTasks.Path).Hash -eq $configurationHash) 'Death exclusion did not exhaust only its own account role cycle without editing settings.'
Stop-AllRows;[ParallelFixture]::MissingPid=202;$b.Start.PerformClick()
Pump-Parallel {$b.Exited} 12000
Assert-Parallel ([ParallelFixture]::UpCount -eq 30 -and [ParallelFixture]::ExitRequests -eq 2 -and [ParallelFixture]::KillRequests -eq 0) 'Missing-name retries were not one arrow/one OCR exactly thirty times before normal exit.'
Stop-AllRows;Update-WowAutoRunInfo
$info=[IO.File]::ReadAllText($script:wowAutoLog.InfoPath) | ConvertFrom-Json
Assert-Parallel ($info.ProcessCount -eq 3 -and $info.Processes[0].Roles.Count -eq 4 -and -not $info.Processes[0].PSObject.Properties['Slots']) 'Info snapshot still describes three process slots.'
$log=@([IO.File]::ReadAllLines($script:wowAutoLog.LogPath) | ForEach-Object {$_ | ConvertFrom-Json})
Assert-Parallel (@($log | Where-Object {$_.Kind -eq 'status' -and $_.Pid -and $_.ThreadId -in [ParallelFixture]::ReadThread.Values}).Count -gt 0) 'Detection threads did not write PID-associated logs.'
Write-Output 'PASS: per-process detector/OCR threads, one operator, request acknowledgement pauses only its detector, parallel OCR/batch barriers, cancellation isolation, independent direct starts, atomic account tasks/periods settings, global four-role wraparound, death exhaustion isolated to one process, exactly thirty arrow/OCR retries, UI-only updates and PID/thread logs. All frames/OCR/inputs/process exits are substitutes.'
${function:Get-WowAutoRestartOptions}={return @{FilePath='mock-wowAuto-restart';WorkingDirectory=$PSScriptRoot;WindowStyle='Hidden';ErrorAction='Stop';ArgumentList=@()}}
${function:Show-WowAutoRestartError}={param([string]$Message) [ParallelFixture]::RestartError=$Message}
function global:Start-Process([string]$FilePath,[string]$WorkingDirectory,[string]$WindowStyle,[string[]]$ArgumentList,[string]$ErrorAction) {
    Assert-Parallel ($script:restartCleanupComplete -and $script:parallelHub.Closing -and $script:parallelWorkers.Count -eq 0 -and $script:parallelOperator.Async.IsCompleted) 'Restart launched before the worker/operator cleanup barrier.'
    [ParallelFixture]::RestartLaunched=$true
}
$before=$c.ExecutionRound;$c.Validated=$true;Set-RowControls $c;$c.DirectStart.PerformClick();Pump-Parallel {$c.ExecutionRound -gt $before}
[ParallelFixture]::BlockPid=303;[ParallelFixture]::Release.Reset();Pump-Parallel {[ParallelFixture]::BlockedPid -eq 303}
Request-WowAutoRestart
if(-not $script:restartRequested){[ParallelFixture]::RestartError='Restart request rejected: '+$countLabel.Text}
