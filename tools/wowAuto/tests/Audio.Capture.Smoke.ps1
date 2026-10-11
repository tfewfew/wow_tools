# Capture only this test PowerShell process, which renders no audio. Never touch WoW.
$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path $PSScriptRoot '..\wowAuto.Audio.cs')
$self=Get-Process -Id $PID
$capture=$null
try {
    $capture=New-Object WowAuto.Audio.ProcessCapture($self.Id,$self.StartTime.Ticks,$self.MainModule.FileName)
    $deadline=[DateTime]::UtcNow.AddSeconds(5)
    while ($capture.Status -eq 'Starting' -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 25 }
    if ($capture.Status -ne 'Listening') { throw "Self-process loopback initialization failed: $($capture.Status) / $($capture.Error)" }
    $capture.Arm(1)
    Start-Sleep -Milliseconds 1200
    $session=0L
    # Windows' PCM conversion may dither silence by one least-significant bit.
    if ($capture.Status -ne 'Listening' -or $capture.TryTakeBite([ref]$session) -or $capture.Peak -gt (2.0/32768)) {
        throw "Silent self-process capture was not isolated: $($capture.Status) / $($capture.Error) / peak=$($capture.Peak) / signal=$session"
    }
    $capture.Arm(0); $capture.StartRecording(1)
    $deadline=[DateTime]::UtcNow.AddSeconds(3)
    while ($capture.Recording -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 25 }
    $recorded=$capture.TakeRecording()
    if ($capture.Recording -or $null -eq $recorded -or $recorded.Length -lt 8000 -or
        [WowAuto.Audio.SpikeDetector]::Pcm16Peak($recorded) -gt (2.0/32768)) { throw 'Silent self-recording was not completed/bounded/isolated.' }
    $rejected=$false
    try { $invalid=New-Object WowAuto.Audio.ProcessCapture($self.Id,($self.StartTime.Ticks+1),$self.MainModule.FileName) } catch { $rejected=$true }
    if (-not $rejected) { $invalid.Dispose(); throw 'Wrong process start time was accepted.' }
    Write-Output 'PASS: Windows process-loopback activation/capture and bounded recording of the silent test process, no system-audio fallback, and PID/start-time identity rejection. No WoW audio or input used.'
}
finally { if ($null -ne $capture) { $capture.Dispose() }; $self.Dispose() }
