# Dot-sourced only by wowAuto.ps1 -UiTest. All focus/pixel operations use fixtures.
function Assert-Ui($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Complete-TestScan {
    $time = 0L
    while ($script:scanning -and $time -lt 10000) {
        Invoke-RefreshScan $time
        $time += 200
    }
    Assert-Ui (-not $script:scanning) 'Scan did not finish.'
}
$a = @($script:rows.Values | Where-Object { $_.Process.Id -eq 101 })[0]
$b = @($script:rows.Values | Where-Object { $_.Process.Id -eq 202 })[0]
$c = @($script:rows.Values | Where-Object { $_.Process.Id -eq 303 })[0]
$b.Process.ScanColor = 'green'
$c.Process.ScanColor = 'yellow'
Assert-Ui ($script:rows.Count -eq 3) 'Expected three rows.'
Assert-Ui ($toolbar.ClientRectangle.Contains($refreshButton.Bounds)) 'Refresh button outside header.'
foreach ($row in $script:rows.Values) {
    Assert-Ui (-not $row.Start.Enabled -and -not $row.Stop.Enabled) 'Unverified row unlocked.'
}
$a.Start.PerformClick()
Assert-Ui ($null -eq $a.State) 'Unverified row started.'
$refreshButton.PerformClick()
Assert-Ui ($script:scanning -and -not $refreshButton.Enabled) 'Scan did not lock refresh.'
Complete-TestScan
Assert-Ui (($script:detectorCommands.Key -join ',') -eq ($a.Key+','+$b.Key+','+$c.Key)) 'Wrong monitor command order.'
Assert-Ui $script:restored 'Original foreground was not restored.'
Assert-Ui ($a.Start.Enabled -and $a.Stop.Enabled -and $b.Start.Enabled -and $b.Stop.Enabled) 'Red/green rows not unlocked.'
Assert-Ui (-not $c.Start.Enabled -and -not $c.Stop.Enabled) 'Yellow row unlocked.'
$a.Start.PerformClick()
Set-VersionWaitRanges 9000 13000 2345 6789 -Persist $false
$b.Start.PerformClick()
Assert-Ui ($a.State.Running -and $b.State.Running -and $b.State.MinimumMs -eq 2345 -and $a.State.MinimumMs -eq 9000) 'Version-based start/ranges failed.'
$a.Stop.PerformClick()
Assert-Ui (-not $a.State.Running -and $b.State.Running) 'Stop affected another row.'
$a.SlotUseItem=$true
$script:scheduler.CompletedCycles[$a.Key]=123
$refreshButton.PerformClick()
Assert-Ui (-not $b.State.Running -and -not $b.Start.Enabled -and -not $b.Stop.Enabled) 'Refresh did not stop and lock active row.'
Complete-TestScan
Assert-Ui ($script:rows[$b.Key] -eq $b -and $script:versionRanges.forerver.MinimumMs -eq 2345 -and $null -eq $b.State) 'Refresh did not preserve version range/stopped row.'
Assert-Ui ($a.SlotUseItem -and -not $b.SlotUseItem) 'Refresh did not preserve current slot item choice.'
Assert-Ui ((Get-WowAutoCycleCount $script:scheduler $a.Key) -eq 123) 'Refresh cleared process cycle count.'
$a.Process.ScanColor = 'unknown'
$b.Process.FocusAllowed = $false
$c.Process.ScanColor = 'not-foreground'
$refreshButton.PerformClick()
Complete-TestScan
foreach ($row in $script:rows.Values) {
    Assert-Ui (-not $row.Start.Enabled -and -not $row.Stop.Enabled) 'Failed scan left controls unlocked.'
}
$script:mockProcesses = @($script:mockProcesses | Where-Object { $_.Id -ne 202 })
$refreshButton.PerformClick()
Complete-TestScan
Assert-Ui ($script:rows.Count -eq 2) 'Exited process not removed.'
$a.Process.StartTime = $a.Process.StartTime.AddSeconds(1)
$a.Process.ScanColor = 'red'
$refreshButton.PerformClick()
Complete-TestScan
$fresh = @($script:rows.Values | Where-Object { $_.Process.Id -eq 101 })[0]
Assert-Ui ($fresh -ne $a -and $null -eq $fresh.State) 'Reused PID inherited old session.'
Assert-Ui (-not $fresh.SlotUseItem) 'Reused PID inherited old item selection.'
Assert-Ui ((Get-WowAutoCycleCount $script:scheduler $fresh.Key) -eq 0) 'Reused PID inherited cycle count.'
$saved = $script:mockProcesses
$script:mockProcesses = @()
$refreshButton.PerformClick()
Assert-Ui ($script:rows.Count -eq 0 -and -not $script:scanning -and $refreshButton.Enabled) 'Empty scan failed.'
$script:mockProcesses = $saved
$refreshButton.PerformClick()
Complete-TestScan
Write-Output 'PASS: red/green gating, scan ordering/restoration, yellow/unknown/focus failure, stop-before-refresh, independent controls, range preservation, exited/reused PID, empty list. No native actions executed.'
