# Numerical fixtures only. No audio recording, media playback or game actions.
Stop-AllRows
$audioCheck.Checked=$true
$savedTemplateMode=$script:audioUseTemplate
$savedThresholds=@{titan=$script:audioThresholds.titan; forerver=$script:audioThresholds.forerver}
$script:audioUseTemplate=$true
try {
    Assert-Ui (@($toolbar.Controls | Where-Object { $_.Text -match '声音样本|录制|导入|试听' }).Count -eq 0) 'Recording/sample UI remains in runtime tool.'
    Assert-Ui ($null -eq [WowAuto.Audio.ProcessCapture].GetMethod('StartRecording') -and
        $null -eq [WowAuto.Audio.ProcessCapture].GetMethod('TakeRecording')) 'Recording API remains in runtime capture.'
    $row=@($script:rows.Values | Where-Object { $_.Client.Flavor -eq 'titan' })[0]
    $other=@($script:rows.Values | Where-Object { $_.Client.Flavor -eq 'forerver' })[0]
    foreach ($current in @($row,$other)) { $current.Validated=$true; $current.Exited=$false; $current.Process.HasExited=$false }
    Start-Row $row
    Assert-Ui (-not $row.State.Running -and $row.Status.Text -match '尚未校准' -and $script:audioCaptures.Count -eq 0) 'Missing feature bank allowed audio automation.'
    $samples=New-Object 'System.Int16[]' 15435
    for ($i=1102;$i -lt 3528;$i++) { $samples[$i]=[int16](20000*[Math]::Exp(-($i-1102)/1102)*[Math]::Sin(2*[Math]::PI*880*$i/11025)) }
    $template=[WowAuto.Audio.AudioTemplate]::FromMono($samples,11025)
    [void][IO.Directory]::CreateDirectory($script:audioFeatureDirectory)
    $path=Join-Path $script:audioFeatureDirectory (Get-AudioRecording 'titan' $script:audioRecordingSelections.titan).Feature
    [WowAuto.Audio.AudioTemplate]::SaveFeatures($path,[WowAuto.Audio.AudioTemplate[]]@($template),0.91)
    $loaded=Get-AudioTemplate 'titan'
    Assert-Ui ($loaded.MinimumSimilarity -eq 0.91 -and $loaded.Compare($samples) -gt 0.99) 'Calibrated numerical feature file failed to load.'
    Start-Row $other
    Assert-Ui (-not $other.State.Running -and $other.Status.Text -match '尚未校准') 'One client inherited another feature bank.'
    Start-Row $row
    Assert-Ui ($row.State.Running -and $script:audioCaptures[$row.Key].TemplateMode -and $script:audioCaptures[$row.Key].Trial) 'Audio row did not use the trial feature bank.'
    $capture=$script:audioCaptures[$row.Key].Capture; $capture.Similarity=0.52; $capture.Rejected=1
    Assert-Ui ($capture.MinimumSimilarity -eq $script:audioThresholds.titan/100.0) 'Startup used the feature recommendation instead of the configured threshold.'
    Update-RowStatus $row; $stamp=$row.StatusTimestamp
    $capture.Similarity=0.94; $capture.Rejected=2; Update-RowStatus $row
    Assert-Ui ($row.StatusTimestamp -eq $stamp -and $row.Status.Text -match '94%' -and $row.Status.Text -match '试用匹配') 'Match metrics refreshed timestamp or lost the trial label.'
    [WowAuto.Audio.AudioTemplate]::SaveFeatures((Join-Path $script:audioFeatureDirectory 'forerver.feature'),[WowAuto.Audio.AudioTemplate[]]@($template),0.91)
    Start-Row $other
    $otherCapture=$script:audioCaptures[$other.Key].Capture
    $capture.Arm(37); $capture.Bite=37
    Set-VersionWaitRanges $script:versionRanges.titan.MinimumMs $script:versionRanges.titan.MaximumMs $script:versionRanges.forerver.MinimumMs $script:versionRanges.forerver.MaximumMs -Persist $false -TitanAudioThresholdPercent 90 -ForerverAudioThresholdPercent 84
    Update-RowStatus $row
    Assert-Ui ($capture.MinimumSimilarity -eq 0.90 -and $otherCapture.MinimumSimilarity -eq 0.84 -and $capture.Session -eq 37 -and $capture.Bite -eq 37) 'Thresholds failed to update per version or reset the active signal/session.'
    Assert-Ui ($row.StatusTimestamp -eq $stamp -and $row.Status.Text -match '门槛 90%') 'Threshold display was missing or refreshed the state timestamp.'
    Stop-AllRows
    [IO.File]::WriteAllText($path,'Format=invalid')
    Start-Row $row
    Assert-Ui (-not $row.State.Running -and $script:audioCaptures.Count -eq 0) 'Invalid calibration silently fell back to peak detection.'
}
finally { Stop-AllRows; $script:audioThresholds=$savedThresholds; Update-VersionSummary; $script:audioUseTemplate=$savedTemplateMode; $audioCheck.Checked=$false }
Write-Output 'PASS: no recording UI/API, per-version features/configured live thresholds, missing/invalid feature gate, signal/session preservation and stable metric timestamps. No game audio/input.'
