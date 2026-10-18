param()
$ErrorActionPreference='Stop'
$helper=@'
namespace WowAuto.Audio {
public static class AdaptiveAudioFixture {
    public static short[] Reference() {
        var pcm=new short[15435];
        for(int i=0;i<pcm.Length;i++) {
            double t=i/11025.0-.1;
            if(t>=0 && t<.22)pcm[i]=(short)(32767*.5*Math.Exp(-t*10)*Math.Sin(2*Math.PI*880*t));
        }
        return pcm;
    }
    public static short[] Scene(double gain,bool bite,bool continuousInterference) {
        var pcm=new short[continuousInterference?110250:49612];
        for(int i=0;i<pcm.Length;i++) {
            double t=i/11025.0;
            double signal=.0002*Math.Sin(2*Math.PI*347*t);
            if(t>=.05 && t<.15)signal+=.08*Math.Sin(2*Math.PI*300*t);
            double first=t-1.1;
            if(first>=0 && (continuousInterference || first<.22))signal+=.08*Math.Sin(2*Math.PI*2800*t);
            double actual=t-1.8;
            if(bite && actual>=0 && actual<.22)signal+=.5*Math.Exp(-actual*10)*Math.Sin(2*Math.PI*880*t);
            pcm[i]=(short)(32767*gain*signal);
        }
        return pcm;
    }
    public static long[] Feed(TemplateDetector detector,short[] pcm,int size) {
        int signals=0;long at=0;int pending=0;
        for(int i=0;i<pcm.Length;i+=size) {
            var packet=new short[Math.Min(size,pcm.Length-i)];Array.Copy(pcm,i,packet,0,packet.Length);
            long now=(long)(i*1000.0/11025);
            if(detector.Feed(packet,SpikeDetector.Pcm16Peak(packet),now)){signals++;at=now;}
            pending=Math.Max(pending,detector.PendingCandidates);
        }
        return new long[]{signals,at,pending};
    }
}
}
'@
Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\wowAuto.Audio.cs'))+$helper)
function Assert-Adaptive($Condition,[string]$Message){if(-not $Condition){throw $Message}}
$template=[WowAuto.Audio.AudioTemplate]::FromMono([WowAuto.Audio.AdaptiveAudioFixture]::Reference(),11025)
$detector=[WowAuto.Audio.TemplateDetector]::new($template,0.88)
foreach($gain in @(1.0,0.5,0.2,0.05,0.01)){
    foreach($size in @(110,256,441)){
        $detector.Reset(0)
        $result=[WowAuto.Audio.AdaptiveAudioFixture]::Feed($detector,[WowAuto.Audio.AdaptiveAudioFixture]::Scene($gain,$true,$false),$size)
        Assert-Adaptive ($result[0] -eq 1 -and $result[1] -ge 2680 -and $result[1] -le 3500) ('Adaptive matching missed/duplicated a bite or interference blocked its window: gain='+$gain+' packet='+$size+' result='+($result -join ','))
        Assert-Adaptive ($result[2] -le [WowAuto.Audio.TemplateDetector]::MaximumPendingCandidates -and $detector.MinimumSimilarity -eq 0.88) 'Adaptive matching exceeded its pending limit or changed the user threshold.'
    }
}
$detector.Reset(0)
$result=[WowAuto.Audio.AdaptiveAudioFixture]::Feed($detector,[WowAuto.Audio.AdaptiveAudioFixture]::Scene(0.2,$false,$true),110)
Assert-Adaptive ($result[0] -eq 0 -and $result[2] -le 8 -and $detector.ComparedCandidates -gt 0 -and $detector.ComparedCandidates -le 40) 'Continuous interference was accepted or caused unbounded comparison work.'
$detector.Reset(0)
Assert-Adaptive ($detector.PendingCandidates -eq 0 -and $detector.ComparedCandidates -eq 0 -and $detector.BestSimilarity -eq 0) 'New round retained pending candidates or learned diagnostics.'
$silence=New-Object 'System.Int16[]' 49612
$result=[WowAuto.Audio.AdaptiveAudioFixture]::Feed($detector,$silence,110)
Assert-Adaptive ($result[0] -eq 0 -and $detector.ComparedCandidates -eq 0) 'Silence created an audio match or FFT work.'
Write-Output 'PASS: automatic 1/5/20/50/100% amplitude with no supplied gain, per-round relearning, overlapping interference/real-bite windows, packet sizes, once-per-round trigger, bounded memory/comparisons, silence and unchanged similarity threshold. Synthetic PCM only.'
