# Complete preference persistence; all game actions remain mocked by -UiTest.
Stop-AllRows
$preferenceSourcePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'config.ini'
$preferenceSourceHash=(Get-FileHash -LiteralPath $preferenceSourcePath).Hash
$savedPreferenceIni=[IO.File]::ReadAllBytes($script:settingsPath)
$savedPreferences=@{
    TitanMinimum=$script:versionRanges.titan.MinimumMs; TitanMaximum=$script:versionRanges.titan.MaximumMs
    ForerverMinimum=$script:versionRanges.forerver.MinimumMs; ForerverMaximum=$script:versionRanges.forerver.MaximumMs
    FocusRetryIntervalMs=$script:scheduler.FocusRetryIntervalMs
    TitanAudioThresholdPercent=$script:audioThresholds.titan; ForerverAudioThresholdPercent=$script:audioThresholds.forerver
    ReelHoldMs=$script:scheduler.ReelHoldMs; KeyBindings=$script:keyBindings
    AudioDetectionEnabled=$script:audioDetectionEnabled; ProcessItemPreferences=$script:processItemPreferences.Clone()
    Persist=$false
}
$preferenceRows=@($script:rows.Values | Sort-Object {$_.Process.Id})
$preferenceA=$preferenceRows[0]; $preferenceB=$preferenceRows[1]
$keysBefore=$script:workerKeys.Count; $focusBefore=$script:workerActivations.Count
try {
    # Every key accepted by the UI must survive the human-readable INI format.
    foreach ($code in 1..255) {
        foreach ($mask in 0..7) {
            $binding=New-KeyBinding $code ([bool]($mask -band 1)) ([bool]($mask -band 2)) ([bool]($mask -band 4))
            if ($null -eq $binding) { continue }
            $decoded=ConvertFrom-KeyBindingText $binding.Text
            Assert-Ui ($decoded.Code -eq $binding.Code -and $decoded.Ctrl -eq $binding.Ctrl -and $decoded.Shift -eq $binding.Shift -and $decoded.Alt -eq $binding.Alt) 'Supported key/chord did not round-trip.'
        }
    }
    $dialog=New-WaitSettingsDialog
    try {
        $dialog.Show($form)
        $dialog.Tag.ReelHold.Value=420
        Set-KeyBinding $dialog.Tag.KeyInputs.Cast 49 $true $false $false
        Set-KeyBinding $dialog.Tag.KeyInputs.Reel 187 $false $true $false
        Set-KeyBinding $dialog.Tag.KeyInputs.Item 189 $false $false $true
        $dialog.Tag.Apply.PerformClick()
        Assert-Ui ($dialog.DialogResult -eq 'OK') 'Complete preferences save failed.'
    }
    finally { $dialog.Dispose() }
    $audioCheck.Checked=$true
    $legacyChoices=@{};$legacyChoices[$preferenceA.Key]=$true;$legacyChoices[$preferenceB.Key]=$false;Save-PreferenceSwitches -ProcessItemPreferences $legacyChoices
    $saved=Read-WowAutoSettingsIni $script:settingsPath
    Assert-Ui ($saved.ReelHoldMs -eq 420 -and $saved.CastKey -eq 'Ctrl+1' -and $saved.ReelKey -eq 'Shift+=' -and $saved.ItemKey -eq 'Alt+-' -and $saved.AudioDetectionEnabled -eq 1) 'Hold/keys/audio mode were not persisted.'
    Assert-Ui ($saved.ProcessItemPreferences[$preferenceA.Key] -and -not $saved.ProcessItemPreferences[$preferenceB.Key]) 'Process choices were not persisted independently.'
    $fullIni=[IO.File]::ReadAllText($script:settingsPath)
    # Reset in-memory defaults as a fresh tool process would, then run the startup loader.
    $script:keyBindings=@{Cast=(New-KeyBinding 48 $false $false $false); Reel=(New-KeyBinding 187 $false $false $false); Item=(New-KeyBinding 189 $false $false $false)}
    Set-WowAutoHoldDuration $script:scheduler 100
    $script:audioDetectionEnabled=$false; $script:processItemPreferences=@{}
    Sync-PreferenceControls
    Import-VersionWaitSettings
    Assert-Ui ($script:settingsWarning -eq '' -and $script:scheduler.ReelHoldMs -eq 420 -and $script:keyBindings.Cast.Text -eq 'Ctrl+1' -and $script:keyBindings.Reel.Text -eq 'Shift+=' -and $script:keyBindings.Item.Text -eq 'Alt+-') 'Startup loader lost hold or shortcut preferences.'
    Assert-Ui ($audioCheck.Checked -and $script:processItemPreferences[$preferenceA.Key] -and -not $script:processItemPreferences[$preferenceB.Key] -and $script:scheduler.Tasks.Count -eq 0) 'Startup loader lost checkbox preferences or started a task.'
    $restoredRow=New-ProcessRow $preferenceA.Process $preferenceA.StartTime $preferenceA.Key $preferenceA.Client
    $newStart=$preferenceA.StartTime.AddSeconds(1)
    $reusedRow=New-ProcessRow $preferenceA.Process $newStart "$($preferenceA.Process.Id):$($newStart.Ticks)" $preferenceA.Client
    try { Assert-Ui (-not $restoredRow.SlotUseItem -and -not $reusedRow.SlotUseItem -and -not $restoredRow.Start.Enabled) 'Recreated row lost its selection or a reused PID inherited it.' }
    finally { $restoredRow.Panel.Dispose(); $reusedRow.Panel.Dispose() }
    $beforeHash=(Get-FileHash -LiteralPath $script:settingsPath).Hash
    $locked=[IO.File]::Open($script:settingsPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try {
        $audioCheck.Checked=$false
        $failed=$false;try {Save-PreferenceSwitches -ProcessItemPreferences @{}} catch {$failed=$true};Assert-Ui $failed "Locked legacy INI should reject save."
        Assert-Ui ($audioCheck.Checked -and $script:audioDetectionEnabled -and $script:processItemPreferences[$preferenceA.Key] -and $script:processItemPreferences[$preferenceA.Key]) 'Failed checkbox write was applied instead of rolled back.'
        $dialog=New-WaitSettingsDialog
        try {
            $dialog.Show($form)
            $dialog.Tag.ReelHold.Value=700
            Set-KeyBinding $dialog.Tag.KeyInputs.Cast 113 $false $false $false
            $dialog.Tag.Apply.PerformClick()
            Assert-Ui ($dialog.DialogResult -ne 'OK' -and $dialog.Tag.Error.Text -ne '' -and $script:scheduler.ReelHoldMs -eq 420 -and $script:keyBindings.Cast.Text -eq 'Ctrl+1') 'Failed complete settings write partially applied hold/keys.'
        }
        finally { $dialog.Dispose() }
    }
    finally { $locked.Dispose() }
    Assert-Ui ((Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $beforeHash) 'Failed preference writes damaged the INI.'
    foreach ($invalid in @(
        $fullIni.Replace('ReelHoldMs=420','ReelHoldMs=60001'),
        $fullIni.Replace('AudioDetectionEnabled=1','AudioDetectionEnabled=2'),
        $fullIni.Replace('CastKey=Ctrl+1','CastKey=Ctrl+Ctrl+1'),
        $fullIni.Replace('ReelKey=Shift+=','ReelKey=Shift'),
        ($fullIni -replace '(?m)^ItemKey=.*\r?\n?', ''),
        ($fullIni+"UseItem_999_123=2`r`n"),
        ($fullIni+"UseItem_999_3155378976000000000=1`r`n"),
        ($fullIni+"useitem_$($preferenceA.Key.Replace(':','_'))=0`r`n")
    )) {
        [IO.File]::WriteAllText($script:settingsPath,$invalid)
        $invalidHash=(Get-FileHash -LiteralPath $script:settingsPath).Hash
        Import-VersionWaitSettings
        Assert-Ui ($script:settingsWarning -ne '' -and $script:scheduler.ReelHoldMs -eq 420 -and $script:keyBindings.Cast.Text -eq 'Ctrl+1' -and $audioCheck.Checked -and $script:processItemPreferences[$preferenceA.Key]) 'Invalid preferences partially applied.'
        Assert-Ui ((Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $invalidHash) 'Loader rewrote an invalid preference file.'
    }
    foreach ($legacyCount in @(5,7)) {
        $legacyLines=@('TitanMinimumMs=300','TitanMaximumMs=600','ForerverMinimumMs=300','ForerverMaximumMs=600','FocusRetryIntervalMs=20000')
        if ($legacyCount -eq 7) { $legacyLines+=@('TitanAudioThresholdPercent=86','ForerverAudioThresholdPercent=86') }
        [IO.File]::WriteAllText($script:settingsPath,($legacyLines -join "`r`n")+"`r`n")
        $legacyHash=(Get-FileHash -LiteralPath $script:settingsPath).Hash
        Import-VersionWaitSettings
        Assert-Ui ($script:settingsWarning -eq '' -and $script:scheduler.ReelHoldMs -eq 420 -and $script:keyBindings.Reel.Text -eq 'Shift+=' -and $audioCheck.Checked -and -not $script:processItemPreferences[$preferenceA.Key]) 'Legacy INI compatibility lost defaults or kept unrecorded process choices.'
        Assert-Ui ((Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $legacyHash) 'Startup rewrote a legacy INI.'
    }
    Assert-Ui ($script:workerKeys.Count -eq $keysBefore -and $script:workerActivations.Count -eq $focusBefore -and $script:scheduler.Tasks.Count -eq 0) 'Preference restoration sent game input, switched focus or started work.'
}
finally {
    [IO.File]::WriteAllBytes($script:settingsPath,$savedPreferenceIni)
    Set-VersionWaitRanges @savedPreferences
}
Assert-Ui ((Get-FileHash -LiteralPath $preferenceSourcePath).Hash -eq $preferenceSourceHash) 'Preference tests modified the source config.ini.'
Write-Output 'PASS: all supported key/chord round-trips, full INI hold/keys/audio/per-process choices, legacy INI restoration without a per-process checkbox, PID reuse isolation, locked-write rollback, malformed/partial/duplicate validation, legacy 5/7-key compatibility. No game actions.'
