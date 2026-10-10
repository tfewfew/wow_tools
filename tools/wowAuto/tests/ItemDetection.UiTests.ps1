Stop-AllRows
$itemRow=@($script:rows.Values)[0]
$script:scheduler=New-WowAutoScheduler
$itemRow.ItemCheck.Checked=$true
foreach ($lureCase in @('present','unknown','missing')) {
    Stop-AllRows
    $script:scheduler.ReelHoldUntil=0L; $script:scheduler.ItemHoldUntil=0L
    $itemRow.Validated=$true; $itemRow.Exited=$false; $itemRow.Process.HasExited=$false
    $itemRow.Process.FocusAllowed=$true; $itemRow.Process.ScanColor='red'; $itemRow.Process.LureColor=$lureCase
    $script:workerFocus=$itemRow.Process.Id; $script:workerKeys=@()
    Start-Row $itemRow
    $when=$itemRow.State.ItemDue
    Invoke-SchedulerTick $when
    if ($lureCase -eq 'present') {
        Assert-Ui (($script:workerKeys -join ',') -eq "$($itemRow.Process.Id):48") 'Existing enchant did not skip item and resume cast.'
        Assert-Ui ($script:scheduler.ActiveKey -eq $itemRow.Key) 'Enchantment check lost the active casting window.'
    } elseif ($lureCase -eq 'unknown') {
        Assert-Ui ($script:workerKeys.Count -eq 0 -and $itemRow.State.InitialItemPending) 'Unknown point emitted an item or cast.'
    } else {
        Assert-Ui (($script:workerKeys -join ',') -eq "$($itemRow.Process.Id):189") 'Missing enchant did not use configured item.'
        Invoke-SchedulerTick ($when+3000)
        Assert-Ui ($script:workerKeys.Count -eq 1 -and $itemRow.State.InitialItemPending) 'No enchant confirmation allowed cast.'
        $itemRow.Process.LureColor='present'
        Invoke-SchedulerTick ($when+4000)
        Assert-Ui ($script:workerKeys[-1] -eq "$($itemRow.Process.Id):48" -and -not $itemRow.State.InitialItemPending) 'Confirmed enchant did not resume.'
    }
}
Stop-AllRows
$script:scheduler.ItemHoldUntil=0L
$itemRow.Process.ScanColor='green'; $itemRow.Process.LureColor='missing'; $itemRow.Validated=$true
Start-Row $itemRow
$script:workerFocus=$itemRow.Process.Id; $script:workerKeys=@()
Invoke-SchedulerTick $itemRow.State.ItemDue
Assert-Ui ($script:workerKeys.Count -eq 0 -and $itemRow.State.Mode -eq 'Wait') 'Missing lure interrupted existing fishing channel.'
$itemRow.ItemCheck.Checked=$false
Stop-AllRows
Write-Output 'PASS: native adapter dispatch follows lure point, present skips, unknown waits, missing applies, failed confirmation blocks cast and green defers. All actions mocked.'
