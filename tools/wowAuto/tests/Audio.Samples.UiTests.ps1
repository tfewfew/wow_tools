# Executed in the stopped UI with mock processes. No game audio/input is used.
Stop-AllRows
$audioCheck.Checked=$true
$savedSimilarity=$script:audioSimilarity
$savedTemplateMode=$script:audioUseTemplate
$script:audioUseTemplate=$true
$sampleDialog=$null
try {
    $row=@($script:rows.Values | Where-Object { $_.Client.Flavor -eq 'titan' })[0]
    $row.Validated=$true; $row.Exited=$false; $row.Process.HasExited=$false
    Start-Row $row
    Assert-Ui (-not $row.State.Running -and $row.Status.Text -match '尚无声音样本' -and $script:audioCaptures.Count -eq 0) 'Missing template silently reverted to peak detection.'
    $samples=New-Object 'System.Int16[]' 7718
    for ($i=1102;$i -lt 3528;$i++) { $samples[$i]=[int16](20000*[Math]::Exp(-($i-1102)/1102)*[Math]::Sin(2*[Math]::PI*880*$i/11025)) }
    Save-AudioSample 'titan' $samples
    Save-AudioSample 'titan' $samples # Windows PS5 File.Replace null-path regression.
    $path=Get-AudioSamplePath 'titan'; $hash=(Get-FileHash $path).Hash
    $failed=$false
    try { Save-AudioSample 'titan' (New-Object 'System.Int16[]' 11025) } catch { $failed=$true }
    Assert-Ui ($failed -and (Get-FileHash $path).Hash -eq $hash) 'Invalid sample overwrote good sample.'
    $sampleDialog=New-AudioSampleDialog; $context=$sampleDialog.Tag
    $sampleDialog.Show(); [System.Windows.Forms.Application]::DoEvents()
    Assert-Ui ($context.Process.Items.Count -gt 0 -and $context.Play.Enabled -and -not $context.Save.Enabled) 'Sample dialog failed to load per-version preview/process rows.'
    Assert-Ui ($toolbar.ClientRectangle.Contains($sampleButton.Bounds)) 'Sample entry clipped.'
    $keysBefore=$script:workerKeys.Count; $activationsBefore=$script:workerActivations.Count
    Start-SampleRecording $context
    $recording=$context.Capture
    Assert-Ui (-not $context.Version.Enabled -and $context.Cancel.Enabled -and -not $context.Import.Enabled) 'Recording controls remain editable.'
    Update-SampleRecording $context
    $recording.Samples=$samples; $recording.Recording=$false
    Update-SampleRecording $context
    Assert-Ui ($recording.Disposed -and $context.Save.Enabled -and $context.Play.Enabled -and $null -ne $context.Pending) 'Mock recording was not prepared/released.'
    Set-SamplePreview $context $samples
    $context.Use.Checked=$false
    $context.Save.PerformClick()
    Assert-Ui ($context.Use.Checked -and (Test-Path -LiteralPath $path)) 'Saving did not suggest template mode.'
    if ($PreviewPath) {
        [System.Windows.Forms.Application]::DoEvents()
        $bitmap=New-Object System.Drawing.Bitmap($sampleDialog.Width,$sampleDialog.Height)
        try {
            $sampleDialog.DrawToBitmap($bitmap,(New-Object System.Drawing.Rectangle(0,0,$sampleDialog.Width,$sampleDialog.Height)))
            $bitmap.Save(([IO.Path]::ChangeExtension($PreviewPath,'')+'-samples.png'),[System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally { $bitmap.Dispose(); $sampleDialog.Hide() }
    }
    Start-SampleRecording $context; $cancelled=$context.Capture; Stop-SampleRecording $context
    Assert-Ui ($cancelled.Disposed -and $context.Save.Enabled) 'Cancel lost pending sample or leaked capture.'
    $context.Version.SelectedIndex=1
    Assert-Ui ($context.Flavor -eq 'forerver' -and -not $context.Play.Enabled -and -not $context.Save.Enabled) 'Version switch inherited another sample.'
    Assert-Ui ($script:workerKeys.Count -eq $keysBefore -and $script:workerActivations.Count -eq $activationsBefore) 'Recording touched game focus or input.'
    Start-Row $row; Update-BatchControls
    Assert-Ui ($row.State.Running -and $script:audioCaptures[$row.Key].TemplateMode -and -not $sampleButton.Enabled) 'Template not assigned or recording available during automation.'
    $capture=$script:audioCaptures[$row.Key].Capture; $capture.Similarity=0.52; $capture.Rejected=1
    Update-RowStatus $row; $stamp=$row.StatusTimestamp
    $capture.Similarity=0.94; $capture.Rejected=2; Update-RowStatus $row
    Assert-Ui ($row.StatusTimestamp -eq $stamp -and $row.Status.Text -match '94%') 'Match metrics refreshed timestamp.'
    Stop-AllRows; Update-BatchControls
    Assert-Ui $sampleButton.Enabled 'Sample entry did not re-enable after stop.'
    Start-SampleRecording $context; $closing=$context.Capture
    Close-SampleDialog $context
    Assert-Ui ($closing.Disposed -and -not [IO.File]::Exists($context.PreviewPath)) 'Closing leaked recording/temporary WAV.'
    $sampleDialog.Dispose(); $sampleDialog=$null
}
finally {
    if ($null -ne $sampleDialog) { Close-SampleDialog $sampleDialog.Tag; $sampleDialog.Dispose() }
    Stop-AllRows; $script:audioUseTemplate=$savedTemplateMode; $script:audioSimilarity=$savedSimilarity; $audioCheck.Checked=$false; Update-SampleButton
}
Write-Output 'PASS: per-version sample save/reload/atomic replacement, missing-template gate, mock manual recording/cancel/cleanup, no automatic focus/input, match metrics and control state.'
