# Runs only inside wowAuto.ps1 -UiTest; all process/window/input operations are inert.
$focusRows=@($script:rows.Values | Sort-Object { $_.Process.Id })
$focusA=$focusRows[0]; $focusB=$focusRows[1]
function Reset-FocusTest {
    Stop-AllRows
    $script:scheduler=New-WowAutoScheduler
    $script:schedulerClock=[pscustomobject]@{ElapsedMilliseconds=1000L}
    $script:workerFocus=0; $script:workerKeys=@(); $script:workerActivations=@()
    foreach ($r in @($focusA,$focusB)) {
        $r.State=$null; $r.Exited=$false; $r.Validated=$true
        $r.Process.HasExited=$false; $r.Process.StartTime=$r.StartTime
        $r.Process.ProcessName='WowClassic'; $r.Process.FocusAllowed=$true; $r.Process.ScanColor='red'
        $r.Minimum.Value=1000; $r.Maximum.Value=1000
        Update-RowStatus $r
    }
}
$savedFocusClock=$script:schedulerClock
try {
    Reset-FocusTest
    Assert-Ui ($focusA.Status.Text -match '^\[\d{2}:\d{2}:\d{2}\] ') 'Unstarted row has no clock.'
    $focusA.Process.FocusAllowed=$false
    Start-Row $focusA
    Invoke-SchedulerTick 1000
    Assert-Ui ($focusA.State.Running -and $focusA.State.FocusRetryAt -eq 31000) 'Activation failure stopped task.'
    Assert-Ui ($focusA.Stop.Enabled -and -not $focusA.Start.Enabled) 'Suspended controls allow duplicate start or disable stop.'
    Assert-Ui ($focusA.Status.Text -match '^\[\d{2}:\d{2}:\d{2}\] ' -and $focusA.Status.Text -match '30') 'Retry status has no time/countdown.'
    $script:schedulerClock.ElapsedMilliseconds=16000
    Update-RowStatus $focusA
    Assert-Ui ($focusA.Status.Text -match '剩余 15 秒' -and ([regex]::Matches($focusA.Status.Text,'\[\d{2}:\d{2}:\d{2}\]')).Count -eq 1) 'Retry countdown or timestamp duplicates are wrong.'

    # Another row must continue casting and reeling during the 30-second pause.
    $script:schedulerClock.ElapsedMilliseconds=1200
    $focusB.Process.ScanColor='green'; Start-Row $focusB
    Invoke-SchedulerTick 1200; Invoke-SchedulerTick 1400; Invoke-SchedulerTick 2400
    Assert-Ui ($script:workerKeys[-1] -eq "$($focusB.Process.Id):187" -and $focusB.State.Mode -eq 'Cooldown') 'Focus failure blocked another reel.'
    Stop-Row $focusB
    Invoke-SchedulerTick 30999
    Assert-Ui (@($script:workerActivations | Where-Object { $_ -eq $focusA.Process.Id }).Count -eq 1) 'Focus retried before 30 seconds.'
    Invoke-SchedulerTick 31000
    Assert-Ui ($focusA.State.FocusRetryAt -eq 61000 -and $focusA.State.Running) 'Repeated denial stopped row or lost retry.'
    Invoke-SchedulerTick 60999
    Assert-Ui (@($script:workerActivations | Where-Object { $_ -eq $focusA.Process.Id }).Count -eq 2) 'Repeated denial retried early.'
    $focusA.Process.FocusAllowed=$true
    Invoke-SchedulerTick 61000; Invoke-SchedulerTick 61200; Invoke-SchedulerTick 61201
    Assert-Ui ($focusA.State.FocusRetryAt -eq 0 -and $script:workerKeys[-1] -eq "$($focusA.Process.Id):48") 'Recovery did not resume casting.'

    # Preserve an overdue registered reel, send it once after recovery, and count it once.
    Reset-FocusTest
    Start-Row $focusA
    $null=Complete-WowAutoPoll $script:scheduler $focusA.Key 1000 'green'
    $focusA.Process.FocusAllowed=$false
    Invoke-SchedulerTick 2000
    Assert-Ui ($focusA.State.Mode -eq 'Wait' -and $focusA.State.Deadline -eq 2000 -and $script:scheduler.Events.Count -eq 1) 'Failed reel lost its event.'
    $focusA.Process.FocusAllowed=$true
    Invoke-SchedulerTick 32000; Invoke-SchedulerTick 32200; Invoke-SchedulerTick 32201
    Assert-Ui (($script:workerKeys -join ',') -eq "$($focusA.Process.Id):187" -and (Get-WowAutoCycleCount $script:scheduler $focusA.Key) -eq 1) 'Recovered reel was lost or duplicated.'

    # Simulate SetForegroundWindow accepting a request but never delivering focus.
    Reset-FocusTest
    $savedActivation=(Get-Item Function:Activate-WorkerRow).ScriptBlock
    try {
        function Activate-WorkerRow($Row) { $script:workerActivations += $Row.Process.Id; return $true }
        $focusA.Process.FocusAllowed=$false; Start-Row $focusA
        Invoke-SchedulerTick 1000; Invoke-SchedulerTick 1200; Invoke-SchedulerTick 1799
        Assert-Ui ($focusA.State.FocusRetryAt -eq 0 -and $script:workerKeys.Count -eq 0) 'Focus timeout ended too early.'
        Invoke-SchedulerTick 1800
        Assert-Ui ($focusA.State.Running -and $focusA.State.FocusRetryAt -eq 31800 -and $null -eq $script:pendingWork) 'Focus timeout permanently stopped row.'
    } finally { Set-Item Function:Activate-WorkerRow $savedActivation }

    Reset-FocusTest
    Start-Row $focusA; $script:workerFocus=$focusA.Process.Id
    $focusA.Process.ScanColor='not-foreground'
    Invoke-SchedulerTick 1000
    Assert-Ui ($focusA.State.FocusRetryAt -eq 31000 -and $script:workerKeys.Count -eq 0) 'Pixel-time focus loss did not pause.'
    Reset-FocusTest
    Start-Row $focusA; $script:workerFocus=$focusA.Process.Id
    $savedSend=(Get-Item Function:Send-WorkerKey).ScriptBlock
    try {
        function Send-WorkerKey($Row, [string]$Action) { $Row.Process.FocusAllowed=$false; return $false }
        Invoke-SchedulerTick 1000
        Assert-Ui ($focusA.State.Running -and $focusA.State.FocusRetryAt -eq 31000 -and $script:workerKeys.Count -eq 0) 'Key-time focus loss did not pause.'
    } finally { Set-Item Function:Send-WorkerKey $savedSend }

    foreach ($identity in @('exited','reused','renamed')) {
        Reset-FocusTest
        $focusA.Process.FocusAllowed=$false; Start-Row $focusA; Invoke-SchedulerTick 1000
        if ($identity -eq 'exited') { $focusA.Process.HasExited=$true }
        if ($identity -eq 'reused') { $focusA.Process.StartTime=$focusA.StartTime.AddSeconds(1) }
        if ($identity -eq 'renamed') { $focusA.Process.ProcessName='Other' }
        Invoke-SchedulerTick 31000
        Assert-Ui (-not $focusA.State.Running -and $focusA.State.FocusRetryAt -eq 0 -and $script:workerActivations.Count -eq 1 -and $script:workerKeys.Count -eq 0) "Retry failed identity check: $identity"
    }
    foreach ($cancel in @('row','all','refresh')) {
        Reset-FocusTest
        $focusA.Process.FocusAllowed=$false; Start-Row $focusA; Invoke-SchedulerTick 1000
        $oldState=$focusA.State
        if ($cancel -eq 'row') { Stop-Row $focusA }
        if ($cancel -eq 'all') { Stop-AllRows }
        if ($cancel -eq 'refresh') { Begin-RefreshScan; Complete-TestScan }
        Invoke-SchedulerTick 99999
        Assert-Ui (-not $oldState.Running -and $oldState.FocusRetryAt -eq 0 -and $script:scheduler.Tasks.Count -eq 0 -and $script:workerKeys.Count -eq 0) "Cancellation left retry: $cancel"
        Assert-Ui ($focusA.Status.Text -match '^\[\d{2}:\d{2}:\d{2}\] ') 'Stopped/refreshed status has no clock.'
    }
} finally {
    Stop-AllRows
    $script:schedulerClock=$savedFocusClock
}
Write-Output 'PASS: status clock/countdown, focus activation/timeout/sample/send failures, 30-second retries, recovery, preserved reel, row isolation, identity and stop/refresh cancellation. Native actions mocked.'
