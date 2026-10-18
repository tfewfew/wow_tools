# Per-client timeout configuration. -UiTest supplies all process/input/audio mocks.
Stop-AllRows
$timeoutSource=Join-Path (Split-Path $PSScriptRoot -Parent) 'config.ini'
$timeoutSourceHash=(Get-FileHash -LiteralPath $timeoutSource).Hash
$savedTimeoutIni=[IO.File]::ReadAllBytes($script:settingsPath)
$savedTimeoutClock=$script:schedulerClock
$savedTimeoutScheduler=$script:scheduler
$savedTimeoutPreferences=@{
    TitanMinimum=$script:versionRanges.titan.MinimumMs; TitanMaximum=$script:versionRanges.titan.MaximumMs
    ForerverMinimum=$script:versionRanges.forerver.MinimumMs; ForerverMaximum=$script:versionRanges.forerver.MaximumMs
    TitanAudioTimeoutMs=$script:versionRanges.titan.AudioTimeoutMs; ForerverAudioTimeoutMs=$script:versionRanges.forerver.AudioTimeoutMs
    FocusRetryIntervalMs=$script:scheduler.FocusRetryIntervalMs
    TitanAudioThresholdPercent=$script:audioThresholds.titan; ForerverAudioThresholdPercent=$script:audioThresholds.forerver
    ReelHoldMs=$script:scheduler.ReelHoldMs; KeyBindings=$script:keyBindings
    AudioDetectionEnabled=$script:audioDetectionEnabled; ProcessItemPreferences=$script:processItemPreferences.Clone(); Persist=$false
}
try {
    Set-VersionWaitRanges 300 300 600 600 -Persist $false -TitanAudioTimeoutMs 35000 -ForerverAudioTimeoutMs 35000
    $dialog=New-WaitSettingsDialog
    try {
        $dialog.Show($form)
        [System.Windows.Forms.Application]::DoEvents()
        foreach($flavor in @('titan','forerver')) {
            $field=$dialog.Tag.Inputs[$flavor].AudioTimeout
            Assert-Ui ($field.Value -eq 35000 -and $field.Minimum -eq 1000 -and $field.Maximum -eq 3600000 -and $field.Increment -eq 1000 -and $dialog.ClientRectangle.Contains($field.Bounds)) 'Timeout default/range/step/layout failed.'
        }
        foreach($label in $dialog.Controls | Where-Object {$_ -is [System.Windows.Forms.Label] -and $_.Top -eq 18}) {
            $measured=[System.Windows.Forms.TextRenderer]::MeasureText($label.Text,$label.Font)
            Assert-Ui ($dialog.ClientRectangle.Contains($label.Bounds) -and $measured.Width -le $label.Width -and $measured.Height -le $label.Height) 'Settings column heading clipped.'
        }
        if ($env:WOWAUTO_TIMEOUT_PREVIEW_PATH) {
            $preview=New-Object System.Drawing.Bitmap($dialog.Width,$dialog.Height)
            try {
                $dialog.DrawToBitmap($preview,(New-Object System.Drawing.Rectangle(0,0,$dialog.Width,$dialog.Height)))
                $preview.Save($env:WOWAUTO_TIMEOUT_PREVIEW_PATH,[System.Drawing.Imaging.ImageFormat]::Png)
            }
            finally {$preview.Dispose()}
        }
        $dialog.Tag.Inputs.titan.AudioTimeout.Value=25000
        $dialog.Tag.Inputs.forerver.AudioTimeout.Value=45000
        Assert-Ui ($script:versionRanges.titan.AudioTimeoutMs -eq 35000) 'Editing timeout applied an unsaved draft.'
        $dialog.Tag.Apply.PerformClick()
        Assert-Ui ($dialog.DialogResult -eq 'OK' -and $script:versionRanges.titan.AudioTimeoutMs -eq 25000 -and $script:versionRanges.forerver.AudioTimeoutMs -eq 45000) 'Separate timeout save failed.'
    }
    finally {$dialog.Dispose()}
    $dialog=New-WaitSettingsDialog
    try {
        $dialog.Show($form)
        Assert-Ui ($dialog.Tag.Inputs.titan.AudioTimeout.Value -eq 25000 -and $dialog.Tag.Inputs.forerver.AudioTimeout.Value -eq 45000) 'Reopen lost client timeouts.'
        $dialog.Tag.Inputs.titan.AudioTimeout.Value=26000; $dialog.Tag.Inputs.forerver.AudioTimeout.Value=48000
        $dialog.Tag.Apply.PerformClick()
        Assert-Ui ($dialog.DialogResult -eq 'OK') 'Second timeout save failed.'
    }
    finally {$dialog.Dispose()}
    $savedTimeoutFullIni=[IO.File]::ReadAllText($script:settingsPath)
    Set-VersionWaitRanges 300 300 600 600 -Persist $false -TitanAudioTimeoutMs 35000 -ForerverAudioTimeoutMs 35000
    Import-VersionWaitSettings
    Assert-Ui ($script:settingsWarning -eq '' -and $script:versionRanges.titan.AudioTimeoutMs -eq 26000 -and $script:versionRanges.forerver.AudioTimeoutMs -eq 48000) 'Startup import lost separate timeouts.'
    $iniHash=(Get-FileHash -LiteralPath $script:settingsPath).Hash
    $dialog=New-WaitSettingsDialog
    try {
        $dialog.Show($form); $dialog.Tag.Inputs.titan.AudioTimeout.Value=55000; $dialog.Tag.Cancel.PerformClick()
        Assert-Ui ($script:versionRanges.titan.AudioTimeoutMs -eq 26000 -and (Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $iniHash) 'Cancel applied or saved timeout draft.'
    }
    finally {$dialog.Dispose()}
    $locked=[IO.File]::Open($script:settingsPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try {
        $dialog=New-WaitSettingsDialog
        try {
            $dialog.Show($form); $dialog.Tag.Inputs.titan.AudioTimeout.Value=55000; $dialog.Tag.Inputs.forerver.AudioTimeout.Value=65000
            $dialog.Tag.Apply.PerformClick()
            Assert-Ui ($dialog.DialogResult -ne 'OK' -and $dialog.Tag.Error.Text -ne '' -and $script:versionRanges.titan.AudioTimeoutMs -eq 26000 -and $script:versionRanges.forerver.AudioTimeoutMs -eq 48000) 'Failed timeout write partially applied.'
        }
        finally {$dialog.Dispose()}
    }
    finally {$locked.Dispose()}
    Assert-Ui ((Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $iniHash) 'Failed timeout write damaged INI.'
    foreach($flavor in @('titan','forerver')) {
        foreach($invalid in @('0','999','3600001','1.5','-1','invalid','999999999999999999999999')) {
            $arguments=@{Persist=$true}
            $arguments[$(if($flavor -eq 'titan'){'TitanAudioTimeoutMs'}else{'ForerverAudioTimeoutMs'})]=$invalid
            $rejected=$false
            try {Set-VersionWaitRanges 1 1 1 1 @arguments} catch {$rejected=$true}
            Assert-Ui ($rejected -and $script:versionRanges.titan.AudioTimeoutMs -eq 26000 -and $script:versionRanges.forerver.AudioTimeoutMs -eq 48000 -and $script:versionRanges.titan.MinimumMs -eq 300 -and (Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $iniHash) 'Invalid timeout partially applied or saved.'
        }
    }
    foreach($invalidIni in @(
        ($savedTimeoutFullIni -replace '(?m)^TitanAudioTimeoutMs=.*\r?\n?', ''),
        ($savedTimeoutFullIni -replace '(?m)^ForerverAudioTimeoutMs=.*\r?\n?', ''),
        ($savedTimeoutFullIni.Replace('TitanAudioTimeoutMs=26000','TitanAudioTimeoutMs=999')),
        ($savedTimeoutFullIni.Replace('ForerverAudioTimeoutMs=48000','ForerverAudioTimeoutMs=3600001')),
        ($savedTimeoutFullIni+"titanaudiotimeoutms=55000`r`n")
    )) {
        [IO.File]::WriteAllText($script:settingsPath,$invalidIni)
        $invalidHash=(Get-FileHash -LiteralPath $script:settingsPath).Hash
        Import-VersionWaitSettings
        Assert-Ui ($script:settingsWarning -ne '' -and $script:versionRanges.titan.AudioTimeoutMs -eq 26000 -and $script:versionRanges.forerver.AudioTimeoutMs -eq 48000 -and (Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $invalidHash) 'Invalid timeout INI partially applied or was rewritten.'
    }
    $legacy=$savedTimeoutFullIni -replace '(?m)^(Titan|Forerver)AudioTimeoutMs=.*\r?\n?', ''
    [IO.File]::WriteAllText($script:settingsPath,$legacy)
    $legacyHash=(Get-FileHash -LiteralPath $script:settingsPath).Hash
    Set-VersionWaitRanges 300 300 600 600 -Persist $false -TitanAudioTimeoutMs 35000 -ForerverAudioTimeoutMs 35000
    Import-VersionWaitSettings
    Assert-Ui ($script:settingsWarning -eq '' -and $script:versionRanges.titan.AudioTimeoutMs -eq 35000 -and $script:versionRanges.forerver.AudioTimeoutMs -eq 35000 -and (Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $legacyHash) 'Legacy twelve-key INI failed or was rewritten.'
    $script:scheduler=New-WowAutoScheduler
    $script:schedulerClock=[pscustomobject]@{ElapsedMilliseconds=1000L}
    $script:audioDetectionEnabled=$true
    Set-VersionWaitRanges 300 300 600 600 -Persist $false -TitanAudioTimeoutMs 5000 -ForerverAudioTimeoutMs 20000
    $t=@($script:rows.Values | Where-Object {$_.Client.Flavor -eq 'titan'})[0]
    $f=@($script:rows.Values | Where-Object {$_.Client.Flavor -eq 'forerver'})[0]
    foreach($row in @($t,$f)) {
        $row.Validated=$true; $row.Exited=$false; $row.Process.HasExited=$false; $row.Process.FocusAllowed=$true; $row.Process.ScanColor='green'; $row.SlotUseItem=$false
        Start-Row $row
        $row.State.AudioReady=$true
        $null=Complete-WowAutoPoll $script:scheduler $row.Key 1000 'green'
    }
    Assert-Ui ($t.State.AudioTimeoutMs -eq 5000 -and $f.State.AudioTimeoutMs -eq 20000 -and $t.State.Deadline -eq 6000 -and $f.State.Deadline -eq 21000) 'Mixed-client tasks used the same protection time.'
    $oldDue=@($script:scheduler.Events | Where-Object Kind -eq 'AudioTimeout' | Sort-Object Key | ForEach-Object Due) -join ','
    Set-VersionWaitRanges 300 300 600 600 -Persist $false -TitanAudioTimeoutMs 9000 -ForerverAudioTimeoutMs 25000
    Assert-Ui ($t.State.AudioTimeoutMs -eq 9000 -and $f.State.AudioTimeoutMs -eq 25000 -and $t.State.Deadline -eq 6000 -and $f.State.Deadline -eq 21000 -and (@($script:scheduler.Events | Where-Object Kind -eq 'AudioTimeout' | Sort-Object Key | ForEach-Object Due) -join ',') -eq $oldDue) 'Runtime edit moved existing protection deadlines.'
    $null=Complete-WowAutoAudioBite $script:scheduler $f.Key 2500 $f.State.AudioSession
    Assert-Ui ($f.State.AudioReelPending -and $f.State.Deadline -eq 3100 -and @($script:scheduler.Events | Where-Object {$_.Key -eq $f.Key -and $_.Kind -eq 'AudioTimeout'}).Count -eq 0) 'Match failed to cancel its client timeout.'
    Set-VersionWaitRanges 300 300 600 600 -Persist $false -ForerverAudioTimeoutMs 26000
    Assert-Ui ($f.State.Deadline -eq 3100) 'Timeout edit moved a matched reel deadline.'
    $script:workerFocus=$f.Process.Id
    Invoke-SchedulerTick 3100
    Assert-Ui ((Get-WowAutoCycleCount $script:scheduler $f.Key) -eq 1) 'Other client reel was blocked by the first client protection event.'
    Stop-Row $f
    Assert-Ui ($null -eq (Get-WowAutoWork $script:scheduler 5999)) 'Protection fired before its saved deadline.'
    $script:workerFocus=$t.Process.Id
    $keysBeforeTimeout=$script:workerKeys.Count
    Invoke-SchedulerTick 6000
    Assert-Ui ($t.State.Mode -eq 'Ready' -and $t.State.Status -match '5000 ms内' -and $script:workerKeys.Count -eq $keysBeforeTimeout -and (Get-WowAutoCycleCount $script:scheduler $t.Key) -eq 0) 'Timeout sent/counted a reel or reported the new duration for an old event.'
    Assert-Ui ((Get-WowAutoBiteTimeoutCount $script:scheduler $t.Key) -eq 1 -and (Get-WowAutoBiteTimeoutCount $script:scheduler $f.Key) -eq 0 -and
        $t.Name.Text -match '循环 0 · 无咬钩超时 1' -and $t.Name.Text -notmatch '职业：') 'No-bite timeout counter is missing, misplaced or not isolated to its process.'
    $null=Complete-WowAutoPoll $script:scheduler $t.Key 7000 'red'
    Complete-WowAutoCast $script:scheduler $t.Key $true
    $null=Complete-WowAutoPoll $script:scheduler $t.Key 7200 'green'
    Assert-Ui ($t.State.Deadline -eq 16200) 'Next fishing wait ignored the newly configured client timeout.'
    Stop-AllRows
    $script:audioDetectionEnabled=$false
    Start-Row $t
    $null=Complete-WowAutoPoll $script:scheduler $t.Key 20000 'green'
    Assert-Ui (-not $t.State.UseAudio -and $t.State.Deadline -eq 20300 -and @($script:scheduler.Events | Where-Object Kind -eq 'AudioTimeout').Count -eq 0) 'Audio protection altered timed mode.'
}
finally {
    Stop-AllRows; $script:schedulerClock=$savedTimeoutClock; $script:scheduler=$savedTimeoutScheduler
    [IO.File]::WriteAllBytes($script:settingsPath,$savedTimeoutIni)
    Set-VersionWaitRanges @savedTimeoutPreferences
}
Assert-Ui ((Get-FileHash -LiteralPath $timeoutSource).Hash -eq $timeoutSourceHash) 'Timeout tests changed the user config.ini.'
Write-Output 'PASS: separate Titan/Infinite protection UI/INI, repeat save/reload/cancel/locked-write/invalid/legacy compatibility, mixed-client deadlines and matched reel isolation, immutable current events/next-round updates, exact timeout/no fake reel count, timed-mode isolation. No game actions.'
