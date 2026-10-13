$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\wowAuto.Engine.ps1')
function Assert-Equal($Actual,$Expected,$Label) {
    if ($Actual -ne $Expected) { throw "$Label : expected $Expected, got $Actual" }
}
function Get-Random {
    param([int]$Minimum,[int]$Maximum)
    if ($Minimum -eq 8000 -and $Maximum -eq 13001) { return 8123 }
    return (Microsoft.PowerShell.Utility\Get-Random -Minimum $Minimum -Maximum $Maximum)
}
foreach ($range in @(@(0,13000),@(13000,8000),@(1,3600001))) {
    $rejected=$false
    try { $null=New-WowAutoState $range[0] $range[1] } catch { $rejected=$true }
    Assert-Equal $rejected $true 'Invalid range rejected'
}
$q=New-WowAutoScheduler
$a=Add-WowAutoTask $q 'A' 8000 13000 0
$b=Add-WowAutoTask $q 'B' 1000 1000 0
$work=Get-WowAutoWork $q 0
Assert-Equal $work.Key 'A' 'First task'
Assert-Equal (Complete-WowAutoPoll $q 'A' 0 'red') 'Ctrl1' 'Red casts'
$a.NextDue=400
Assert-Equal ($null -eq (Get-WowAutoWork $q 399)) $true 'Wait between repeated casts'
Assert-Equal (Get-WowAutoWork $q 400).Key 'A' 'Red keeps active window'
$null=Complete-WowAutoPoll $q 'A' 400 'green'
Assert-Equal $a.Deadline 8523 'Millisecond random deadline'
Assert-Equal (Get-WowAutoWork $q 400).Key 'B' 'Green yields to next window'
$null=Complete-WowAutoPoll $q 'B' 400 'green'
Assert-Equal ($null -eq (Get-WowAutoWork $q 1399)) $true 'All waiting leaves worker idle'
Assert-Equal (Get-WowAutoWork $q 1400).Key 'B' 'Earliest deadline wins'
Complete-WowAutoReel $q 'B' 1450 $true
Assert-Equal (Get-WowAutoCycleCount $q 'B') 1 'Successful reel increments once'
Complete-WowAutoReel $q 'B' 1451 $true
Assert-Equal (Get-WowAutoCycleCount $q 'B') 1 'Duplicate completion cannot count twice'
Assert-Equal $b.Deadline 2450 'Cooldown starts at key release'
Assert-Equal ($null -eq (Get-WowAutoWork $q 2449)) $true 'Cooldown blocks only own task'
Assert-Equal (Get-WowAutoWork $q 2450).Key 'B' 'Cooldown requeues task'
$null=Complete-WowAutoPoll $q 'B' 2450 'red'
$b.NextDue=9000
$work=Get-WowAutoWork $q 8523
Assert-Equal $work.Kind 'Reel' 'Due timer preempts casting wait'
Assert-Equal $work.Key 'A' 'Correct timed target'
Complete-WowAutoReel $q 'A' 8573 $true
Assert-Equal @($q.Events | Where-Object { $_.Key -eq 'A' -and $_.Kind -eq 'Reel' }).Count 0 'Reel fires once'
Stop-WowAutoTask $q 'A'
Assert-Equal @($q.Events | Where-Object { $_.Key -eq 'A' }).Count 0 'Stop removes all events'
Stop-WowAutoTask $q 'B'
Assert-Equal $q.Tasks.Count 0 'All stopped'
Assert-Equal ($null -eq (Get-WowAutoWork $q 99999)) $true 'No stale work after stop'
$q=New-WowAutoScheduler
$old=Add-WowAutoTask $q 'A' 20 20 100
$null=Complete-WowAutoPoll $q 'A' 100 'green'
Stop-WowAutoTask $q 'A'
$fresh=Add-WowAutoTask $q 'A' 8000 13000 110
Assert-Equal (Get-WowAutoWork $q 200).Kind 'Poll' 'Restart cannot inherit old timer'
Assert-Equal (Complete-WowAutoPoll $q 'A' 200 'yellow') 'Stop' 'Yellow always stops the current fishing task'
Assert-Equal $fresh.Running $false 'Yellow clears running state'
$x=Add-WowAutoTask $q 'X' 100 100 0
$y=Add-WowAutoTask $q 'Y' 100 100 0
$null=Complete-WowAutoPoll $q 'X' 0 'green'
$null=Complete-WowAutoPoll $q 'Y' 0 'green'
Assert-Equal (Get-WowAutoWork $q 100).Key 'X' 'Tied deadlines preserve event order'
Complete-WowAutoReel $q 'X' 100 $true
Assert-Equal ($null -eq (Get-WowAutoWork $q 100)) $true 'Hold starts after successful reel'
Assert-Equal ($null -eq (Get-WowAutoWork $q 199)) $true 'Overdue timer cannot preempt 100ms hold'
Assert-Equal (Get-WowAutoWork $q 200).Key 'Y' 'Overdue timer runs at hold expiry'
Complete-WowAutoReel $q 'Y' 200 $false
Assert-Equal (Get-WowAutoCycleCount $q 'Y') 0 'Failed key send is not a cycle'
Assert-Equal $q.ReelHoldUntil 200 'Failed key send does not extend hold'
Complete-WowAutoReel $q 'Y' 250 $true
Assert-Equal (Get-WowAutoCycleCount $q 'Y') 1 'Successful retry counts once'
Stop-WowAutoTask $q 'Y'
$null=Add-WowAutoTask $q 'Y' 100 100 200
Assert-Equal (Get-WowAutoCycleCount $q 'Y') 1 'Stop and restart retain process count'
$q.CompletedCycles['Y']=501
Assert-Equal (Complete-WowAutoPoll $q 'Y' 250 'yellow') 'Stop' 'Yellow never exits based on reel count'
Assert-Equal (Get-WowAutoCycleCount $q 'new-process-identity') 0 'New process starts at zero'
$previous=-1
$itemQueue=New-WowAutoScheduler
$itemA=Add-WowAutoTask $itemQueue 'itemA' 100 100 0
Assert-Equal $itemA.ItemDue 0 'Items disabled initially'
Set-WowAutoItemEnabled $itemQueue 'itemA' $true 100
$itemB=Add-WowAutoTask $itemQueue 'itemB' 100 100 200 -UseItem $true
Assert-Equal $itemA.ItemDue 100 'Enable immediately queues enchant detection'
Assert-Equal $itemB.ItemDue 200 'Start immediately queues initial item'
Assert-Equal (Get-WowAutoWork $itemQueue 200).Key 'itemA' 'Earlier enchant check precedes fishing'
$null=Complete-WowAutoItemCheck $itemQueue 'itemA' 200 'present' 'red'
Assert-Equal (Get-WowAutoWork $itemQueue 200).Key 'itemB' 'Second row checks after present enchant'
Complete-WowAutoItem $itemQueue 'itemB' 200 $true
Assert-Equal $itemB.ItemConfirmUntil 5200 'Sent item starts a five-second confirmation deadline'
Assert-Equal $itemB.InitialItemPending $true 'Unconfirmed item keeps casting gated'
Assert-Equal ($null -eq (Get-WowAutoWork $itemQueue 3199)) $true 'Initial item holds all tasks for three seconds'
$null=Complete-WowAutoItemCheck $itemQueue 'itemA' 600000 'present' 'green'
$null=Complete-WowAutoPoll $itemQueue 'itemA' 600000 'green'
Assert-Equal (Get-WowAutoWork $itemQueue 600100).Kind 'Reel' 'Due reel outranks item'
Complete-WowAutoReel $itemQueue 'itemA' 600100 $true
Assert-Equal ($null -eq (Get-WowAutoWork $itemQueue 600199)) $true 'Item respects foreground hold'
$itemWork=Get-WowAutoWork $itemQueue 600200
Assert-Equal $itemWork.Kind 'Item' 'Unconfirmed item remains scheduled for a final check'
Assert-Equal $itemWork.Key 'itemB' 'Overdue confirmation belongs to the original row'
Assert-Equal (Complete-WowAutoItemCheck $itemQueue 'itemB' 600200 'missing' 'red') 'Continue' 'Unconfirmed item times out and continues fishing'
Assert-Equal $itemB.ItemDetectionDisabled $true 'Timed-out item disables detection for this task'
Complete-WowAutoItem $itemQueue 'itemB' 600200 $false
Assert-Equal $itemQueue.ItemHoldUntil 3200 'Duplicate item completion does not extend hold'
Complete-WowAutoItem $itemQueue 'itemB' 600201 $true
Assert-Equal $itemB.ItemDetectionDisabled $true 'Duplicate completion cannot restart disabled detection'
Assert-Equal (Get-WowAutoWork $itemQueue 603201).Key 'itemA' 'Another row can still check its own item'
Assert-Equal (Complete-WowAutoItemCheck $itemQueue 'itemA' 603201 'missing' 'red') 'UseItem' 'Missing enchant requests a new item'
Complete-WowAutoItem $itemQueue 'itemA' 603201 $true
Assert-Equal ($null -eq (Get-WowAutoWork $itemQueue 606200)) $true 'Other row item holds all work for full three seconds'
Set-WowAutoItemEnabled $itemQueue 'itemA' $false 603202
Set-WowAutoItemEnabled $itemQueue 'itemB' $false 603202
$null=Complete-WowAutoPoll $itemQueue 'itemB' 603202 'green'
Assert-Equal ($null -eq (Get-WowAutoWork $itemQueue 606200)) $true 'Due reel cannot interrupt item hold even after unchecking'
Assert-Equal (Get-WowAutoWork $itemQueue 606201).Kind 'Reel' 'Overdue reel resumes at three-second boundary'
Assert-Equal (Get-WowAutoCycleCount $itemQueue 'itemA') 1 'Item does not count as fishing cycle'
Set-WowAutoItemEnabled $itemQueue 'itemA' $false 700000
Assert-Equal $itemA.ItemDue 0 'Disable clears pending items'
Set-WowAutoItemEnabled $itemQueue 'itemA' $true 700100
Assert-Equal $itemA.ItemDue 700100 'Reenable queues fresh enchant check'
Stop-WowAutoTask $itemQueue 'itemA'
Stop-WowAutoTask $itemQueue 'itemB'
Assert-Equal ($null -eq (Get-WowAutoWork $itemQueue 2000000)) $true 'Stopped tasks cannot use items'
$holdQueue=New-WowAutoScheduler
$startupQueue=New-WowAutoScheduler
$null=Add-WowAutoTask $startupQueue 'first' 100 100 0 -UseItem $true
Complete-WowAutoItem $startupQueue 'first' 0 $false
Assert-Equal ($null -eq (Get-WowAutoWork $startupQueue 499)) $true 'Failed initial item cannot fall through to casting'
$null=Add-WowAutoTask $startupQueue 'second' 100 100 500 -UseItem $true
Complete-WowAutoItem $startupQueue 'first' 500 $true
Assert-Equal ($null -eq (Get-WowAutoWork $startupQueue 3499)) $true 'Second startup cannot interrupt initial item hold'
Assert-Equal (Get-WowAutoWork $startupQueue 3500).Key 'second' 'Second startup item follows first full hold'
foreach ($duration in @(0,275,1500)) {
    Set-WowAutoHoldDuration $holdQueue $duration
    $null=Add-WowAutoTask $holdQueue 'hold-test' 1 1 0
    $null=Complete-WowAutoPoll $holdQueue 'hold-test' 0 'green'
    Complete-WowAutoReel $holdQueue 'hold-test' 1 $true
    Assert-Equal $holdQueue.ReelHoldUntil (1+$duration) 'Configured hold duration'
    Assert-Equal $holdQueue.Tasks['hold-test'].Deadline (1+[Math]::Max(1000,$duration)) 'Cooldown includes full hold'
    if ($duration -gt 0) {
        Set-WowAutoHoldDuration $holdQueue 0
        Assert-Equal ($null -eq (Get-WowAutoWork $holdQueue $duration)) $true 'Changing input cannot shorten current hold'
    }
}
$invalidHoldRejected=$false
foreach ($color in @('red','green')) {
    $castQueue=New-WowAutoScheduler
    $castState=Add-WowAutoTask $castQueue 'cast' 100 100 0
    Assert-Equal (Complete-WowAutoPoll $castQueue 'cast' 0 'green') 'None' 'Initial green does not force cast'
    Complete-WowAutoReel $castQueue 'cast' 100 $false
    Assert-Equal $castState.ForceNextCast $false 'Failed reel does not force cast'
    Complete-WowAutoReel $castQueue 'cast' 100 $true
    Assert-Equal ($null -eq (Get-WowAutoWork $castQueue 1099)) $true 'Forced cast respects cooldown'
    $null=Get-WowAutoWork $castQueue 1100
    Assert-Equal (Complete-WowAutoPoll $castQueue 'cast' 1100 'unknown') 'None' 'Unknown still skips input'
    if ($color -eq 'green') {
        Assert-Equal (Complete-WowAutoPoll $castQueue 'cast' 1200 'green') 'Jump' 'Post-reel green jumps first'
        Complete-WowAutoJump $castQueue 'cast' $false
        Assert-Equal $castState.CheckReelGreen $true 'Failed jump remains pending'
        Assert-Equal (Complete-WowAutoPoll $castQueue 'cast' 1500 'green') 'Jump' 'Retry failed jump'
        Complete-WowAutoJump $castQueue 'cast' $true
    }
    Assert-Equal (Complete-WowAutoPoll $castQueue 'cast' 1600 $color) 'Ctrl1' 'First post-reel cast ignores green'
    Complete-WowAutoCast $castQueue 'cast' $false
    Assert-Equal $castState.ForceNextCast $true 'Failed cast retains pending forced cast'
    Assert-Equal (Complete-WowAutoPoll $castQueue 'cast' 2200 $color) 'Ctrl1' 'Failed cast retries'
    Complete-WowAutoCast $castQueue 'cast' $true
    if ($color -eq 'green') {
        foreach ($time in @(2500,2600,2700)) {
            Assert-Equal (Complete-WowAutoPoll $castQueue 'cast' $time 'green') 'None' 'Stale green emits no extra cast'
            Assert-Equal $castState.Mode 'Casting' 'Stale green must not start countdown'
            Assert-Equal @($castQueue.Events | Where-Object { $_.Kind -eq 'Reel' }).Count 0 'No reel event until red observed'
        }
        Assert-Equal (Complete-WowAutoPoll $castQueue 'cast' 2750 'red') 'Ctrl1' 'Red resumes casting'
        Complete-WowAutoCast $castQueue 'cast' $true
    }
    Assert-Equal (Complete-WowAutoPoll $castQueue 'cast' 2800 'green') 'None' 'Successful cast restores green wait'
    Assert-Equal $castState.Mode 'Wait' 'Only one successful forced cast'
    Assert-Equal $castState.Deadline 2900 'Countdown starts at confirmed green'
    Complete-WowAutoReel $castQueue 'cast' 2900 $true
    Assert-Equal $castState.SawIdle $false 'Previous cycle red cannot confirm new cycle'
    Assert-Equal (Complete-WowAutoPoll $castQueue 'cast' 3900 'yellow') 'Stop' 'Yellow takes priority over forced cast'
    $freshCast=Add-WowAutoTask $castQueue 'cast' 100 100 4000
    Assert-Equal $freshCast.ForceNextCast $false 'Restart clears forced cast'
}
try { Set-WowAutoHoldDuration $holdQueue -1 } catch { $invalidHoldRejected=$true }
Assert-Equal $invalidHoldRejected $true 'Invalid hold rejected'
for ($i=0;$i -lt 1000;$i++) {
    $next=Get-WowAutoInterval $previous
    if ($next -lt 300 -or $next -gt 600 -or $next -eq $previous) { throw 'Invalid polling interval.' }
    $previous=$next
}
Write-Output 'PASS: repeated casting, green yield, shared deadlines, timer preemption/order, cooldown, cancellation/restart, yellow, range validation, random polling. No native actions.'
