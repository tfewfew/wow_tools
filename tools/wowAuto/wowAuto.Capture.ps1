# One source for white point, fishing, combat and OCR. Read requests never activate a window.
if (-not ('WowAutoCapture.Native' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'wowAuto.Capture.cs') -ReferencedAssemblies System.Drawing
}
if (-not $UiTest) {Add-Type -AssemblyName System.Runtime.WindowsRuntime}
[WowAuto.NativeInput]::WindowPixelReader=[WowAutoCapture.Native]::PixelReader
function Test-WindowCapturePending($ErrorRecord) {
    return [WowAutoCapture.Native]::IsPending($ErrorRecord.Exception)
}
function Submit-WindowCaptureActions([long]$Now) {
    if ($UiTest) {return}
    foreach ($request in [WowAutoCapture.Native]::PendingRestores()) {
        Add-GameAction -Id ('capture-restore:'+$request.Key) -Kind Capture.Restore -Domain Capture -Key $request.Key -Owner $request -Due $Now -Data $request -Execute {
            param($event,$now)
            Assert-GameActionContext
            [WowAutoCapture.Native]::RestoreMinimized($event.Data)
        }
    }
}
function Request-FishingForeground([long]$Now) {
    Assert-GameActionContext
    $event=$script:gameActions.Current
    if ($event.Foreground) {return $true}
    # Requeue the same intent before changing fishing state or sending input.
    if ($event.Data.Kind -eq 'Item') {$event.Data.Due=$event.Owner.ItemDue}
    $event.Foreground=$true;$event.Due=$Now;$event.ReadyAt=0L;$event.FocusUntil=0L
    [void]$script:gameActions.Events.Add($event)
    return $false
}
