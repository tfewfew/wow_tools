# No real playback, capture, focus changes or input: -UiTest mocks every action.
Stop-AllRows
$recordSource=Join-Path (Split-Path $PSScriptRoot -Parent) 'config.ini'
$recordSourceHash=(Get-FileHash -LiteralPath $recordSource).Hash
$savedRecordIni=[IO.File]::ReadAllBytes($script:settingsPath)
$savedRecordMode=$script:audioUseTemplate
$savedRecordScheduler=$script:scheduler; $savedRecordClock=$script:schedulerClock
$savedRecordSettings=@{
    TitanMinimum=$script:versionRanges.titan.MinimumMs; TitanMaximum=$script:versionRanges.titan.MaximumMs
    ForerverMinimum=$script:versionRanges.forerver.MinimumMs; ForerverMaximum=$script:versionRanges.forerver.MaximumMs
    TitanAudioTimeoutMs=$script:versionRanges.titan.AudioTimeoutMs; ForerverAudioTimeoutMs=$script:versionRanges.forerver.AudioTimeoutMs
    TitanAudioRecordingId=$script:audioRecordingSelections.titan; ForerverAudioRecordingId=$script:audioRecordingSelections.forerver
    TitanAudioThresholdPercent=$script:audioThresholds.titan; ForerverAudioThresholdPercent=$script:audioThresholds.forerver
    FocusRetryIntervalMs=$script:scheduler.FocusRetryIntervalMs; ReelHoldMs=$script:scheduler.ReelHoldMs
    KeyBindings=$script:keyBindings; AudioDetectionEnabled=$script:audioDetectionEnabled
    ProcessItemPreferences=$script:processItemPreferences.Clone(); Persist=$false
}
$recordKeys=$script:workerKeys.Count; $recordActivations=$script:workerActivations.Count
try {
    $script:scheduler=New-WowAutoScheduler
    $script:schedulerClock=[pscustomobject]@{ElapsedMilliseconds=1000L}
    $script:audioUseTemplate=$true
    [void][IO.Directory]::CreateDirectory($script:audioFeatureDirectory)
    [void][IO.Directory]::CreateDirectory($script:audioRecordingDirectory)
    $tones=@{}
    foreach($spec in @(@('titan',1,880),@('titan',2,2800),@('forerver',1,1700))) {
        $recording=Get-AudioRecording $spec[0] $spec[1]
        $pcm=New-Object 'System.Int16[]' 15435
        for($i=2205;$i -lt 4630;$i++) { $pcm[$i]=[int16](20000*[Math]::Exp(-($i-2205)/1102)*[Math]::Sin(2*[Math]::PI*$spec[2]*$i/11025)) }
        $tones["$($spec[0]):$($spec[1])"]=$pcm
        $template=[WowAuto.Audio.AudioTemplate]::FromMono($pcm,11025)
        [WowAuto.Audio.AudioTemplate]::SaveFeatures((Join-Path $script:audioFeatureDirectory $recording.Feature),[WowAuto.Audio.AudioTemplate[]]@($template),0.90)
        [IO.File]::WriteAllBytes((Join-Path $script:audioRecordingDirectory $recording.Wave),[Text.Encoding]::ASCII.GetBytes('RIFF mocked WAV; no real playback'))
    }
    Set-VersionWaitRanges 300 300 600 600 -TitanAudioRecordingId 2 -ForerverAudioRecordingId 1
    $recordHash=(Get-FileHash -LiteralPath $script:settingsPath).Hash
    $dialog=New-WaitSettingsDialog
    try {
        $dialog.Show($form); [System.Windows.Forms.Application]::DoEvents()
        foreach($flavor in @('titan','forerver')) {
            $fields=$dialog.Tag.Recordings[$flavor]
            Assert-Ui ($fields.Selection.DropDownStyle -eq 'DropDownList' -and $fields.Selection.Items.Count -eq $script:audioRecordings[$flavor].Count -and $fields.Selection.Parent.ClientRectangle.Contains($fields.Selection.Bounds) -and $fields.Play.Parent.ClientRectangle.Contains($fields.Play.Bounds)) 'Recording list/playback layout failed.'
        }
        foreach($control in $dialog.Controls) {Assert-Ui ($dialog.ClientRectangle.Contains($control.Bounds)) 'Settings content clipped after adding recording selectors.'}
        Assert-Ui ($dialog.Tag.Recordings.titan.Selection.SelectedItem.Id -eq 2) 'Default/reopened recording selection incorrect.'
        if($env:WOWAUTO_RECORDINGS_PREVIEW_PATH) {
            $bitmap=New-Object System.Drawing.Bitmap($dialog.Width,$dialog.Height)
            try {$dialog.DrawToBitmap($bitmap,(New-Object System.Drawing.Rectangle(0,0,$dialog.Width,$dialog.Height))); $bitmap.Save($env:WOWAUTO_RECORDINGS_PREVIEW_PATH,[System.Drawing.Imaging.ImageFormat]::Png)}
            finally {$bitmap.Dispose()}
        }
        $dialog.Tag.Recordings.titan.Play.PerformClick(); $played2=$dialog.Tag.PreviewPlayer
        Assert-Ui ($played2.Played -and $played2.SoundLocation.EndsWith('titan-02-match.wav')) 'Preview played the wrong matching excerpt.'
        $dialog.Tag.Recordings.titan.Selection.SelectedItem=Get-AudioRecording 'titan' 1
        Assert-Ui ($played2.Stopped -and $played2.Disposed -and $null -eq $dialog.Tag.PreviewPlayer -and $script:audioRecordingSelections.titan -eq 2 -and (Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $recordHash) 'Changing a draft failed to stop playback or applied/saved the choice.'
        $dialog.Tag.Recordings.titan.Play.PerformClick(); $played1=$dialog.Tag.PreviewPlayer
        $dialog.Tag.Recordings.forerver.Play.PerformClick(); $playedForever=$dialog.Tag.PreviewPlayer
        Assert-Ui ($played1.Stopped -and $played1.Disposed -and $playedForever.SoundLocation.EndsWith('forerver-01-match.wav')) 'Switching clients left two previews playing.'
        $dialog.Tag.StopPreview.PerformClick()
        Assert-Ui ($playedForever.Stopped -and $playedForever.Disposed -and $null -eq $dialog.Tag.PreviewPlayer) 'Stop-preview failed.'
        $dialog.Tag.Recordings.titan.Play.PerformClick(); $savedPlayer=$dialog.Tag.PreviewPlayer
        $dialog.Tag.Apply.PerformClick()
        Assert-Ui ($dialog.DialogResult -eq 'OK' -and $savedPlayer.Stopped -and $savedPlayer.Disposed -and $script:audioRecordingSelections.titan -eq 1 -and (Read-WowAutoSettingsIni $script:settingsPath).TitanAudioRecordingId -eq 1) 'Saving did not stop playback/persist recording.'
    }
    finally {$dialog.Dispose()}
    $dialog=New-WaitSettingsDialog
    try {
        $dialog.Show($form)
        Assert-Ui ($dialog.Tag.Recordings.titan.Selection.SelectedItem.Id -eq 1) 'Reopening lost recording selection.'
        $dialog.Tag.Recordings.titan.Selection.SelectedItem=Get-AudioRecording 'titan' 2
        $dialog.Tag.Recordings.titan.Play.PerformClick(); $cancelPlayer=$dialog.Tag.PreviewPlayer
        $dialog.Tag.Cancel.PerformClick()
        Assert-Ui ($cancelPlayer.Stopped -and $cancelPlayer.Disposed -and $script:audioRecordingSelections.titan -eq 1) 'Cancel changed recording or leaked playback.'
    }
    finally {$dialog.Dispose()}
    $dialog=New-WaitSettingsDialog
    try {$dialog.Show($form); $dialog.Tag.Recordings.titan.Play.PerformClick(); $closePlayer=$dialog.Tag.PreviewPlayer; $dialog.Close(); Assert-Ui ($closePlayer.Stopped -and $closePlayer.Disposed) 'Closing settings leaked playback.'}
    finally {$dialog.Dispose()}
    $dialog=New-WaitSettingsDialog
    $dialog.Show($form); $dialog.Tag.Recordings.titan.Play.PerformClick(); $disposePlayer=$dialog.Tag.PreviewPlayer; $dialog.Dispose()
    Assert-Ui ($disposePlayer.Stopped -and $disposePlayer.Disposed) 'Disposing settings leaked playback.'
    [IO.File]::Delete((Join-Path $script:audioRecordingDirectory 'titan-01-match.wav'))
    $dialog=New-WaitSettingsDialog
    try {$dialog.Show($form); $dialog.Tag.Recordings.titan.Play.PerformClick(); Assert-Ui ($dialog.Tag.Error.Text -match '试听文件不存在' -and $null -eq $dialog.Tag.PreviewPlayer -and $script:audioRecordingSelections.titan -eq 1) 'Missing preview was not handled safely.'}
    finally {$dialog.Dispose()}
    $locked=[IO.File]::Open($script:settingsPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try {
        $dialog=New-WaitSettingsDialog
        try {$dialog.Show($form); $dialog.Tag.Recordings.titan.Selection.SelectedItem=Get-AudioRecording 'titan' 2; $dialog.Tag.Apply.PerformClick(); Assert-Ui ($dialog.DialogResult -ne 'OK' -and $dialog.Tag.Error.Text -ne '' -and $script:audioRecordingSelections.titan -eq 1) 'Failed INI write applied a recording draft.'}
        finally {$dialog.Dispose()}
    }
    finally {$locked.Dispose()}
    $dialog=New-WaitSettingsDialog
    try {$dialog.Show($form); $dialog.Tag.Recordings.titan.Selection.SelectedItem=Get-AudioRecording 'titan' 2; $dialog.Tag.Apply.PerformClick(); Assert-Ui ($dialog.DialogResult -eq 'OK') 'Second recording save failed.'}
    finally {$dialog.Dispose()}
    $fullRecordIni=[IO.File]::ReadAllText($script:settingsPath)
    Set-VersionWaitRanges 300 300 600 600 -Persist $false -TitanAudioRecordingId 1
    Import-VersionWaitSettings
    Assert-Ui ($script:settingsWarning -eq '' -and $script:audioRecordingSelections.titan -eq 2) 'Startup failed to restore recording choice.'
    foreach($invalid in @('0','3','-1','1.5','../titan','9999999999999999999999')) {
        $bad=$false; try {Set-VersionWaitRanges 1 1 1 1 -TitanAudioRecordingId $invalid} catch {$bad=$true}
        Assert-Ui ($bad -and $script:audioRecordingSelections.titan -eq 2 -and [IO.File]::ReadAllText($script:settingsPath) -ceq $fullRecordIni) 'Invalid recording ID partially applied/saved.'
    }
    foreach($invalidIni in @(
        ($fullRecordIni -replace '(?m)^TitanAudioRecordingId=.*\r?\n?',''),
        ($fullRecordIni -replace '(?m)^ForerverAudioRecordingId=.*\r?\n?',''),
        $fullRecordIni.Replace('TitanAudioRecordingId=2','TitanAudioRecordingId=3'),
        $fullRecordIni.Replace('ForerverAudioRecordingId=1','ForerverAudioRecordingId=2'),
        ($fullRecordIni+"titanaudiorecordingid=1`r`n")
    )) {
        [IO.File]::WriteAllText($script:settingsPath,$invalidIni); Import-VersionWaitSettings
        Assert-Ui ($script:settingsWarning -ne '' -and $script:audioRecordingSelections.titan -eq 2 -and $script:audioRecordingSelections.forerver -eq 1) 'Invalid/missing/duplicate recording INI applied.'
    }
    $legacy=$fullRecordIni -replace '(?m)^(Titan|Forerver)AudioRecordingId=.*\r?\n?',''
    [IO.File]::WriteAllText($script:settingsPath,$legacy); $legacyHash=(Get-FileHash -LiteralPath $script:settingsPath).Hash
    Import-VersionWaitSettings
    Assert-Ui ($script:settingsWarning -eq '' -and (Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $legacyHash) 'Legacy fourteen-key INI failed or was rewritten.'
    $audioCheck.Checked=$true
    $t=@($script:rows.Values | Where-Object {$_.Client.Flavor -eq 'titan'})[0]
    $f=@($script:rows.Values | Where-Object {$_.Client.Flavor -eq 'forerver'})[0]
    foreach($row in @($t,$f)) {$row.Validated=$true; $row.Exited=$false; $row.Process.HasExited=$false; $row.Process.FocusAllowed=$true; $row.Process.ScanColor='green'; $row.ItemCheck.Checked=$false; Start-Row $row; $row.State.AudioReady=$true; $null=Complete-WowAutoPoll $script:scheduler $row.Key 1000 'green'}
    Update-AudioCaptures 1000
    $tEntry=$script:audioCaptures[$t.Key]; $fEntry=$script:audioCaptures[$f.Key]
    Assert-Ui ($tEntry.RecordingId -eq 2 -and $tEntry.Capture.Template.Compare($tones['titan:2']) -gt 0.99 -and $fEntry.Capture.Template.Compare($tones['forerver:1']) -gt 0.99) 'Tasks loaded the wrong recording/client feature.'
    $oldDeadline=$t.State.Deadline; $oldSession=$t.State.AudioSession; $foreverDeadline=$f.State.Deadline
    Set-VersionWaitRanges 300 300 600 600 -Persist $false -TitanAudioRecordingId 1
    Update-AudioCaptures 1500
    Assert-Ui ($tEntry.RecordingId -eq 2 -and $tEntry.Capture.TemplateChanges -eq 0 -and $t.State.Deadline -eq $oldDeadline -and $t.State.AudioSession -eq $oldSession) 'Saving switched the current round or moved its deadline/session.'
    $script:scheduler.ItemHoldUntil=1800; Update-AudioCaptures 1700; Update-AudioCaptures 1800
    Assert-Ui ($tEntry.RecordingId -eq 2 -and $tEntry.Capture.TemplateChanges -eq 0) 'Rearming after item hold switched the same fishing round.'
    $tEntry.Capture.Bite=$oldSession; Update-AudioCaptures 2000
    Assert-Ui ($t.State.AudioReelPending -and $t.State.Deadline -eq 2300) 'Changing recordings lost an old-round matched bite.'
    Reset-WowAutoAudioWait $script:scheduler $t.Key 2500
    $null=Complete-WowAutoPoll $script:scheduler $t.Key 2600 'red'; Complete-WowAutoCast $script:scheduler $t.Key $true
    $null=Complete-WowAutoPoll $script:scheduler $t.Key 2800 'green'; Update-AudioCaptures 2800
    Assert-Ui ($tEntry.RecordingId -eq 1 -and $tEntry.Capture.TemplateChanges -eq 1 -and $tEntry.Capture.Template.Compare($tones['titan:1']) -gt 0.99 -and $fEntry.RecordingId -eq 1 -and $fEntry.Capture.TemplateChanges -eq 0 -and $f.State.Deadline -eq $foreverDeadline) 'Next-round recording update/client isolation failed.'
    Stop-Row $t; Start-Row $t
    Assert-Ui ($script:audioCaptures[$t.Key].RecordingId -eq 1) 'Restart ignored saved recording.'
    $t.State.AudioReady=$true; $null=Complete-WowAutoPoll $script:scheduler $t.Key 3000 'green'; Update-AudioCaptures 3000
    [IO.File]::WriteAllText((Join-Path $script:audioFeatureDirectory 'titan-02.feature'),'Format=invalid')
    Set-VersionWaitRanges 300 300 600 600 -Persist $false -TitanAudioRecordingId 2
    Reset-WowAutoAudioWait $script:scheduler $t.Key 3100
    $null=Complete-WowAutoPoll $script:scheduler $t.Key 3200 'red'; Complete-WowAutoCast $script:scheduler $t.Key $true
    $null=Complete-WowAutoPoll $script:scheduler $t.Key 3400 'green'; Update-AudioCaptures 3400
    Assert-Ui (-not $t.State.Running -and $f.State.Running -and -not $script:audioCaptures.ContainsKey($t.Key)) 'Invalid selected feature did not stop only the affected row.'
    Assert-Ui ($script:workerKeys.Count -eq $recordKeys -and $script:workerActivations.Count -eq $recordActivations) 'Recording/preview tests sent game input or activated windows.'
}
finally {
    Stop-AllRows; $script:scheduler=$savedRecordScheduler; $script:schedulerClock=$savedRecordClock; $script:audioUseTemplate=$savedRecordMode
    [IO.File]::WriteAllBytes($script:settingsPath,$savedRecordIni); Set-VersionWaitRanges @savedRecordSettings
}
Assert-Ui ((Get-FileHash -LiteralPath $recordSource).Hash -eq $recordSourceHash) 'Recording tests changed user config.ini.'
Write-Output 'PASS: numbered per-client recording lists, preview routing/stop/change/save/cancel/close/dispose/missing-file, repeated save/reload/legacy/invalid/locked-write, selected feature dispatch, immutable active round/bite, next-round switch and client/failure isolation. Playback/input/capture mocked.'
