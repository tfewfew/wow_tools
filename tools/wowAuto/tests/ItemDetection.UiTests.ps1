Stop-AllRows
$itemRow=@($script:rows.Values)[0]
$script:scheduler=New-WowAutoScheduler
$itemRow.SlotUseItem=$true
Set-WowAutoItemEnabled $script:scheduler $itemRow.Key $true $script:schedulerClock.ElapsedMilliseconds
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
        Assert-Ui ($itemRow.State.ItemConfirmUntil -eq ($when+5000) -and $itemRow.State.InitialItemPending) 'Sent item did not start confirmation.'
        Invoke-SchedulerTick ($when+2999)
        Assert-Ui ($script:workerKeys.Count -eq 1) 'Item hold released input early.'
        Invoke-SchedulerTick ($when+3000)
        Assert-Ui ($script:workerKeys.Count -eq 1 -and $itemRow.State.InitialItemPending) 'Unconfirmed item repeated or resumed casting before timeout.'
        Invoke-SchedulerTick ($when+5000)
        Assert-Ui ($itemRow.State.ItemDetectionDisabled -and $itemRow.SlotUseItem -and $script:workerKeys[-1] -eq "$($itemRow.Process.Id):48" -and @($script:workerKeys | Where-Object {$_ -eq "$($itemRow.Process.Id):189"}).Count -eq 1) 'Timed-out item did not disable only this task detection and continue fishing.'
    }
}
Stop-AllRows
$script:scheduler.ItemHoldUntil=0L
$itemRow.Validated=$true; $itemRow.Exited=$false; $itemRow.Process.HasExited=$false
$itemRow.Process.FocusAllowed=$true; $itemRow.Process.ScanColor='red'; $itemRow.Process.LureColor='missing'
$script:workerFocus=$itemRow.Process.Id; $script:workerKeys=@()
Start-Row $itemRow
$when=$itemRow.State.ItemDue
Invoke-SchedulerTick $when
Assert-Ui (@($script:workerKeys | Where-Object {$_ -eq "$($itemRow.Process.Id):189"}).Count -eq 1) 'First item attempt was not sent.'
$itemRow.Process.LureColor='present'
Invoke-SchedulerTick ($when+3000)
Assert-Ui ($itemRow.State.ItemConfirmUntil -eq 0 -and -not $itemRow.State.ItemDetectionDisabled) 'Successful item confirmation did not retain later detection.'
$itemRow.Process.LureColor='missing'
Invoke-SchedulerTick ($when+4000)
Assert-Ui (@($script:workerKeys | Where-Object {$_ -eq "$($itemRow.Process.Id):189"}).Count -eq 2) 'Later lost enchant did not send a replacement item.'
Stop-AllRows
$script:scheduler.ItemHoldUntil=0L
$itemRow.Process.ScanColor='green'; $itemRow.Process.LureColor='missing'; $itemRow.Validated=$true
Start-Row $itemRow
$script:workerFocus=$itemRow.Process.Id; $script:workerKeys=@()
Invoke-SchedulerTick $itemRow.State.ItemDue
Assert-Ui ($script:workerKeys.Count -eq 0 -and $itemRow.State.Mode -eq 'Wait') 'Missing lure interrupted existing fishing channel.'
$itemRow.SlotUseItem=$false
Set-WowAutoItemEnabled $script:scheduler $itemRow.Key $false $script:schedulerClock.ElapsedMilliseconds
Stop-AllRows
Write-Output 'PASS: native adapter dispatch follows lure point, present skips, unknown waits, timeout resumes fishing, confirmed enchant can be replenished, and green defers. All actions mocked.'
