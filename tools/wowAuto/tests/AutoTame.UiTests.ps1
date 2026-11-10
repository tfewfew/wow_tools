$tameUi=$script:autoTame.Ui
Assert-Parallel ($tameUi.Page.Text -eq '自动抓宠' -and $tameUi.Windows.Items.Count -eq 3 -and $tameUi.Keys.Count -eq 4 -and $tameUi.Waits.Count -eq 4) 'Dedicated taming page is incomplete.'
$originalTame=$script:autoTame.Config
try {
    $tabs.SelectedTab=$tameUi.Page;[Windows.Forms.Application]::DoEvents()
    $tameUi.Keys.Trap.Text='F1';$tameUi.Keys.Opening.Text='F2';$tameUi.Keys.Backward.Text='S';$tameUi.Keys.Tame.Text='F3'
    foreach($wait in $tameUi.Waits.Values){$wait.Value=[decimal]0.2}
    Assert-Parallel ($tameUi.BackwardHold.Value -eq 0 -and $tameUi.BackwardHold.Maximum -eq 60) 'Hold control lacks legacy default or bounds.'
    $tameUi.BackwardHold.Value=[decimal]0.25
    Save-AutoTamePage
    Assert-Parallel ((Read-AutoTameConfig $script:autoTame.ConfigPath).BackwardHoldMs -eq 250) 'Hold duration did not persist.'
    $saved=[IO.File]::ReadAllText($script:autoTame.ConfigPath)
    $tameUi.Keys.Tame.Text=''
    $failed=$false;try{Save-AutoTamePage}catch{$failed=$true}
    Assert-Parallel ($failed -and [IO.File]::ReadAllText($script:autoTame.ConfigPath) -ceq $saved -and $script:autoTame.Config.TameKey -eq 'F3') 'Invalid draft changed saved keys.'
    $tameUi.Keys.Tame.Text='F3'
    foreach($id in @(101,202)) {[ParallelFixture]::TameStates[$id]='matched';[ParallelFixture]::TameCombat[$id]=1;[ParallelFixture]::TameTargets[$id]=1}
    Start-AutoTameRow $a;Start-AutoTameRow $b
    Pump-Parallel {@([ParallelFixture]::TameActions.ToArray() | Where-Object {$_ -eq '101:F3'}).Count -ge 2 -and @([ParallelFixture]::TameActions.ToArray() | Where-Object {$_ -eq '202:F3'}).Count -ge 2}
    foreach($id in @(101,202)) {
        $keys=@([ParallelFixture]::TameActions.ToArray() | Where-Object {$_ -like ($id.ToString()+':*')} | Select-Object -First 5)
        Assert-Parallel (($keys -join ',') -eq ($id.ToString()+':F1,'+$id+':F2,'+$id+':S,'+$id+':F3,'+$id+':F3')) 'Threaded sequence/repeat order changed.'
        Assert-Parallel (@([ParallelFixture]::TameHoldRequests.ToArray() | Where-Object {$_ -eq ($id.ToString()+':Backward:250')}).Count -eq 1) 'Hold duration did not reach the operator request.'
    }
    Assert-Parallel (-not @([ParallelFixture]::TameHoldRequests.ToArray() | Where-Object {$_ -notmatch ':Backward:' -and $_ -notmatch ':0$'}).Count) 'Another stage received the backward hold.'
    Assert-Parallel ($a.RuntimeDirect -and $b.RuntimeDirect -and $a.TaskMode -eq 'tame' -and $b.TaskMode -eq 'tame') 'Taming entered account rotation.'
    # Saving new settings must not rewrite a running task's immutable snapshot.
    $tameUi.Keys.Tame.Text='F4';Save-AutoTamePage
    $previous=@([ParallelFixture]::TameActions.ToArray() | Where-Object {$_ -eq '202:F3'}).Count
    Pump-Parallel {@([ParallelFixture]::TameActions.ToArray() | Where-Object {$_ -eq '202:F3'}).Count -gt $previous}
    Assert-Parallel (-not @([ParallelFixture]::TameActions.ToArray() | Where-Object {$_ -match ':F4$'}).Count) 'Running capture used newly saved keys.'
    [ParallelFixture]::TameStates[101]='idle';[ParallelFixture]::TameCombat[202]=0
    $tameWaitUntil=$script:parallelHub.Now+300;Pump-Parallel {$script:parallelHub.Now -ge $tameWaitUntil}
    $count=[ParallelFixture]::TameActions.Count
    $tameWaitUntil=$script:parallelHub.Now+500;Pump-Parallel {$script:parallelHub.Now -ge $tameWaitUntil}
    Assert-Parallel ([ParallelFixture]::TameActions.Count -eq $count) 'Target loss or leaving combat kept sending capture.'
    Stop-Row $a
    Assert-Parallel ($b.RuntimeRunning -and -not $a.RuntimeRunning -and $a.TaskMode -eq $a.DefaultTaskMode -and -not $a.Validated) 'Stopping capture affected another process or kept a stale fishing validation.'
    [ParallelFixture]::TameTargets[202]=2;[ParallelFixture]::TameCombat[202]=1;[ParallelFixture]::TameInterruptPid=202
    Pump-Parallel {[ParallelFixture]::TameInterruptions -eq 1}
    $tameWaitUntil=$script:parallelHub.Now+500;Pump-Parallel {$script:parallelHub.Now -ge $tameWaitUntil}
    Assert-Parallel ([ParallelFixture]::TameActions.Count -eq $count+3 -and $b.RuntimeRunning) 'An interrupted move advanced to capture or repeated on the same target.'
    $count=[ParallelFixture]::TameActions.Count
    [ParallelFixture]::TameTargets[202]=3;[ParallelFixture]::TameInterruptPid=0
    [ParallelFixture]::BlockPid=202;[ParallelFixture]::BlockedPid=0;[ParallelFixture]::Release.Reset()
    Pump-Parallel {[ParallelFixture]::BlockedPid -eq 202}
    Stop-Row $b;[ParallelFixture]::Release.Set();[ParallelFixture]::BlockPid=0
    $tameWaitUntil=$script:parallelHub.Now+300;Pump-Parallel {$script:parallelHub.Now -ge $tameWaitUntil}
    Assert-Parallel ([ParallelFixture]::TameActions.Count -eq $count -and -not $b.RuntimeRunning) 'Stop let a queued taming action execute.'
    if($env:WOWAUTO_PARALLEL_PREVIEW){
        $bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height)
        try{$form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$bitmap.Width,$bitmap.Height)));$bitmap.Save((Join-Path $env:WOWAUTO_PARALLEL_PREVIEW 'auto-tame.png'))}finally{$bitmap.Dispose()}
    }
    Write-Output 'PASS: dedicated taming UI, atomic settings, both process threads, stage/repeat order, immutable running config, target loss/combat exit, isolated stop and queued cancellation. Mock input only.'
}finally {
    [ParallelFixture]::Release.Set();[ParallelFixture]::BlockPid=0;Stop-Row $a;Stop-Row $b
    $script:autoTame.Config=$originalTame
    $tameUi.BackwardHold.Value=[decimal]$originalTame.BackwardHoldMs/1000
    foreach($stage in @('Trap','Opening','Backward','Tame')){$tameUi.Keys[$stage].Text=$originalTame.($stage+'Key');$tameUi.Waits[$stage].Value=[decimal]$originalTame.($stage+'WaitMs')/1000}
    if([IO.File]::Exists($script:autoTame.ConfigPath)){[IO.File]::Delete($script:autoTame.ConfigPath)}
    $tabs.SelectedTab=$tab
}
