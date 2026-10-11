$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path $PSScriptRoot '..\wowAuto.Audio.cs')
function Assert-Switch($Condition,[string]$Message) {if(-not $Condition) {throw $Message}}
function New-SwitchTone([double]$Hz) {
    $samples=New-Object 'System.Int16[]' 15435
    for($i=2205;$i -lt 4630;$i++) {$samples[$i]=[int16](22000*[Math]::Exp(-($i-2205)/1102)*[Math]::Sin(2*[Math]::PI*$Hz*$i/11025))}
    return ,$samples
}
$first=New-SwitchTone 880; $second=New-SwitchTone 2800
$a=[WowAuto.Audio.AudioTemplate]::FromMono($first,11025); $b=[WowAuto.Audio.AudioTemplate]::FromMono($second,11025)
# Initialize only the in-memory fields. Never call ProcessCapture's native constructor:
# no thread, process identity lookup, Windows audio activation or disposal is involved.
$capture=[Runtime.Serialization.FormatterServices]::GetUninitializedObject([WowAuto.Audio.ProcessCapture])
$flags=[Reflection.BindingFlags]'Instance,NonPublic'
$fields=@{gate=(New-Object object);clock=[Diagnostics.Stopwatch]::StartNew();detector=[WowAuto.Audio.SpikeDetector]::new();matcher=[WowAuto.Audio.TemplateDetector]::new($a,0.90);session=41L;pendingBite=41L}
foreach($name in $fields.Keys) {$capture.GetType().GetField($name,$flags).SetValue($capture,$fields[$name])}
$rejected=$false
try {$capture.SetTemplate($b,0.90)} catch {$rejected=$true}
Assert-Switch ($rejected -and [object]::ReferenceEquals($fields.matcher,$capture.GetType().GetField('matcher',$flags).GetValue($capture)) -and $capture.GetType().GetField('pendingBite',$flags).GetValue($capture) -eq 41L) 'Armed template replacement discarded the current matcher or bite.'
$capture.Arm(0)
foreach($invalid in @([double]::NaN,0.49,1.01)) {
    $rejected=$false; try {$capture.SetTemplate($b,$invalid)} catch {$rejected=$true}
    Assert-Switch ($rejected -and [object]::ReferenceEquals($fields.matcher,$capture.GetType().GetField('matcher',$flags).GetValue($capture))) 'Invalid threshold changed a matcher.'
}
$rejected=$false; try {$capture.SetTemplate($null,0.90)} catch {$rejected=$true}
Assert-Switch $rejected 'Null template was accepted.'
$capture.SetTemplate($b,0.90); $capture.Arm(42)
$matcher=$capture.GetType().GetField('matcher',$flags).GetValue($capture)
Assert-Switch (-not [object]::ReferenceEquals($matcher,$fields.matcher) -and $capture.GetType().GetField('session',$flags).GetValue($capture) -eq 42L -and $capture.GetType().GetField('pendingBite',$flags).GetValue($capture) -eq 0L) 'New-round matcher/session reset failed.'
foreach($spec in @(@($first,0),@($second,1))) {
    $matcher.Reset(-1500); $accepted=0; $pcm=$spec[0]
    for($i=0;$i -lt $pcm.Length;$i+=110) {
        $end=[Math]::Min($pcm.Length-1,$i+109); $packet=[int16[]]$pcm[$i..$end]
        if($matcher.Feed($packet,[WowAuto.Audio.SpikeDetector]::Pcm16Peak($packet),[long]($i*1000.0/11025))) {$accepted++}
    }
    Assert-Switch ($accepted -eq $spec[1]) 'Replacement matcher still accepted only the old recording.'
}
$capture.GetType().GetField('disposed',$flags).SetValue($capture,$true); $capture.SetTemplate($a,0.90)
Assert-Switch ([object]::ReferenceEquals($matcher,$capture.GetType().GetField('matcher',$flags).GetValue($capture)) -and $null -eq $capture.GetType().GetField('thread',$flags).GetValue($capture)) 'Disposed replacement changed the matcher or started a capture thread.'
Write-Output 'PASS: armed-round protection, null/threshold validation, disarmed replacement, new-session identity, new-only matching and disposed no-op. Synthetic PCM and in-memory fields only; no native capture/playback.'
