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
$old=Add-WowAutoTask $q 'A' 20 20 100
$null=Complete-WowAutoPoll $q 'A' 100 'green'
Stop-WowAutoTask $q 'A'
$fresh=Add-WowAutoTask $q 'A' 8000 13000 110
Assert-Equal (Get-WowAutoWork $q 200).Kind 'Poll' 'Restart cannot inherit old timer'
Assert-Equal (Complete-WowAutoPoll $q 'A' 200 'yellow') 'ExitGame' 'Yellow stops target'
Assert-Equal $fresh.Running $false 'Yellow clears running state'
$x=Add-WowAutoTask $q 'X' 100 100 0
$y=Add-WowAutoTask $q 'Y' 100 100 0
$null=Complete-WowAutoPoll $q 'X' 0 'green'
$null=Complete-WowAutoPoll $q 'Y' 0 'green'
Assert-Equal (Get-WowAutoWork $q 100).Key 'X' 'Tied deadlines preserve event order'
Complete-WowAutoReel $q 'X' 100 $true
Assert-Equal (Get-WowAutoWork $q 100).Key 'Y' 'Second due timer runs before normal work'
$previous=-1
for ($i=0;$i -lt 1000;$i++) {
    $next=Get-WowAutoInterval $previous
    if ($next -lt 300 -or $next -gt 600 -or $next -eq $previous) { throw 'Invalid polling interval.' }
    $previous=$next
}
Write-Output 'PASS: repeated casting, green yield, shared deadlines, timer preemption/order, cooldown, cancellation/restart, yellow, range validation, random polling. No native actions.'
