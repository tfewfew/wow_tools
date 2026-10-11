# Dot-sourced by the GUI. Samples are local data, independent of config.ini.
$script:sampleDirectory = if ($UiTest) { Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-samples-test-' + [Guid]::NewGuid()) }
    else { Join-Path $PSScriptRoot 'audio-samples' }
$script:audioSimilarity = 0.88
$script:audioUseTemplate = -not $UiTest -and ((Test-Path -LiteralPath (Join-Path $script:sampleDirectory 'titan.wav')) -or
    (Test-Path -LiteralPath (Join-Path $script:sampleDirectory 'forerver.wav')))

function Get-AudioSamplePath([string]$Flavor) {
    if ($Flavor -notin @('titan','forerver')) { throw '未知客户端版本。' }
    return Join-Path $script:sampleDirectory ($Flavor + '.wav')
}
function Get-AudioTemplate([string]$Flavor) {
    $path=Get-AudioSamplePath $Flavor
    if (-not (Test-Path -LiteralPath $path)) { throw '此版本尚无声音样本，请打开“声音样本”录制或导入。' }
    return [WowAuto.Audio.AudioTemplate]::FromWave($path)
}
function Save-AudioSample([string]$Flavor, [int16[]]$Samples) {
    # Reject silence/invalid data before touching an existing sample.
    $template=[WowAuto.Audio.AudioTemplate]::FromMono($Samples,[WowAuto.Audio.AudioTemplate]::SampleRate)
    $path=Get-AudioSamplePath $Flavor
    [void][IO.Directory]::CreateDirectory($script:sampleDirectory)
    $temp=Join-Path $script:sampleDirectory ([Guid]::NewGuid().ToString()+'.wav')
    try {
        [WowAuto.Audio.AudioTemplate]::WriteWave($temp,$template.Clip)
        if ([IO.File]::Exists($path)) { [IO.File]::Replace($temp,$path,[System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temp,$path) }
    }
    finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}
function Update-SampleButton {
    $sampleButton.Text=if ($script:audioUseTemplate) { '声音样本：匹配开' } else { '声音样本：匹配关' }
}
function Set-SampleDialogControls($Context) {
    $busy=$null -ne $Context.Capture
    foreach ($control in @($Context.Version,$Context.Process,$Context.Import,$Context.Record,$Context.Save,$Context.Use,$Context.Threshold)) {
        $control.Enabled=-not $busy
    }
    $Context.Record.Enabled=-not $busy -and $Context.Process.Items.Count -gt 0
    $Context.Save.Enabled=-not $busy -and $null -ne $Context.Pending
    $Context.Play.Enabled=-not $busy -and (Test-Path -LiteralPath $Context.PreviewPath)
    $Context.Cancel.Enabled=$busy
}
function Update-SampleDialogVersion($Context) {
    $Context.Player.Stop()
    $Context.Pending=$null
    if ([IO.File]::Exists($Context.PreviewPath)) { [IO.File]::Delete($Context.PreviewPath) }
    $flavor=if ($Context.Version.SelectedIndex -eq 0) { 'titan' } else { 'forerver' }
    $Context.Flavor=$flavor
    $Context.Process.Items.Clear(); $Context.Rows=@()
    foreach ($row in @($script:rows.Values | Sort-Object { $_.Process.Id })) {
        if ($row.Client.Flavor -eq $flavor -and -not $row.Exited) {
            $Context.Rows+=,$row
            [void]$Context.Process.Items.Add("PID $($row.Process.Id) · $($row.Process.MainWindowTitle)")
        }
    }
    if ($Context.Process.Items.Count -gt 0) { $Context.Process.SelectedIndex=0 }
    $path=Get-AudioSamplePath $flavor
    $Context.Status.Text=if (Test-Path -LiteralPath $path) { "已有样本：$path" } else { '尚无样本。请选择进程录制，或导入干净的咬钩 WAV。' }
    if (Test-Path -LiteralPath $path) {
        try { $sample=Get-AudioTemplate $flavor; [WowAuto.Audio.AudioTemplate]::WriteWave($Context.PreviewPath,$sample.Clip) }
        catch { $Context.Status.Text='已有样本无法读取：'+$_.Exception.Message }
    }
    Set-SampleDialogControls $Context
}
function Set-SamplePreview($Context, [int16[]]$Samples) {
    $template=[WowAuto.Audio.AudioTemplate]::FromMono($Samples,[WowAuto.Audio.AudioTemplate]::SampleRate)
    $Context.Player.Stop()
    [WowAuto.Audio.AudioTemplate]::WriteWave($Context.PreviewPath,$template.Clip)
    $Context.Pending=$template.Clip
    $Context.Status.Text='已提取最响事件约370ms。请试听确认确实为咬钩，再点击“保存此版本样本”。'
}
function Stop-SampleRecording($Context) {
    if ($null -ne $Context.Capture) { $Context.Capture.Dispose(); $Context.Capture=$null }
    $Context.Phase='Idle'
    Set-SampleDialogControls $Context
}
function Start-SampleRecording($Context) {
    if ($script:scheduler.Tasks.Count -gt 0 -or $script:pendingGameExits.Count -gt 0 -or $script:scanning) {
        throw '请先全部停止并结束刷新扫描，再录制样本。'
    }
    if ($Context.Process.SelectedIndex -lt 0) { throw '请选择要录制的游戏进程。' }
    $row=$Context.Rows[$Context.Process.SelectedIndex]
    if (-not (Test-RowProcessIdentity $row)) { throw '进程身份已变化，请关闭窗口并刷新进程。' }
    $Context.Player.Stop()
    if ($UiTest) {
        $capture=[pscustomobject]@{Status='Listening'; Error=''; Recording=$false; Samples=$null; Disposed=$false}
        $capture | Add-Member ScriptMethod StartRecording { param($seconds) $this.Recording=$true }
        $capture | Add-Member ScriptMethod TakeRecording { return ,$this.Samples }
        $capture | Add-Member ScriptMethod Dispose { $this.Disposed=$true; $this.Recording=$false }
    }
    else { $capture=New-Object WowAuto.Audio.ProcessCapture($row.Process.Id,$row.StartTime.Ticks,$row.Client.ExecutablePath) }
    $Context.Capture=$capture; $Context.Phase='Starting'; $Context.Clock.Restart()
    $Context.Status.Text='正在启动此 PID 的录音；不会切换窗口或发送按键。'
    Set-SampleDialogControls $Context
}
function Update-SampleRecording($Context) {
    if ($null -eq $Context.Capture) { return }
    try {
        if ($Context.Capture.Status -in @('Error','Stopped')) { throw $Context.Capture.Error }
        if ($Context.Phase -eq 'Starting' -and $Context.Capture.Status -eq 'Listening') {
            $Context.Capture.StartRecording(5); $Context.Phase='Recording'; $Context.Clock.Restart()
        }
        if ($Context.Phase -eq 'Recording') {
            if ($Context.Capture.Recording) {
                $remaining=[Math]::Max(0,5-$Context.Clock.Elapsed.TotalSeconds)
                $Context.Status.Text=('正在录制此 PID：剩余 {0:F1}s。请手动让咬钩声出现在这5秒内，避免抛竿及其他声音。' -f $remaining)
            }
            else {
                $samples=$Context.Capture.TakeRecording()
                if ($null -eq $samples) { throw '未录到音频，请重录或导入 WAV。' }
                Set-SamplePreview $Context $samples
                Stop-SampleRecording $Context
            }
        }
        if ($Context.Clock.Elapsed.TotalSeconds -gt 12) { throw '录音超时，请重试。' }
    }
    catch { $Context.Status.Text='录音失败：'+$_.Exception.Message; Stop-SampleRecording $Context }
}
function Close-SampleDialog($Context) {
    if ($Context.Closed) { return }
    $Context.Closed=$true
    Stop-SampleRecording $Context
    $Context.Timer.Stop(); $Context.Timer.Dispose(); $Context.Player.Stop(); $Context.Player.Dispose()
    if ([IO.File]::Exists($Context.PreviewPath)) { [IO.File]::Delete($Context.PreviewPath) }
}
function New-AudioSampleDialog {
    $dialog=New-Object System.Windows.Forms.Form
    $dialog.Text='咬钩声音样本'; $dialog.Font=$form.Font; $dialog.AutoScaleMode='Dpi'
    $dialog.ClientSize=New-Object System.Drawing.Size(690,405)
    $dialog.StartPosition='CenterParent'; $dialog.FormBorderStyle='FixedDialog'; $dialog.MaximizeBox=$false; $dialog.MinimizeBox=$false
    $context=[pscustomobject]@{Dialog=$dialog; Flavor='titan'; Rows=@(); Capture=$null; Phase='Idle'; Pending=$null; Closed=$false
        Clock=[Diagnostics.Stopwatch]::StartNew(); Timer=(New-Object System.Windows.Forms.Timer)
        Player=(New-Object System.Media.SoundPlayer); PreviewPath=(Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-preview-'+[Guid]::NewGuid()+'.wav'))
        Version=$null; Process=$null; Record=$null; Cancel=$null; Import=$null; Save=$null; Play=$null; Use=$null; Threshold=$null; Status=$null}
    $dialog.Tag=$context
    $tip=New-Object System.Windows.Forms.Label
    $tip.Text='录制不操作游戏。请先全部停止、在游戏开启检测（效果音最大），手动钓鱼。样本应仅包含一次清晰咬钩；系统其他进程声音不会被录入。'
    $tip.SetBounds(16,14,654,60); $dialog.Controls.Add($tip)
    $context.Version=New-Object System.Windows.Forms.ComboBox
    $context.Version.DropDownStyle='DropDownList'; $context.Version.SetBounds(16,82,140,30)
    [void]$context.Version.Items.AddRange([object[]]@('时光服','无限服')); $dialog.Controls.Add($context.Version)
    $context.Process=New-Object System.Windows.Forms.ComboBox
    $context.Process.DropDownStyle='DropDownList'; $context.Process.SetBounds(168,82,502,30); $dialog.Controls.Add($context.Process)
    foreach ($spec in @(@('Record','录制5秒',16,120,125),@('Cancel','取消录制',153,120,110),@('Import','导入 WAV',275,120,125),
        @('Play','试听样本',412,120,125),@('Save','保存此版本样本',16,170,205))) {
        $button=New-Object System.Windows.Forms.Button; $button.Text=$spec[1]; $button.SetBounds($spec[2],$spec[3],$spec[4],36)
        $context.($spec[0])=$button; $dialog.Controls.Add($button)
    }
    $context.Use=New-Object System.Windows.Forms.CheckBox
    $context.Use.Text='启用样本匹配（两服）'; $context.Use.Checked=$script:audioUseTemplate; $context.Use.SetBounds(242,175,245,30)
    $dialog.Controls.Add($context.Use)
    $thresholdLabel=New-Object System.Windows.Forms.Label; $thresholdLabel.Text='相似度门槛（%）'; $thresholdLabel.SetBounds(16,224,175,28); $dialog.Controls.Add($thresholdLabel)
    $context.Threshold=New-Object System.Windows.Forms.NumericUpDown; $context.Threshold.SetBounds(196,220,90,30)
    $context.Threshold.Minimum=50; $context.Threshold.Maximum=100; $context.Threshold.Value=[decimal]($script:audioSimilarity*100)
    $dialog.Controls.Add($context.Threshold)
    $context.Status=New-Object System.Windows.Forms.TextBox; $context.Status.Multiline=$true; $context.Status.ReadOnly=$true
    $context.Status.ScrollBars='Vertical'; $context.Status.SetBounds(16,266,654,80); $dialog.Controls.Add($context.Status)
    $done=New-Object System.Windows.Forms.Button; $done.Text='应用并关闭'; $done.SetBounds(500,360,170,34); $dialog.Controls.Add($done)
    $context.Version.Add_SelectedIndexChanged({param($sender,$e) Update-SampleDialogVersion $sender.FindForm().Tag})
    $context.Record.Add_Click({param($sender,$e) $c=$sender.FindForm().Tag
        try { Start-SampleRecording $c } catch { $c.Status.Text=$_.Exception.Message } })
    $context.Cancel.Add_Click({param($sender,$e) $c=$sender.FindForm().Tag; Stop-SampleRecording $c; $c.Status.Text='已取消录制，已有样本保留。'})
    $context.Import.Add_Click({param($sender,$e) $c=$sender.FindForm().Tag; $picker=New-Object System.Windows.Forms.OpenFileDialog
        $picker.Filter='WAV音频 (*.wav)|*.wav'; $picker.Title='选择0.2–10秒的干净咬钩音效（PCM16 / float32）'
        try { if ($picker.ShowDialog($c.Dialog) -eq 'OK') { Set-SamplePreview $c ([WowAuto.Audio.AudioTemplate]::ReadWave($picker.FileName)); Set-SampleDialogControls $c } }
        catch { $c.Status.Text='导入失败：'+$_.Exception.Message } finally { $picker.Dispose() } })
    $context.Play.Add_Click({param($sender,$e) $c=$sender.FindForm().Tag
        try { $c.Player.Stop(); $c.Player.SoundLocation=$c.PreviewPath; $c.Player.Play() } catch { $c.Status.Text='试听失败：'+$_.Exception.Message } })
    $context.Save.Add_Click({param($sender,$e) $c=$sender.FindForm().Tag
        try { Save-AudioSample $c.Flavor $c.Pending; $c.Use.Checked=$true; $c.Status.Text='样本已保存：'+(Get-AudioSamplePath $c.Flavor) }
        catch { $c.Status.Text='保存失败：'+$_.Exception.Message } })
    $done.Add_Click({param($sender,$e) $c=$sender.FindForm().Tag
        if ($null -ne $c.Capture) { $c.Status.Text='请先完成或取消录制。'; return }
        $script:audioUseTemplate=$c.Use.Checked; $script:audioSimilarity=[double]$c.Threshold.Value/100; Update-SampleButton; $c.Dialog.Close() })
    $context.Timer.Interval=100; $context.Timer.Tag=$context
    $context.Timer.Add_Tick({param($sender,$e) Update-SampleRecording $sender.Tag})
    $dialog.Add_Shown({param($sender,$e) $sender.Tag.Timer.Start()})
    $dialog.Add_FormClosed({param($sender,$e) Close-SampleDialog $sender.Tag})
    $context.Version.SelectedIndex=0
    return $dialog
}

$sampleButton=New-Object System.Windows.Forms.Button
$sampleButton.SetBounds(1090,56,195,35); $toolbar.Controls.Add($sampleButton); Update-SampleButton
$sampleButton.Add_Click({
    if ($script:scanning -or $script:editingSettings -or $script:scheduler.Tasks.Count -gt 0 -or $script:pendingGameExits.Count -gt 0) { return }
    $script:editingSettings=$true; $dialog=$null
    try { $dialog=New-AudioSampleDialog; [void]$dialog.ShowDialog($form) }
    finally { if ($null -ne $dialog) { Close-SampleDialog $dialog.Tag; $dialog.Dispose() }; $script:editingSettings=$false; Update-BatchControls }
})
