# Runs only inside wowAuto.ps1 -UiTest, with an inert wall clock and no native actions.
Stop-AllRows
$stampRow=@($script:rows.Values)[0]
$savedStampClock=$script:schedulerClock
$script:stampTime='10:00:00'
function Get-Date { param([string]$Format) return $script:stampTime }
try {
    $script:scheduler=New-WowAutoScheduler
    $script:schedulerClock=[pscustomobject]@{ElapsedMilliseconds=1000L}
    $stampRow.State=$null
    Set-RowStatusText $stampRow 'Waiting for validation.'
    Assert-Ui ($stampRow.Status.Text.StartsWith('[10:00:00] ')) 'Initial status has no event timestamp.'
    $script:stampTime='10:00:10'
    Update-RowStatus $stampRow
    Set-RowStatusText $stampRow 'Waiting for validation.'
    Assert-Ui ($stampRow.Status.Text.StartsWith('[10:00:00] ')) 'Unchanged status follows wall clock.'
    Set-RowStatusText $stampRow 'Validation passed.'
    Assert-Ui ($stampRow.Status.Text.StartsWith('[10:00:10] ')) 'New message kept an old timestamp.'

    $stampRow.State=Add-WowAutoTask $script:scheduler $stampRow.Key 9000 9000 1000
    $stampRow.State.Mode='Wait'; $stampRow.State.Deadline=10000
    $stampRow.State.Status='Fishing: wait for reel.'
    $script:stampTime='10:00:20'; Update-RowStatus $stampRow
    $script:stampTime='10:00:21'; $script:schedulerClock.ElapsedMilliseconds=2000
    Update-RowStatus $stampRow
    Assert-Ui ($stampRow.Status.Text.StartsWith('[10:00:20] ') -and $stampRow.Status.Text.Contains('8000 ms')) 'Fishing countdown changed timestamp or froze countdown.'
    $stampRow.State.Deadline=11000; Update-RowStatus $stampRow
    Assert-Ui ($stampRow.Status.Text.StartsWith('[10:00:21] ')) 'New deadline did not refresh timestamp.'

    Suspend-WowAutoFocus $script:scheduler $stampRow.Key 2000 'Denied.'
    $script:stampTime='10:00:22'; Update-RowStatus $stampRow
    $script:stampTime='10:00:23'; $script:schedulerClock.ElapsedMilliseconds=3000
    Update-RowStatus $stampRow
    Assert-Ui ($stampRow.Status.Text.StartsWith('[10:00:22] ') -and $stampRow.Status.Text.Contains('29')) 'Retry countdown changed timestamp or froze countdown.'
    Suspend-WowAutoFocus $script:scheduler $stampRow.Key 32000 'Denied.'
    Update-RowStatus $stampRow
    Assert-Ui ($stampRow.Status.Text.StartsWith('[10:00:23] ')) 'Repeated focus failure kept old timestamp.'
    Resume-WowAutoFocus $script:scheduler $stampRow.Key

    $script:scheduler.ItemHoldUntil=6000
    $script:stampTime='10:00:24'; Update-RowStatus $stampRow
    $script:stampTime='10:00:25'; $script:schedulerClock.ElapsedMilliseconds=4000
    Update-RowStatus $stampRow
    Assert-Ui ($stampRow.Status.Text.StartsWith('[10:00:24] ') -and $stampRow.Status.Text.Contains('2000 ms')) 'Item countdown changed timestamp or froze countdown.'
    $script:schedulerClock.ElapsedMilliseconds=6000; Update-RowStatus $stampRow
    Assert-Ui ($stampRow.Status.Text.StartsWith('[10:00:25] ')) 'Item hold exit kept old timestamp.'

    $script:stampTime='10:00:26'; Stop-Row $stampRow 'Waiting for game exit.'
    $script:pendingGameExits[$stampRow.Key]=[pscustomobject]@{Due=36000L}
    Update-RowStatus $stampRow
    $script:stampTime='10:00:27'; $script:schedulerClock.ElapsedMilliseconds=7000
    Update-RowStatus $stampRow
    Assert-Ui ($stampRow.Status.Text.StartsWith('[10:00:26] ') -and $stampRow.Status.Text.Contains('29000 ms')) 'Exit countdown changed timestamp or froze countdown.'
    $script:pendingGameExits.Clear()
} finally {
    Remove-Item Function:Get-Date
    Stop-AllRows
    $script:schedulerClock=$savedStampClock
}
Write-Output 'PASS: stable status timestamps, message/deadline/retry transitions, live fishing/retry/item/exit countdowns. Clocks mocked; no native actions.'
