# Offline UI/config coverage; all input endpoints are the existing -UiTest substitutes.
Stop-AllRows
$savedRod=$script:equipRodBinding
$rodIni=[IO.File]::ReadAllBytes($script:settingsPath)
$rodDialog=$null
try {
    $script:equipRodBinding=$null
    $rodDialog=New-WaitSettingsDialog;$rodDialog.Show($form)
    $rodBox=$rodDialog.Tag.KeyInputs.EquipRod
    Assert-Ui ($rodBox.ReadOnly -and $rodBox.Text -ceq '未配置' -and $null -eq $rodDialog.Tag.KeyBindings.EquipRod -and
        $rodBox.Parent.ClientRectangle.Contains($rodBox.Bounds) -and $rodBox.Parent.ClientRectangle.Contains($rodDialog.Tag.ClearEquipRod.Bounds)) 'Empty default or rod editor layout is invalid.'
    Set-KeyBinding $rodBox 114 $true $false $false
    Assert-Ui ($null -eq $script:equipRodBinding) 'Rod draft applied before save.'
    $rodDialog.Tag.Inputs.titan.Minimum.Value=3600000;$rodDialog.Tag.Apply.PerformClick()
    Assert-Ui ($null -eq $script:equipRodBinding -and $rodDialog.Tag.Error.Text -ne '') 'Invalid settings applied a rod draft.'
    $rodDialog.Tag.Cancel.PerformClick();$rodDialog.Dispose()
    $rodDialog=New-WaitSettingsDialog;$rodDialog.Show($form)
    Assert-Ui ($rodDialog.Tag.KeyInputs.EquipRod.Text -ceq '未配置') 'Cancelled rod binding survived reopening.'
    $keyEvent=New-Object Windows.Forms.KeyEventArgs([Windows.Forms.Keys]::Control -bor [Windows.Forms.Keys]::F3)
    $onKeyDown=[Windows.Forms.Control].GetMethod('OnKeyDown',[Reflection.BindingFlags]'Instance,NonPublic')
    $null=$onKeyDown.Invoke($rodDialog.Tag.KeyInputs.EquipRod,@($keyEvent.PSObject.BaseObject))
    $rodDialog.Tag.Apply.PerformClick()
    Assert-Ui ($rodDialog.DialogResult -eq 'OK' -and $script:equipRodBinding.Text -ceq 'Ctrl+F3' -and $keyEvent.SuppressKeyPress) 'Rod chord was not captured or saved.'
    $rodDialog.Dispose();$fullRodIni=[IO.File]::ReadAllText($script:settingsPath)
    $script:equipRodBinding=$null;Import-VersionWaitSettings
    Assert-Ui ($script:settingsWarning -eq '' -and $script:equipRodBinding.Text -ceq 'Ctrl+F3') 'Rod binding did not survive reload.'
    foreach($invalid in @($fullRodIni.Replace('EquipRodKey=Ctrl+F3','EquipRodKey=Ctrl+Ctrl+F3'),($fullRodIni+"equiprodkey=F4`r`n"))) {
        [IO.File]::WriteAllText($script:settingsPath,$invalid)
        Import-VersionWaitSettings
        Assert-Ui ($script:settingsWarning -ne '' -and $script:equipRodBinding.Text -ceq 'Ctrl+F3') 'Invalid/duplicate rod field partially applied.'
    }
    [IO.File]::WriteAllText($script:settingsPath,$fullRodIni)
    $rodDialog=New-WaitSettingsDialog;$rodDialog.Show($form)
    Set-KeyBinding $rodDialog.Tag.KeyInputs.EquipRod 115 $false $true $false
    $lockedRodIni=[IO.File]::Open($script:settingsPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try{$rodDialog.Tag.Apply.PerformClick()}finally{$lockedRodIni.Dispose()}
    Assert-Ui ($script:equipRodBinding.Text -ceq 'Ctrl+F3' -and $rodDialog.DialogResult -ne 'OK') 'Failed write applied rod draft.'
    $rodDialog.Tag.ClearEquipRod.PerformClick()
    Assert-Ui ($null -eq $rodDialog.Tag.KeyBindings.EquipRod -and $script:equipRodBinding.Text -ceq 'Ctrl+F3') 'Clear bypassed draft isolation.'
    $rodDialog.Tag.Apply.PerformClick();$rodDialog.Dispose()
    $script:equipRodBinding=ConvertFrom-KeyBindingText 'F4';Import-VersionWaitSettings
    Assert-Ui ($script:settingsWarning -eq '' -and $null -eq $script:equipRodBinding -and (Read-WowAutoSettingsIni $script:settingsPath).EquipRodKey -eq '') 'Cleared binding did not round-trip as empty.'
    [IO.File]::WriteAllText($script:settingsPath,($fullRodIni -replace '(?m)^EquipRodKey=.*\r?\n?',''))
    $beforeLegacy=(Get-FileHash $script:settingsPath).Hash;Import-VersionWaitSettings
    Assert-Ui ($script:settingsWarning -eq '' -and $null -eq $script:equipRodBinding -and (Get-FileHash $script:settingsPath).Hash -eq $beforeLegacy) 'Old INI invented a default or was rewritten.'
} finally {
    if($rodDialog){$rodDialog.Dispose()}
    [IO.File]::WriteAllBytes($script:settingsPath,$rodIni);$script:equipRodBinding=$savedRod;$script:settingsWarning=''
}
Write-Output 'PASS: rod key starts empty, draft/save/cancel/clear/reload and old INI compatibility, invalid/duplicate fields and write rollback; offline UI only.'
