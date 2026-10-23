# Draft and atomic INI persistence; this suite runs only with -UiTest substitutes.
function Assert-DirectSettings($Condition,[string]$Message){if(-not $Condition){throw $Message}}
Stop-AllRows
$savedDirectSettings=$script:directStartUseItem;$savedDirectWarning=$script:settingsWarning
$directIniExisted=[IO.File]::Exists($script:settingsPath)
$directIniBackup=if($directIniExisted){[IO.File]::ReadAllBytes($script:settingsPath)}else{$null}
$directDialog=$null
try {
    $rangeT=$script:versionRanges.titan;$rangeF=$script:versionRanges.forerver
    Set-VersionWaitRanges $rangeT.MinimumMs $rangeT.MaximumMs $rangeF.MinimumMs $rangeF.MaximumMs -DirectStartUseItem $false
    $directDialog=New-WaitSettingsDialog;$directDialog.Show($form)
    $directBox=$directDialog.Tag.DirectStartUseItem
    Assert-DirectSettings (-not $directBox.Checked -and $directBox -is [WowAuto.DimCheckBox] -and
        $directBox.Parent.Text -eq '直接开始（所有进程）' -and $directBox.Parent.ClientRectangle.Contains($directBox.Bounds) -and
        $directDialog.ClientRectangle.Contains($directBox.Parent.Bounds) -and $directDialog.ClientRectangle.Contains($directDialog.Tag.Apply.Bounds)) 'Direct-start group/default/layout is invalid.'
    $directBox.Checked=$true
    Assert-DirectSettings (-not $script:directStartUseItem) 'Direct-start draft applied before saving.'
    if($env:WOWAUTO_PARALLEL_PREVIEW){
        $preview=New-Object Drawing.Bitmap($directDialog.Width,$directDialog.Height)
        try{$directDialog.DrawToBitmap($preview,(New-Object Drawing.Rectangle(0,0,$preview.Width,$preview.Height)));$preview.Save((Join-Path $env:WOWAUTO_PARALLEL_PREVIEW 'direct-start-settings.png'))}finally{$preview.Dispose()}
    }
    $directDialog.Tag.Cancel.PerformClick();$directDialog.Dispose()
    $directDialog=New-WaitSettingsDialog;$directDialog.Show($form)
    Assert-DirectSettings (-not $directDialog.Tag.DirectStartUseItem.Checked) 'Cancelled direct-start draft survived reopening.'
    $directDialog.Tag.DirectStartUseItem.Checked=$true
    $beforeInvalid=(Get-FileHash -LiteralPath $script:settingsPath).Hash
    $directDialog.Tag.Inputs.titan.Minimum.Value=3600000;$directDialog.Tag.Apply.PerformClick()
    Assert-DirectSettings (-not $script:directStartUseItem -and $directDialog.Tag.Error.Text -ne '' -and (Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $beforeInvalid) 'Invalid settings partially saved/applied the direct-start flag.'
    $directDialog.Tag.Inputs.titan.Minimum.Value=$rangeT.MinimumMs;$directDialog.Tag.Apply.PerformClick();$directDialog.Dispose()
    Assert-DirectSettings ($script:directStartUseItem -and (Read-WowAutoSettingsIni $script:settingsPath).DirectStartUseItem -eq 1) 'Direct-start flag was not saved.'
    $enabledDirectIni=[IO.File]::ReadAllText($script:settingsPath)
    $script:directStartUseItem=$false;Import-VersionWaitSettings
    Assert-DirectSettings ($script:settingsWarning -eq '' -and $script:directStartUseItem) 'Direct-start flag did not survive restart/import.'
    foreach($invalid in @($enabledDirectIni.Replace('DirectStartUseItem=1','DirectStartUseItem=2'),$enabledDirectIni.Replace('DirectStartUseItem=1','DirectStartUseItem='),($enabledDirectIni+"directstartuseitem=0`r`n"))){
        [IO.File]::WriteAllText($script:settingsPath,$invalid);Import-VersionWaitSettings
        Assert-DirectSettings ($script:settingsWarning -ne '' -and $script:directStartUseItem) 'Invalid/duplicate direct-start flag partially applied.'
    }
    [IO.File]::WriteAllText($script:settingsPath,($enabledDirectIni -replace '(?m)^DirectStartUseItem=.*\r?\n?',''))
    $legacyHash=(Get-FileHash -LiteralPath $script:settingsPath).Hash;Import-VersionWaitSettings
    Assert-DirectSettings ($script:settingsWarning -eq '' -and -not $script:directStartUseItem -and (Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $legacyHash) 'Old INI did not use the independent off default without rewriting.'
    [IO.File]::WriteAllText($script:settingsPath,$enabledDirectIni);Import-VersionWaitSettings
    $directDialog=New-WaitSettingsDialog;$directDialog.Show($form);$directDialog.Tag.DirectStartUseItem.Checked=$false
    $locked=[IO.File]::Open($script:settingsPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try{$directDialog.Tag.Apply.PerformClick()}finally{$locked.Dispose()}
    Assert-DirectSettings ($script:directStartUseItem -and $directDialog.DialogResult -ne 'OK') 'Failed write applied the direct-start draft.'
    $directDialog.Tag.Apply.PerformClick();$directDialog.Dispose()
    $script:directStartUseItem=$true;Import-VersionWaitSettings
    Assert-DirectSettings ($script:settingsWarning -eq '' -and -not $script:directStartUseItem) 'Disabled direct-start flag did not round-trip.'
    Write-Output 'PASS: direct-start global fish settings group, draft/cancel/atomic save/import, off default for old INI, invalid/duplicate rejection and write rollback. No game input.'
} finally {
    if($directDialog){$directDialog.Dispose()}
    if($directIniExisted){[IO.File]::WriteAllBytes($script:settingsPath,$directIniBackup)}elseif([IO.File]::Exists($script:settingsPath)){[IO.File]::Delete($script:settingsPath)}
    $script:directStartUseItem=$savedDirectSettings;$script:settingsWarning=$savedDirectWarning
}
