# Run only in wowAuto.ps1 -UiTest; captures and all window/input adapters are mocked.
Stop-AllRows
$audioCheck.Checked=$true
$savedAudioClock=$script:schedulerClock
$savedAudioRanges=$script:versionRanges
$script:schedulerClock=[pscustomobject]@{ElapsedMilliseconds=0L}
try {
    $script:scheduler=New-WowAutoScheduler
    Set-VersionWaitRanges 300 300 600 600 -Persist $false
    $audioRows=@($script:rows.Values | Sort-Object { $_.Process.Id })
    $a=@($audioRows | Where-Object { $_.Client.Flavor -eq 'titan' })[0]
    $b=@($audioRows | Where-Object { $_.Client.Flavor -eq 'forerver' })[0]
    foreach ($row in @($a,$b)) {
        $row.Validated=$true; $row.Exited=$false; $row.Process.HasExited=$false
        $row.Process.FocusAllowed=$true; $row.Process.ScanColor='green'; $row.ItemCheck.Checked=$false
        Start-Row $row
    }
    $ca=$script:audioCaptures[$a.Key].Capture; $cb=$script:audioCaptures[$b.Key].Capture
    $script:workerKeys=@(); $script:workerFocus=$a.Process.Id
    Invoke-SchedulerTick 0; Invoke-SchedulerTick 25; Invoke-SchedulerTick 225; Invoke-SchedulerTick 250
    Assert-Ui ($a.State.UseAudio -and $b.State.UseAudio -and $ca.Session -gt 0 -and $cb.Session -gt 0) 'Audio captures did not arm per row.'
    Assert-Ui ($script:workerKeys.Count -eq 0 -and @($script:scheduler.Events | Where-Object Kind -eq 'Reel').Count -eq 0) 'Green sent an unsolicited reel.'
    Update-RowStatus $a; $timestamp=$a.StatusTimestamp
    $ca.Peak=0.12; Update-RowStatus $a
    Assert-Ui ($a.StatusTimestamp -eq $timestamp -and $a.CurrentStatusText -match '12%') 'Audio peak changes refreshed the state timestamp.'
    $ca.Bite=$ca.Session
    $script:scheduler.ItemHoldUntil=4000
    Invoke-SchedulerTick 3000
    Assert-Ui ($script:workerKeys.Count -eq 0 -and $ca.Session -eq 0 -and $cb.Session -eq 0) 'Item hold did not suppress audio/casting/reels.'
    Invoke-SchedulerTick 4000 # Re-arm; no old hold-period noise survives.
    $cb.Bite=$cb.Session
    $script:scheduler.ReelHoldUntil=6300
    Invoke-SchedulerTick 5500
    Assert-Ui ($script:workerKeys.Count -eq 0 -and $b.State.AudioReelPending -and $b.State.Deadline -eq 6100) 'Audio failed to queue a delayed reel or interrupted the hold.'
    $script:schedulerClock.ElapsedMilliseconds=5500; Update-RowStatus $b; $delayStamp=$b.StatusTimestamp
    $script:schedulerClock.ElapsedMilliseconds=5501; Update-RowStatus $b
    Assert-Ui ($b.CurrentStatusText -match '收竿等待：剩余 599 ms' -and $b.CurrentStatusText -notmatch '无咬钩超时保护' -and
        $b.StatusTimestamp -eq $delayStamp) 'Audio delay status used the no-signal label or refreshed its timestamp during countdown.'
    $script:schedulerClock.ElapsedMilliseconds=0
    Invoke-SchedulerTick 6000
    Assert-Ui ($script:workerKeys.Count -eq 0 -and $cb.Session -eq 0) 'Post-match delay emitted input early or left the listener armed.'
    Invoke-SchedulerTick 6100
    Assert-Ui ($script:workerKeys.Count -eq 0) 'Due audio reel interrupted the existing hold.'
    Invoke-SchedulerTick 6300
    Assert-Ui ($script:workerKeys[-1] -eq "$($b.Process.Id):187" -and (Get-WowAutoCycleCount $script:scheduler $b.Key) -eq 1) 'Audio signal did not target its own PID.'
    Stop-Row $b
    $captureBefore=$ca
    $retiredSession=$a.State.AudioSession
    Stop-Row $a
    Assert-Ui ($captureBefore.Disposed -and -not $script:audioCaptures.ContainsKey($a.Key)) 'Stop leaked a capture.'
    Start-Row $a; $script:workerFocus=$a.Process.Id
    Invoke-SchedulerTick 7000; Invoke-SchedulerTick 7025
    $current=$script:audioCaptures[$a.Key].Capture
    $timeoutDeadline=$a.State.Deadline
    Set-VersionWaitRanges 400 400 700 700 -Persist $false
    Assert-Ui ($a.State.MinimumMs -eq 400 -and $a.State.Deadline -eq $timeoutDeadline) 'Runtime range update ignored the active audio row or rewrote the no-signal timeout.'
    $keyCount=$script:workerKeys.Count
    $current.Bite=$retiredSession
    Invoke-SchedulerTick 9000
    Assert-Ui ($script:workerKeys.Count -eq $keyCount) 'Restart accepted a retired capture event.'
    $current.Bite=$current.Session; $a.Process.ScanColor='red'
    Invoke-SchedulerTick 10000
    Assert-Ui ($script:workerKeys.Count -eq $keyCount -and $a.State.AudioReelPending -and $a.State.Deadline -eq 10400) 'Next signal ignored the updated delay range or reeled immediately.'
    Invoke-SchedulerTick 10399
    Assert-Ui ($script:workerKeys.Count -eq $keyCount -and $a.State.Mode -eq 'Wait') 'Idle signal was acted on before its delay.'
    Invoke-SchedulerTick 10400
    Assert-Ui ($script:workerKeys.Count -eq $keyCount -and $a.State.Mode -eq 'Ready') 'Audio signal reeled outside fishing state.'
    $current.Status='Error'; $current.Error='mock capture failure'
    Invoke-SchedulerTick 11000
    Assert-Ui (-not $a.State.Running -and $a.CurrentStatusText -match 'mock capture failure' -and -not $script:audioCaptures.ContainsKey($a.Key)) 'Capture failure lacked cleanup/status.'
    $a.Process.ScanColor='green'; $a.Validated=$true
    Start-Row $a
    Invoke-SchedulerTick 12000; Invoke-SchedulerTick 12025
    $cyclesBefore=Get-WowAutoCycleCount $script:scheduler $a.Key
    $keyCount=$script:workerKeys.Count
    Invoke-SchedulerTick $a.State.Deadline
    Assert-Ui ($a.State.Mode -eq 'Ready' -and $a.State.ForceNextCast -and $script:workerKeys.Count -eq $keyCount -and
        (Get-WowAutoCycleCount $script:scheduler $a.Key) -eq $cyclesBefore) 'Audio timeout sent/counted a reel.'
    Stop-Row $a; Start-Row $a
    Invoke-SchedulerTick 50000; Invoke-SchedulerTick 50025
    $current=$script:audioCaptures[$a.Key].Capture; $current.Bite=$current.Session
    $a.Process.ScanColor='gray'
    Invoke-SchedulerTick 52000
    Invoke-SchedulerTick 52400
    Assert-Ui (-not $a.State.Running -and $current.Disposed -and $script:workerKeys.Count -eq $keyCount) 'Disabled monitor allowed an audio reel or leaked its capture.'
    $a.Process.ScanColor='green'; Start-Row $a
    $current=$script:audioCaptures[$a.Key].Capture; $current.Status='Starting'
    Invoke-SchedulerTick 60000
    Assert-Ui ($a.State.Running -and -not $a.State.AudioReady -and $script:workerKeys.Count -eq $keyCount) 'Audio startup gate was bypassed.'
    $current.Status='Error'; $current.Error='mock initialization failure'
    Invoke-SchedulerTick 60100
    Assert-Ui (-not $a.State.Running -and $current.Disposed -and $a.CurrentStatusText -match 'mock initialization failure') 'Startup failure did not stop and report.'
    Stop-AllRows
    Assert-Ui ($cb.Disposed -and $script:audioCaptures.Count -eq 0 -and $script:scheduler.Events.Count -eq 0) 'Stop all leaked listeners or events.'
}
finally {
    Stop-AllRows; $audioCheck.Checked=$false; $script:schedulerClock=$savedAudioClock
    Set-VersionWaitRanges $savedAudioRanges.titan.MinimumMs $savedAudioRanges.titan.MaximumMs $savedAudioRanges.forerver.MinimumMs $savedAudioRanges.forerver.MaximumMs -Persist $false
}
Write-Output 'PASS: mocked per-PID capture startup/arming, post-match version delays/live updates/stable countdowns, no early input, item suppression, reel hold/priority, targeted input, stale/idle signal rejection, failure status and listener cleanup.'
