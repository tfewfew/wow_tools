# Exercise production expiry/queue submission against the parallel input substitutes.
$savedShutdownClose=${function:Close-WowAutoAfterShutdown}
$savedShutdownProcesses=@($script:mockProcesses)
$script:shutdownParallelCloses=0
function Close-WowAutoAfterShutdown {
    Assert-Parallel (@($script:shutdownState.Operations | Where-Object {-not $_.Done.IsSet -or -not $_.Success}).Count -eq 0) 'Script closed before all game exit requests completed.'
    $script:shutdownParallelCloses++
}
try {
    Stop-AllRows
    $extra=$script:mockProcesses[0].PSObject.Copy();$extra.Id=404;$extra.HasExited=$false
    $script:mockProcesses+=,$extra;[ParallelFixture]::World[404]=1
    $before=$c.ExecutionRound;$c.Validated=$true;Set-RowControls $c;$c.DirectStart.PerformClick()
    Pump-Parallel {$c.ExecutionRound -gt $before}
    [ParallelFixture]::BlockPid=303;[ParallelFixture]::Release.Reset()
    Pump-Parallel {[ParallelFixture]::BlockedPid -eq 303}
    $beforeRequests=[ParallelFixture]::ShutdownRequests
    Set-WowAutoShutdownCountdown 1 1000
    # An open settings window must not leave the shutdown queue paused.
    $script:parallelHub.Paused=$true
    Invoke-WowAutoShutdownTick 2000
    Pump-Parallel {Invoke-WowAutoShutdownTick 2500;$script:shutdownParallelCloses -eq 1}
    Assert-Parallel ([ParallelFixture]::ShutdownRequests -eq $beforeRequests+4 -and -not $c.RuntimeRunning -and -not $script:parallelHub.Paused) 'Expiry did not cancel active input and close every process, including one not in the UI list.'
    Assert-Parallel (@($script:shutdownState.Operations | Where-Object {$_.Owner.Pid -eq 404 -and $_.Owner.StartTicks -eq $extra.StartTime.Ticks -and $_.Owner.Path -eq $extra.ExecutablePath}).Count -eq 1) 'Shutdown did not snapshot the newly discovered process identity.'
    Assert-Parallel (@($script:shutdownState.Operations | Where-Object {[ParallelFixture]::OpThread[$_.Owner.Pid] -eq [Threading.Thread]::CurrentThread.ManagedThreadId}).Count -eq 0) 'UI thread executed a game exit.'
    Invoke-WowAutoShutdownTick 5000
    Assert-Parallel ($script:shutdownParallelCloses -eq 1 -and -not $script:restartRequested) 'Expiry repeated script close or requested a restart.'
    Write-Output 'PASS: real countdown expiry cancels pending input, unpauses the operator and queues all four client identities including an unrefreshed process, waits for replies and closes once. All process operations substituted.'
} finally {
    [ParallelFixture]::Release.Set();[ParallelFixture]::BlockPid=0;[ParallelFixture]::World[303]=1
    $script:mockProcesses=$savedShutdownProcesses;${function:Close-WowAutoAfterShutdown}=$savedShutdownClose
    $script:shutdownState=@{Deadline=0L;Started=$false;DialogOpen=$false;CloseRequested=$false;Operations=@()}
    $tabs.Enabled=$true;$shutdownButton.Text='结束倒计时';Update-BatchControls
}
