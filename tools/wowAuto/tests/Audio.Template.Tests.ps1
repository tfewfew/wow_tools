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

}
'@
function Assert-Template($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
$tone=[SampleFixture]::Tone(880,0.7,0.7)
$quiet=[SampleFixture]::Tone(880,0.14,0.7)
$other=[SampleFixture]::Tone(2800,0.7,0.7)
$template=[WowAuto.Audio.AudioTemplate]::FromMono($tone,11025)
Assert-Template ($template.Compare($quiet) -gt 0.99) 'Volume normalization changed a matching sound.'
Assert-Template ($template.Compare($other) -lt 0.6) 'Different frequency was accepted.'
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
Assert-Template ((Feed-Synthetic $matcher $tone 2000) -eq 1) 'Rejected interference consumed the session or real template failed.'
Assert-Template ((Feed-Synthetic $matcher $tone 3000) -eq 0) 'A session emitted a second signal.'
$matcher.Reset(4000)
Assert-Template ((Feed-Synthetic $matcher $tone 4100) -eq 0) 'Reset skipped cast warmup.'
# An incomplete candidate must not survive disarm / new fishing session.
$matcher.Reset(5000)
for ($time=5000; $time -lt 6000; $time+=10) { $null=$matcher.Feed($silence,0,$time) }
$null=$matcher.Feed([int16[]]@(20000,20000),0.7,6000)
$matcher.Reset(6100)
for ($time=6100; $time -lt 7800; $time+=10) { Assert-Template (-not $matcher.Feed($silence,0,$time)) 'Old candidate survived reset.' }
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
    foreach ($invalid in @('Format=invalid', ($valid+"`nThreshold=0.9"), ($valid -replace 'Threshold=0.9','Threshold=NaN'), ($valid -replace 'Template=.*','Template=0,0,0'), ($valid -replace 'Status=trial','Status=invalid'))) {
        [IO.File]::WriteAllText($path,$invalid)
        $rejected=$false; try { $null=[WowAuto.Audio.AudioTemplate]::LoadFeatures($path) } catch { $rejected=$true }
        Assert-Template $rejected 'Malformed/duplicate/non-finite numerical features accepted.'
    }
    $rejected=$false; try { $null=[WowAuto.Audio.AudioTemplate]::FromMono((New-Object 'System.Int16[]' 11025),11025) } catch { $rejected=$true }
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
    Write-Output ("PASS: normalized FFT/envelope matching, rejected interference followed by real bite, warmup/dedup/reset, numerical feature banks/variants/invalid input. 100 candidate comparisons: {0}ms; synthetic only." -f $clock.ElapsedMilliseconds)
}
finally { if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) } }
