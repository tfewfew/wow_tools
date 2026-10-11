$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path $PSScriptRoot '..\wowAuto.Audio.cs')
Add-Type -TypeDefinition @'
using System;
using System.IO;
public static class SampleFixture {
    public static short[] Tone(double hz, double volume, double seconds) {
        int rate=11025; short[] result=new short[(int)(rate*seconds)];
        for (int i=0;i<result.Length;i++) {
            double t=i/(double)rate-0.10;
            if(t>=0 && t<0.22) result[i]=(short)(32767*volume*Math.Exp(-t*10)*Math.Sin(2*Math.PI*hz*t));
        }
        return result;
    }
    public static short[] Sequence(bool reverse) {
        short[] result = new short[15435];
        for (int i=0; i<result.Length; i++) {
            double t=i/11025.0, hz=0, volume=0;
            if (t>=.2 && t<.28) { hz=440; volume=.65; }
            if (t>=.36 && t<.61) { hz=reverse?2800:880; volume=.35; }
            if (t>=.72 && t<.97) { hz=reverse?880:2800; volume=.35; }
            result[i]=(short)(32767*volume*Math.Sin(2*Math.PI*hz*t));
        }
        return result;
    }
    public static short[] Shift(short[] source, int offset) {
        short[] result=new short[source.Length];
        for(int i=0; i<source.Length; i++) if(i+offset>=0 && i+offset<result.Length) result[i+offset]=source[i];
        return result;
    }
    public static short[] LateRise() {
        short[] result=new short[22050];
        for(int i=0;i<result.Length;i++) {
            double t=i/11025.0, amplitude=0;
            // An early quiet gate, a low-energy gap, then the actual loud burst.
            if(t>=.25 && t<.31) amplitude=.08;
            if(t>=.54 && t<.64) amplitude=.65;
            if(t>=.64 && t<1.40) amplitude=.65*Math.Exp(-(t-.64)*3);
            result[i]=(short)(32767*amplitude*Math.Sin(2*Math.PI*880*t));
        }
        return result;
    }

}
'@
function Assert-Template($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
$tone=[SampleFixture]::Tone(880,0.7,1.4)
$quiet=[SampleFixture]::Tone(880,0.14,1.4)
$other=[SampleFixture]::Tone(2800,0.7,1.4)
$template=[WowAuto.Audio.AudioTemplate]::FromMono($tone,11025)
Assert-Template ($template.Compare($quiet) -gt 0.99) 'Volume normalization changed a matching sound.'
Assert-Template ($template.Compare($other) -lt 0.6) 'Different frequency was accepted.'
$sequence=[SampleFixture]::Sequence($false)
$ordered=[WowAuto.Audio.AudioTemplate]::FromMono($sequence,11025)
Assert-Template ($ordered.Compare([SampleFixture]::Sequence($true)) -lt 0.86) 'Reordering sounds with the same spectrum/envelope was accepted.'
$truncated=[int16[]]$sequence[0..7000]
Assert-Template ($ordered.Compare($truncated) -eq 0) 'Truncated sound was padded into a matching full candidate.'
foreach ($offset in @(-55,17,55,109,221)) {
    Assert-Template ($ordered.Compare([SampleFixture]::Shift($sequence,$offset)) -gt 0.96) 'Small onset/packet alignment change lost the sound.'
}
# The second half of the reference is now part of the decision.
$missingTail=[int16[]]$sequence.Clone(); [Array]::Clear($missingTail,7200,($missingTail.Length-7200))
Assert-Template ($ordered.Compare($missingTail) -lt 0.86) 'Deleting the late sound did not affect the decision.'
$silence=New-Object 'System.Int16[]' 110
$matcher=[WowAuto.Audio.TemplateDetector]::new($template,0.88)
$matcher.Reset(0)
for ($time=0; $time -lt 1000; $time+=10) { Assert-Template (-not $matcher.Feed($silence,0,$time)) 'Warmup sent a signal.' }
function Feed-Synthetic($Detector,[int16[]]$Samples,[long]$Start) {
    $fired=0
    for ($i=0; $i -lt $Samples.Length; $i+=110) {
        $packet=[int16[]]$Samples[$i..([Math]::Min($Samples.Length-1,$i+109))]
        if ($Detector.Feed($packet,[WowAuto.Audio.SpikeDetector]::Pcm16Peak($packet),($Start+[long]($i*1000/11025)))) { $fired++ }
    }
    return $fired
}
Assert-Template ((Feed-Synthetic $matcher $other 1000) -eq 0 -and $matcher.Rejected -gt 0) 'Interference was not rejected.'
Assert-Template ((Feed-Synthetic $matcher $tone 3000) -eq 1) 'Rejected interference consumed the session or real template failed.'
$matcher.SetMinimumSimilarity(0.5)
Assert-Template ((Feed-Synthetic $matcher $tone 5000) -eq 0) 'A session emitted a second signal.'
$matcher.Reset(7000)
Assert-Template ((Feed-Synthetic $matcher $tone 7100) -eq 0) 'Reset skipped cast warmup.'
# An incomplete candidate must not survive disarm / new fishing session.
$matcher.Reset(9000)
for ($time=9000; $time -lt 10000; $time+=10) { $null=$matcher.Feed($silence,0,$time) }
$null=$matcher.Feed([int16[]]@(20000,20000),0.7,10000)
$matcher.Reset(10100)
for ($time=10100; $time -lt 12800; $time+=10) { Assert-Template (-not $matcher.Feed($silence,0,$time)) 'Old candidate survived reset.' }
# Change a threshold while collecting a real candidate; preserve its frames.
$live=[WowAuto.Audio.TemplateDetector]::new($ordered,0.99); $live.Reset(0)
for ($time=0; $time -lt 1000; $time+=10) { $null=$live.Feed($silence,0,$time) }
$liveSignals=0
for ($i=0; $i -lt $missingTail.Length; $i+=110) {
    if ($i -eq 4400) { $live.SetMinimumSimilarity(0.5) }
    $packet=[int16[]]$missingTail[$i..([Math]::Min($missingTail.Length-1,$i+109))]
    if ($live.Feed($packet,[WowAuto.Audio.SpikeDetector]::Pcm16Peak($packet),(1000+[long]($i*1000/11025)))) { $liveSignals++ }
}
Assert-Template ($liveSignals -eq 1) 'Live threshold update discarded a candidate or failed to use the new threshold.'
foreach ($invalid in @([double]::NaN,0.49,1.01)) {
    $rejected=$false; try { $live.SetMinimumSimilarity($invalid) } catch { $rejected=$true }
    Assert-Template ($rejected -and $live.MinimumSimilarity -eq 0.5) 'Invalid live threshold changed the active threshold.'
}
# A later onset needs a complete tail beyond the minimum 1.2-second candidate.
$late=[SampleFixture]::LateRise()
$lateTemplate=[WowAuto.Audio.AudioTemplate]::FromMono($late,11025)
$lateMatcher=[WowAuto.Audio.TemplateDetector]::new($lateTemplate,0.95); $lateMatcher.Reset(0)
for ($time=0; $time -lt 1000; $time+=10) { $null=$lateMatcher.Feed($silence,0,$time) }
$lateSignals=0; $lateFiredAt=0L
for ($i=0; $i -lt $late.Length; $i+=110) {
    $packet=[int16[]]$late[$i..([Math]::Min($late.Length-1,$i+109))]
    $now=1000+[long]($i*1000/11025)
    if ($lateMatcher.Feed($packet,[WowAuto.Audio.SpikeDetector]::Pcm16Peak($packet),$now)) { $lateSignals++; $lateFiredAt=$now }
}
Assert-Template ($lateSignals -eq 1 -and $lateMatcher.Rejected -eq 0 -and $lateFiredAt -gt 2200 -and $lateFiredAt -lt 2700) 'Late-rise candidate was truncated/rejected, fired early or exceeded the bounded tail wait.'
$path=Join-Path ([IO.Path]::GetTempPath()) ('wow-feature-test-'+[Guid]::NewGuid()+'.feature')
try {
    [WowAuto.Audio.AudioTemplate]::SaveFeatures($path,[WowAuto.Audio.AudioTemplate[]]@($template),0.91)
    $loaded=[WowAuto.Audio.AudioTemplate]::LoadFeatures($path)
    Assert-Template ($loaded.Count -eq 1 -and $loaded.IsTrial -and $loaded.MinimumSimilarity -eq 0.91 -and $loaded.Compare($tone) -gt 0.99) 'Numerical feature round-trip failed.'
    $second=[WowAuto.Audio.AudioTemplate]::FromMono($other,11025)
    [WowAuto.Audio.AudioTemplate]::SaveFeatures($path,[WowAuto.Audio.AudioTemplate[]]@($template,$second),0.9)
    $loaded=[WowAuto.Audio.AudioTemplate]::LoadFeatures($path)
    Assert-Template ($loaded.Count -eq 2 -and $loaded.Compare($other) -gt 0.99 -and $loaded.Compare($quiet) -gt 0.99) 'Feature variants did not match independently.'
    $valid=[IO.File]::ReadAllText($path)
    foreach ($invalid in @('Format=invalid', ($valid -replace 'Format=2','Format=1'), ($valid -replace 'WindowSamples=11025','WindowSamples=4096'), ($valid -replace 'TimeSlices=8','TimeSlices=1'), ($valid+"`nThreshold=0.9"), ($valid -replace 'Threshold=0.9','Threshold=NaN'), ($valid -replace 'Template=.*','Template=0,0,0'), ($valid -replace 'Status=trial','Status=invalid'))) {
        [IO.File]::WriteAllText($path,$invalid)
        $rejected=$false; try { $null=[WowAuto.Audio.AudioTemplate]::LoadFeatures($path) } catch { $rejected=$true }
        Assert-Template $rejected 'Malformed/duplicate/non-finite numerical features accepted.'
    }
    $rejected=$false; try { $null=[WowAuto.Audio.AudioTemplate]::FromMono((New-Object 'System.Int16[]' 15435),11025) } catch { $rejected=$true }
    Assert-Template $rejected 'Silence accepted as a template.'
    $rejected=$false; try { $null=[WowAuto.Audio.AudioTemplate]::FromMono((New-Object 'System.Int16[]' 121276),11025) } catch { $rejected=$true }
    Assert-Template $rejected 'Oversized sample accepted.'
    [IO.File]::WriteAllText($path,($valid -replace 'Status=trial','Status=verified'))
    Assert-Template (-not [WowAuto.Audio.AudioTemplate]::LoadFeatures($path).IsTrial) 'Verified status was not loaded.'
    [IO.File]::WriteAllText($path,($valid -replace 'Status=trial',''))
    Assert-Template ([WowAuto.Audio.AudioTemplate]::LoadFeatures($path).IsTrial) 'Unreviewed legacy features were marked verified.'
    $null=[WowAuto.Audio.AudioTemplate]::LoadFeatures((Join-Path $PSScriptRoot '..\audio-features\forerver.feature'))
    $clock=[Diagnostics.Stopwatch]::StartNew()
    for ($i=0;$i -lt 100;$i++) { $null=$template.Compare($tone) }
    $clock.Stop()
    Write-Output ("PASS: normalized time-resolved FFT/envelope matching, time order/tail/packet alignment, bounded late-rise capture, live thresholds, rejected interference followed by real bite, warmup/dedup/reset, format-2 feature banks/variants/invalid input. 100 candidate comparisons: {0}ms; synthetic only." -f $clock.ElapsedMilliseconds)
}
finally { if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) } }
