# Exercise production direct/rotation start commands and item handling on worker threads.
$savedDirectFlag=$script:directStartUseItem
$directRuntimeIniExisted=[IO.File]::Exists($script:settingsPath)
$directRuntimeIni=if($directRuntimeIniExisted){[IO.File]::ReadAllBytes($script:settingsPath)}else{$null}
$directRole=@(Get-AccountTaskRoles $a)[0];$savedRoleItem=$directRole.UseItem
$directAccountHash=(Get-FileHash -LiteralPath $script:accountTasks.Path).Hash
$directRuntimeDialog=$null
try {
    Stop-AllRows
    if(-not $directRuntimeIniExisted){$t=$script:versionRanges.titan;$f=$script:versionRanges.forerver;Set-VersionWaitRanges $t.MinimumMs $t.MaximumMs $f.MinimumMs $f.MaximumMs}
    $directRuntimeDialog=New-UnifiedSettingsDialog;$directRuntimeDialog.Show($form)
    $directRuntimeDialog.Tag.Tabs.SelectedTab=$directRuntimeDialog.Tag.Fish.Parent
    $directRuntimeDialog.Tag.Fish.Tag.DirectStartUseItem.Checked=$true
    Assert-Parallel (-not $script:directStartUseItem) 'Editing the embedded direct-start draft changed the active global flag.'
    $directRuntimeDialog.Tag.Fish.Tag.Apply.PerformClick()
    Assert-Parallel ($script:directStartUseItem -and (Read-WowAutoSettingsIni $script:settingsPath).DirectStartUseItem -eq 1) 'Saving the automatic-fishing tab did not persist the direct-start flag.'
    $directRuntimeDialog.Dispose()
    $a.SlotUseItem=$false;$b.SlotUseItem=$true;$a.TaskMode='fish';$b.TaskMode='fight'
    [ParallelFixture]::Lures[101]='missing'
    $beforeItems=[ParallelFixture]::Items[101];$beforeLureB=[ParallelFixture]::LureReads[202]
    $a.Validated=$true;$b.Validated=$true;Set-RowControls $a;Set-RowControls $b
    $a.DirectStart.PerformClick();$b.DirectStart.PerformClick()
    Pump-Parallel {$a.RuntimeDirect -and $a.SlotUseItem -and [ParallelFixture]::Items[101] -eq $beforeItems+1 -and $b.RuntimeDirect -and $b.ExecutionRound -gt 0}
    Assert-Parallel (-not $directRole.UseItem -and -not $b.SlotUseItem -and [ParallelFixture]::LureReads[202] -eq $beforeLureB) 'Direct fish used the role flag or direct combat performed a fishing item check.'
    $t=$script:versionRanges.titan;$f=$script:versionRanges.forerver
    Set-VersionWaitRanges $t.MinimumMs $t.MaximumMs $f.MinimumMs $f.MaximumMs -Persist $false -DirectStartUseItem $false
    Assert-Parallel ($a.SlotUseItem -and $a.RuntimeRunning -and $b.RuntimeRunning) 'Changing the next-start setting altered an active process task.'
    $a.Stop.PerformClick();$a.SlotUseItem=$true;$beforeRound=$a.ExecutionRound
    $a.Validated=$true;Set-RowControls $a;$a.DirectStart.PerformClick()
    Pump-Parallel {$a.ExecutionRound -gt $beforeRound -and -not $a.SlotUseItem}
    $reads=[ParallelFixture]::LureReads[101];$items=[ParallelFixture]::Items[101];$directWaitDeadline=$script:parallelHub.Now+180
    Pump-Parallel {$script:parallelHub.Now -ge $directWaitDeadline}
    Assert-Parallel ([ParallelFixture]::LureReads[101] -eq $reads -and [ParallelFixture]::Items[101] -eq $items -and $b.RuntimeRunning) 'Disabled global flag still checked/used bait or interfered with another process.'
    $a.Stop.PerformClick();$directRole.UseItem=$true;$beforeRound=$a.ExecutionRound
    Set-RowControls $a;$a.Start.PerformClick()
    Pump-Parallel {$a.ExecutionRound -gt $beforeRound -and -not $a.RuntimeDirect -and $a.SlotUseItem}
    Assert-Parallel (-not $script:directStartUseItem -and $a.CurrentRole -ceq $directRole.Name) 'Role rotation used the disabled direct-start global flag.'
    $a.Stop.PerformClick();$directRole.UseItem=$false;$script:directStartUseItem=$true;$beforeRound=$a.ExecutionRound
    Set-RowControls $a;$a.Start.PerformClick()
    Pump-Parallel {$a.ExecutionRound -gt $beforeRound -and -not $a.RuntimeDirect -and -not $a.SlotUseItem}
    Assert-Parallel ((Get-FileHash -LiteralPath $script:accountTasks.Path).Hash -eq $directAccountHash) 'Direct-start settings rewrote account/role configuration.'
    Write-Output 'PASS: embedded fish-page save drives direct bait checks/use independently of cached/role flags; disabled direct and combat skip bait, active tasks remain unchanged, rotation retains each role flag and other processes continue. All input/frames mocked.'
} finally {
    if($directRuntimeDialog){$directRuntimeDialog.Dispose()}
    Stop-AllRows;$directRole.UseItem=$savedRoleItem;$script:directStartUseItem=$savedDirectFlag
    [ParallelFixture]::Lures[101]='present'
    if($directRuntimeIniExisted){[IO.File]::WriteAllBytes($script:settingsPath,$directRuntimeIni)}elseif([IO.File]::Exists($script:settingsPath)){[IO.File]::Delete($script:settingsPath)}
}
