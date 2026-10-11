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
    public static void FloatWave(string path, short[] mono) {
        using(BinaryWriter w=new BinaryWriter(File.Create(path))) {
            w.Write(System.Text.Encoding.ASCII.GetBytes("RIFF")); w.Write(36+mono.Length*8);
            w.Write(System.Text.Encoding.ASCII.GetBytes("WAVEfmt ")); w.Write(16);
            w.Write((short)3); w.Write((short)2); w.Write(11025); w.Write(88200); w.Write((short)8); w.Write((short)32);
            w.Write(System.Text.Encoding.ASCII.GetBytes("data")); w.Write(mono.Length*8);
            foreach(short s in mono) { w.Write(s/32768f); w.Write(s/32768f); }
        }
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
$path=Join-Path ([IO.Path]::GetTempPath()) ('wow-template-test-'+[Guid]::NewGuid()+'.wav')
try {
    [WowAuto.Audio.AudioTemplate]::WriteWave($path,$tone)
    $loaded=[WowAuto.Audio.AudioTemplate]::FromWave($path)
    Assert-Template ($loaded.Compare($tone) -gt 0.99) 'PCM16 WAV round-trip failed.'
    [SampleFixture]::FloatWave($path,$tone)
    $loaded=[WowAuto.Audio.AudioTemplate]::FromWave($path)
    Assert-Template ($loaded.Compare($tone) -gt 0.99) 'Stereo float32 WAV import failed.'
    [IO.File]::WriteAllBytes($path,[byte[]]@(1,2,3))
    $rejected=$false; try { $null=[WowAuto.Audio.AudioTemplate]::FromWave($path) } catch { $rejected=$true }
    Assert-Template $rejected 'Malformed WAV accepted.'
    $rejected=$false; try { $null=[WowAuto.Audio.AudioTemplate]::FromMono((New-Object 'System.Int16[]' 11025),11025) } catch { $rejected=$true }
    Assert-Template $rejected 'Silence accepted as a template.'
    $rejected=$false; try { $null=[WowAuto.Audio.AudioTemplate]::FromMono((New-Object 'System.Int16[]' 121276),11025) } catch { $rejected=$true }
    Assert-Template $rejected 'Oversized sample accepted.'
    $clock=[Diagnostics.Stopwatch]::StartNew()
    for ($i=0;$i -lt 100;$i++) { $null=$template.Compare($tone) }
    $clock.Stop()
    Write-Output ("PASS: normalized FFT/envelope matching, rejected interference followed by real bite, warmup/dedup/reset, WAV formats/invalid input. 100 candidate comparisons: {0}ms; synthetic only." -f $clock.ElapsedMilliseconds)
}
finally { if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) } }
