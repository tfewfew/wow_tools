# Runs only in -UiTest with two simulated game processes and an inert scheduler clock.
Stop-AllRows
$processItemRows=@($script:rows.Values | Sort-Object { $_.Process.Id })
$itemA=$processItemRows[0]; $itemB=$processItemRows[1]
$savedProcessItemClock=$script:schedulerClock
try {
    $script:scheduler=New-WowAutoScheduler
    $script:schedulerClock=[pscustomobject]@{ElapsedMilliseconds=1000L}
    $script:workerKeys=@(); $script:workerActivations=@()
    foreach ($r in $processItemRows) {
        $r.State=$null; $r.Exited=$false; $r.Validated=$true
        $r.ItemCheck.Checked=$false
        $r.Process.HasExited=$false; $r.Process.FocusAllowed=$true
        $r.Process.ScanColor='red'; $r.Process.LureColor='unknown'
        Update-RowStatus $r
    }
    $itemA.ItemCheck.Checked=$true
    Update-BatchControls
    $startAllButton.PerformClick()
    Assert-Ui ($itemA.State.UseItem -and -not $itemB.State.UseItem) 'Start All ignored individual item selections.'
    $script:workerFocus=$itemA.Process.Id
    Invoke-SchedulerTick 1000
    Invoke-SchedulerTick 1001
    Invoke-SchedulerTick 1201
    Assert-Ui ($itemA.State.InitialItemPending -and -not $itemB.State.InitialItemPending) 'Unknown lure gated an unchecked process.'
    Assert-Ui (($script:workerKeys -join ',') -eq "$($itemB.Process.Id):48") 'Unchecked process did not cast independently of unknown lure.'
    Assert-Ui ($itemB.State.ItemStatus -eq '') 'Unchecked process shows another process item status.'

    $savedADue=$itemA.State.ItemDue
    $script:schedulerClock.ElapsedMilliseconds=1300
    $itemB.ItemCheck.Checked=$true
    Assert-Ui ($itemB.State.UseItem -and $itemB.State.ItemDue -eq 1300 -and $itemA.State.ItemDue -eq $savedADue) 'Enabling B changed A schedule.'
    $itemB.Process.LureColor='missing'
    Invoke-SchedulerTick 1300
    Assert-Ui ($script:workerKeys[-1] -eq "$($itemB.Process.Id):189" -and $script:scheduler.ItemHoldUntil -eq 4300) 'Selected process did not apply missing lure.'
    $script:schedulerClock.ElapsedMilliseconds=1400
    $itemB.ItemCheck.Checked=$false
    Assert-Ui (-not $itemB.State.UseItem -and $itemB.State.ItemDue -eq 0 -and $itemA.State.UseItem) 'Disabling B changed A or left checks queued.'
    $keyCount=$script:workerKeys.Count; $activationCount=$script:workerActivations.Count
    Invoke-SchedulerTick 4299
    Assert-Ui ($script:workerKeys.Count -eq $keyCount -and $script:workerActivations.Count -eq $activationCount) 'Unchecking interrupted the three-second item hold.'
    Invoke-SchedulerTick 4300
    Invoke-SchedulerTick 4500
    Invoke-SchedulerTick 4501
    Invoke-SchedulerTick 4701
    Assert-Ui (($script:workerKeys -join ',') -eq "$($itemB.Process.Id):48,$($itemB.Process.Id):189,$($itemB.Process.Id):48") 'Per-process dispatch leaked an item or blocked unchecked casting after hold.'

    Stop-Row $itemA
    $script:schedulerClock.ElapsedMilliseconds=4800
    Start-Row $itemA
    Assert-Ui ($itemA.ItemCheck.Checked -and $itemA.State.UseItem -and $itemA.State.ItemDue -eq 4800) 'Restart lost the process selection or reused an old item deadline.'
} finally {
    Stop-AllRows
    foreach ($r in $processItemRows) { $r.ItemCheck.Checked=$false }
    $script:schedulerClock=$savedProcessItemClock
}
Write-Output 'PASS: individual Start All selection, unchecked unknown-lure isolation, runtime toggles, per-process item dispatch, shared full hold and restart. All native actions mocked.'
