$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\wowAuto.Engine.ps1')
function Assert-Jump($Condition,[string]$Label) { if (-not $Condition) { throw $Label } }
$q=New-WowAutoScheduler
Set-WowAutoJumpInterval $q 2
$a=Add-WowAutoTask $q 'titan:1' 100 100 0
$b=Add-WowAutoTask $q 'forerver:2' 100 100 0
function Finish-TestCycle([string]$Key,[long]$Now) {
    $s=$q.Tasks[$Key]; $s.Mode='Ready'; $s.ForceNextCast=$false; $s.CheckReelGreen=$false; $s.AwaitingFishingTransition=$false
    $null=Complete-WowAutoPoll $q $Key $Now 'green'
    Complete-WowAutoReel $q $Key ($Now+100) $true
}
Finish-TestCycle 'titan:1' 0
Assert-Jump (-not $a.CycleJumpPending -and $q.CyclesSinceJump['titan:1'] -eq 1) 'First cycle should not schedule periodic jump.'
Finish-TestCycle 'titan:1' 2000
Assert-Jump ($a.CycleJumpPending -and -not $b.CycleJumpPending) 'Each process must count independently.'
Complete-WowAutoReel $q 'titan:1' 2101 $true
Assert-Jump ($q.CyclesSinceJump['titan:1'] -eq 2) 'Duplicate callback counted a cycle.'
Assert-Jump ($null -eq (Get-WowAutoWork $q 2199)) 'Jump bypassed reel foreground hold.'
$null=Get-WowAutoWork $q 3100
Assert-Jump ((Complete-WowAutoPoll $q 'titan:1' 3100 'gray') -eq 'None' -and $a.CycleJumpPending) 'Unknown data must defer jump.'
Assert-Jump ((Complete-WowAutoPoll $q 'titan:1' 3600 'red') -eq 'Jump') 'Periodic jump must run before next cast even after turning red.'
Complete-WowAutoJump $q 'titan:1' $false
Assert-Jump ($a.CycleJumpPending -and $q.CyclesSinceJump['titan:1'] -eq 2) 'Failed jump lost retry.'
Assert-Jump ((Complete-WowAutoPoll $q 'titan:1' 4100 'green') -eq 'Jump') 'Green jump retry missing.'
Complete-WowAutoJump $q 'titan:1' $true
Assert-Jump (-not $a.CycleJumpPending -and -not $a.CheckReelGreen -and $q.CyclesSinceJump['titan:1'] -eq 0) 'Successful jump must clear both reasons once.'
Assert-Jump ((Complete-WowAutoPoll $q 'titan:1' 4600 'red') -eq 'Ctrl1') 'Casting did not resume after jump.'
Finish-TestCycle 'forerver:2' 5000
Complete-WowAutoReel $q 'forerver:2' 5101 $false
Set-WowAutoJumpInterval $q 2
Assert-Jump ($q.CyclesSinceJump['forerver:2'] -eq 1) 'Saving unchanged frequency reset progress.'
Stop-WowAutoTask $q 'forerver:2'
$b=Add-WowAutoTask $q 'forerver:2' 100 100 5200
Assert-Jump ($q.CyclesSinceJump['forerver:2'] -eq 1 -and -not $b.CycleJumpPending) 'Restart lost process counter.'
Finish-TestCycle 'forerver:2' 6000
Stop-WowAutoTask $q 'forerver:2'
$b=Add-WowAutoTask $q 'forerver:2' 100 100 7200
Assert-Jump ($b.CycleJumpPending) 'Restart bypassed due jump.'
Set-WowAutoJumpInterval $q 0
Assert-Jump (-not $b.CycleJumpPending -and $q.CyclesSinceJump.Count -eq 0) 'Disabling periodic jump must clear its pending work.'
Finish-TestCycle 'forerver:2' 8000
Assert-Jump ((Complete-WowAutoPoll $q 'forerver:2' 9200 'green') -eq 'Jump') 'Existing green recovery jump must remain available.'
Complete-WowAutoJump $q 'forerver:2' $true
Finish-TestCycle 'titan:1' 10000
Assert-Jump ((Complete-WowAutoPoll $q 'titan:1' 11200 'red') -eq 'Ctrl1') 'Disabled periodic jump should allow casting.'
Set-WowAutoJumpInterval $q 1
$q.ItemHoldUntil=15000
Finish-TestCycle 'titan:1' 12000
Assert-Jump ($null -eq (Get-WowAutoWork $q 14000)) 'Jump bypassed item hold.'
Assert-Jump ((Complete-WowAutoPoll $q 'titan:1' 15000 'yellow') -eq 'Stop') 'Bag full must take priority over a jump.'
Write-Output 'PASS: per-process fishing jump frequency, successful cycles only, failed retry, hold/unknown/bag priorities, settings change, stop/restart and disabled recovery compatibility. No native input.'
