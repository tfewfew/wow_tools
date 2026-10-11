# Previews are one-second matching excerpts; full recordings remain archived locally.
$script:audioRecordingSelections=@{titan=2; forerver=1}
$script:audioRecordingDirectory=if ($UiTest) { Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-recordings-test-'+[Guid]::NewGuid()) }
    else { Join-Path $PSScriptRoot 'audio-samples' }
$script:audioRecordings=@{
    titan=@(
        [pscustomobject]@{Id=1; Label='片段 1 · 2026-10-11 · 右侧窗口 · 1秒'; Feature='titan-01.feature'; Wave='titan-01-match.wav'},
        [pscustomobject]@{Id=2; Label='片段 2 · 2026-10-12 · 左上窗口 · 1秒'; Feature='titan-02.feature'; Wave='titan-02-match.wav'}
    )
    forerver=@([pscustomobject]@{Id=1; Label='片段 1 · 2026-10-11 · 1秒'; Feature='forerver.feature'; Wave='forerver-01-match.wav'})
}
$script:previewActions=@()
function Get-AudioRecording([string]$Flavor, $RecordingId) {
    if ($Flavor -notin @('titan','forerver')) { throw '未知客户端版本。' }
    $id=0
    if ([string]$RecordingId -notmatch '^\d+$' -or -not [int]::TryParse([string]$RecordingId,[ref]$id)) { throw '录音序号需为可用的整数序号。' }
    $recording=@($script:audioRecordings[$Flavor] | Where-Object {$_.Id -eq $id})
    if ($recording.Count -ne 1) { throw "此版本没有音频片段 $id，请选择下拉菜单中的片段。" }
    return $recording[0]
}
function Get-AudioTemplate([string]$Flavor, $RecordingId=$script:audioRecordingSelections[$Flavor]) {
    $recording=Get-AudioRecording $Flavor $RecordingId
    $path=Join-Path $script:audioFeatureDirectory $recording.Feature
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "此版本片段 $($recording.Id) 尚未校准咬钩声音特征。" }
    return [WowAuto.Audio.AudioTemplate]::LoadFeatures($path)
}
function Stop-AudioPreview($Dialog) {
    if ($null -eq $Dialog.Tag) { return }
    if ($null -ne $Dialog.Tag.PreviewPlayer) {
        try { $Dialog.Tag.PreviewPlayer.Stop() }
        finally { $Dialog.Tag.PreviewPlayer.Dispose(); $Dialog.Tag.PreviewPlayer=$null }
    }
    $Dialog.Tag.PreviewStatus.Text=''
}
function Start-AudioPreview($Dialog, [string]$Flavor, $RecordingId) {
    Stop-AudioPreview $Dialog
    $recording=Get-AudioRecording $Flavor $RecordingId
    $path=Join-Path $script:audioRecordingDirectory $recording.Wave
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "片段 $($recording.Id) 的试听文件不存在：$path" }
    $player=$null
    try {
        if ($UiTest) {
            $player=[pscustomobject]@{SoundLocation=$path; Played=$false; Stopped=$false; Disposed=$false}
            $player | Add-Member ScriptMethod Load { $script:previewActions+=('load:'+ $this.SoundLocation) }
            $player | Add-Member ScriptMethod Play { $this.Played=$true; $script:previewActions+=('play:'+ $this.SoundLocation) }
            $player | Add-Member ScriptMethod Stop { $this.Stopped=$true; $script:previewActions+=('stop:'+ $this.SoundLocation) }
            $player | Add-Member ScriptMethod Dispose { $this.Disposed=$true }
        }
        else { $player=New-Object System.Media.SoundPlayer($path) }
        $player.Load(); $player.Play()
        $Dialog.Tag.PreviewPlayer=$player
        $label=if ($Flavor -eq 'titan') {'时光服'} else {'无限服'}
        $Dialog.Tag.PreviewStatus.Text="试听片段：$label · $($recording.Label)"
    }
    catch { if ($null -ne $player) { $player.Dispose() }; throw }
}
