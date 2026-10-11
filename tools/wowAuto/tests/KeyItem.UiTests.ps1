Stop-AllRows
$script:scheduler=New-WowAutoScheduler
$script:pendingWork=$null
foreach ($r in $script:rows.Values) {
    Assert-Ui (-not $r.ItemCheck.Checked) 'Process items must default off.'
    Assert-Ui ($r.ItemCheck.Parent -eq $r.Panel -and $r.ItemCheck.Left -gt $r.Stop.Right -and
        $r.ItemCheck.Right -lt $r.Status.Left) 'Item checkbox is outside its process row or overlaps controls.'
}
Assert-Ui (@($toolbar.Controls | Where-Object { $_ -is [System.Windows.Forms.TextBox] }).Count -eq 0) 'Key editors remain in the toolbar.'
$savedKeyBindings=$script:keyBindings
$keyIniExisted=[IO.File]::Exists($script:settingsPath)
$keyIniBytes=if ($keyIniExisted) { [IO.File]::ReadAllBytes($script:settingsPath) } else { $null }
$keyDialog=$null
try {
    $keyDialog=New-WaitSettingsDialog; $keyDialog.Show($form)
    [System.Windows.Forms.Application]::DoEvents()
    foreach ($action in @('Cast','Reel','Item')) {
        $inputBox=$keyDialog.Tag.KeyInputs[$action]
        Assert-Ui ($inputBox.ReadOnly -and $inputBox.Parent.Parent -eq $keyDialog -and
            $inputBox.Parent.ClientRectangle.Contains($inputBox.Bounds) -and
            $keyDialog.ClientRectangle.Contains($inputBox.Parent.Bounds)) 'Settings key editor is missing or clipped.'
    }
    foreach ($keyCase in @(@(189,'-'),@(187,'='))) {
        Set-KeyBinding $keyDialog.Tag.KeyInputs.Item $keyCase[0] $false $false $false
        Assert-Ui ($keyDialog.Tag.KeyBindings.Item.Text -eq $keyCase[1] -and $keyDialog.Tag.KeyBindings.Item.Code -eq $keyCase[0]) 'Punctuation single key rejected.'
        Set-KeyBinding $keyDialog.Tag.KeyInputs.Item $keyCase[0] $true $false $false
        Assert-Ui ($keyDialog.Tag.KeyBindings.Item.Text -eq ('Ctrl+'+$keyCase[1]) -and $keyDialog.Tag.KeyBindings.Item.Ctrl) 'Punctuation chord rejected.'
    }
    $keyEvent=New-Object System.Windows.Forms.KeyEventArgs([System.Windows.Forms.Keys]::Shift -bor [System.Windows.Forms.Keys]::F2)
    $onKeyDown=[System.Windows.Forms.Control].GetMethod('OnKeyDown',[Reflection.BindingFlags]'Instance,NonPublic')
    $null=$onKeyDown.Invoke($keyDialog.Tag.KeyInputs.Item,@($keyEvent.PSObject.BaseObject))
    Assert-Ui ($keyDialog.Tag.KeyBindings.Item.Text -eq 'Shift+F2' -and $keyEvent.Handled -and $keyEvent.SuppressKeyPress) 'Settings key handler did not capture/suppress Shift+F2.'
    Set-KeyBinding $keyDialog.Tag.KeyInputs.Item 16 $true $true $false
    Assert-Ui ($keyDialog.Tag.KeyBindings.Item.Text -eq 'Shift+F2') 'Modifier alone overwrote binding.'
    Assert-Ui ([object]::ReferenceEquals($script:keyBindings,$savedKeyBindings)) 'Editing changed the active bindings before save.'
    $keyDialog.Tag.Inputs.titan.Minimum.Value=3600000
    $keyDialog.Tag.Apply.PerformClick()
    Assert-Ui ($keyDialog.Tag.Error.Text -ne '' -and [object]::ReferenceEquals($script:keyBindings,$savedKeyBindings)) 'Invalid timing partially applied draft key bindings.'
    $keyDialog.Tag.Cancel.PerformClick()
    Assert-Ui ([object]::ReferenceEquals($script:keyBindings,$savedKeyBindings)) 'Cancel applied draft key bindings.'
    $keyDialog.Dispose()
    $keyDialog=New-WaitSettingsDialog; $keyDialog.Show($form)
    Assert-Ui ($keyDialog.Tag.KeyInputs.Item.Text -eq $savedKeyBindings.Item.Text) 'Reopening retained a cancelled key draft.'
    Set-KeyBinding $keyDialog.Tag.KeyInputs.Item 113 $false $true $false
    $keyDialog.Tag.Apply.PerformClick()
    Assert-Ui ($keyDialog.DialogResult -eq 'OK' -and $script:keyBindings.Item.Text -eq 'Shift+F2') 'Saving settings did not apply the new binding.'
    $keyDialog.Dispose()
    $keyDialog=New-WaitSettingsDialog
    Assert-Ui ($keyDialog.Tag.KeyInputs.Item.Text -eq 'Shift+F2') 'Reopening lost the active saved key binding.'
}
finally {
    if ($null -ne $keyDialog) { $keyDialog.Dispose() }
    if ($keyIniExisted) { [IO.File]::WriteAllBytes($script:settingsPath,$keyIniBytes) }
    elseif ([IO.File]::Exists($script:settingsPath)) { [IO.File]::Delete($script:settingsPath) }
}
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
$script:keyBindings=$savedKeyBindings
Write-Output 'PASS: settings-only key editors, draft key capture/punctuation/chords, save/cancel/error isolation/reopening, checkbox binding, configured item dispatch, full hold and confirmation. Native input mocked.'
