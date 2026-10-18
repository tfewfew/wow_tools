$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path $PSScriptRoot '..\wowAuto.Audio.cs')
function Assert-Audio($Condition, $Message) { if (-not $Condition) { throw $Message } }
$detector=New-Object WowAuto.Audio.SpikeDetector
$detector.Reset(0)
Assert-Audio (-not $detector.Observe(0.8,100)) 'Cast audio bypassed the warmup.'
for ($time=110; $time -le 990; $time+=10) { $null=$detector.Observe(0.005,$time) }
Assert-Audio (-not $detector.Observe(0.03,1000)) 'Quiet audio triggered a bite.'
Assert-Audio $detector.Observe(0.3,1010) 'Sharp rise over quiet baseline was missed.'
Assert-Audio (-not $detector.Observe(0.9,1020)) 'One fishing session triggered twice.'
$detector.Reset(2000)
for ($time=2000; $time -le 2990; $time+=10) { $null=$detector.Observe(0.1,$time) }
Assert-Audio (-not $detector.Observe(0.12,3000)) 'Stable ambient audio triggered a bite.'
Assert-Audio $detector.Observe(0.6,3010) 'Adaptive baseline prevented a real spike.'
$quietDetector=[WowAuto.Audio.SpikeDetector]::new([WowAuto.Audio.ProcessCapture]::MasterVolumeScale)
$quietDetector.Reset(0)
for ($time=0;$time -lt 1000;$time+=10){Assert-Audio (-not $quietDetector.Observe(0.001,$time)) '20% volume bypassed cast warmup.'}
Assert-Audio (-not $quietDetector.Observe(0.006,1000)) '20% volume admitted quiet noise below the scaled floor.'
Assert-Audio ($quietDetector.Observe(0.04,1010) -and -not $quietDetector.Observe(0.1,1020)) '20% volume missed a scaled bite or emitted a duplicate.'
$quietDetector.Reset(2000)
for ($time=2000;$time -lt 3000;$time+=10){$null=$quietDetector.Observe(0.02,$time)}
Assert-Audio (-not $quietDetector.Observe(0.024,3000) -and $quietDetector.Observe(0.12,3010)) 'Scaled volume lost adaptive ambient rejection.'
foreach($scale in @(0,0.009,1.01,[double]::NaN,[double]::PositiveInfinity)){
    $rejected=$false;try{$null=[WowAuto.Audio.SpikeDetector]::new($scale)}catch{$rejected=$true}
    Assert-Audio $rejected 'Invalid volume scale accepted.'
}
Assert-Audio ([WowAuto.Audio.ProcessCapture]::MasterVolumeScale -eq 0.2) 'Capture gate does not match the addon 20% master volume.'
Assert-Audio ([WowAuto.Audio.SpikeDetector]::Pcm16Peak([int16[]]@(-32768,0,32767)) -eq 1) 'Negative PCM full scale overflowed.'
Assert-Audio ([WowAuto.Audio.SpikeDetector]::Pcm16Peak([int16[]]@(0,0)) -eq 0) 'Silence was not silent.'
$assembly=[WowAuto.Audio.ProcessCapture].Assembly
Assert-Audio ([Runtime.InteropServices.Marshal]::SizeOf([Activator]::CreateInstance($assembly.GetType('WowAuto.Audio.WaveFormat'))) -eq 18) 'WAVEFORMATEX layout is incorrect.'
$variantSize=if ([IntPtr]::Size -eq 8) {24} else {16}
Assert-Audio ([Runtime.InteropServices.Marshal]::SizeOf([Activator]::CreateInstance($assembly.GetType('WowAuto.Audio.Native+PropVariant'))) -eq $variantSize) 'PROPVARIANT blob layout is incorrect.'
Write-Output 'PASS: .NET Framework compile, 100%/20% volume gates, unchanged warmup/ambient rejection/deduplication, scale validation, synthetic PCM peaks and native structure sizes. No audio or game input captured.'
