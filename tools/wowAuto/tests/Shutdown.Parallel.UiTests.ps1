# Exercise production expiry/queue submission against the parallel input substitutes.
$savedShutdownComplete=${function:Complete-WowAutoGameShutdown}
$savedShutdownProcesses=@($script:mockProcesses)
$savedShutdownExited=@{};foreach($row in $script:rows.Values){$savedShutdownExited[$row.Key]=$row.Exited}
$script:shutdownParallelCompletions=0;$script:shutdownParallelOperations=@()
function Complete-WowAutoGameShutdown {
    Assert-Parallel (@($script:shutdownState.Operations | Where-Object {-not $_.Done.IsSet -or -not $_.Success}).Count -eq 0) 'Countdown reset before all game exit requests completed.'
    $script:shutdownParallelOperations=@($script:shutdownState.Operations)
    & $savedShutdownComplete
    $script:shutdownParallelCompletions++
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
    Pump-Parallel {Invoke-WowAutoShutdownTick 2500;$script:shutdownParallelCompletions -eq 1}
    Assert-Parallel ([ParallelFixture]::ShutdownRequests -eq $beforeRequests+4 -and -not $c.RuntimeRunning -and -not $script:parallelHub.Paused) 'Expiry did not cancel active input and close every process, including one not in the UI list.'
    Assert-Parallel (@($script:shutdownParallelOperations | Where-Object {$_.Owner.Pid -eq 404 -and $_.Owner.StartTicks -eq $extra.StartTime.Ticks -and $_.Owner.Path -eq $extra.ExecutablePath}).Count -eq 1) 'Shutdown did not snapshot the newly discovered process identity.'
    Assert-Parallel (@($script:shutdownParallelOperations | Where-Object {[ParallelFixture]::OpThread[$_.Owner.Pid] -eq [Threading.Thread]::CurrentThread.ManagedThreadId}).Count -eq 0) 'UI thread executed a game exit.'
    Invoke-WowAutoShutdownTick 5000
    Assert-Parallel ($script:shutdownParallelCompletions -eq 1 -and -not $script:restartRequested -and $form.Visible -and -not $script:parallelHub.Closing -and -not $script:parallelOperator.Async.IsCompleted -and
        $shutdownButton.Enabled -and $refreshButton.Enabled -and $restartButton.Enabled -and $tabs.Enabled) 'Completed countdown retriggered, closed the script/operator or left the interface locked.'
    Assert-Parallel (@($script:shutdownParallelOperations | Where-Object {$_.Owner.Current($_.Version)}).Count -eq 0) 'Completed shutdown retained its temporary process registrations.'
    # Reuse the same simulated identities to catch leaked endpoint registrations.
    Set-WowAutoShutdownCountdown 1 6000;Invoke-WowAutoShutdownTick 7000
    Pump-Parallel {Invoke-WowAutoShutdownTick 7500;$script:shutdownParallelCompletions -eq 2}
    Assert-Parallel ([ParallelFixture]::ShutdownRequests -eq $beforeRequests+8 -and $script:shutdownParallelOperations.Count -eq 4 -and $form.Visible -and -not $script:parallelHub.Closing) 'Another countdown could not reuse the still-running script and process registrations.'
    Write-Output 'PASS: real expiry cancels pending input, exits all current identities on the operator, waits for replies, keeps script/operator/UI alive and supports a second countdown without leaked registrations. Process operations substituted.'
} finally {
    [ParallelFixture]::Release.Set();[ParallelFixture]::BlockPid=0;[ParallelFixture]::World[303]=1
    $script:mockProcesses=$savedShutdownProcesses;${function:Complete-WowAutoGameShutdown}=$savedShutdownComplete
    foreach($row in $script:rows.Values){$row.Exited=$savedShutdownExited[$row.Key]}
    if($script:parallelWorkers[$c.Key].Endpoint.Closed){$null=Ensure-ParallelWorker $c}
    $script:shutdownState=@{Deadline=0L;Started=$false;DialogOpen=$false;Operations=@()}
    $tabs.Enabled=$true;$shutdownButton.Text='结束倒计时';Update-BatchControls
}
