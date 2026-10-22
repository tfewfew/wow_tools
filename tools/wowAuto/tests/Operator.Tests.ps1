$ErrorActionPreference='Stop'
$tool=Split-Path $PSScriptRoot -Parent
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $tool 'autoFight.Engine.ps1')
Add-Type -Path (Join-Path $tool 'wowAuto.Threading.cs') -ReferencedAssemblies System.Core
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $tool 'wowAuto.Operator.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Operator source does not parse.'}
foreach($function in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){. ([scriptblock]::Create($function.Extent.Text))}
function Assert-OperatorTest($Condition,[string]$Message){if(-not $Condition){throw $Message}}
$Hub=[pscustomobject]@{Now=0L;Closing=$false;Focus=$null;ActiveTasks=0}
$Hub | Add-Member ScriptMethod Requeue {param($request,$delay) $request.Due=$this.Now+$delay}
$script:adapter=@{Foreground=$true;Login=$true;Color='red';Lure='missing';Identity=$true;Activations=0;Pressed=@();Clicks=@();Enabled=0;Packet=[pscustomobject]@{ClassId=1;Action='opening';Recovery='none';Busy=$false}}
function Invoke-OperatorAdapter([string]$Action,$Endpoint,$Data=$null,[int]$DurationMs=30) {
    $script:lastAdapterDuration=$DurationMs
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
        'ProcessState' {return $script:adapter.ProcessState}
        'Exit' {$script:adapter.Closes++;return $script:adapter.CloseAccepted}
        'Kill' {$script:adapter.Kills++;return $true}
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
$script:adapter.Identity=$true;$script:adapter.Login=$true;$script:adapter.Foreground=$true;$script:adapter.Packet.Action='combat';$Hub.Now=0L;$script:commandReadyAt=0L
$custom=New-OperatorTestRequest Fight.Combat Fight @{ClassId=1;Action='combat';Keys=@('Z');RecoveryReadyAt=0;HoldMs=0}
$custom.Timing.ForegroundSettleMs=73;$custom.Timing.KeyPressMs=41;$custom.Timing.CommandIntervalMs=1234
Assert-OperatorTest (-not (Invoke-OperatorRequest $custom) -and $custom.ReadyAt -eq 73) 'Custom settle duration was ignored.'
$Hub.Now=72L;Assert-OperatorTest (-not (Invoke-OperatorRequest $custom)) 'Custom settle executed early.'
$Hub.Now=73L;Assert-OperatorTest ((Invoke-OperatorRequest $custom).Executed -and $script:lastAdapterDuration -eq 41 -and $script:commandReadyAt -eq 1307) 'Custom native key duration or shared combat interval was ignored.'
$script:adapter.Foreground=$false;$Hub.Now=0L;$script:adapter.Activations=0
$customFocus=New-OperatorTestRequest Rotation.Logout Rotation;$customFocus.Timing.RotationFocusRetryMs=80;$customFocus.Timing.RotationFocusTimeoutMs=240
foreach($now in 0,79,80,159,160){$Hub.Now=[long]$now;$null=Invoke-OperatorRequest $customFocus}
Assert-OperatorTest ($script:adapter.Activations -eq 3) 'Custom foreground retry interval was ignored.'
$Hub.Now=240L;$failed=$false;try{$null=Invoke-OperatorRequest $customFocus}catch{$failed=$true};Assert-OperatorTest $failed 'Custom foreground timeout was ignored.'
$script:adapter.Foreground=$true;$script:adapter.Login=$false;$Hub.Now=1000L
$customClick=New-OperatorTestRequest Rotation.Click Rotation @{X=0.84;Y=0.119;Width=800;Height=500;FirstDelay=11;SecondDelay=19}
$customClick.ReadyAt=1;$customClick.Timing.ClickMinMs=10;$customClick.Timing.ClickMaxMs=20;$customClick.Timing.ClickGuardMs=65
Assert-OperatorTest ((Invoke-OperatorRequest $customClick).Executed -and $script:adapter.Clicks[-1].MinimumMs -eq 10 -and $script:adapter.Clicks[-1].MaximumMs -eq 20) 'Custom click bounds did not reach the native adapter.'
$customEnable=New-OperatorTestRequest Rotation.Enable Rotation @{Mode='fish'};$customEnable.Owner=$other;$customEnable.ReadyAt=1;$customEnable.Timing.ChatKeyPressMs=47;$script:adapter.Login=$true
$Hub.Now=1064L;Assert-OperatorTest (-not (Invoke-OperatorRequest $customEnable)) 'Custom cross-process click guard executed early.'
$Hub.Now=1065L;Assert-OperatorTest ((Invoke-OperatorRequest $customEnable).Executed -and $script:lastAdapterDuration -eq 47) 'Custom click guard or chat key duration was ignored.'
$script:lastClickKey='';$script:adapter.Color='unknown';$script:adapter.Pressed=@();$Hub.Now=2000L
$rod=New-OperatorTestRequest Rotation.EquipRod Rotation @{Mode='fish';Key='Ctrl+F3'};$rod.ReadyAt=1;$rod.Timing.KeyPressMs=43
Assert-OperatorTest ((Invoke-OperatorRequest $rod).Executed -and ($script:adapter.Pressed -join ',') -ceq 'Ctrl+F3' -and $script:lastAdapterDuration -eq 43) 'Rod equip required an active monitor color or ignored its configured chord/duration.'
foreach($case in @('marker','identity','stale','mode','empty','invalid')) {
    $script:adapter.Login=$case -ne 'marker';$script:adapter.Identity=$case -ne 'identity'
    $testRod=New-OperatorTestRequest Rotation.EquipRod Rotation @{Mode=$(if($case -eq 'mode'){'fight'}else{'fish'});Key=$(if($case -eq 'empty'){''}elseif($case -eq 'invalid'){'Ctrl+Ctrl+F3'}else{'Ctrl+F3'})};$testRod.ReadyAt=1
    if($case -eq 'stale'){$testRod.Version--}
    try{$null=Invoke-OperatorRequest $testRod}catch{}
    Assert-OperatorTest ($script:adapter.Pressed.Count -eq 1) ('Unsafe rod input was sent: '+$case)
}
$directRod=New-OperatorTestRequest Fish.EquipRod Fish @{Mode='fish';Key='Ctrl+F3'};$directRod.ReadyAt=1;$directRod.Timing.KeyPressMs=51
Assert-OperatorTest ((Invoke-OperatorRequest $directRod).Executed -and $script:adapter.Pressed.Count -eq 2 -and $script:lastAdapterDuration -eq 51) 'Direct-start rod equip required active fish colors or bypassed configured key timing.'
Write-Output 'PASS: production operator routing with substituted native primitives; timing and foreground guards, fresh protocol/identity checks, login/direct-start rod equip with stale/missing/invalid requests rejected. No native input.'
$Hub | Add-Member ScriptMethod Log {param($endpoint,$version,$kind,$text)}
$script:adapter.ProcessState='same';$script:adapter.CloseAccepted=$true;$script:adapter.Closes=0;$script:adapter.Kills=0
$script:adapter.Foreground=$false;$script:adapter.Login=$false;$Hub.Now=1000L
$shutdown=New-OperatorTestRequest Process.Shutdown Process
Assert-OperatorTest ($null -eq (Invoke-OperatorRequest $shutdown) -and $shutdown.CloseRequested -and $shutdown.CloseDeadline -eq 31000 -and $script:adapter.Closes -eq 1 -and $script:adapter.Kills -eq 0) 'Shutdown required a foreground/color marker or did not yield after normal close.'
$Hub.Now=30999L;$null=Invoke-OperatorRequest $shutdown
Assert-OperatorTest ($script:adapter.Closes -eq 1 -and $script:adapter.Kills -eq 0) 'Shutdown repeated normal close or killed before 30 seconds.'
$Hub.Now=31000L;$null=Invoke-OperatorRequest $shutdown
Assert-OperatorTest ($shutdown.KillRequested -and $script:adapter.Kills -eq 1) 'Shutdown did not force-close at its actual 30-second dispatch deadline.'
$Hub.Now=31001L;$null=Invoke-OperatorRequest $shutdown
Assert-OperatorTest ($script:adapter.Kills -eq 1) 'Shutdown repeated a force-close request.'
$script:adapter.ProcessState='exited'
Assert-OperatorTest ((Invoke-OperatorRequest $shutdown).Exited) 'Shutdown did not confirm process exit.'
$earlyExit=New-OperatorTestRequest Process.Shutdown Process
Assert-OperatorTest ((Invoke-OperatorRequest $earlyExit).Exited -and -not $earlyExit.CloseRequested) 'Already exited process received a close request.'
$script:adapter.ProcessState='same';$script:adapter.CloseAccepted=$false;$Hub.Now=0L
$rejected=New-OperatorTestRequest Process.Shutdown Process;$null=Invoke-OperatorRequest $rejected
Assert-OperatorTest ($rejected.CloseDeadline -eq 30000) 'Rejected normal close lost its timeout protection.'
$script:adapter.ProcessState='changed';$Hub.Now=30000L;$beforeKills=$script:adapter.Kills
$failed=$false;try{$null=Invoke-OperatorRequest $rejected}catch{$failed=$true}
Assert-OperatorTest ($failed -and $script:adapter.Kills -eq $beforeKills) 'PID reuse received a force-close request.'
$script:adapter.ProcessState='same';$Hub.Now=0L
$normal=New-OperatorTestRequest Process.Shutdown Process;$null=Invoke-OperatorRequest $normal
$script:adapter.ProcessState='exited';$Hub.Now=500L
Assert-OperatorTest ((Invoke-OperatorRequest $normal).Exited -and $script:adapter.Kills -eq $beforeKills) 'Normal exit unnecessarily forced the game to quit.'
$script:adapter.ProcessState='same';$Hub.Now=0L
$stuck=New-OperatorTestRequest Process.Shutdown Process;$null=Invoke-OperatorRequest $stuck
$Hub.Now=30000L;$null=Invoke-OperatorRequest $stuck;$Hub.Now=35000L
$failed=$false;try{$null=Invoke-OperatorRequest $stuck}catch{$failed=$true}
Assert-OperatorTest $failed 'Unconfirmed force-close left shutdown waiting forever.'
$cancelled=New-OperatorTestRequest Process.Shutdown Process;$owner.Close();$beforeCloses=$script:adapter.Closes
Assert-OperatorTest (-not (Invoke-OperatorRequest $cancelled).Executed -and $script:adapter.Closes -eq $beforeCloses) 'Cancelled shutdown operated on a game process.'
Write-Output 'PASS: queued shutdown normal close, 30-second force-close boundary, rejected-close protection, nonblocking waits, exit confirmation, bounded kill confirmation, PID reuse and cancellation. Process primitives substituted.'
