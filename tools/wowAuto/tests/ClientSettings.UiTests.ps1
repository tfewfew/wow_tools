# Runs last in -UiTest. All game processes/windows and scheduler time are fixtures.
Stop-AllRows
$savedClientClock=$script:schedulerClock
$script:scheduler=New-WowAutoScheduler
$script:schedulerClock=[pscustomobject]@{ElapsedMilliseconds=1000L}
$sourceConfigPath=Join-Path (Split-Path $PSScriptRoot -Parent) 'config.ini'
$sourceConfigHash=(Get-FileHash -LiteralPath $sourceConfigPath).Hash
Assert-Ui ($script:settingsPath.EndsWith('.ini') -and $script:settingsPath -ne $sourceConfigPath) 'UiTest must use an isolated INI file.'
try {
    $script:mockProcesses=@()
    foreach ($spec in @(@(401,'titan'),@(402,'titan'),@(403,'forerver'),@(404,'forerver'),@(405,'retail'))) {
        $forever=$spec[1] -eq 'forerver'; $retail=$spec[1] -eq 'retail'
        $mock=[pscustomobject]@{
            Id=$spec[0]; StartTime=[datetime]'2026-10-11'; ProcessName=$(if ($forever -or $retail) {'Wow'} else {'WowClassic'})
            ExecutablePath=$(if ($retail) {'C:\games\_retail_\Wow.exe'} elseif ($forever) {'C:\games\_cn_beta_\Wow.exe'} else {'C:\games\_classic_titan_\WowClassic.exe'})
            FileVersion=$(if ($retail) {'12.1.0.69933'} elseif ($forever) {'1.60.1.70338'} else {'3.80.2.70177'})
            MainWindowTitle="模拟游戏 $($spec[0])"; HasExited=$false; FocusAllowed=$true; ScanColor='red'; LureColor='present'
            WindowBounds=@(20,20,820,520); ScreenBounds=@(0,0,1920,1080); Minimized=$false
        }
        $mock | Add-Member ScriptMethod Refresh { }
        $script:mockProcesses+=$mock
    }
    Begin-RefreshScan; Complete-TestScan
    Assert-Ui ($script:rows.Count -eq 4 -and -not @($script:rows.Values | Where-Object {$_.Process.Id -eq 405}).Count) 'Retail process entered rows/scan.'
    $mixedRows=@($script:rows.Values | Sort-Object {$_.Process.Id})
    foreach ($row in $mixedRows) {
        Assert-Ui ($row.Validated -and $row.Name.Text -match "PID $($row.Process.Id) · $($row.Client.Label) · 左上") 'PID version/location label or mixed-client scan failed.'
        Assert-Ui (@($row.Panel.Controls | Where-Object {$_ -is [System.Windows.Forms.NumericUpDown]}).Count -eq 0) 'Per-process wait inputs remain.'
    }
    Assert-Ui ($settingsButton.Parent -eq $toolbar -and $toolbar.ClientRectangle.Contains($settingsButton.Bounds)) 'Settings button missing/clipped.'
    $dialog=New-WaitSettingsDialog
    try {
        $dialog.Show($form)
        [System.Windows.Forms.Application]::DoEvents()
        $fields=$dialog.Tag.Inputs
        foreach ($flavor in @('titan','forerver')) {
            Assert-Ui ($fields[$flavor].Minimum.Increment -eq 100 -and $fields[$flavor].Maximum.Increment -eq 100 -and $dialog.ClientRectangle.Contains($fields[$flavor].Maximum.Bounds)) 'Settings field step/layout failed.'
            Assert-Ui ($fields[$flavor].AudioThreshold.Minimum -eq 50 -and $fields[$flavor].AudioThreshold.Maximum -eq 100 -and $fields[$flavor].AudioThreshold.Increment -eq 1 -and $dialog.ClientRectangle.Contains($fields[$flavor].AudioThreshold.Bounds)) 'Audio threshold field range/step/layout failed.'
        }
        Assert-Ui ($dialog.Tag.FocusRetry.Value -eq 30000 -and $dialog.Tag.FocusRetry.Minimum -eq 1000 -and $dialog.Tag.FocusRetry.Maximum -eq 3600000 -and $dialog.Tag.FocusRetry.Increment -eq 1000) 'Focus retry default/range/step failed.'
        Assert-Ui ($dialog.ClientRectangle.Contains($dialog.Tag.FocusRetry.Bounds) -and $dialog.ClientRectangle.Contains($dialog.Tag.Apply.Bounds)) 'Focus retry field or save button clipped.'
        Assert-Ui ($dialog.Tag.ReelHold.Value -eq 100 -and $dialog.Tag.ReelHold.Minimum -eq 0 -and $dialog.Tag.ReelHold.Maximum -eq 60000 -and $dialog.Tag.ReelHold.Increment -eq 1 -and $dialog.Tag.ReelHold.Parent -eq $dialog -and $dialog.ClientRectangle.Contains($dialog.Tag.ReelHold.Bounds)) 'Settings reel hold default/range/step/layout failed.'
        $dialog.Tag.ReelHold.Value=275
        Assert-Ui ($script:scheduler.ReelHoldMs -eq 100) 'Reel hold draft applied before save.'
        $fields.titan.Minimum.Value=9000; $fields.titan.Maximum.Value=13000
        $fields.forerver.Minimum.Value=12000; $fields.forerver.Maximum.Value=18000
        $dialog.Tag.FocusRetry.Value=5000
        $fields.titan.AudioThreshold.Value=89; $fields.forerver.AudioThreshold.Value=85
        if ($PreviewPath) {
            $bitmap=New-Object System.Drawing.Bitmap($dialog.Width,$dialog.Height)
            try {
                $dialog.DrawToBitmap($bitmap,(New-Object System.Drawing.Rectangle(0,0,$dialog.Width,$dialog.Height)))
                $bitmap.Save((Join-Path (Split-Path $PreviewPath -Parent) 'wowAuto-settings-preview.png'),[System.Drawing.Imaging.ImageFormat]::Png)
            }
            finally { $bitmap.Dispose() }
        }
        $dialog.Tag.Apply.PerformClick()
        Assert-Ui ($dialog.DialogResult -eq 'OK' -and (Test-Path -LiteralPath $script:settingsPath)) 'Dialog failed to save separate version settings.'
        Assert-Ui ($script:scheduler.ReelHoldMs -eq 275) 'Saving settings did not apply reel hold.'
    }
    finally { $dialog.Dispose() }
    # Reopen and save changed values with an existing destination: exercises File.Replace.
    $dialog=New-WaitSettingsDialog
    try {
        $dialog.Show($form)
        $fields=$dialog.Tag.Inputs
        Assert-Ui ($fields.titan.Minimum.Value -eq 9000 -and $fields.forerver.Maximum.Value -eq 18000 -and $dialog.Tag.FocusRetry.Value -eq 5000) 'Reopened dialog lost first saved values.'
        Assert-Ui ($fields.titan.AudioThreshold.Value -eq 89 -and $fields.forerver.AudioThreshold.Value -eq 85) 'Reopened dialog lost per-version audio thresholds.'
        Assert-Ui ($dialog.Tag.ReelHold.Value -eq 275) 'Reopening settings lost active reel hold.'
        $dialog.Tag.ReelHold.Value=350
        $fields.titan.Minimum.Value=9500; $fields.titan.Maximum.Value=9500
        $fields.forerver.Minimum.Value=12000; $fields.forerver.Maximum.Value=12000
        $dialog.Tag.FocusRetry.Value=7500
        $fields.titan.AudioThreshold.Value=88; $fields.forerver.AudioThreshold.Value=87
        $previousHoldUntil=$script:scheduler.ReelHoldUntil
        $script:scheduler.ReelHoldUntil=20000L
        $dialog.Tag.Apply.PerformClick()
        Assert-Ui ($script:scheduler.ReelHoldMs -eq 350 -and $script:scheduler.ReelHoldUntil -eq 20000L) 'Saving reel hold changed the current hold deadline or failed to apply future duration.'
        $script:scheduler.ReelHoldUntil=$previousHoldUntil
        Assert-Ui ($dialog.DialogResult -eq 'OK' -and $dialog.Tag.Error.Text -eq '') 'Second save failed to overwrite existing settings.'
        $persisted=Read-WowAutoSettingsIni $script:settingsPath
        Assert-Ui ($persisted.TitanMinimumMs -eq 9500 -and $persisted.TitanMaximumMs -eq 9500 -and $persisted.ForerverMinimumMs -eq 12000 -and $persisted.ForerverMaximumMs -eq 12000) 'Second save did not persist both changed ranges.'
        Assert-Ui ($persisted.FocusRetryIntervalMs -eq 7500 -and $script:scheduler.FocusRetryIntervalMs -eq 7500 -and $settingsSummary.Text -match '焦点重试 7500') 'Saved focus retry not persisted/applied/displayed.'
        Assert-Ui ($persisted.TitanAudioThresholdPercent -eq 88 -and $persisted.ForerverAudioThresholdPercent -eq 87 -and $script:audioThresholds.titan -eq 88 -and $script:audioThresholds.forerver -eq 87) 'Second save did not persist/apply the two thresholds.'
        $temporaryFiles=@(Get-ChildItem -LiteralPath (Split-Path $script:settingsPath -Parent) -Filter ((Split-Path $script:settingsPath -Leaf)+'.*.tmp'))
        Assert-Ui ($temporaryFiles.Count -eq 0) 'Second save leaked a temporary settings file.'
    }
    finally { $dialog.Dispose() }
    Set-VersionWaitRanges 1000 1000 2000 2000 -Persist $false -FocusRetryIntervalMs 30000 -TitanAudioThresholdPercent 50 -ForerverAudioThresholdPercent 100
    Import-VersionWaitSettings
    Assert-Ui ($script:versionRanges.titan.MinimumMs -eq 9500 -and $script:versionRanges.forerver.MinimumMs -eq 12000 -and $script:scheduler.FocusRetryIntervalMs -eq 7500) 'Saved settings did not reload.'
    Assert-Ui ($script:audioThresholds.titan -eq 88 -and $script:audioThresholds.forerver -eq 87) 'Audio thresholds did not reload.'
    # INI supports comments, blank lines, whitespace, case-insensitive keys and UTF-8 BOM.
    $savedIni=[IO.File]::ReadAllText($script:settingsPath)
    try {
        $commented="# 自定义配置`r`n`r`n"+$savedIni.Replace('TitanMinimumMs=9500','  titanminimumms = 9500  ')
        [IO.File]::WriteAllText($script:settingsPath,$commented,(New-Object Text.UTF8Encoding($true)))
        Set-VersionWaitRanges 1000 1000 2000 2000 -Persist $false -FocusRetryIntervalMs 30000
        Import-VersionWaitSettings
        Assert-Ui ($script:versionRanges.titan.MinimumMs -eq 9500 -and $script:versionRanges.forerver.MinimumMs -eq 12000 -and $script:scheduler.FocusRetryIntervalMs -eq 7500 -and $script:settingsWarning -eq '') 'Commented INI failed to reload.'
        foreach ($invalidIni in @(
            ($savedIni+"titanminimumms=1000`r`n"),
            ($savedIni -replace '(?m)^FocusRetryIntervalMs=.*\r?\n?', ''),
            ($savedIni.Replace('FocusRetryIntervalMs=7500','FocusRetryIntervalMs=0')),
            ($savedIni.Replace('TitanAudioThresholdPercent=88','TitanAudioThresholdPercent=49')),
            ($savedIni.Replace('ForerverAudioThresholdPercent=87','ForerverAudioThresholdPercent=101')),
            ($savedIni -replace '(?m)^TitanAudioThresholdPercent=.*\r?\n?', ''),
            ($savedIni.Replace('TitanMinimumMs=9500','TitanMinimumMs=20000')),
            ($savedIni.Replace('ForerverMaximumMs=12000','ForerverMaximumMs=abc')),
            ($savedIni+"UnknownKey=1234`r`n"),
            ($savedIni+"[autofish]`r`n"),
            ($savedIni+"broken line`r`n")
        )) {
            [IO.File]::WriteAllText($script:settingsPath,$invalidIni)
            $invalidHash=(Get-FileHash -LiteralPath $script:settingsPath).Hash
            Import-VersionWaitSettings
            Assert-Ui ($script:scheduler.FocusRetryIntervalMs -eq 7500 -and $script:versionRanges.titan.MinimumMs -eq 9500 -and $script:versionRanges.forerver.MaximumMs -eq 12000 -and $script:settingsWarning -ne '') 'Invalid INI partially applied or lacked a warning.'
            Assert-Ui ($script:audioThresholds.titan -eq 88 -and $script:audioThresholds.forerver -eq 87) 'Invalid INI partially applied an audio threshold.'
            Assert-Ui ((Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $invalidHash) 'Import rewrote invalid INI.'
        }
        $legacy=$savedIni -replace '(?m)^(Titan|Forerver)AudioThresholdPercent=.*\r?\n?', ''
        [IO.File]::WriteAllText($script:settingsPath,$legacy)
        $legacyHash=(Get-FileHash -LiteralPath $script:settingsPath).Hash
        Import-VersionWaitSettings
        Assert-Ui ($script:settingsWarning -eq '' -and $script:audioThresholds.titan -eq 88 -and $script:audioThresholds.forerver -eq 87 -and (Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $legacyHash) 'Legacy five-key INI failed or was rewritten on read.'
    }
    finally { [IO.File]::WriteAllText($script:settingsPath,$savedIni); Import-VersionWaitSettings }
    $savedSettingsPath=$script:settingsPath
    try {
        $script:settingsPath=$savedSettingsPath+'.missing'
        Import-VersionWaitSettings
        Assert-Ui ($script:scheduler.FocusRetryIntervalMs -eq 7500 -and $script:versionRanges.titan.MinimumMs -eq 9500 -and $script:settingsWarning -match '不存在') 'Missing INI failed to retain settings/report warning.'
    }
    finally { $script:settingsPath=$savedSettingsPath; Import-VersionWaitSettings }
    $savedHash=(Get-FileHash -LiteralPath $script:settingsPath).Hash
    # A locked file must leave both persisted and running settings unchanged.
    $locked=[IO.File]::Open($script:settingsPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try {
        $rejected=$false
        try { Set-VersionWaitRanges 1000 1000 2000 2000 -FocusRetryIntervalMs 1000 -TitanAudioThresholdPercent 95 -ForerverAudioThresholdPercent 95 } catch { $rejected=$true }
        Assert-Ui ($rejected -and $script:scheduler.FocusRetryIntervalMs -eq 7500 -and $script:versionRanges.titan.MinimumMs -eq 9500) 'Failed INI write partially applied settings.'
        Assert-Ui ($script:audioThresholds.titan -eq 88 -and $script:audioThresholds.forerver -eq 87) 'Failed INI write partially applied thresholds.'
        $lockedDialog=New-WaitSettingsDialog
        try {
            $lockedDialog.Show($form)
            $lockedDialog.Tag.ReelHold.Value=700
            $lockedDialog.Tag.Apply.PerformClick()
            Assert-Ui ($lockedDialog.DialogResult -ne 'OK' -and $lockedDialog.Tag.Error.Text -ne '' -and $script:scheduler.ReelHoldMs -eq 350) 'Failed settings save partially applied draft reel hold.'
        }
        finally { $lockedDialog.Dispose() }
    }
    finally { $locked.Dispose() }
    Assert-Ui ((Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $savedHash) 'Failed INI write damaged saved settings.'
    Assert-Ui (@(Get-ChildItem -LiteralPath (Split-Path $script:settingsPath -Parent) -Filter ((Split-Path $script:settingsPath -Leaf)+'.*.tmp')).Count -eq 0) 'Failed INI write leaked a temporary file.'
    foreach ($invalid in @('0','999','3600001','1.5','not-an-integer','999999999999999999999999')) {
        $rejected=$false
        try { Set-VersionWaitRanges 1000 1000 2000 2000 -FocusRetryIntervalMs $invalid } catch { $rejected=$true }
        Assert-Ui ($rejected -and $script:scheduler.FocusRetryIntervalMs -eq 7500 -and $script:versionRanges.titan.MinimumMs -eq 9500 -and (Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $savedHash) 'Invalid retry partially applied or saved settings.'
    }
    foreach ($invalid in @('49','101','86.5','NaN','999999999999999999999999')) {
        $rejected=$false
        try { Set-VersionWaitRanges 1000 1000 2000 2000 -ForerverAudioThresholdPercent $invalid } catch { $rejected=$true }
        Assert-Ui ($rejected -and $script:audioThresholds.forerver -eq 87 -and $script:versionRanges.titan.MinimumMs -eq 9500 -and (Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $savedHash) 'Invalid audio threshold partially applied or saved settings.'
    }
    $dialog=New-WaitSettingsDialog
    try {
        $dialog.Show($form)
        $dialog.Tag.Inputs.titan.Minimum.Value=20000
        $dialog.Tag.FocusRetry.Value=1000
        $dialog.Tag.ReelHold.Value=450
        $dialog.Tag.Apply.PerformClick()
        Assert-Ui ($dialog.Tag.Error.Text -ne '' -and $dialog.DialogResult -ne 'OK' -and $script:versionRanges.titan.MinimumMs -eq 9500 -and $script:scheduler.FocusRetryIntervalMs -eq 7500) 'Invalid range partially applied.'
        Assert-Ui ((Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $savedHash) 'Invalid edit overwrote saved settings.'
        Assert-Ui ($script:scheduler.ReelHoldMs -eq 350) 'Invalid settings applied draft reel hold.'
        $dialog.Tag.Inputs.titan.Minimum.Value=1000
        $dialog.Tag.Cancel.PerformClick()
        Assert-Ui ($script:versionRanges.titan.MinimumMs -eq 9500 -and $script:scheduler.FocusRetryIntervalMs -eq 7500 -and (Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $savedHash) 'Cancel changed settings.'
        Assert-Ui ($script:scheduler.ReelHoldMs -eq 350) 'Cancel applied draft reel hold.'
    }
    finally { $dialog.Dispose() }
    Set-WowAutoHoldDuration $script:scheduler 100
    Update-BatchControls; $startAllButton.PerformClick()
    foreach ($row in $mixedRows) {
        $expected=if ($row.Client.Flavor -eq 'titan') {9500} else {12000}
        Assert-Ui ($row.State.Running -and $row.State.MinimumMs -eq $expected -and $row.State.MaximumMs -eq $expected) 'Same-version tasks use different wait ranges.'
    }
    $a=$mixedRows[0]; $b=$mixedRows[1]; $f=$mixedRows[2]
    $script:workerFocus=$a.Process.Id; $a.Process.ScanColor='green'
    Invoke-SchedulerTick 1000
    $deadline=$a.State.Deadline; $event=@($script:scheduler.Events | Where-Object {$_.Key -eq $a.Key})[0]
    Assert-Ui ($deadline -eq 10500) 'Initial version wait not used.'
    Pause-RowForFocus $f 1000 'Simulated focus denial.'
    Assert-Ui ($f.State.FocusRetryAt -eq 8500) 'New failure ignored saved retry interval.'
    $script:editingSettings=$true
    $pausedKeys=$script:workerKeys.Count; $pausedActivations=$script:workerActivations.Count
    Invoke-SchedulerTick 11000; Begin-RefreshScan
    Assert-Ui (-not $script:scanning -and $a.State.Running -and $event.Due -eq $deadline -and $script:workerKeys.Count -eq $pausedKeys -and $script:workerActivations.Count -eq $pausedActivations) 'Editing settings emitted input, switched focus or cancelled overdue work.'
    $script:editingSettings=$false
    Set-VersionWaitRanges 1000 1000 2000 2000 -Persist $false -FocusRetryIntervalMs 2500
    Assert-Ui ($a.State.Deadline -eq $deadline -and $event.Due -eq $deadline -and $a.State.MinimumMs -eq 1000 -and $f.State.MinimumMs -eq 2000 -and $f.State.FocusRetryAt -eq 8500) 'Runtime settings changed an existing deadline or missed tasks.'
    Pause-RowForFocus $f 8500 'Repeated simulated denial.'
    Assert-Ui ($f.State.FocusRetryAt -eq 11000 -and $f.CurrentStatusText -notmatch '每30秒') 'Repeated failure ignored updated retry interval/status.'
    $null=Complete-WowAutoPoll $script:scheduler $b.Key 1100 'green'
    Assert-Ui ($b.State.Deadline -eq 2100) 'New wait ignored updated version settings.'
    $timestamp=$a.StatusTimestamp
    $keysBefore=$script:workerKeys.Count; $activationsBefore=$script:workerActivations.Count
    $a.Process.WindowBounds=@(1100,560,1900,1060)
    Update-WindowPositions
    Assert-Ui ($a.Position -eq '右下' -and $a.Name.Text -match '时光服 · 右下' -and $a.StatusTimestamp -eq $timestamp) 'Moving a window did not update its label independently of status time.'
    $f.Process.ScreenBounds=@(-1920,0,0,1080); $f.Process.WindowBounds=@(-1900,20,-1100,520)
    Update-WindowPositions
    Assert-Ui ($f.Position -eq '左上') 'Second monitor coordinates misclassified.'
    $f.Process.Minimized=$true; Update-WindowPositions
    Assert-Ui ($f.Position -eq '最小化' -and $script:workerKeys.Count -eq $keysBefore -and $script:workerActivations.Count -eq $activationsBefore) 'Position refresh activated a window or sent input.'
    $f.Process.Minimized=$false
    Stop-AllRows
    $script:scheduler=New-WowAutoScheduler
    Set-VersionWaitRanges 1000 1000 2000 2000 -Persist $false -FocusRetryIntervalMs 5000
    $f.Process.ScanColor='red'; $f.Process.FocusAllowed=$false; $f.Validated=$true
    Start-Row $f; Invoke-SchedulerTick 1000
    Assert-Ui ($f.State.Running -and $f.State.FocusRetryAt -eq 6000) 'Infinite focus failure ignored configured retry.'
    $f.Process.FocusAllowed=$true
    $activationsBefore=$script:workerActivations.Count
    Invoke-SchedulerTick 5999
    Assert-Ui ($script:workerActivations.Count -eq $activationsBefore -and $f.State.FocusRetryAt -eq 6000) 'Configured retry activated too early.'
    Invoke-SchedulerTick 6000; Invoke-SchedulerTick 6200; Invoke-SchedulerTick 6201
    Assert-Ui ($f.State.FocusRetryAt -eq 0 -and $script:workerKeys[-1] -eq "$($f.Process.Id):48") 'Infinite task did not recover/cast.'
    $script:scheduler.CompletedCycles[$f.Key]=501
    Close-WorkerGame $f
    Assert-Ui ($script:pendingGameExits.ContainsKey($f.Key) -and -not $f.State.Running) 'Infinite yellow exit guard did not register.'
    $f.Process.FileVersion='12.1.0.69933'
    $killCount=$script:workerKilled.Count
    Invoke-GameExitChecks 31000
    Assert-Ui (-not $script:pendingGameExits.ContainsKey($f.Key) -and $script:workerKilled.Count -eq $killCount) 'Unsupported client survived identity check before exit timeout.'
    $f.Process.FileVersion='1.60.1.70338'; $f.Validated=$true
    Start-Row $f
    $f.Process.ExecutablePath='D:\other\_cn_beta_\Wow.exe'
    Invoke-SchedulerTick 40000
    Assert-Ui (-not $f.State.Running) 'Changed executable path remained scheduled.'
    $f.Process.ExecutablePath=$f.Client.ExecutablePath
    Fit-WindowToContent
}
finally { $script:editingSettings=$false; Stop-AllRows; $script:schedulerClock=$savedClientClock }
Assert-Ui ((Get-FileHash -LiteralPath $sourceConfigPath).Hash -eq $sourceConfigHash) 'UiTest changed the source config.ini.'
Write-Output 'PASS: mixed Titan/Infinite UI/scan/start, retail exclusion, shared waits/configurable focus retry, INI first-save/overwrite/reload/comments/invalid/locked/cancel and source-file isolation, immutable pending deadlines, moving/minimized monitors, configured Infinite focus recovery and exit/client identity. All native actions mocked.'
