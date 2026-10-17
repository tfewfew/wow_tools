# Exercise production restart requests with mock process launch/window close only.
Stop-AllRows
$savedRestart=@{Close=${function:Close-WowAutoForRestart};Error=${function:Show-WowAutoRestartError};Options=${function:Get-WowAutoRestartOptions};
    Start=(Get-Item -LiteralPath Function:Start-Process -ErrorAction SilentlyContinue);Requested=$script:restartRequested;
    Clean=$script:restartCleanupComplete;LaunchOptions=$script:restartOptions}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-restart-'+[guid]::NewGuid()+' with spaces')
$script:restartTestEvents=New-Object Collections.ArrayList
$script:restartTestLaunches=New-Object Collections.ArrayList
$script:restartTestError='';$script:restartTestCloseFails=$false;$script:restartTestLaunchFails=$false
$sourceHashes=@{}
foreach ($name in @('config.ini','autoFight.config.json','rotation.config.json')) {
    $path=Join-Path (Split-Path $PSScriptRoot -Parent) $name;$sourceHashes[$path]=(Get-FileHash $path).Hash
}
function Close-WowAutoForRestart {
    [void]$script:restartTestEvents.Add('close')
    if ($script:restartTestCloseFails) {throw 'mock close failure'}
}
function Show-WowAutoRestartError([string]$Message) {$script:restartTestError=$Message}
function Start-Process {
    [CmdletBinding()]param([string]$FilePath,[string[]]$ArgumentList,[string]$WorkingDirectory,[string]$WindowStyle)
    [void]$script:restartTestEvents.Add('launch')
    [void]$script:restartTestLaunches.Add([pscustomobject]@{FilePath=$FilePath;Arguments=$ArgumentList;Directory=$WorkingDirectory;Style=$WindowStyle})
    if ($script:restartTestLaunchFails) {throw 'mock launch failure'}
}
try {
    [void][IO.Directory]::CreateDirectory($fixture)
    $entry=Join-Path $fixture 'wowAuto.ps1';[IO.File]::WriteAllText($entry,'# Mock entry; never executed.')
    $options=Get-WowAutoRestartOptions $entry
    Assert-Ui ($options.WindowStyle -eq 'Hidden' -and $options.WorkingDirectory -eq $fixture -and
        $options.ArgumentList[-1] -ceq ('"'+$entry+'"') -and $options.ArgumentList -contains '-STA' -and
        $options.ArgumentList -contains '-NoProfile' -and $options.ArgumentList -notcontains '-UiTest') 'Restart arguments lost quoting, STA/hidden settings or entered test mode.'
    $script:restartRequested=$false;$script:restartCleanupComplete=$true;Restart-WowAutoIfRequested
    Assert-Ui ($script:restartTestLaunches.Count -eq 0) 'Ordinary close launched a replacement.'
    $script:restartCleanupComplete=$false
    $script:editingSettings=$true;Update-BatchControls;Request-WowAutoRestart
    Assert-Ui (-not $restartButton.Enabled -and -not $script:restartRequested -and $script:restartTestEvents.Count -eq 0) 'Restart interrupted an open settings dialog.'
    $script:editingSettings=$false;Update-BatchControls
    $row=@($script:rows.Values)[0];Set-RowTaskMode $row fish
    $row.State=Add-WowAutoTask $script:scheduler $row.Key 1000 1000 $script:schedulerClock.ElapsedMilliseconds
    $capture=[pscustomobject]@{Disposed=$false}
    $capture | Add-Member ScriptMethod Dispose {$this.Disposed=$true;[void]$script:restartTestEvents.Add('capture-dispose')}
    $script:audioCaptures[$row.Key]=[pscustomobject]@{Capture=$capture}
    $script:pendingGameExits[$row.Key]=[pscustomobject]@{Row=$row}
    Add-GameAction -Id restart-mock -Kind Scan.Observe -Domain Test -Due 0 -Execute {throw 'Cancelled action was executed.'}
    $closed=$script:workerClosed.Count;$killed=$script:workerKilled.Count;$keys=$script:workerKeys.Count
    $restartButton.PerformClick()
    Assert-Ui ($script:restartRequested -and -not $restartButton.Enabled -and -not $row.State.Running -and
        $capture.Disposed -and $script:audioCaptures.Count -eq 0 -and $script:pendingGameExits.Count -eq 0 -and
        $script:gameActions.Events.Count -eq 0 -and ($script:restartTestEvents -join ',') -eq 'capture-dispose,close') 'Restart did not stop tasks/captures/exits/queued input before requesting close.'
    Request-WowAutoRestart;Restart-WowAutoIfRequested
    Assert-Ui ($script:restartTestLaunches.Count -eq 0 -and $script:restartTestEvents.Count -eq 2) 'Repeat click or incomplete cleanup launched/repeated restart.'
    $script:restartCleanupComplete=$true;Restart-WowAutoIfRequested;Restart-WowAutoIfRequested
    Assert-Ui ($script:restartTestLaunches.Count -eq 1 -and -not $script:restartRequested -and
        $script:restartTestLaunches[0].Style -eq 'Hidden' -and ($script:restartTestEvents -join ',') -eq 'capture-dispose,close,launch' -and
        $script:workerClosed.Count -eq $closed -and $script:workerKilled.Count -eq $killed -and $script:workerKeys.Count -eq $keys) 'Restart launched twice, preceded cleanup or operated on game processes/input.'
    $script:restartCleanupComplete=$false;Update-BatchControls
    Begin-RefreshScan
    Assert-Ui $script:scanning 'Refresh fixture did not start.'
    $restartButton.PerformClick()
    Assert-Ui (-not $script:scanning -and $script:gameActions.Events.Count -eq 0 -and $script:restartRequested) 'Restart could not cancel a refresh or left a restore callback queued.'
    $script:restartRequested=$false;Update-BatchControls
    $row=@($script:rows.Values)[0]
    $row.State=Add-WowAutoTask $script:scheduler $row.Key 1000 1000 $script:schedulerClock.ElapsedMilliseconds
    function Get-WowAutoRestartOptions {throw 'mock missing entry'}
    $restartButton.PerformClick()
    Assert-Ui ($row.State.Running -and -not $script:restartRequested -and $restartButton.Enabled -and $countLabel.Text -match 'mock missing entry') 'Failed preflight stopped a task or locked the restart control.'
    ${function:Get-WowAutoRestartOptions}=$savedRestart.Options
    $script:restartTestCloseFails=$true;$restartButton.PerformClick()
    Assert-Ui (-not $script:restartRequested -and $restartButton.Enabled -and $countLabel.Text -match 'mock close failure') 'Failed window close left restart locked.'
    $script:restartTestCloseFails=$false;$script:restartTestLaunchFails=$true
    $script:restartRequested=$true;$script:restartCleanupComplete=$true;$script:restartOptions=$options
    Restart-WowAutoIfRequested
    Assert-Ui ($script:restartTestError -match 'mock launch failure' -and -not $script:restartRequested) 'Launch failure did not report a manual restart path.'
    foreach ($path in $sourceHashes.Keys) {Assert-Ui ((Get-FileHash $path).Hash -eq $sourceHashes[$path]) 'Restart changed saved user configuration.'}
    Write-Output 'PASS: restart button layout/settings gate, normal-close isolation, task/audio/exit/queue cancellation, refresh cancellation, cleanup-before-launch, duplicate protection, quoted hidden STA launch and preflight/close/launch failure handling. Window close and process launch mocked; no game input.'
} finally {
    $script:editingSettings=$false;$script:restartRequested=$savedRestart.Requested;$script:restartCleanupComplete=$savedRestart.Clean;$script:restartOptions=$savedRestart.LaunchOptions
    ${function:Close-WowAutoForRestart}=$savedRestart.Close;${function:Show-WowAutoRestartError}=$savedRestart.Error;${function:Get-WowAutoRestartOptions}=$savedRestart.Options
    if ($savedRestart.Start) {${function:Start-Process}=$savedRestart.Start.ScriptBlock} else {Remove-Item -LiteralPath Function:Start-Process}
    Stop-AllRows
    if ([IO.File]::Exists((Join-Path $fixture 'wowAuto.ps1'))) {[IO.File]::Delete((Join-Path $fixture 'wowAuto.ps1'))}
    if ([IO.Directory]::Exists($fixture)) {[IO.Directory]::Delete($fixture)}
}
