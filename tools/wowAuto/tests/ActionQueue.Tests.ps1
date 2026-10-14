$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\wowAuto.ActionQueue.ps1')
function Assert-Queue($Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
function Reset-TestQueue {
    Initialize-GameActionQueue (Join-Path $PSScriptRoot '..\action-priorities.json')
    $script:scheduler=[pscustomobject]@{ReelHoldUntil=0L;ItemHoldUntil=0L;Tasks=@{};Events=@()}
    $script:autoFight=$null;$script:rotation=$null;$script:editingSettings=$false;$script:seen=New-Object Collections.ArrayList
    $script:schedulerClock=[pscustomobject]@{ElapsedMilliseconds=0L}
    $script:testFocus='';$script:activations=0;$script:stopped=0;$script:activateAllowed=$true;$script:focusOnActivate=$true
}
function Add-TestAction([string]$Id,[string]$Kind,[long]$Due,$Owner=$null) {
    Add-GameAction -Id $Id -Kind $Kind -Domain Test -Owner $Owner -Due $Due -Execute {
        param($event,$now) Assert-GameActionContext;[void]$script:seen.Add($event.Id)
    }
}
function Test-RowProcessIdentity($Row) {return $Row.Process.SameIdentity}
function Test-WorkerForeground($Row) {return $script:testFocus -eq $Row.Key}
function Activate-WorkerRow($Row) {Assert-GameActionContext;$script:activations++;if (-not $script:activateAllowed) {return $false};if ($script:focusOnActivate) {$script:testFocus=$Row.Key};return $true}
function Stop-Row($Row,[string]$Reason,[switch]$CancelExit) {$script:stopped++}
function New-TestRow([string]$Key) {
    $process=[pscustomobject]@{HasExited=$false;SameIdentity=$true}
    $process | Add-Member ScriptMethod Refresh {}
    return [pscustomobject]@{Key=$Key;Process=$process}
}
Reset-TestQueue
Add-TestAction late Fight.Combat 500
Add-TestAction first Fish.Cast 10
Add-TestAction second Fish.Cast 10
Add-TestAction overdue Fish.Cast 5
Add-TestAction emergency Fight.Emergency 20
Invoke-GameActionQueue 20
Assert-Queue (($script:seen -join ',') -eq 'emergency,overdue,first,second') 'Priority/deadline/FIFO or future event exclusion changed.'
Invoke-GameActionQueue 500
Assert-Queue ($script:seen[-1] -eq 'late') 'Future event did not become runnable.'

Reset-TestQueue
$owner=[pscustomobject]@{Session=1}
Add-TestAction duplicate Fish.Cast 10 $owner
$sequence=$script:gameActions.Sequence
Add-TestAction duplicate Fish.Cast 20 $owner
Assert-Queue ($script:gameActions.Events.Count -eq 1 -and $script:gameActions.Sequence -eq $sequence) 'Duplicate intent reset order or multiplied work.'
Add-TestAction duplicate Fight.Emergency 20 $owner
Assert-Queue ($script:gameActions.Events.Count -eq 1 -and $script:gameActions.Events[0].Priority -eq 10) 'Changed action did not replace old intent.'
Remove-GameActions -IncludeProcess
Invoke-GameActionQueue 100
Assert-Queue ($script:seen.Count -eq 0) 'Cancelled work executed.'

Reset-TestQueue
$script:scheduler.ItemHoldUntil=3000
Add-TestAction emergency Fight.Emergency 0
Add-GameAction -Id release -Kind Safety.Release -Domain Safety -Due 0 -Execute {param($event,$now) [void]$script:seen.Add('release')}
Invoke-GameActionQueue 100
Invoke-GameActionQueue 200
Assert-Queue (($script:seen -join ',') -eq 'release') 'Ordinary input bypassed hold or release was blocked.'
Invoke-GameActionQueue 3000
Assert-Queue ($script:seen[-1] -eq 'emergency') 'Held work was lost.'

Reset-TestQueue
$row=New-TestRow a
Add-GameAction -Id activate -Kind Fish.Cast -Domain Test -Key a -Row $row -Due 0 -Foreground $true -Execute {param($event,$now) [void]$script:seen.Add('cast')}
Invoke-GameActionQueue 0
Invoke-GameActionQueue 199
Assert-Queue ($script:activations -eq 1 -and -not $script:seen.Count) 'Activation was repeated or settle delay skipped.'
$script:gameActions.Priorities['Scan.Restore']=10
Add-GameAction -Id urgent -Kind Scan.Restore -Domain Test -Due 0 -Execute {param($event,$now) $script:testFocus='other';[void]$script:seen.Add('urgent')}
Invoke-GameActionQueue 199
Assert-Queue ($script:activations -eq 2 -and $script:stopped -eq 0) 'Preempted activation was not resumed in the same batch.'
Invoke-GameActionQueue 398
Assert-Queue ($script:seen.Count -eq 1) 'Resumed focus skipped settle delay.'
Invoke-GameActionQueue 399
Assert-Queue (($script:seen -join ',') -eq 'urgent,cast') 'Resumed action did not execute once.'

# A no-activation restore and a background read do not preempt or retain a pending input focus.
Reset-TestQueue
$row=New-TestRow waiting
$script:focusOnActivate=$false
Add-GameAction -Id input -Kind Fight.Combat -Domain Test -Key waiting -Row $row -Due 0 -Foreground $true -Execute {param($event,$now) [void]$script:seen.Add('input')}
Add-TestAction capture-restore Capture.Restore 0
Add-TestAction capture-read Rotation.Login 0
Invoke-GameActionQueue 0
Assert-Queue (($script:seen -join ',') -eq 'capture-restore,capture-read' -and $script:activations -eq 1 -and $script:gameActions.Focus.Id -eq 'input') 'Background capture/restore changed focus ownership.'

# Pending first-frame/restoration work waits without a focus failure or a same-tick busy loop.
Reset-TestQueue
$originalCapturePending=Get-Command Test-WindowCapturePending -ErrorAction SilentlyContinue
function Test-WindowCapturePending($ErrorRecord) {return $ErrorRecord.Exception.Message.Contains('[CAPTURE_PENDING]')}
$script:captureAttempts=0
Add-GameAction -Id awaiting-frame -Kind Rotation.Login -Domain Test -Due 0 -Execute {
    param($event,$now)
    $script:captureAttempts++
    if ($script:captureAttempts -eq 1) {throw '[CAPTURE_PENDING] synthetic first frame'}
    [void]$script:seen.Add('frame-ready')
}
Add-TestAction independent Process.Observe 0
Invoke-GameActionQueue 0
Assert-Queue ($script:captureAttempts -eq 1 -and $script:gameActions.Events.Count -eq 1 -and $script:stopped -eq 0 -and ($script:seen -join ',') -eq 'independent') 'Pending capture blocked other work or stopped the row.'
Invoke-GameActionQueue 99
Assert-Queue ($script:captureAttempts -eq 1) 'Capture wait retried early.'
Invoke-GameActionQueue 100
Assert-Queue ($script:captureAttempts -eq 2 -and $script:gameActions.Events.Count -eq 0 -and $script:seen[-1] -eq 'frame-ready') 'Capture wait did not resume exactly once.'
if ($originalCapturePending) {Set-Item Function:\Test-WindowCapturePending $originalCapturePending.ScriptBlock}
else {Remove-Item Function:\Test-WindowCapturePending}

Reset-TestQueue
$row=New-TestRow reused;$row.Process.SameIdentity=$false
Add-GameAction -Id stale -Kind Fish.Cast -Domain Test -Key reused -Row $row -Due 0 -Foreground $true -Execute {param($event,$now) throw 'Identity guard failed.'}
Invoke-GameActionQueue 0
Assert-Queue ($script:stopped -eq 1 -and $script:activations -eq 0) 'Changed process reached activation/input.'
Reset-TestQueue
$old=[pscustomobject]@{Running=$true};$new=[pscustomobject]@{Running=$true}
$script:scheduler.Tasks['restarted']=$new
Add-GameAction -Id stale-session -Kind Fish.Cast -Domain Fish -Key restarted -Owner $old -Due 0 -Data ([pscustomobject]@{Kind='Poll';Due=0L}) -Execute {param($event,$now) [void]$script:seen.Add('old')}
Invoke-GameActionQueue 0
Assert-Queue ($script:seen.Count -eq 0 -and $script:gameActions.Events.Count -eq 0) 'Old session executed after restart.'

Reset-TestQueue
Add-TestAction ordinary Fish.Cast 0
$outer=[pscustomobject]@{Kind='Fish.Cast'};$script:gameActions.Current=$outer
Add-GameAction -Id release -Kind Safety.Release -Domain Safety -Due 0 -Execute {param($event,$now) Assert-GameActionContext;[void]$script:seen.Add('release')}
Invoke-GameActionQueue 0 -SafetyOnly
Assert-Queue ([object]::ReferenceEquals($script:gameActions.Current,$outer) -and ($script:seen -join ',') -eq 'release') 'Safety execution lost outer context or ran ordinary input.'
$script:gameActions.Current=$null

Reset-TestQueue
Add-TestAction low Fish.Cast 0
Add-GameAction -Id producer -Kind Fight.Combat -Domain Test -Due 0 -Execute {
    param($event,$now)
    [void]$script:seen.Add('producer')
    Add-TestAction new-urgent Fight.Emergency $now
}
Invoke-GameActionQueue 0
Assert-Queue (($script:seen -join ',') -eq 'producer,new-urgent,low') 'New due work was delayed or not reprioritized during the batch.'

Reset-TestQueue
Add-GameAction -Id hold-start -Kind Fight.Combat -Domain Test -Due 0 -Execute {
    param($event,$now) [void]$script:seen.Add('hold-start');$script:scheduler.ItemHoldUntil=$now+100
}
Add-TestAction held Fish.Cast 0
Invoke-GameActionQueue 0
Assert-Queue (($script:seen -join ',') -eq 'hold-start') 'Batch ignored a hold created by the preceding action.'
Invoke-GameActionQueue 100
Assert-Queue (($script:seen -join ',') -eq 'hold-start,held') 'Held event did not resume.'

Reset-TestQueue
$row=New-TestRow foreground
Add-GameAction -Id focus-wait -Kind Fight.Combat -Domain Test -Key foreground -Row $row -Due 0 -Foreground $true -Execute {param($event,$now) [void]$script:seen.Add('focused')}
$other=New-TestRow other
Add-GameAction -Id other-focus -Kind Fish.Cast -Domain Test -Key other -Row $other -Due 0 -Foreground $true -Execute {param($event,$now) [void]$script:seen.Add('other-focus')}
Add-TestAction background Process.Observe 0
Invoke-GameActionQueue 0
Assert-Queue (($script:seen -join ',') -eq 'background' -and $script:activations -eq 1 -and $script:testFocus -eq 'foreground') 'Focus wait blocked reads or allowed a lower priority window switch.'
Invoke-GameActionQueue 200
Assert-Queue (($script:seen -join ',') -eq 'background,focused' -and $script:activations -eq 2 -and $script:testFocus -eq 'other') 'Completed focus did not continue the batch.'
Invoke-GameActionQueue 400
Assert-Queue (($script:seen -join ',') -eq 'background,focused,other-focus') 'Second foreground action was lost.'

Reset-TestQueue
Add-TestAction due-later Fish.Cast 50
Add-GameAction -Id advance-clock -Kind Fight.Combat -Domain Test -Due 0 -Execute {
    param($event,$now) [void]$script:seen.Add('advance-clock');$script:schedulerClock.ElapsedMilliseconds=50L
}
Invoke-GameActionQueue 0
Assert-Queue (($script:seen -join ',') -eq 'advance-clock,due-later') 'Batch did not refresh its clock after an action.'

Reset-TestQueue
$row=New-TestRow foreground
Add-GameAction -Id settles-during-batch -Kind Fight.Combat -Domain Test -Key foreground -Row $row -Due 0 -Foreground $true -Execute {param($event,$now) [void]$script:seen.Add('focused')}
Add-GameAction -Id background -Kind Process.Observe -Domain Test -Due 0 -Execute {
    param($event,$now) [void]$script:seen.Add('background');$script:schedulerClock.ElapsedMilliseconds=200L
}
Invoke-GameActionQueue 0
Assert-Queue (($script:seen -join ',') -eq 'background,focused' -and $script:activations -eq 1) 'Activation that settled during other work was postponed to another tick.'

Reset-TestQueue
$savedHold=${function:Test-GameActionHold}
try {
    # Keep this gate fixture inert: no combat native type or game window is loaded.
    function Test-GameActionHold([long]$Now) {return $false}
    $script:autoFight=[pscustomobject]@{Editing=$false;CommandGate=[pscustomobject]@{LastSentAt=-1L;IntervalMs=500}}
    foreach ($key in @('a','b')) {
        $session=[pscustomobject]@{Id=$key};$row=[pscustomobject]@{Session=$session}
        Add-GameAction -Id $key -Kind Fight.Combat -Domain Fight -Owner $session -Due 0 -Data ([pscustomobject]@{Row=$row}) -Execute {
            param($event,$now) [void]$script:seen.Add($event.Id);$script:autoFight.CommandGate.LastSentAt=$now
        }
    }
    Invoke-GameActionQueue 0
    Assert-Queue (($script:seen -join ',') -eq 'a') 'Batch bypassed the combat shared gate.'
    Invoke-GameActionQueue 499
    Assert-Queue ($script:seen.Count -eq 1) 'Second combat command ran before the gate deadline.'
    Invoke-GameActionQueue 500
    Assert-Queue (($script:seen -join ',') -eq 'a,b') 'Second combat command did not resume at its deadline.'
} finally {${function:Test-GameActionHold}=$savedHold;$script:autoFight=$null}

Reset-TestQueue
$other=New-TestRow other
Add-GameAction -Id other-input -Kind Fight.Combat -Domain Test -Key other -Row $other -Due 0 -Foreground $true -Execute {
    param($event,$now) [void]$script:seen.Add('other-input')
}
Invoke-GameActionQueue 0
Assert-Queue ($script:activations -eq 1 -and $script:gameActions.Focus) 'Foreground activation fixture did not start.'
$script:rotation=[pscustomobject]@{Current=$null;LogoutQueue=(New-Object Collections.Queue);Queue=(New-Object Collections.Queue);ClickQueue=(New-Object Collections.Queue);LoginQueue=(New-Object Collections.Queue)}
$script:rotation.LogoutQueue.Enqueue('first');$script:rotation.Queue.Enqueue('second')
Add-GameAction -Id release -Kind Safety.Release -Domain Safety -Due 50 -Execute {
    param($event,$now) [void]$script:seen.Add('release')
}
Add-GameAction -Id rotation -Kind Rotation.Activate -Domain Rotation -Due 50 -Execute {
    param($event,$now) [void]$script:seen.Add([string]$script:rotation.LogoutQueue.Dequeue());$script:testFocus='rotation'
}
Invoke-GameActionQueue 50
Assert-Queue (($script:seen -join ',') -eq 'release,first' -and $script:rotation.LogoutQueue.Count -eq 0 -and $script:rotation.Queue.Count -eq 1 -and
    $script:activations -eq 1 -and -not $script:gameActions.Focus) 'Rotation did not displace a pending nonrotation activation or keep the next process exclusive.'
Add-GameAction -Id rotation -Kind Rotation.Activate -Domain Rotation -Due 100 -Execute {
    param($event,$now) [void]$script:seen.Add([string]$script:rotation.Queue.Dequeue());$script:testFocus='rotation'
    $script:rotation.Current=[pscustomobject]@{Phase='login'}
}
Invoke-GameActionQueue 100
Assert-Queue (($script:seen -join ',') -eq 'release,first,second' -and $script:activations -eq 1 -and
    $script:rotation.Queue.Count -eq 0 -and $script:rotation.Current) 'Other input ran while the last selected role was still logging in.'
$script:rotation.Current=$null
$script:rotation.ClickQueue.Enqueue('cached-target')
Invoke-GameActionQueue 100
Assert-Queue ($script:activations -eq 1 -and (Test-RotationWorkPending)) 'Other input ran while prepared clicks were pending.'
$script:rotation.ClickQueue.Clear();$script:rotation.LoginQueue.Enqueue('clicked-target')
Invoke-GameActionQueue 100
Assert-Queue ($script:activations -eq 1 -and (Test-RotationWorkPending)) 'Other input ran while clicked roles awaited login checks.'
$script:rotation.LoginQueue.Clear()
Invoke-GameActionQueue 100
Assert-Queue ($script:activations -eq 2 -and $script:gameActions.Focus) 'Queued input did not resume after all role logins completed.'
Invoke-GameActionQueue 299
Assert-Queue ($script:seen.Count -eq 3) 'Resumed input skipped its fresh foreground settle delay.'
Invoke-GameActionQueue 300
Assert-Queue (($script:seen -join ',') -eq 'release,first,second,other-input') 'Queued input was lost after rotation completed.'

Reset-TestQueue
$row=New-TestRow rotation
$entry=[pscustomobject]@{Row=$row}
$work=[pscustomobject]@{Entry=$entry;Phase='menu';FocusUntil=0L}
$script:rotation=[pscustomobject]@{Current=$work;Active=@{rotation=$entry};LogoutQueue=(New-Object Collections.Queue);Queue=(New-Object Collections.Queue);ClickQueue=(New-Object Collections.Queue);LoginQueue=(New-Object Collections.Queue)}
$script:activateAllowed=$false
Add-GameAction -Id rotation -Kind Rotation.Menu -Domain Rotation -Key rotation -Row $row -Owner $work -Due 0 -Data menu -Foreground $true -Execute {
    param($event,$now) [void]$script:seen.Add('menu')
}
Invoke-GameActionQueue 0
Assert-Queue ($script:activations -eq 1 -and $script:stopped -eq 0 -and $work.FocusUntil -eq 5000) 'Rotation did not begin a five-second focus window.'
Invoke-GameActionQueue 499
Assert-Queue ($script:activations -eq 1) 'Rotation retried activation before the retry interval.'
Invoke-GameActionQueue 500
Assert-Queue ($script:activations -eq 2 -and $script:stopped -eq 0) 'Rotation did not retry a rejected activation.'
$script:activateAllowed=$true
Invoke-GameActionQueue 1000
Invoke-GameActionQueue 1199
Assert-Queue ($script:seen.Count -eq 0 -and $script:stopped -eq 0) 'Recovered rotation skipped foreground settling.'
Invoke-GameActionQueue 1200
Assert-Queue ($script:seen.Count -eq 1 -and $script:activations -eq 3 -and $script:stopped -eq 0) 'Rotation did not recover within five seconds.'

Reset-TestQueue
$row=New-TestRow rotation
$entry=[pscustomobject]@{Row=$row}
$work=[pscustomobject]@{Entry=$entry;Phase='menu';FocusUntil=0L}
$script:rotation=[pscustomobject]@{Current=$work;Active=@{rotation=$entry};LogoutQueue=(New-Object Collections.Queue);Queue=(New-Object Collections.Queue);ClickQueue=(New-Object Collections.Queue);LoginQueue=(New-Object Collections.Queue)}
$script:focusOnActivate=$false
Add-GameAction -Id rotation -Kind Rotation.Menu -Domain Rotation -Key rotation -Row $row -Owner $work -Due 0 -Data menu -Foreground $true -Execute {
    param($event,$now) [void]$script:seen.Add('menu')
}
Invoke-GameActionQueue 0
Invoke-GameActionQueue 500
Assert-Queue ($script:activations -eq 2 -and $script:stopped -eq 0) 'Accepted activation without foreground was not retried.'
$script:focusOnActivate=$true
Invoke-GameActionQueue 1000
Invoke-GameActionQueue 1200
Assert-Queue ($script:seen.Count -eq 1 -and $script:stopped -eq 0) 'Rotation did not confirm foreground after retry.'

Reset-TestQueue
$row=New-TestRow rotation
$entry=[pscustomobject]@{Row=$row}
$work=[pscustomobject]@{Entry=$entry;Phase='menu';FocusUntil=0L}
$script:rotation=[pscustomobject]@{Current=$work;Active=@{rotation=$entry};LogoutQueue=(New-Object Collections.Queue);Queue=(New-Object Collections.Queue);ClickQueue=(New-Object Collections.Queue);LoginQueue=(New-Object Collections.Queue)}
$script:activateAllowed=$false
Add-GameAction -Id rotation -Kind Rotation.Menu -Domain Rotation -Key rotation -Row $row -Owner $work -Due 0 -Data menu -Foreground $true -Execute {
    param($event,$now) [void]$script:seen.Add('menu')
}
for ($at=0;$at -lt 5000;$at+=500) {Invoke-GameActionQueue $at}
Assert-Queue ($script:activations -eq 10 -and $script:stopped -eq 0 -and $script:seen.Count -eq 0) 'Rotation stopped before the full five seconds.'
Invoke-GameActionQueue 5000
Assert-Queue ($script:stopped -eq 1 -and $script:gameActions.Events.Count -eq 0 -and $script:activations -eq 10) 'Rotation did not fail at the five-second deadline.'

Write-Output 'PASS: draining due work, callback enqueue/reprioritization, clock refresh, new holds, combat gate, shared priority/deadline/FIFO queue, deduplication, cancellation, holds, safety release, rotation foreground exclusivity/five-second focus retry, focus preemption and process identity. Inert callbacks only.'
