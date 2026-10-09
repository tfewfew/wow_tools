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
Assert-Ui (($script:workerKeys -join ',') -eq "$($a.Process.Id):48") 'First row did not cast.'
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
Assert-Ui ($script:workerKeys[-1] -eq "$($b.Process.Id):187") 'Due reel did not preempt red casting.'
Assert-Ui ($b.State.Mode -eq 'Cooldown' -and $b.State.Deadline -eq $base+4025) 'Reel did not schedule 1-second cooldown.'
$a.State.Mode='Wait'; $a.State.Deadline=$base+3050
Add-WowAutoEvent $script:scheduler $a.Key 'Reel' $a.State.Deadline
$focusCount=$script:workerActivations.Count
$keyCount=$script:workerKeys.Count
Invoke-SchedulerTick ($base+3075)
Invoke-SchedulerTick ($base+3124)
Assert-Ui ($script:workerActivations.Count -eq $focusCount -and $script:workerKeys.Count -eq $keyCount) 'Overdue reel preempted the 100ms foreground hold.'
Invoke-SchedulerTick ($base+3125)
Assert-Ui ($script:workerActivations.Count -eq $focusCount+1 -and $script:workerFocus -eq $a.Process.Id) 'Overdue window was not selected after hold expiry.'
Invoke-SchedulerTick ($base+3325)
Assert-Ui ($script:workerKeys[-1] -eq "$($a.Process.Id):187") 'Deferred reel did not execute.'
$a.Process.ScanColor='green'
Invoke-SchedulerTick ($base+4025)
Invoke-SchedulerTick ($base+4225)
Assert-Ui ($script:workerKeys[-1] -eq "$($b.Process.Id):32" -and $b.State.ForceNextCast) 'Post-reel green did not jump before casting.'
Invoke-SchedulerTick ($base+4825)
Assert-Ui ($script:workerKeys[-1] -eq "$($b.Process.Id):48" -and -not $b.State.ForceNextCast) 'Post-reel green did not force and acknowledge Ctrl+1.'
Assert-Ui ($b.State.Mode -eq 'Casting' -and $b.State.Deadline -eq 0) 'Stale green started countdown before red was observed.'
$keyCount=$script:workerKeys.Count
Invoke-SchedulerTick ($base+5425)
Assert-Ui ($script:workerKeys.Count -eq $keyCount -and $b.State.Mode -eq 'Casting') 'Stale green should only poll, without another forced cast.'
$b.Process.ScanColor='red'
Invoke-SchedulerTick ($base+6025)
Assert-Ui ($script:workerKeys.Count -eq $keyCount+1) 'Red did not resume casting.'
$b.Process.ScanColor='green'
Invoke-SchedulerTick ($base+6625)
Assert-Ui ($b.State.Mode -eq 'Wait' -and $b.State.Deadline -eq $base+7625) 'Red-to-green did not start a fresh countdown.'
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

$script:workerClosed=@()
$b.Validated=$true
Start-Row $b
foreach ($count in @(0,500,501)) {
    $a.Process.HasExited=$false; $a.Exited=$false; $a.Validated=$true
    $script:scheduler.CompletedCycles[$a.Key]=$count
    Start-Row $a
    $closedBefore=$script:workerClosed.Count
    Close-WorkerGame $a
    Assert-Ui (-not $a.State.Running) 'Yellow did not stop current row.'
    Assert-Ui $b.State.Running 'Yellow affected another row.'
    Assert-Ui (@($script:scheduler.Events | Where-Object { $_.Key -eq $a.Key }).Count -eq 0) 'Yellow left pending events.'
    if ($count -le 500) {
        Assert-Ui (-not $a.Process.HasExited -and $script:workerClosed.Count -eq $closedBefore -and -not $a.Validated) 'Low-count yellow terminated game or left it enabled.'
    }
    else {
        Assert-Ui (-not $a.Process.HasExited -and -not $a.Exited -and -not $a.Validated -and $script:workerClosed.Count -eq $closedBefore+1) '501 cycles must request normal exit without claiming immediate termination.'
    }
}
Stop-AllRows
Write-Output 'PASS: yellow preserves game at 0/500 cycles, requests normal exit at 501, clears only target events, leaves other task running. Close requests mocked.'
