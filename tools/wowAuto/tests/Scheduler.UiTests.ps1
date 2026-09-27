# Runs inside wowAuto.ps1 -UiTest with native adapters mocked.
Stop-AllRows
$testRows=@($script:rows.Values | Sort-Object { $_.Process.Id })
$a=$testRows[0]; $b=$testRows[1]
$a.Process.FocusAllowed=$true; $a.Process.ScanColor='red'; $a.Validated=$true
$b.Process.FocusAllowed=$true; $b.Process.ScanColor='green'; $b.Validated=$true
$a.Minimum.Value=8000; $a.Maximum.Value=13000
$b.Minimum.Value=1000; $b.Maximum.Value=1000
Update-BatchControls
Assert-Ui ($refreshButton.Parent -eq $toolbar -and $toolbar.Parent -eq $tab) 'Refresh button is outside autofish tab.'
$startAllButton.PerformClick()
Assert-Ui ($a.State.Running -and $b.State.Running -and $script:scheduler.Tasks.Count -eq 2) ("Start all failed: count=" + $script:scheduler.Tasks.Count + "; A=" + $a.Status.Text + "; B=" + $b.Status.Text + "; enabled=" + $startAllButton.Enabled)
$script:workerKeys=@(); $script:workerActivations=@()
$base=$script:schedulerClock.ElapsedMilliseconds+10
Invoke-SchedulerTick $base
Invoke-SchedulerTick ($base+200)
Assert-Ui (($script:workerKeys -join ',') -eq "$($a.Process.Id):49") 'First row did not cast.'
Invoke-SchedulerTick ($base+900)
Assert-Ui ($script:workerKeys.Count -ge 2 -and $script:workerActivations.Count -eq 1) 'Red must keep casting without rotating.'
$a.Process.ScanColor='green'
Invoke-SchedulerTick ($base+1600)
Assert-Ui ($a.State.Mode -eq 'Wait') 'Green did not schedule reel.'
Invoke-SchedulerTick ($base+1625)
Invoke-SchedulerTick ($base+1825)
Assert-Ui ($b.State.Mode -eq 'Wait' -and $b.State.Deadline -eq $base+2825) 'Next window did not get its timer.'
# Expire A's first wait and force its cast to stay red while B's event is due.
Remove-WowAutoEvents $script:scheduler $a.Key
$a.State.Mode='Ready'; $a.State.NextDue=$base+1900; $a.Process.ScanColor='red'
Invoke-SchedulerTick ($base+1900)
Invoke-SchedulerTick ($base+2100)
Invoke-SchedulerTick ($base+2825)
Invoke-SchedulerTick ($base+3025)
Assert-Ui ($script:workerKeys[-1] -eq "$($b.Process.Id):50") 'Due reel did not preempt red casting.'
Assert-Ui ($b.State.Mode -eq 'Cooldown' -and $b.State.Deadline -eq $base+4025) 'Reel did not schedule 1-second cooldown.'
$stopAllButton.PerformClick()
Assert-Ui ($script:scheduler.Tasks.Count -eq 0 -and $script:scheduler.Events.Count -eq 0) 'Stop all left events behind.'
$keyCount=$script:workerKeys.Count
Invoke-SchedulerTick ($base+20000)
Assert-Ui ($script:workerKeys.Count -eq $keyCount) 'Stopped scheduler emitted input.'
$b.Validated=$false
Update-BatchControls
$startAllButton.PerformClick()
Assert-Ui ($a.State.Running -and -not $b.State.Running -and $script:scheduler.Tasks.Count -eq 1) 'Start all included an ineligible row.'
Stop-AllRows
Write-Output 'PASS: tab toolbar, eligible start-all, repeated red casting, green rotation, timed preemption, 1-second cooldown, stop-all cancellation. Native actions mocked.'
