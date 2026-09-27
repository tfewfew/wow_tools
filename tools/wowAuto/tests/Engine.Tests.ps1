$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\wowAuto.Engine.ps1')
function Assert-Equal($Actual, $Expected, $Label) {
    if ($Actual -ne $Expected) { throw "$Label : expected $Expected, got $Actual" }
}
function Get-Random {
    param([int]$Minimum, [int]$Maximum)
    if ($Minimum -eq 8000 -and $Maximum -eq 13001) { return 8123 }
    return (Microsoft.PowerShell.Utility\Get-Random -Minimum $Minimum -Maximum $Maximum)
}
foreach ($range in @(@(0, 13000), @(13000, 8000), @(1, 3600001))) {
    $rejected = $false
    try { $null = New-WowAutoState $range[0] $range[1] } catch { $rejected = $true }
    Assert-Equal $rejected $true 'Invalid range rejected'
}
$state = New-WowAutoState 8000 13000
Assert-Equal (Invoke-WowAutoState $state 0 $true 'green') 'None' 'Green starts wait'
Assert-Equal $state.Deadline 8123 'Millisecond deadline'
Assert-Equal (Invoke-WowAutoState $state 8000 $true 'red') 'None' 'Wait suppresses Ctrl1'
Assert-Equal $state.NextDue 8123 'Final poll aligns to deadline'
Assert-Equal (Invoke-WowAutoState $state 8123 $true 'green') 'Ctrl2' 'Interaction at deadline'
Complete-WowAutoInteraction $state 8173 $true
Assert-Equal $state.Deadline 9173 'Cooldown starts after key release'
Assert-Equal (Invoke-WowAutoState $state 8673 $true 'red') 'None' 'No input during cooldown'
Assert-Equal (Invoke-WowAutoState $state 9173 $true 'red') 'None' 'Cooldown ends before fresh sample'
Assert-Equal (Invoke-WowAutoState $state 9174 $true 'red') 'Ctrl1' 'Fresh detection resumes'
$state = New-WowAutoState 8000 13000
$null = Invoke-WowAutoState $state 0 $true 'green'
$null = Invoke-WowAutoState $state 500 $false 'unknown'
Assert-Equal $state.Deadline 0 'Background cancels pending interaction'
Assert-Equal $state.NextDue 1000 'Background poll is 500 ms'
$null = Invoke-WowAutoState $state 1000 $true 'green'
Assert-Equal $state.Deadline 9123 'Return starts fresh wait'
Stop-WowAutoState $state
Assert-Equal (Invoke-WowAutoState $state 20000 $true 'green') 'None' 'Stop cancels all actions'
$state = New-WowAutoState 8000 13000
$null = Invoke-WowAutoState $state 0 $true 'green'
Assert-Equal (Invoke-WowAutoState $state 500 $true 'yellow') 'ExitGame' 'Yellow interrupts wait'
Assert-Equal $state.Running $false 'Yellow stops runner'
$state = New-WowAutoState 1234 1234
$null = Invoke-WowAutoState $state 0 $true 'green'
Assert-Equal $state.Deadline 1234 'Equal bounds supported'
$previous = -1
for ($i=0; $i -lt 1000; $i++) {
    $next = Get-WowAutoInterval $previous
    if ($next -lt 300 -or $next -gt 600 -or $next -eq $previous) { throw 'Invalid detection interval.' }
    $previous = $next
}
Write-Output 'PASS: range validation, deadlines, cooldown, pause/resume, Stop, yellow priority, equal bounds, random polling. No native actions executed.'
