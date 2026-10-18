$ErrorActionPreference='Stop'
$tool=Split-Path $PSScriptRoot -Parent
Add-Type -Path (Join-Path $tool 'wowAuto.Threading.cs') -ReferencedAssemblies System.Core
Add-Type -TypeDefinition @'
using System;
using System.Threading;
public static class AudioNotificationFixture {
    public static Thread Notify(Action<long> callback,long session) {
        var thread=new Thread(()=>callback(session));thread.Start();return thread;
    }
}
'@
. (Join-Path $tool 'wowAuto.Engine.ps1')
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $tool 'wowAuto.Detector.ps1'),[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Detector source does not parse.'}
foreach($name in @('Test-DetectorCurrent','Receive-DetectorAudioBite')){
    $definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    . ([scriptblock]::Create($definition.Extent.Text))
}
function Write-Detector([string]$Text){$script:receivedStatus=$Text}
function Assert-Notification($Condition,[string]$Message){if(-not $Condition){throw $Message}}
$directory=Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-audio-notify-'+[guid]::NewGuid().ToString('N'))
$Hub=New-Object WowAuto.Threading.Hub($directory,1)
try {
    $Endpoint=$Hub.Register('11:1',11,1,'fixture','titan');$other=$Hub.Register('12:1',12,1,'fixture','forerver')
    $script:version=$Endpoint.Send('Start','{}');$null=$Endpoint.Receive(0)
    $script:running=$true;$script:mode='fish';$script:audio=[pscustomobject]@{Mock=$true}
    $script:scheduler=New-WowAutoScheduler
    $script:fish=Add-WowAutoTask $script:scheduler $Endpoint.Key 37 37 0 -UseAudio $true
    $script:fish.AudioReady=$true;$null=Complete-WowAutoPoll $script:scheduler $Endpoint.Key 0 green
    $script:fish.FishingStartedAt=$Hub.Now-2000
    $callback=$Hub.CreateAudioNotifier($Endpoint,$script:version)
    $producer=[AudioNotificationFixture]::Notify($callback,$script:fish.AudioSession)
    $message=$Endpoint.Receive(1000);$producer.Join()
    $data=$message.Json | ConvertFrom-Json
    Assert-Notification ($message.Kind -eq 'Audio.Bite' -and $message.Version -eq $script:version -and
        $data.Session -eq $script:fish.AudioSession -and $data.MatchedAt -le $Hub.Now -and -not $other.Receive(0)) 'Notification lost its owner/session/version/time.'
    Receive-DetectorAudioBite $message
    Assert-Notification ($script:fish.AudioReelPending -and $script:fish.Deadline -eq $data.MatchedAt+37 -and $script:receivedStatus -match '音频匹配成功') 'Production handler did not schedule from the match time.'
    $deadline=$script:fish.Deadline;Receive-DetectorAudioBite $message
    Assert-Notification ($script:fish.Deadline -eq $deadline -and @($script:scheduler.Events | Where-Object Kind -eq Reel).Count -eq 1) 'Duplicate event changed the pending reel.'
    $null=$Endpoint.Send('Stop','{}');$null=$Endpoint.Receive(0)
    $callback.Invoke($script:fish.AudioSession);Receive-DetectorAudioBite $message
    Assert-Notification (-not $Endpoint.Receive(0) -and $script:fish.Deadline -eq $deadline) 'An obsolete callback/event survived a stop generation.'
    $fresh=$Hub.CreateAudioNotifier($Endpoint,$Endpoint.Version);$fresh.Invoke(0)
    Assert-Notification (-not $Endpoint.Receive(0)) 'Disarmed audio emitted a notification.'
    $Endpoint.Close();$fresh.Invoke(123)
    Assert-Notification (-not $Endpoint.Receive(0)) 'A closed endpoint accepted a late notification.'
    $Hub.Close();$Hub.CreateAudioNotifier($other,$other.Version).Invoke(123)
    Assert-Notification (-not $other.Receive(0)) 'A closing runtime accepted a late notification.'
    Write-Output 'PASS: native-thread notification wakes only its owner, carries session/version/match time, production handler uses event time, duplicate/stopped/disarmed/closed callbacks ignored. No live audio or game input.'
}finally {
    $Hub.Close();if(-not $Hub.Logger.Close(5000)){throw 'Log writer is still running.'}
    $resolved=[IO.Path]::GetFullPath($directory)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'wowAuto-audio-notify-*'){throw 'Unsafe fixture cleanup'}
    if([IO.Directory]::Exists($resolved)){[IO.Directory]::Delete($resolved,$true)}
}
