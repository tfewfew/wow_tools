$ErrorActionPreference='Stop'
$tool=Split-Path $PSScriptRoot -Parent
. (Join-Path $tool 'wowAuto.Engine.ps1')
. (Join-Path $tool 'wowAuto.Timing.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $tool 'wowAuto.Detector.ps1'),[ref]$tokens,[ref]$errors)
if($errors){throw $errors[0]}
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-DetectorTaskCore'},$true)
Invoke-Expression $fn.Extent.Text
function Write-Detector($Text){$script:status=$Text}
function Get-DetectorObservation {$script:reads++;return [pscustomobject]@{Login=$true;Color=$script:color;Packet=$null}}
function Get-WowAutoWork {return $null}
function Remove-DetectorRole($Reason){$script:removed=$Reason}
$Hub=[pscustomobject]@{Now=100L}
$Endpoint=[pscustomobject]@{Key='test'}
$script:config=[pscustomobject]@{Operations=[pscustomobject](New-OperationTimings);Periods=[pscustomobject]@{DeathMs=1000;FishMs=100;AudioMs=50}}
$script:config.Operations.FishColorRetryMs=5000
$script:mode='fish';$script:scheduler=New-WowAutoScheduler
$script:fish=Add-WowAutoTask $script:scheduler test 300 600 0 -UseAudio $true
$script:fish.AudioSession=12L;$script:fish.AudioReelPending=$true;$script:fish.PostReelJumpAllowed=$true;$script:fish.CycleJumpPending=$true
Add-WowAutoEvent $script:scheduler test Reel 200
$script:scheduler.CompletedCycles.test=20L
$script:audio=$null;$script:nextColor=0L;$script:nextDeath=0L;$script:fishColorRetryAt=0L;$script:reads=0;$script:color='unknown'
Invoke-DetectorTaskCore
if($script:fishColorRetryAt -ne 5100 -or $script:reads -ne 1 -or -not $script:fish.Running){throw 'Unknown color must retain task and honor configured retry.'}
if($script:fish.AudioSession -ne 0 -or $script:fish.AudioReelPending -or $script:fish.PostReelJumpAllowed -or -not $script:fish.CycleJumpPending){throw 'Old bite/jump permission survived, or pending cycle request was lost.'}
if($script:scheduler.Events.Count -ne 0 -or (Get-WowAutoCycleCount $script:scheduler test) -ne 20){throw 'Pending reel survived or cycle count was reset.'}
$Hub.Now=1099;Invoke-DetectorTaskCore
if($script:reads -ne 1){throw 'Read retried before deadline.'}
$Hub.Now=5099;Invoke-DetectorTaskCore
if($script:reads -ne 2 -or $script:fishColorRetryAt -ne 5100){throw 'Terminal polling must not extend the retry deadline.'}
$Hub.Now=5100;Invoke-DetectorTaskCore
if($script:reads -ne 3 -or $script:fishColorRetryAt -ne 10100){throw 'Repeated unknown must schedule another retry.'}
$script:color='red';$Hub.Now=10100;Invoke-DetectorTaskCore
if($script:reads -ne 4 -or $script:fishColorRetryAt -ne 0 -or $script:observation.Color -ne 'red'){throw 'Valid color did not resume detection.'}
$script:fishColorRetryAt=20000L;$script:nextDeath=11000L;$Hub.Now=11000;$script:color='dead';Invoke-DetectorTaskCore
if($script:removed -ne '角色死亡'){throw 'Death was ignored during retry wait.'}
$script:nextDeath=12000L;$Hub.Now=12000;$script:color='yellow';Invoke-DetectorTaskCore
if($script:removed -ne '背包已满'){throw 'Full bag was ignored during retry wait.'}
$timing=New-OperationTimings;Test-OperationTimings $timing
$timing.FishColorRetryMs=999
try {Test-OperationTimings $timing;throw 'Invalid retry accepted'}catch{if($_.Exception.Message -eq 'Invalid retry accepted'){throw}}
'PASS: configurable color retry, deadline boundaries, repeated unknown, recovery and stale audio/jump invalidation; no game input.'
