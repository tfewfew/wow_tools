# Run only in wowAuto.ps1 -UiTest; captures and all window/input adapters are mocked.
Stop-AllRows
$audioCheck.Checked=$true
$savedAudioClock=$script:schedulerClock
$script:schedulerClock=[pscustomobject]@{ElapsedMilliseconds=0L}
try {
    $script:scheduler=New-WowAutoScheduler
    $audioRows=@($script:rows.Values | Sort-Object { $_.Process.Id })
    $a=$audioRows[0]; $b=$audioRows[1]
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
    Assert-Ui ($a.StatusTimestamp -eq $timestamp -and $a.Status.Text -match '12%') 'Audio peak changes refreshed the state timestamp.'
    $ca.Bite=$ca.Session
    $script:scheduler.ItemHoldUntil=4000
    Invoke-SchedulerTick 3000
    Assert-Ui ($script:workerKeys.Count -eq 0 -and $ca.Session -eq 0 -and $cb.Session -eq 0) 'Item hold did not suppress audio/casting/reels.'
    Invoke-SchedulerTick 4000 # Re-arm; no old hold-period noise survives.
    $cb.Bite=$cb.Session
    $script:scheduler.ReelHoldUntil=6000
    Invoke-SchedulerTick 5500
    Assert-Ui ($script:workerKeys.Count -eq 0 -and $b.State.Deadline -eq 5500) 'Audio failed to queue a held reel or interrupted the hold.'
    Invoke-SchedulerTick 6000
    Assert-Ui ($script:workerKeys[-1] -eq "$($b.Process.Id):187" -and (Get-WowAutoCycleCount $script:scheduler $b.Key) -eq 1) 'Audio signal did not target its own PID.'
    Stop-Row $b
    $captureBefore=$ca
    $retiredSession=$a.State.AudioSession
    Stop-Row $a
    Assert-Ui ($captureBefore.Disposed -and -not $script:audioCaptures.ContainsKey($a.Key)) 'Stop leaked a capture.'
    Start-Row $a; $script:workerFocus=$a.Process.Id
    Invoke-SchedulerTick 7000; Invoke-SchedulerTick 7025
    $current=$script:audioCaptures[$a.Key].Capture
    $keyCount=$script:workerKeys.Count
    $current.Bite=$retiredSession
    Invoke-SchedulerTick 9000
    Assert-Ui ($script:workerKeys.Count -eq $keyCount) 'Restart accepted a retired capture event.'
    $current.Bite=$current.Session; $a.Process.ScanColor='red'
    Invoke-SchedulerTick 10000
    Assert-Ui ($script:workerKeys.Count -eq $keyCount -and $a.State.Mode -eq 'Ready') 'Audio signal reeled outside fishing state.'
    $current.Status='Error'; $current.Error='mock capture failure'
    Invoke-SchedulerTick 11000
    Assert-Ui (-not $a.State.Running -and $a.Status.Text -match 'mock capture failure' -and -not $script:audioCaptures.ContainsKey($a.Key)) 'Capture failure lacked cleanup/status.'
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
    Assert-Ui (-not $a.State.Running -and $current.Disposed -and $script:workerKeys.Count -eq $keyCount) 'Disabled monitor allowed an audio reel or leaked its capture.'
    $a.Process.ScanColor='green'; Start-Row $a
    $current=$script:audioCaptures[$a.Key].Capture; $current.Status='Starting'
    Invoke-SchedulerTick 60000
    Assert-Ui ($a.State.Running -and -not $a.State.AudioReady -and $script:workerKeys.Count -eq $keyCount) 'Audio startup gate was bypassed.'
    $current.Status='Error'; $current.Error='mock initialization failure'
    Invoke-SchedulerTick 60100
    Assert-Ui (-not $a.State.Running -and $current.Disposed -and $a.Status.Text -match 'mock initialization failure') 'Startup failure did not stop and report.'
    Stop-AllRows
    Assert-Ui ($cb.Disposed -and $script:audioCaptures.Count -eq 0 -and $script:scheduler.Events.Count -eq 0) 'Stop all leaked listeners or events.'
}
finally { Stop-AllRows; $audioCheck.Checked=$false; $script:schedulerClock=$savedAudioClock }
Write-Output 'PASS: mocked per-PID capture startup/arming, no timed reels, item suppression, reel hold/priority, targeted input, stale/idle signal rejection, failure status and listener cleanup.'
