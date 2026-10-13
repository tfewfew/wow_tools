$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\wowAuto.ActionQueue.ps1')
function Assert-Queue($Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
function Reset-TestQueue {
    Initialize-GameActionQueue (Join-Path $PSScriptRoot '..\action-priorities.json')
    $script:scheduler=[pscustomobject]@{ReelHoldUntil=0L;ItemHoldUntil=0L;Tasks=@{};Events=@()}
    $script:autoFight=$null;$script:editingSettings=$false;$script:seen=New-Object Collections.ArrayList
    $script:testFocus='';$script:activations=0;$script:stopped=0
}
function Add-TestAction([string]$Id,[string]$Kind,[long]$Due,$Owner=$null) {
    Add-GameAction -Id $Id -Kind $Kind -Domain Test -Owner $Owner -Due $Due -Execute {
        param($event,$now) Assert-GameActionContext;[void]$script:seen.Add($event.Id)
    }
}
function Test-RowProcessIdentity($Row) {return $Row.Process.SameIdentity}
function Test-WorkerForeground($Row) {return $script:testFocus -eq $Row.Key}
function Activate-WorkerRow($Row) {Assert-GameActionContext;$script:activations++;$script:testFocus=$Row.Key;return $true}
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
1..4 | ForEach-Object {Invoke-GameActionQueue 20}
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
Add-GameAction -Id urgent -Kind Fight.Emergency -Domain Test -Due 0 -Execute {param($event,$now) $script:testFocus='other';[void]$script:seen.Add('urgent')}
Invoke-GameActionQueue 199
Invoke-GameActionQueue 1000
Assert-Queue ($script:activations -eq 2 -and $script:stopped -eq 0) 'Preempted activation retained expired timeout.'
Invoke-GameActionQueue 1199
Assert-Queue ($script:seen.Count -eq 1) 'Resumed focus skipped settle delay.'
Invoke-GameActionQueue 1200
Assert-Queue (($script:seen -join ',') -eq 'urgent,cast') 'Resumed action did not execute once.'

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

Write-Output 'PASS: shared priority/deadline/FIFO queue, deduplication, cancellation, holds, safety release, focus preemption and process identity. Inert callbacks only.'
