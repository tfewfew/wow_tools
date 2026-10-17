$ErrorActionPreference='Stop'
$tool=Split-Path $PSScriptRoot -Parent
Add-Type -Path (Join-Path $tool 'wowAuto.Threading.cs') -ReferencedAssemblies System.Core
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $tool 'wowAuto.Operator.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Operator source does not parse.'}
foreach($function in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){. ([scriptblock]::Create($function.Extent.Text))}
function Assert-OperatorTest($Condition,[string]$Message){if(-not $Condition){throw $Message}}
$Hub=[pscustomobject]@{Now=0L;Closing=$false;Focus=$null;ActiveTasks=0}
$Hub | Add-Member ScriptMethod Requeue {param($request,$delay) $request.Due=$this.Now+$delay}
$script:adapter=@{Foreground=$true;Login=$true;Color='red';Lure='missing';Identity=$true;Activations=0;Pressed=@();Clicks=@();Enabled=0;Packet=[pscustomobject]@{ClassId=1;Action='opening';Recovery='none';Busy=$false}}
function Invoke-OperatorAdapter([string]$Action,$Endpoint,$Data=$null) {
    switch($Action) {
        'Identity' {if(-not $script:adapter.Identity){throw 'fixture identity changed'};return $true}
        'Foreground' {return $script:adapter.Foreground}
        'Activate' {$script:adapter.Activations++;return $false}
        'Login' {return $script:adapter.Login}
        'Color' {return $script:adapter.Color}
        'Lure' {return $script:adapter.Lure}
        'Packet' {return [pscustomobject]@{Packet=$script:adapter.Packet}}
        'Press' {$script:adapter.Pressed+=,[string]$Data;return $true}
        'Click' {$script:adapter.Clicks+=,$Data;return $true}
        'Enable' {$script:adapter.Enabled++;return $true}
        default {return $true}
    }
}
$owner=New-Object WowAuto.Threading.Endpoint;$owner.Key='11:1';$owner.Pid=11;$owner.StartTicks=1;$owner.Flavor='titan';$owner.Path='fixture'
function New-OperatorTestRequest([string]$Kind,[string]$Domain,$Body=@{}) {
    $request=New-Object WowAuto.Threading.Operation;$request.Owner=$owner;$request.Version=$owner.Version;$request.Kind=$Kind;$request.Domain=$Domain;$request.Json=$Body | ConvertTo-Json -Depth 8 -Compress
    return $request
}
$script:lastClickKey='';$script:clickUntil=0L;$script:commandReadyAt=0L
$opening=New-OperatorTestRequest Fight.Opening Fight @{ClassId=1;Action='opening';Keys=@('Tab','Z');HoldMs=0;RecoveryReadyAt=0;CommandIntervalMs=500}
Assert-OperatorTest (-not (Invoke-OperatorRequest $opening) -and $script:adapter.Pressed.Count -eq 0) 'Input skipped the 200ms foreground settle.'
$Hub.Now=200L;$result=Invoke-OperatorRequest $opening
Assert-OperatorTest ($result.Executed -and ($script:adapter.Pressed -join ',') -eq 'Tab,Z') 'Opening did not send target then configured opener as one transaction.'
$Hub.Now=1000L;$script:adapter.Packet.Action='combat';$opening.ReadyAt=1
$result=Invoke-OperatorRequest $opening
Assert-OperatorTest (-not $result.Executed -and $script:adapter.Pressed.Count -eq 2) 'A stale opening action executed after the main color changed.'
$script:adapter.Packet.Recovery='recover';$combat=New-OperatorTestRequest Fight.Combat Fight @{ClassId=1;Action='combat';Keys=@('F6');RecoveryReadyAt=0;HoldMs=0};$combat.ReadyAt=1
Assert-OperatorTest (-not (Invoke-OperatorRequest $combat).Executed) 'Combat ignored a fresh recovery request.'
$script:adapter.Packet.Recovery='none';$script:adapter.Packet.ClassId=2
Assert-OperatorTest (-not (Invoke-OperatorRequest $combat).Executed) 'A different class received a queued action.'
$script:adapter.Packet.ClassId=1;$script:adapter.Login=$false
$click=New-OperatorTestRequest Rotation.Click Rotation @{X=0.84;Y=0.119;Width=800;Height=500;FirstDelay=110;SecondDelay=220};$click.ReadyAt=1
Assert-OperatorTest ((Invoke-OperatorRequest $click).Executed -and $script:adapter.Clicks[0].FirstDelay -eq 110 -and $script:adapter.Clicks[0].SecondDelay -eq 220) 'Click mapping or precomputed intervals changed.'
$other=New-Object WowAuto.Threading.Endpoint;$other.Key='12:1';$other.Pid=12
$enable=New-OperatorTestRequest Rotation.Enable Rotation @{Mode='fish'};$enable.Owner=$other;$enable.ReadyAt=1;$script:adapter.Login=$true
$Hub.Now=1999L;Assert-OperatorTest (-not (Invoke-OperatorRequest $enable) -and $script:adapter.Enabled -eq 0) 'Cross-process input skipped the one-second click guard.'
$Hub.Now=2000L;Assert-OperatorTest ((Invoke-OperatorRequest $enable).Executed -and $script:adapter.Enabled -eq 1) 'Click guard did not release at the exact boundary.'
$script:lastClickKey='';$script:adapter.Foreground=$false;$Hub.Now=0L;$script:adapter.Activations=0
$logout=New-OperatorTestRequest Rotation.Logout Rotation
foreach($now in 0,500,1000,1500,2000,2500,3000,3500,4000,4500){$Hub.Now=[long]$now;$null=Invoke-OperatorRequest $logout}
Assert-OperatorTest ($script:adapter.Activations -eq 10) 'Rotation foreground acquisition did not retry every 500ms.'
$Hub.Now=5000L;$failed=$false;try{$null=Invoke-OperatorRequest $logout}catch{$failed=$true}
Assert-OperatorTest $failed 'Rotation foreground failure was not bounded at five seconds.'
$Hub.Now=0L;$ordinary=New-OperatorTestRequest Fish.Cast Fish @{Keys=@('0')};$null=Invoke-OperatorRequest $ordinary
$Hub.Now=800L;$failed=$false;try{$null=Invoke-OperatorRequest $ordinary}catch{$failed=$true}
Assert-OperatorTest $failed 'Ordinary input no longer respects its 800ms focus timeout.'
$script:adapter.Foreground=$true;$script:adapter.Login=$false;$ordinary.ReadyAt=1;$failed=$false
try{$null=Invoke-OperatorRequest $ordinary}catch{$failed=$true};Assert-OperatorTest $failed 'Input was allowed without a fresh login marker.'
$script:adapter.Identity=$false;$failed=$false;try{$null=Invoke-OperatorRequest $ordinary}catch{$failed=$true}
Assert-OperatorTest $failed 'Queued input ignored a changed process identity.'
Write-Output 'PASS: production operator routing with substituted native primitives, target/opener transaction, fresh color/recovery/class/identity/marker checks, 200ms settle, exact one-second click guard, 500ms rotation retries/five-second limit and 800ms ordinary limit. No native input.'
