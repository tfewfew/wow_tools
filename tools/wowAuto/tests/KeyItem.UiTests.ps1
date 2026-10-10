Stop-AllRows
$script:scheduler=New-WowAutoScheduler
$script:pendingWork=$null
foreach ($r in $script:rows.Values) {
    Assert-Ui (-not $r.ItemCheck.Checked) 'Process items must default off.'
    Assert-Ui ($r.ItemCheck.Parent -eq $r.Panel -and $r.ItemCheck.Left -gt $r.Stop.Right -and
        $r.ItemCheck.Right -lt $r.Status.Left) 'Item checkbox is outside its process row or overlaps controls.'
}
foreach ($action in @('Cast','Reel','Item')) {
    $inputBox=$script:keyInputs[$action]
    Assert-Ui ($toolbar.ClientRectangle.Contains($inputBox.Bounds) -and $inputBox.Top -gt $holdInput.Bottom) 'Key input is clipped or not below hold controls.'
}
foreach ($keyCase in @(@(189,'-'),@(187,'='))) {
    Set-KeyBinding $script:keyInputs['Item'] $keyCase[0] $false $false $false
    Assert-Ui ($script:keyBindings.Item.Text -eq $keyCase[1] -and $script:keyBindings.Item.Code -eq $keyCase[0]) 'Punctuation single key rejected.'
    Set-KeyBinding $script:keyInputs['Item'] $keyCase[0] $true $false $false
    Assert-Ui ($script:keyBindings.Item.Text -eq ('Ctrl+'+$keyCase[1]) -and $script:keyBindings.Item.Ctrl) 'Punctuation chord rejected.'
}
Set-KeyBinding $script:keyInputs['Item'] 113 $false $true $false
Assert-Ui ($script:keyBindings.Item.Text -eq 'Shift+F2') 'Key capture did not accept Shift+F2.'
Set-KeyBinding $script:keyInputs['Item'] 16 $true $true $false
Assert-Ui ($script:keyBindings.Item.Text -eq 'Shift+F2') 'Modifier alone overwrote binding.'
$row=@($script:rows.Values)[0]
$row.ItemCheck.Checked=$true
$row.Process.HasExited=$false; $row.Exited=$false; $row.Validated=$true
$row.Process.FocusAllowed=$true; $row.Process.ScanColor='red'
$row.Process.LureColor='missing'
Start-Row $row
Assert-Ui $row.State.UseItem 'Process checkbox did not enable item scheduling.'
$due=$row.State.ItemDue
Assert-Ui ($due -le $script:schedulerClock.ElapsedMilliseconds -and $row.State.InitialItemPending) 'Start did not immediately queue an item.'
$script:workerFocus=$row.Process.Id
$script:workerKeys=@()
Invoke-SchedulerTick $due
Assert-Ui (($script:workerKeys -join ',') -eq "$($row.Process.Id):113") 'Item did not send configured key.'
Assert-Ui ($row.State.ItemDue -eq $due+3000 -and $row.State.InitialItemPending) 'Item did not schedule confirmation after full hold.'
$keysBefore=$script:workerKeys.Count
$focusBefore=$script:workerActivations.Count
Invoke-SchedulerTick ($due+2999)
Assert-Ui ($script:workerKeys.Count -eq $keysBefore -and $script:workerActivations.Count -eq $focusBefore) 'Item wait allowed input or window switching.'
$row.Process.LureColor='present'
Invoke-SchedulerTick ($due+3000)
Assert-Ui ($script:workerKeys.Count -eq $keysBefore+1 -and $script:workerKeys[-1] -eq "$($row.Process.Id):48") 'Casting did not resume after three seconds.'
$row.ItemCheck.Checked=$false
Assert-Ui (-not $row.State.UseItem -and $row.State.ItemDue -eq 0) 'Unchecking left item scheduled.'
Stop-AllRows
Set-KeyBinding $script:keyInputs['Item'] 189 $false $false $false
Write-Output 'PASS: key layout/capture, checkbox binding, missing-enchant item dispatch, full hold, confirmation and cancellation. Native input mocked.'
