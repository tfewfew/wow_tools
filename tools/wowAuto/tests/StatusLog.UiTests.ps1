# Only mocked processes/capture/input and an isolated INI are used by -UiTest.
Stop-AllRows
$logSource=Join-Path (Split-Path $PSScriptRoot -Parent) 'config.ini'
$logSourceHash=(Get-FileHash -LiteralPath $logSource).Hash
$savedLogIni=[IO.File]::ReadAllBytes($script:settingsPath)
$savedLogScheduler=$script:scheduler; $savedLogClock=$script:schedulerClock; $savedLogTemplate=$script:audioUseTemplate
$logKeys=$script:workerKeys.Count; $logActivations=$script:workerActivations.Count
try {
    $script:scheduler=New-WowAutoScheduler
    $script:schedulerClock=[pscustomobject]@{ElapsedMilliseconds=1000L}
    $script:audioUseTemplate=$false
    Set-VersionWaitRanges 300 600 700 700 -StatusLogLimit 50
    $a=@($script:rows.Values | Where-Object {$_.Client.Flavor -eq 'titan'})[0]
    $b=@($script:rows.Values | Where-Object {$_.Client.Flavor -eq 'forerver'})[0]
    foreach($row in @($a,$b)) {$row.State=$null; $row.StatusHistory.Clear(); $row.StatusSnapshot=$null}
    for($n=1;$n -le 60;$n++) {Set-RowStatusText $a ("history-event-$n")}
    Assert-Ui ($a.StatusHistory.Count -eq 50 -and $a.StatusHistory[0] -match 'history-event-11$' -and $a.StatusHistory[49] -match 'history-event-60$') 'Default history did not evict the oldest records at 50.'
    Assert-Ui ($a.Status.Text.StartsWith($a.CurrentStatusText) -and $a.Status.Text.IndexOf('history-event-60') -lt $a.Status.Text.IndexOf('history-event-11') -and $a.Status.Text -notmatch 'history-event-10(?:\r?\n|$)') 'Visible history ordering/eviction failed.'
    $stableStamp=$a.StatusTimestamp; $stableHistory=$a.StatusHistory -join '|'
    for($n=0;$n -lt 100;$n++) {Update-RowStatus $a}
    Assert-Ui ($a.StatusTimestamp -eq $stableStamp -and ($a.StatusHistory -join '|') -ceq $stableHistory) 'Unchanged polling appended logs or refreshed timestamps.'
    Set-RowStatusText $b 'independent-history'
    Assert-Ui ($b.StatusHistory.Count -eq 1 -and ($a.StatusHistory -join '|') -ceq $stableHistory) 'Another process changed this process history.'
    $script:audioDetectionEnabled=$true
    foreach($row in @($a,$b)) {$row.Validated=$true; $row.Exited=$false; $row.Process.HasExited=$false; $row.SlotUseItem=$false}
    Start-Row $a; $a.State.AudioReady=$true
    $null=Complete-WowAutoPoll $script:scheduler $a.Key 1000 'green'
    Update-RowStatus $a
    Assert-Ui ($a.State.ReelDelayMs -eq 0 -and $a.CurrentStatusText -notmatch '当前随机延迟') 'Audio protection was shown as an already sampled reel delay.'
    $script:schedulerClock.ElapsedMilliseconds=2500
    Assert-Ui (Complete-WowAutoAudioBite $script:scheduler $a.Key 2500 $a.State.AudioSession) 'Mock audio match rejected.'
    Update-RowStatus $a
    $sampled=$a.State.ReelDelayMs; $due=$a.State.Deadline
    Assert-Ui ($sampled -ge 300 -and $sampled -le 600 -and $due -eq 2500+$sampled -and $a.CurrentStatusText.Contains("当前随机延迟：$sampled ms")) 'Displayed random delay did not equal the registered event delay.'
    $delayHistory=$a.StatusHistory -join '|'; $delayStamp=$a.StatusTimestamp
    $script:audioCaptures[$a.Key].Capture.Peak=0.12
    $script:schedulerClock.ElapsedMilliseconds=2501
    Update-RowStatus $a
    Assert-Ui ($a.CurrentStatusText -match '12%' -and $a.CurrentStatusText.Contains("剩余 $($sampled-1) ms") -and $a.StatusTimestamp -eq $delayStamp -and ($a.StatusHistory -join '|') -ceq $delayHistory) 'Live metrics/countdown overwrote old logs, added entries or refreshed timestamp.'
    Set-VersionWaitRanges 800 900 700 700 -StatusLogLimit 50
    Assert-Ui ($a.State.ReelDelayMs -eq $sampled -and $a.State.Deadline -eq $due) 'Editing the range resampled/moved a pending reel.'
    $dialog=New-WaitSettingsDialog
    try {
        $dialog.Show($form); [System.Windows.Forms.Application]::DoEvents()
        $labels=@($dialog.Controls | Where-Object {$_ -is [System.Windows.Forms.Label]} | ForEach-Object Text)
        Assert-Ui ($labels -contains '收杆延迟区间配置（ms）' -and $labels -notcontains '最小等待（ms）' -and $labels -notcontains '最大等待（ms）') 'Range name did not consolidate into one header.'
        foreach($fields in $dialog.Tag.Inputs.Values) {
            Assert-Ui ($fields.Separator.Text -eq '-' -and $fields.Separator.Left -ge $fields.Minimum.Right -and $fields.Separator.Right -le $fields.Maximum.Left -and $fields.Minimum.Increment -eq 100 -and $fields.Maximum.Increment -eq 100) 'Range separator or 100-ms steps failed.'
        }
        Assert-Ui ($dialog.Tag.StatusLogLimit.Value -eq 50 -and $dialog.ClientRectangle.Contains($dialog.Tag.StatusLogLimit.Bounds)) 'History settings control clipped or incorrect.'
        if($env:WOWAUTO_STATUSLOG_PREVIEW_DIRECTORY) {
            $bitmap=New-Object Drawing.Bitmap($dialog.Width,$dialog.Height)
            try {$dialog.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$dialog.Width,$dialog.Height)));$bitmap.Save((Join-Path $env:WOWAUTO_STATUSLOG_PREVIEW_DIRECTORY 'settings.png'),[Drawing.Imaging.ImageFormat]::Png)}
            finally {$bitmap.Dispose()}
            $bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height)
            try {$form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)));$bitmap.Save((Join-Path $env:WOWAUTO_STATUSLOG_PREVIEW_DIRECTORY 'main.png'),[Drawing.Imaging.ImageFormat]::Png)}
            finally {$bitmap.Dispose()}
        }
        $dialog.Tag.StatusLogLimit.Value=3; $dialog.Tag.Apply.PerformClick()
        Assert-Ui ($dialog.DialogResult -eq 'OK' -and $script:statusLogLimit -eq 3 -and $a.StatusHistory.Count -eq 3 -and $b.StatusHistory.Count -le 3 -and (Read-WowAutoSettingsIni $script:settingsPath).StatusLogLimit -eq 3) 'Saving history limit did not persist/trim all rows.'
    } finally {$dialog.Dispose()}
    $a.Status.Select($a.Status.TextLength,0); $a.Status.ScrollToCaret()
    $firstLine=$a.Status.FirstVisibleLine
    $script:audioCaptures[$a.Key].Capture.Peak=0.23; Update-RowStatus $a
    Assert-Ui ($firstLine -gt 0 -and $a.Status.FirstVisibleLine -eq $firstLine) 'A live update reset the log scroll position.'
    $dialog=New-WaitSettingsDialog
    try {$dialog.Show($form); $dialog.Tag.StatusLogLimit.Value=30; $dialog.Tag.Cancel.PerformClick(); Assert-Ui ($script:statusLogLimit -eq 3 -and $a.StatusHistory.Count -eq 3) 'Cancel applied a history draft.'}
    finally {$dialog.Dispose()}
    $locked=[IO.File]::Open($script:settingsPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try {
        $dialog=New-WaitSettingsDialog
        try {$dialog.Show($form); $dialog.Tag.StatusLogLimit.Value=1; $dialog.Tag.Apply.PerformClick(); Assert-Ui ($dialog.DialogResult -ne 'OK' -and $dialog.Tag.Error.Text -ne '' -and $script:statusLogLimit -eq 3 -and $a.StatusHistory.Count -eq 3) 'Failed write applied the limit or destroyed older logs.'}
        finally {$dialog.Dispose()}
    } finally {$locked.Dispose()}
    $dialog=New-WaitSettingsDialog
    try {$dialog.Show($form); Assert-Ui ($dialog.Tag.StatusLogLimit.Value -eq 3) 'Reopening lost the saved limit.'; $dialog.Tag.StatusLogLimit.Value=5; $dialog.Tag.Apply.PerformClick(); Assert-Ui ($dialog.DialogResult -eq 'OK' -and $script:statusLogLimit -eq 5 -and $a.StatusHistory.Count -eq 3) 'Repeat save failed or invented evicted logs.'}
    finally {$dialog.Dispose()}
    $fullIni=[IO.File]::ReadAllText($script:settingsPath)
    foreach($invalid in @('0','1001','-1','1.5','abc','9999999999999999999999')) {
        $rejected=$false; try {Set-VersionWaitRanges 1 1 1 1 -StatusLogLimit $invalid} catch {$rejected=$true}
        Assert-Ui ($rejected -and $script:statusLogLimit -eq 5 -and [IO.File]::ReadAllText($script:settingsPath) -ceq $fullIni -and $a.State.ReelDelayMs -eq $sampled -and $a.State.Deadline -eq $due) 'Invalid limit partially applied or saved.'
        [IO.File]::WriteAllText($script:settingsPath,$fullIni.Replace('StatusLogLimit=5',('StatusLogLimit='+$invalid)))
        Import-VersionWaitSettings
        Assert-Ui ($script:settingsWarning -ne '' -and $script:statusLogLimit -eq 5) 'Invalid INI limit was accepted.'
        [IO.File]::WriteAllText($script:settingsPath,$fullIni)
    }
    [IO.File]::WriteAllText($script:settingsPath,($fullIni+"statusloglimit=2`r`n")); Import-VersionWaitSettings
    Assert-Ui ($script:settingsWarning -ne '' -and $script:statusLogLimit -eq 5) 'Duplicate limit was accepted.'
    $legacy=$fullIni -replace '(?m)^StatusLogLimit=.*\r?\n?',''
    [IO.File]::WriteAllText($script:settingsPath,$legacy)
    Set-VersionWaitRanges 800 900 700 700 -Persist $false -StatusLogLimit 50
    $legacyHash=(Get-FileHash -LiteralPath $script:settingsPath).Hash
    Import-VersionWaitSettings
    Assert-Ui ($script:settingsWarning -eq '' -and $script:statusLogLimit -eq 50 -and (Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $legacyHash) 'Old sixteen-key INI failed or was rewritten.'
    [IO.File]::WriteAllText($script:settingsPath,$fullIni); Import-VersionWaitSettings
    Assert-Ui ($script:statusLogLimit -eq 5) 'Startup failed to restore saved history limit.'
    $historyBeforeStop=$a.StatusHistory -join '|'; Stop-Row $a
    Assert-Ui ($a.State.ReelDelayMs -eq 0 -and $a.StatusHistory.Count -gt 1 -and $a.Status.Text -match '当前随机延迟' -and $a.CurrentStatusText -notmatch '当前随机延迟') 'Stop lost delay history or kept a stale active delay.'
    $timed=Add-WowAutoTask $script:scheduler $b.Key 700 700 3000
    $b.State=$timed; $null=Complete-WowAutoPoll $script:scheduler $b.Key 3000 'green'; Update-RowStatus $b
    Assert-Ui ($b.State.ReelDelayMs -eq 700 -and $b.State.Deadline -eq 3700 -and $b.CurrentStatusText -match '当前随机延迟：700 ms') 'Timed-mode delay display did not equal its actual event.'
    $startedAgain=@($a.StatusHistory.ToArray()); Start-Row $a
    Assert-Ui ($a.State.ReelDelayMs -eq 0 -and $a.StatusHistory.Count -gt 1) 'Restart inherited a delay or discarded history.'
    $fresh=New-ProcessRow $a.Process $a.StartTime ($a.Key+':new-row-test') $a.Client
    try {Assert-Ui ($fresh.StatusHistory.Count -eq 1 -and $fresh.Status.Text -notmatch '当前随机延迟') 'A new process row inherited an old history.'} finally {$fresh.Panel.Dispose()}
    Assert-Ui ($script:workerKeys.Count -eq $logKeys -and $script:workerActivations.Count -eq $logActivations) 'History tests sent game input or activated game windows.'
} finally {
    Stop-AllRows; $script:scheduler=$savedLogScheduler; $script:schedulerClock=$savedLogClock; $script:audioUseTemplate=$savedLogTemplate
    [IO.File]::WriteAllBytes($script:settingsPath,$savedLogIni); Import-VersionWaitSettings
}
Assert-Ui ((Get-FileHash -LiteralPath $logSource).Hash -eq $logSourceHash) 'History tests changed user config.ini.'
Write-Output 'PASS: consolidated delay interval/separator, actual audio/timed random delay, bounded per-process history, newest-first rendering, immutable prior events/live timestamp/scroll, save/cancel/repeat/reload/locked/invalid/duplicate/legacy INI, stop/restart/new-row isolation. No real game/audio actions.'
