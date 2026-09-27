Stop-AllRows
$script:scheduler=New-WowAutoScheduler
$script:pendingWork=$null
Assert-Ui (-not $itemCheck.Checked) 'Items must default off.'
Assert-Ui ($itemCheck.Right -le $holdLabel.Left) 'Item checkbox must precede hold input.'
foreach ($action in @('Cast','Reel','Item')) {
    $inputBox=$script:keyInputs[$action]
    Assert-Ui ($toolbar.ClientRectangle.Contains($inputBox.Bounds) -and $inputBox.Top -gt $holdInput.Bottom) 'Key input is clipped or not below hold controls.'
}
Set-KeyBinding $script:keyInputs['Item'] 113 $false $true $false
Assert-Ui ($script:keyBindings.Item.Text -eq 'Shift+F2') 'Key capture did not accept Shift+F2.'
Set-KeyBinding $script:keyInputs['Item'] 16 $true $true $false
Assert-Ui ($script:keyBindings.Item.Text -eq 'Shift+F2') 'Modifier alone overwrote binding.'
$itemCheck.Checked=$true
Assert-Ui $script:scheduler.UseItem 'Checkbox did not enable item scheduling.'
$row=@($script:rows.Values)[0]
$row.Process.HasExited=$false; $row.Exited=$false; $row.Validated=$true
$row.Process.FocusAllowed=$true; $row.Process.ScanColor='red'
Start-Row $row
$due=$row.State.ItemDue
$script:workerFocus=$row.Process.Id
$script:workerKeys=@()
Invoke-SchedulerTick $due
Assert-Ui (($script:workerKeys -join ',') -eq "$($row.Process.Id):113") 'Item did not send configured key.'
Assert-Ui ($row.State.ItemDue -eq $due+600000) 'Item did not reschedule from successful send.'
$itemCheck.Checked=$false
Assert-Ui (-not $script:scheduler.UseItem -and $row.State.ItemDue -eq 0) 'Unchecking left item scheduled.'
Stop-AllRows
Set-KeyBinding $script:keyInputs['Item'] 51 $true $false $false
Write-Output 'PASS: key layout/capture, checkbox binding, configured item dispatch and cancellation. Native input mocked.'
