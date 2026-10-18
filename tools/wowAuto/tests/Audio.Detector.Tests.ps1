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
$quietDetector=[WowAuto.Audio.SpikeDetector]::new()
foreach($scale in @(1.0,0.5,0.2,0.05,0.01)){
    $quietDetector.Reset(0)
    for($time=0;$time -lt 1000;$time+=10){$peak=$(if($time -lt 100){0.08}else{0.001})*$scale;Assert-Audio (-not $quietDetector.Observe($peak,$time)) 'Adaptive gate bypassed cast warmup.'}
    Assert-Audio (-not $quietDetector.Observe((0.0012*$scale),1000)) 'Adaptive gate admitted stable background noise.'
    Assert-Audio ($quietDetector.Observe((0.3*$scale),1010) -and -not $quietDetector.Observe((0.5*$scale),1020)) 'Adaptive volume missed a bite or emitted a duplicate.'
}
$quietDetector.Reset(0);$gate=$quietDetector.PeakThreshold
foreach($scale in @(1.0,0.5,0.2,0.05,0.01)){
    $rising=[WowAuto.Audio.SpikeDetector]::new();$rising.Reset(0)
    for($time=0;$time -lt 2000;$time+=10){Assert-Audio (-not $rising.Observe((0.01*$scale),$time)) 'Stable background triggered a gradual-rise candidate.'}
    $signals=0;$firedAt=0
    # A one-second, tenfold rise was previously absorbed into the noise model.
    for($step=0;$step -le 100;$step++){
        $peak=0.01*[Math]::Pow(10,$step/100.0)*$scale;$time=2000+$step*10
        if($rising.Observe($peak,$time)){$signals++;$firedAt=$time}
    }
    Assert-Audio ($signals -eq 1 -and $firedAt -ge 2500 -and $firedAt -le 3000 -and $rising.Baseline -le 0.02*$scale) 'Gradually rising bite poisoned its own background model or emitted duplicate signals.'
}
foreach($invalid in @([double]::NaN,[double]::PositiveInfinity,[double]::NegativeInfinity)){
    Assert-Audio (-not $quietDetector.Probe($invalid,2000) -and $quietDetector.PeakThreshold -eq $gate) 'Invalid PCM peak poisoned the adaptive noise model.'
}
Assert-Audio (-not $quietDetector.Probe((4.0/32768),2000)) 'PCM quantization noise triggered a candidate.'
Assert-Audio ([WowAuto.Audio.SpikeDetector]::Pcm16Peak([int16[]]@(-32768,0,32767)) -eq 1) 'Negative PCM full scale overflowed.'
Assert-Audio ([WowAuto.Audio.SpikeDetector]::Pcm16Peak([int16[]]@(0,0)) -eq 0) 'Silence was not silent.'
$assembly=[WowAuto.Audio.ProcessCapture].Assembly
Assert-Audio ([Runtime.InteropServices.Marshal]::SizeOf([Activator]::CreateInstance($assembly.GetType('WowAuto.Audio.WaveFormat'))) -eq 18) 'WAVEFORMATEX layout is incorrect.'
$variantSize=if ([IntPtr]::Size -eq 8) {24} else {16}
Assert-Audio ([Runtime.InteropServices.Marshal]::SizeOf([Activator]::CreateInstance($assembly.GetType('WowAuto.Audio.Native+PropVariant'))) -eq $variantSize) 'PROPVARIANT blob layout is incorrect.'
Write-Output 'PASS: .NET Framework compile, adaptive 1/5/20/50/100% amplitude and gradual-rise protection, warmup/background rejection/deduplication, invalid/quantized noise rejection and native structure sizes. Synthetic only.'
