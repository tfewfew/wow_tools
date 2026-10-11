# Runs last in -UiTest. All game processes/windows and scheduler time are fixtures.
Stop-AllRows
$savedClientClock=$script:schedulerClock
$script:scheduler=New-WowAutoScheduler
$script:schedulerClock=[pscustomobject]@{ElapsedMilliseconds=1000L}
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
            Assert-Ui ($fields[$flavor].Minimum.Increment -eq 1000 -and $dialog.ClientRectangle.Contains($fields[$flavor].Maximum.Bounds)) 'Settings field step/layout failed.'
        }
        $fields.titan.Minimum.Value=9000; $fields.titan.Maximum.Value=13000
        $fields.forerver.Minimum.Value=12000; $fields.forerver.Maximum.Value=18000
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
    }
    finally { $dialog.Dispose() }
    # Reopen and save changed values with an existing destination: exercises File.Replace.
    $dialog=New-WaitSettingsDialog
    try {
        $dialog.Show($form)
        $fields=$dialog.Tag.Inputs
        Assert-Ui ($fields.titan.Minimum.Value -eq 9000 -and $fields.forerver.Maximum.Value -eq 18000) 'Reopened dialog lost first saved values.'
        $fields.titan.Minimum.Value=9500; $fields.titan.Maximum.Value=9500
        $fields.forerver.Minimum.Value=12000; $fields.forerver.Maximum.Value=12000
        $dialog.Tag.Apply.PerformClick()
        Assert-Ui ($dialog.DialogResult -eq 'OK' -and $dialog.Tag.Error.Text -eq '') 'Second save failed to overwrite existing settings.'
        $persisted=[IO.File]::ReadAllText($script:settingsPath) | ConvertFrom-Json
        Assert-Ui ($persisted.titan.MinimumMs -eq 9500 -and $persisted.titan.MaximumMs -eq 9500 -and $persisted.forerver.MinimumMs -eq 12000 -and $persisted.forerver.MaximumMs -eq 12000) 'Second save did not persist both changed ranges.'
        $temporaryFiles=@(Get-ChildItem -LiteralPath (Split-Path $script:settingsPath -Parent) -Filter ((Split-Path $script:settingsPath -Leaf)+'.*.tmp'))
        Assert-Ui ($temporaryFiles.Count -eq 0) 'Second save leaked a temporary settings file.'
    }
    finally { $dialog.Dispose() }
    Set-VersionWaitRanges 1000 1000 2000 2000 -Persist $false
    Import-VersionWaitSettings
    Assert-Ui ($script:versionRanges.titan.MinimumMs -eq 9500 -and $script:versionRanges.forerver.MinimumMs -eq 12000) 'Saved settings did not reload.'
    $savedHash=(Get-FileHash -LiteralPath $script:settingsPath).Hash
    $dialog=New-WaitSettingsDialog
    try {
        $dialog.Show($form)
        $dialog.Tag.Inputs.titan.Minimum.Value=20000
        $dialog.Tag.Apply.PerformClick()
        Assert-Ui ($dialog.Tag.Error.Text -ne '' -and $dialog.DialogResult -ne 'OK' -and $script:versionRanges.titan.MinimumMs -eq 9500) 'Invalid range partially applied.'
        Assert-Ui ((Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $savedHash) 'Invalid edit overwrote saved settings.'
        $dialog.Tag.Inputs.titan.Minimum.Value=1000
        $dialog.Tag.Cancel.PerformClick()
        Assert-Ui ($script:versionRanges.titan.MinimumMs -eq 9500 -and (Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $savedHash) 'Cancel changed settings.'
    }
    finally { $dialog.Dispose() }
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
    $script:editingSettings=$true
    $pausedKeys=$script:workerKeys.Count; $pausedActivations=$script:workerActivations.Count
    Invoke-SchedulerTick 11000; Begin-RefreshScan
    Assert-Ui (-not $script:scanning -and $a.State.Running -and $event.Due -eq $deadline -and $script:workerKeys.Count -eq $pausedKeys -and $script:workerActivations.Count -eq $pausedActivations) 'Editing settings emitted input, switched focus or cancelled overdue work.'
    $script:editingSettings=$false
    Set-VersionWaitRanges 1000 1000 2000 2000 -Persist $false
    Assert-Ui ($a.State.Deadline -eq $deadline -and $event.Due -eq $deadline -and $a.State.MinimumMs -eq 1000 -and $f.State.MinimumMs -eq 2000) 'Runtime settings changed an existing deadline or missed tasks.'
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
    $f.Process.ScanColor='red'; $f.Process.FocusAllowed=$false; $f.Validated=$true
    Start-Row $f; Invoke-SchedulerTick 1000
    Assert-Ui ($f.State.Running -and $f.State.FocusRetryAt -eq 31000) 'Infinite focus failure stopped task.'
    $f.Process.FocusAllowed=$true
    Invoke-SchedulerTick 31000; Invoke-SchedulerTick 31200; Invoke-SchedulerTick 31201
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
Write-Output 'PASS: mixed Titan/Infinite UI/scan/start, retail exclusion, shared waits, settings dialog/first-save/overwrite/reload/invalid/cancel, immutable pending deadlines, moving/minimized monitors, Infinite focus recovery and exit/client identity. All native actions mocked.'
