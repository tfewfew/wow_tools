# Real orchestration functions, mock clients/screens/inputs, temporary configuration only.
Stop-AllRows
Initialize-AutoFightTab $tabs $form -Unified
$script:autoFight.Profiles['titan:1'].BuffIntervalSeconds=120
$script:autoFight.Profiles['titan:1'].BuffCount=2
$sourceRotation=Join-Path (Split-Path $PSScriptRoot -Parent) 'rotation.config.json'
$sourceHashes=@{}
foreach ($p in @($sourceRotation,(Join-Path (Split-Path $PSScriptRoot -Parent) 'config.ini'),(Join-Path (Split-Path $PSScriptRoot -Parent) 'autoFight.config.json'))) {$sourceHashes[$p]=(Get-FileHash $p).Hash}
$oldRotationPath=$script:rotation.Path
$script:rotation.Path=Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-rotation-'+[Guid]::NewGuid()+'.json')
$script:rotation.Plans=@{};$script:rotation.IntervalSeconds=0;$script:rotation.Active.Clear();$script:rotation.LogoutQueue.Clear();$script:rotation.Queue.Clear();$script:rotation.ClickQueue.Clear();$script:rotation.LoginQueue.Clear();$script:rotation.Current=$null;$script:rotation.ClickSwitch=$null
$script:scheduler=New-WowAutoScheduler;$script:schedulerClock=[pscustomobject]@{ElapsedMilliseconds=0L};$script:autoFight.Clock=$script:schedulerClock
function Step-RotationTest([long]$Now,[string]$Screen='automatic') {
    $script:schedulerClock.ElapsedMilliseconds=$Now
    $work=$script:rotation.Current
    if ($work) {
        $kind=if ($Screen -ne 'automatic') {$Screen} elseif ($work.Row.Process.PSObject.Properties['RotationForcedScreen']) {$work.Row.Process.RotationForcedScreen} elseif ($work.Phase -in @('menu','find','selection-up','click-activate','click')) {'menu'} else {'world'}
        $work.Row.Process | Add-Member NoteProperty LoginPointPresent ($kind -eq 'world') -Force
        $missingTarget=$work.Row.Process.PSObject.Properties['RotationMissingTarget'] -and $work.Row.Process.RotationMissingTarget
        $work.Row.Process.RotationScreen=[pscustomobject]@{Kind=$kind;RoleName=$work.Entry.Plan.Slots[$work.Entry.Index].Name;Targets=@(for ($slotIndex=0;$slotIndex -lt 3;$slotIndex++) {if ($work.Entry.Plan.Slots[$slotIndex].Name -and (-not $missingTarget -or $slotIndex -ne $work.Entry.Index)) {[pscustomobject]@{Name=$work.Entry.Plan.Slots[$slotIndex].Name;RawName=$work.Entry.Plan.Slots[$slotIndex].Name;MenuRow=($slotIndex+1);X=0.84;Y=(0.119+$slotIndex*0.0743)}}})}
        if ($work.Row.TaskMode -eq 'fight') {[WowAutoFight.Native]::Current.Flavor=$work.Row.Client.Flavor;[WowAutoFight.Native]::Current.ClassId=1}
    }
    $null=Invoke-RotationTick $Now
}
function Complete-RotationTest([ref]$Now) {
    $iterations=0
    while ((Test-RotationWorkPending) -and $iterations++ -lt 200) {Step-RotationTest $Now.Value;$Now.Value+=300}
    Assert-Ui ($iterations -lt 200) 'Rotation failed to finish.'
}
function Prepare-RotationTestBatch([ref]$Now,[int]$Count) {
    $clicks=@($script:rotation.Actions | Where-Object {$_.Action -eq 'tripleclick'}).Count
    $iterations=0
    while (($script:rotation.LogoutQueue.Count -or $script:rotation.Queue.Count -or
        ($script:rotation.Current -and $script:rotation.Current.Phase -in @('logout-activate','logout-inspect','logout-send','activate','menu','menu-logout','find'))) -and $iterations++ -lt 100) {
        Step-RotationTest $Now.Value;$Now.Value+=300
        Assert-Ui (@($script:rotation.Actions | Where-Object {$_.Action -eq 'tripleclick'}).Count -eq $clicks) 'Clicked a role before every process had a prepared position.'
    }
    Assert-Ui ($iterations -lt 100 -and -not $script:rotation.Current -and $script:rotation.ClickQueue.Count -eq $Count -and $script:rotation.LoginQueue.Count -eq 0) 'Position preparation did not finish as a separate batch.'
    foreach ($entry in @($script:rotation.ClickQueue.ToArray())) {
        Assert-Ui ($entry.PreparedTarget.ProcessKey -eq $entry.Row.Key -and $entry.PreparedSlot -eq $entry.Index -and
            $entry.PreparedTarget.Name -ceq $entry.Plan.Slots[$entry.Index].Name -and $entry.PreparedTarget.ClientSize.Width -gt 0) 'Prepared target lost process/slot/geometry identity.'
    }
}
function Click-RotationTestBatch([ref]$Now,[int]$Count) {
    $reads=0;foreach ($entry in @($script:rotation.ClickQueue.ToArray())) {$reads+=$entry.Row.Process.RotationOcrReads}
    $entries=@($script:rotation.ClickQueue.ToArray());$iterations=0
    $checkedCrossProcessGuard=$false
    while (($script:rotation.ClickQueue.Count -or ($script:rotation.Current -and $script:rotation.Current.Phase -in @('click-activate','click'))) -and $iterations++ -lt 60) {
        $at=$Now.Value;$before=@($script:rotation.Actions | Where-Object {$_.Action -eq 'tripleclick'}).Count
        Step-RotationTest $Now.Value;$Now.Value+=300
        foreach ($entry in $entries) {Assert-Ui (-not (Test-UnifiedTaskRunning $entry.Row)) 'Started a task before all prepared clicks completed.'}
        if ($Count -gt 1 -and -not $checkedCrossProcessGuard -and
            @($script:rotation.Actions | Where-Object {$_.Action -eq 'tripleclick'}).Count -gt $before) {
            $clicked=@($script:rotation.Actions | Where-Object {$_.Action -eq 'tripleclick'})[-1]
            $until=$script:rotation.ClickSwitch.Until
            Assert-Ui ($script:rotation.ClickSwitch.Key -eq $clicked.Key -and $until -eq $at+1000) 'Cross-process guard did not start when the third click finished.'
            Step-RotationTest ($until-1)
            Assert-Ui ($script:rotation.Current -and $script:rotation.Current.Row.Key -ne $clicked.Key -and
                $script:rotation.Current.Phase -eq 'click-activate' -and $script:rotation.Current.Due -eq $until -and
                @($script:rotation.Actions | Where-Object {$_.Action -eq 'tripleclick'}).Count -eq $before+1) 'Next process advanced before the one-second click guard elapsed.'
            Step-RotationTest $until
            Assert-Ui ($script:rotation.Current.Phase -eq 'click') 'Next process did not advance when the click guard expired.'
            $Now.Value=$until+300
            $checkedCrossProcessGuard=$true
        }
    }
    $after=0;foreach ($entry in $entries) {$after+=$entry.Row.Process.RotationOcrReads}
    Assert-Ui ($iterations -lt 60 -and -not $script:rotation.Current -and $script:rotation.LoginQueue.Count -eq $Count -and $after -eq $reads) 'Click batch performed OCR or waited for login before clicking every process.'
    if ($Count -gt 1) {
        Assert-Ui $checkedCrossProcessGuard 'Multi-process click guard was not exercised.'
        $lastClick=@($script:rotation.Actions | Where-Object {$_.Action -eq 'tripleclick'})[-1]
        $until=$script:rotation.ClickSwitch.Until
        Assert-Ui ($script:rotation.ClickSwitch.Key -eq $lastClick.Key -and $script:rotation.LoginQueue.Peek().Row.Key -ne $lastClick.Key) 'Login phase did not cross to another process.'
        Step-RotationTest ($until-1)
        Assert-Ui ($script:rotation.Current -and $script:rotation.Current.Phase -eq 'login-activate' -and
            $script:rotation.Current.Due -eq $until) 'Login confirmation changed process before the one-second guard elapsed.'
        Step-RotationTest $until
        Assert-Ui ($script:rotation.Current.Phase -eq 'login') 'Login confirmation did not resume when the guard expired.'
        $Now.Value=$until+300
    }
}
function Reach-RotationTestPhase($Row,[string]$Phase,[ref]$Now) {
    Stop-AllRows;$script:rotation.Actions=@();Start-Row $Row
    for ($i=0;$i -lt 80;$i++) {
        Step-RotationTest $Now.Value;$Now.Value+=300
        if ($script:rotation.Current -and $script:rotation.Current.Phase -eq $Phase) {return}
    }
    throw ('Did not reach rotation phase '+$Phase)
}
try {
    $script:mockProcesses=@($script:mockProcesses | Select-Object -First 2)
    foreach ($process in $script:mockProcesses) {
        $process.FocusAllowed=$true;$process.CommandAllowed=$true;$process.ScanColor='red'
        $process | Add-Member NoteProperty RotationScreen ([pscustomobject]@{Kind='world';RoleName=$null;Targets=@()}) -Force
        $process | Add-Member NoteProperty RotationOcrReads 0 -Force
        $process | Add-Member NoteProperty RotationFindReads 0 -Force
    }
    $null=Refresh-ProcessRows
    $clients=@($script:rows.Values | Sort-Object {$_.Process.Id});$a=$clients[0];$b=$clients[1]
    $accountFixture=Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-accounts-'+[Guid]::NewGuid())
    $savedRoots=$script:rotation.GameDirectories.Clone()
    foreach ($row in @($a,$b)) {
        $product=if ($row.Client.Flavor -eq 'titan') {'_classic_titan_'} else {'_cn_beta_'}
        $game=Join-Path $accountFixture $product;$script:rotation.GameDirectories[$row.Client.Flavor]=$game
        $row.Process.ExecutablePath=Join-Path $game ([IO.Path]::GetFileName($row.Process.ExecutablePath));$row.Client.ExecutablePath=$row.Process.ExecutablePath
        foreach ($name in @('双持船橘二咪','咆史呀嘞','小船长','持剑腕豪','测试新角色')) {[void][IO.Directory]::CreateDirectory((Join-Path $game ('WTF\Account\ACCOUNT#1\Realm\'+$name)))}
        [void][IO.Directory]::CreateDirectory((Join-Path $game 'WTF\Account\ACCOUNT#2\Realm\别的账号角色'))
    }
    $plan=New-RotationPlan;$plan | Add-Member NoteProperty Account 'ACCOUNT#1';$plan.Slots[0].UseItem=$true;$plan.Slots[0].Name='双持船橘二咪';$plan.Slots[2].Name='咆史呀嘞';$plan.Slots[2].Mode='fight'
    $single=New-RotationPlan;$single | Add-Member NoteProperty Account 'ACCOUNT#1';$single.Slots[1].Name='小船长'
    Assert-Ui ((Get-RotationNextSlot $plan -1) -eq 0 -and (Get-RotationNextSlot $plan 0) -eq 2 -and (Get-RotationNextSlot $plan 2) -eq 0) 'Empty slot not skipped/wrapped.'
    Assert-Ui ((Get-RotationNextSlot $single 1) -eq 1 -and (Get-RotationNextSlot (New-RotationPlan) -1) -eq -1) 'Single/all-empty slot behavior wrong.'
    $plans=@{};$plans[$a.Key]=$plan;$plans[$b.Key]=$single
    Save-RotationConfiguration 20 $plans
    $hash=(Get-FileHash $script:rotation.Path).Hash;$script:rotation.Plans=@{};Import-RotationConfiguration
    Assert-Ui ($script:rotation.ConfigReady -and $script:rotation.Plans[$a.Key].Slots[2].Name -ceq '咆史呀嘞' -and (Get-FileHash $script:rotation.Path).Hash -eq $hash) 'Saved rotation config did not reload read-only.'
    $locked=[IO.File]::Open($script:rotation.Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try {$failed=$false;try {Save-RotationConfiguration 30} catch {$failed=$true};Assert-Ui ($failed -and $script:rotation.IntervalSeconds -eq 20) 'Locked config applied interval.'} finally {$locked.Dispose()}
    Assert-Ui ($script:rotation.NameHistory -contains '双持船橘二咪' -and $script:rotation.NameHistory -contains '咆史呀嘞') 'Saved name history was not restored.'
    $draft=Copy-RotationPlan $plan;$draft.Slots[0].Name='错误 名称'
    $rejected=$false;try {Test-RotationPlan $draft} catch {$rejected=$true};Assert-Ui $rejected 'Whitespace in name accepted.'
    $draft.Slots[0].Name='/logout';$rejected=$false;try {Test-RotationPlan $draft} catch {$rejected=$true};Assert-Ui $rejected 'Command in name accepted.'
    $script:scheduler.CompletedCycles[$a.Key]=501;$script:scheduler.CyclesSinceJump[$a.Key]=5
    Update-RowAccountChoices $a;Update-RowAccountChoices $b
    $b.Validated=$false;Set-RowControls $b
    Assert-Ui (-not $b.DirectStart.Enabled) 'Direct start was enabled before detector validation.'
    $b.Validated=$true;Set-RowControls $b
    Assert-Ui ($b.DirectStart.Enabled) 'Validated planned row cannot start its current character directly.'
    $b.DirectStart.PerformClick()
    Assert-Ui ((Test-UnifiedTaskRunning $b) -and -not $script:rotation.Active.ContainsKey($b.Key) -and
        $script:rotation.LogoutQueue.Count -eq 0 -and $script:rotation.Queue.Count -eq 0 -and
        $script:rotation.Actions.Count -eq 0 -and $b.Process.RotationOcrReads -eq 0) 'Direct start entered character selection instead of starting the current task.'
    Stop-Row $b
    Assert-Ui ($b.Start.Enabled -and $b.DirectStart.Enabled) 'Stopping direct start did not restore both start choices.'
    Start-Row $a;Start-Row $b
    Assert-Ui ($script:rotation.Active.Count -eq 2 -and -not (Test-UnifiedTaskRunning $a) -and $script:rotation.NextAt -eq 20000) 'Start bypassed role selection or timers are not global.'
    $now=0L;$logoutSteps=0
    while (($script:rotation.LogoutQueue.Count -or ($script:rotation.Current -and $script:rotation.Current.Phase -like 'logout-*')) -and $logoutSteps++ -lt 20) {
        Step-RotationTest $now;$now+=300
    }
    Assert-Ui ($logoutSteps -lt 20 -and $script:rotation.LogoutQueue.Count -eq 0 -and
        ($script:rotation.Actions.Action -join ',') -eq 'logout,logout' -and
        ($script:rotation.Actions.Key -join ',') -eq "$($a.Key),$($b.Key)" -and $script:rotation.Queue.Count -eq 2 -and
        $a.Process.RotationOcrReads -eq 0 -and $b.Process.RotationOcrReads -eq 0) 'Started OCR/login before requesting logout from every process.'
    # The first window is still in the world while the second reaches character selection.
    # Its wait must yield so the second window can finish OCR, but neither may be clicked yet.
    $a.Process | Add-Member NoteProperty RotationForcedScreen 'world' -Force
    $b.Process | Add-Member NoteProperty RotationForcedScreen 'menu' -Force
    for ($i=0;$i -lt 70 -and -not $script:rotation.Active[$b.Key].PreparedTarget;$i++) {Step-RotationTest $now;$now+=300}
    Assert-Ui ($i -lt 70 -and $script:rotation.Active[$b.Key].PreparedTarget -and
        -not $script:rotation.Active[$a.Key].PreparedTarget -and $a.Process.RotationOcrReads -eq 0 -and
        $script:rotation.ClickQueue.Count -eq 1 -and
        -not @($script:rotation.Actions | Where-Object {$_.Action -eq 'tripleclick'}).Count) 'Ready process did not start OCR while another process was waiting to leave the world, or clicked before the barrier.'
    $a.Process.PSObject.Properties.Remove('RotationForcedScreen')
    $b.Process.PSObject.Properties.Remove('RotationForcedScreen')
    Prepare-RotationTestBatch ([ref]$now) 2
    Click-RotationTestBatch ([ref]$now) 2
    Assert-Ui (($script:rotation.Actions.Action -join ',') -eq 'logout,logout,tripleclick,tripleclick') 'All-process phase barriers or click order changed.'
    Complete-RotationTest ([ref]$now)
    Assert-Ui ((Test-UnifiedTaskRunning $a) -and (Test-UnifiedTaskRunning $b) -and (Get-WowAutoCycleCount $script:scheduler $a.Key) -eq 0 -and [long]$script:scheduler.CyclesSinceJump[$a.Key] -eq 0) 'Initial role login/task start or character counter reset failed.'
    Assert-Ui ($a.State.UseItem -and -not $b.State.UseItem) 'Initial per-slot item choices did not reach engine.'
    $actions=@($script:rotation.Actions | Where-Object {$_.Key -eq $a.Key})
    Assert-Ui (($actions.Action -join ',') -eq 'logout,tripleclick' -and $a.Process.RotationCursorParks -eq 0) 'First-page three-click selection failed or background OCR moved the cursor.'
    Assert-Ui ($actions[-1].Intervals.Count -eq 2 -and @($actions[-1].Intervals | Where-Object {$_ -ge 100 -and $_ -le 250}).Count -eq 2 -and $actions[-1].Target.MenuRow -eq 1) 'Three-click intervals or fixed role row were not prepared.'
    Assert-Ui (@($a.StatusHistory | Where-Object {$_ -match 'OCR角色列表：' -and $_ -match '第1个角色槽位 双持船橘二咪' -and $_ -match '第3个角色槽位 咆史呀嘞' -and $_ -match '已定位第1个角色槽位'}).Count -gt 0) 'OCR role list and selected row missing from status log.'
    $oldCount=$script:rotation.Actions.Count
    Step-RotationTest 19999
    Assert-Ui ($script:rotation.Actions.Count -eq $oldCount -and -not $script:rotation.Current) 'Switched before global deadline.'
    Step-RotationTest 20000
    Assert-Ui (-not (Test-UnifiedTaskRunning $a) -and -not (Test-UnifiedTaskRunning $b) -and $script:rotation.Active[$a.Key].Index -eq 2 -and $script:rotation.Active[$b.Key].Index -eq 1) 'Batch did not stop all tasks or cycle slots atomically.'
    $now=20300L;$logoutSteps=0
    $ocrBefore=$a.Process.RotationOcrReads+$b.Process.RotationOcrReads
    while (($script:rotation.LogoutQueue.Count -or ($script:rotation.Current -and $script:rotation.Current.Phase -like 'logout-*')) -and $logoutSteps++ -lt 20) {
        Step-RotationTest $now;$now+=300
    }
    Assert-Ui ($logoutSteps -lt 20 -and
        (@($script:rotation.Actions | Select-Object -Skip $oldCount -First 2 | ForEach-Object Action) -join ',') -eq 'logout,logout' -and
        $script:rotation.Queue.Count -eq 2 -and
        $a.Process.RotationOcrReads+$b.Process.RotationOcrReads -eq $ocrBefore) 'Timed batch selected a role before sending all logout requests.'
    Prepare-RotationTestBatch ([ref]$now) 2
    Click-RotationTestBatch ([ref]$now) 2
    Complete-RotationTest ([ref]$now)
    Assert-Ui (-not $a.SlotUseItem) 'Combat slot inherited fishing item.'
    Assert-Ui ($a.TaskMode -eq 'fight' -and $a.FightRow.Session -and $b.State.Running) 'Per-slot task modes not started.'
    Assert-Ui ($a.FightRow.Session.BuffIntervalSeconds -eq 120 -and $a.FightRow.Session.BuffCount -eq 2 -and
        $a.FightRow.Session.NextBuffAt -lt $now -and $a.FightRow.Session.BuffRemaining -eq 0) 'Rotation login did not arm the first per-class buff cycle.'
    $actions=@($script:rotation.Actions | Select-Object -Skip $oldCount | Where-Object {$_.Key -eq $b.Key})
    Assert-Ui (@($actions | Where-Object {$_.Action -eq 'logout'}).Count -eq 1 -and @($actions | Where-Object {$_.Action -eq 'tripleclick'}).Count -eq 1) 'Single configured character did not log out and log back in.'
    # Unknown screens and incomplete OCR never receive navigation, chat or task input.
    Stop-AllRows;$script:rotation.Actions=@();Start-Row $a
    Step-RotationTest 30000;Step-RotationTest 30300 'unknown';Step-RotationTest 30600 'unknown'
    Assert-Ui (-not $script:rotation.Actions.Count) 'Unknown screen received input.'
    Step-RotationTest 30900 'world';Step-RotationTest 31200 'world';Step-RotationTest 31500 'world';Step-RotationTest 31800 'unknown'
    Assert-Ui (($script:rotation.Actions.Action -join ',') -eq 'logout') 'Loading received navigation.'
    $script:editingSettings=$true;$before=$script:rotation.Actions.Count;Step-RotationTest 40000 'menu';$script:editingSettings=$false
    Assert-Ui ($script:rotation.Actions.Count -eq $before) 'Settings failed to pause orchestration.'
    Step-RotationTest $script:rotation.Current.Deadline 'unknown'
    Assert-Ui (-not $script:rotation.Active.ContainsKey($a.Key) -and -not (Test-UnifiedTaskRunning $a)) 'Timeout restarted work.'
    Start-Row $b;Step-RotationTest 211000;$script:workerFocus=-1;$b.Process.FocusAllowed=$false;Step-RotationTest 211300;Step-RotationTest 211600
    Assert-Ui ($script:rotation.Active.ContainsKey($b.Key) -and $script:rotation.Current.FocusUntil -eq 216600) 'First failed activation stopped rotation or missed the five-second deadline.'
    Step-RotationTest 211799
    Assert-Ui ($script:rotation.Active.ContainsKey($b.Key)) 'Rotation stopped before the next focus retry.'
    $b.Process.FocusAllowed=$true
    Step-RotationTest 211800
    Assert-Ui ($script:rotation.Active.ContainsKey($b.Key) -and $script:rotation.Current.Phase -eq 'logout-send') 'Temporary activation failure did not recover into the pending input stage.'

    Stop-AllRows;Start-Row $b;Step-RotationTest 212000;$script:workerFocus=-1;$b.Process.FocusAllowed=$false;Step-RotationTest 212300;Step-RotationTest 212600
    Step-RotationTest 217599
    Assert-Ui ($script:rotation.Active.ContainsKey($b.Key)) 'Rotation failed before five seconds of focus retries.'
    Step-RotationTest 217600
    Assert-Ui (-not $script:rotation.Active.ContainsKey($b.Key)) 'Persistent focus failure did not stop rotation after five seconds.'
    $b.Process.FocusAllowed=$true
    Stop-AllRows;$script:rotation.Actions=@();Start-Row $a;Stop-Row $a;Step-RotationTest 212000
    Assert-Ui (-not $script:rotation.Current -and -not $script:rotation.Actions.Count) 'Stopped queued work still ran.'
    # Starting in the menu only clicks the name visible on the first page.
    Stop-AllRows;$script:rotation.Actions=@();Start-Row $b
    Step-RotationTest 213000;Step-RotationTest 213300 'menu'
    $now=213600L
    for ($i=0;$i -lt 80 -and $script:rotation.Current.Phase -ne 'login';$i++) {Step-RotationTest $now;$now+=300}
    Assert-Ui ($script:rotation.Current.Phase -eq 'login') 'Initial menu did not reach login.'
    Assert-Ui (($script:rotation.Actions.Action -join ',') -eq 'tripleclick' -and $script:rotation.Actions[-1].Target.Name -ceq '小船长' -and $script:rotation.Actions[-1].Target.MenuRow -eq 2) 'Menu login scrolled or missed the first-page name.'
    $before=$script:rotation.Actions.Count
    Step-RotationTest $now 'unknown';$now+=300;Step-RotationTest $now 'pending';$now+=300
    Assert-Ui (-not $b.State.Running -and $script:rotation.Actions.Count -eq $before) 'Loading used a readiness color/chat request or started work.'
    Complete-RotationTest ([ref]$now)
    Assert-Ui $b.State.Running 'Permanent login point did not start task.'
    $deadline=$script:rotation.NextAt;Save-RotationConfiguration 20
    Assert-Ui ($script:rotation.NextAt -eq $deadline) 'Saving unchanged interval reset global deadline.'
    Save-RotationConfiguration 0
    Assert-Ui ($script:rotation.NextAt -eq 0 -and $b.State.Running -and $script:rotation.Active.Count -eq 1) 'Disabling timer stopped current role or retained deadline.'
    Save-RotationConfiguration 20;Stop-AllRows
    $b.Process.CommandAllowed=$false;Start-Row $b;$now=220000L;Complete-RotationTest ([ref]$now)
    Assert-Ui (-not $script:rotation.Active.ContainsKey($b.Key) -and -not (Test-UnifiedTaskRunning $b)) 'Failed monitor command started character task.'
    $b.Process.CommandAllowed=$true
    # Partial/duplicate names cannot receive character clicks; login uses the point, never OCR names.
    $now=230000L;Reach-RotationTestPhase $a 'find' ([ref]$now)
    $a.Process.RotationScreen=[pscustomobject]@{Kind='menu';RoleName=$null;Targets=@([pscustomobject]@{Name='双持船橘二';X=0.84;Y=0.2})}
    $script:schedulerClock.ElapsedMilliseconds=$now;$null=Invoke-RotationTick $now;$now+=300
    Assert-Ui ($script:rotation.Active.ContainsKey($a.Key) -and $script:rotation.Current.Phase -eq 'selection-up' -and
        -not @($script:rotation.Actions | Where-Object {$_.Action -eq 'tripleclick'}).Count) 'Partial/no-progress search clicked a role before the retry.'
    $now=240000L;Reach-RotationTestPhase $a 'find' ([ref]$now)
    $a.Process.RotationScreen=[pscustomobject]@{Kind='menu';RoleName=$null;Targets=@(1..2 | ForEach-Object {[pscustomobject]@{Name='双持船橘二咪';X=0.84;Y=0.2}})}
    $script:schedulerClock.ElapsedMilliseconds=$now;$null=Invoke-RotationTick $now
    Assert-Ui (-not $script:rotation.Active.ContainsKey($a.Key)) 'Duplicate names did not stop selection.'
    $now=250000L;Reach-RotationTestPhase $a 'login' ([ref]$now)
    $a.Process.RotationScreen=[pscustomobject]@{Kind='world';RoleName='咆史呀嘞';Targets=@()}
    $a.Process.LoginPointPresent=$false;$reads=$a.Process.RotationOcrReads
    $script:schedulerClock.ElapsedMilliseconds=$now;$null=Invoke-RotationTick $now;$now+=300
    Assert-Ui ($script:rotation.Current.Phase -eq 'login' -and -not (Test-UnifiedTaskRunning $a) -and $a.Process.RotationOcrReads -eq $reads) 'Login used OCR or started without the point.'
    Complete-RotationTest ([ref]$now)
    Assert-Ui ((Test-UnifiedTaskRunning $a) -and $a.Process.RotationOcrReads -eq $reads) 'Login/enable stages ran OCR or failed to use the point.'
    # Embedded settings and editor use isolated drafts; saves require atomic persistence.
    $dialog=New-RotationEditor $a
    try {
        Assert-Ui ($dialog.Tag.Slots[0].Name -is [System.Windows.Forms.ComboBox] -and $dialog.Tag.Slots[0].Name.DropDownStyle -eq 'DropDown' -and $dialog.Tag.Slots[0].Name.Items.Contains('双持船橘二咪') -and -not $dialog.Tag.Slots[0].Name.Items.Contains('别的账号角色')) 'Editable account dropdown missing.'
        $dialog.Tag.Slots[0].Name.Text='持剑腕豪';Assert-Ui ($script:rotation.Plans[$a.Key].Slots[0].Name -ceq '双持船橘二咪') 'Editor draft leaked.'
        if ($env:WOWAUTO_UNIFIED_PREVIEW_DIRECTORY) {
            $dialog.Show($form);[System.Windows.Forms.Application]::DoEvents()
            $image=New-Object Drawing.Bitmap($dialog.Width,$dialog.Height)
            try {$dialog.DrawToBitmap($image,(New-Object Drawing.Rectangle(0,0,$image.Width,$image.Height)));$image.Save((Join-Path $env:WOWAUTO_UNIFIED_PREVIEW_DIRECTORY 'rotation-editor.png'),[Drawing.Imaging.ImageFormat]::Png)} finally {$image.Dispose()}
        }
    } finally {$dialog.Dispose()}
    # Exercise actual save/cancel and a locked config with an editable history combo.
    $savedPlans=$script:rotation.Plans.Clone()
    $historyBefore=($script:rotation.NameHistory -join '|')
    $dialog=New-RotationEditor $a
    try {
        $dialog.Show($form);[System.Windows.Forms.Application]::DoEvents()
        $dialog.Tag.Slots[0].Name.SelectedItem='小船长'
        Assert-Ui ($dialog.Tag.Slots[0].Name.Text -ceq '小船长') 'History selection did not fill the editable field.'
        $dialog.Tag.Slots[0].Name.Text='测试新角色';$dialog.Tag.Slots[0].Mode.SelectedIndex=1
        $locked=[IO.File]::Open($script:rotation.Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
        try {$dialog.Tag.Save.PerformClick()} finally {$locked.Dispose()}
        Assert-Ui ($dialog.Visible -and ($script:rotation.NameHistory -join '|') -ceq $historyBefore -and $script:rotation.Plans[$a.Key].Slots[0].Name -ceq '双持船橘二咪') 'Failed save applied draft/history.'
        $dialog.Tag.Save.PerformClick()
        Assert-Ui (-not $dialog.Visible -and $script:rotation.NameHistory -contains '测试新角色' -and $a.TaskMode -eq 'fight' -and -not $a.Validated) 'Saved role name/history did not select its task mode.'
    } finally {$dialog.Dispose()}
    Save-RotationConfiguration -Plans $savedPlans
    Set-RowTaskMode $a fish
    $script:rotation.NameHistory=@();Import-RotationConfiguration
    Assert-Ui ($script:rotation.NameHistory -contains '测试新角色') 'Removed slot name was not retained after reload.'
    $dialog=New-RotationEditor $a
    try {
        $dialog.Show($form);[System.Windows.Forms.Application]::DoEvents()
        Assert-Ui ($dialog.Tag.Slots[1].Name.Items.Contains('测试新角色')) 'Reopened dropdown lost a historical name.'
        $dialog.Tag.Slots[0].Name.Text='取消的新名字';$dialog.Close()
        Assert-Ui ($script:rotation.NameHistory -notcontains '取消的新名字' -and $script:rotation.Plans[$a.Key].Slots[0].Name -ceq '双持船橘二咪') 'Cancel remembered an unsaved name.'
    } finally {$dialog.Dispose()}
    $dialog=New-UnifiedSettingsDialog
    try {
        $dialog.Show($form);[System.Windows.Forms.Application]::DoEvents()
        Assert-Ui ($dialog.Tag.Rotation.Value.Value -eq 20 -and $dialog.Tag.Tabs.TabPages.Count -eq 3 -and $dialog.Tag.Tabs.Top -ge 52) 'Global interval missing/covered or settings tabs changed.'
    } finally {$dialog.Dispose()}
    # Bag-full exclusion is per process and per character, independent of reel count.
    Stop-AllRows
    $fishPlans=$script:rotation.Plans.Clone();$fishPlan=Copy-RotationPlan $fishPlans[$a.Key]
    $fishPlan.Slots[2].Mode='fish';$fishPlans[$a.Key]=$fishPlan
    Save-RotationConfiguration -Plans $fishPlans
    $duplicate=Copy-RotationPlan $fishPlan;$duplicate.Slots[2].Name=$duplicate.Slots[0].Name
    Assert-Ui ((Get-RotationNextSlot $duplicate 0 @($duplicate.Slots[0].Name)) -eq -1) 'Duplicate slots did not exclude the entire full character.'
    Start-Row $a;Start-Row $b
    $now=300000L;Complete-RotationTest ([ref]$now)
    $closedBefore=$script:workerClosed.Count
    $script:scheduler.CompletedCycles[$a.Key]=501
    Close-WorkerGame $a
    Assert-Ui ($script:rotation.Active.ContainsKey($a.Key) -and $script:rotation.Active[$a.Key].Index -eq 2 -and
        $script:rotation.Active[$a.Key].ExcludedNames -ccontains '双持船橘二咪' -and $script:rotation.LogoutQueue.Count -gt 0 -and
        -not $a.State.Running -and $b.State.Running -and $script:workerClosed.Count -eq $closedBefore -and
        -not $script:pendingGameExits.ContainsKey($a.Key)) 'One full character closed its process or stopped another row.'
    Complete-RotationTest ([ref]$now)
    Assert-Ui ($a.State.Running -and $script:rotation.Active[$a.Key].Index -eq 2 -and
        (Get-WowAutoCycleCount $script:scheduler $a.Key) -eq 0 -and $script:rotation.Plans[$a.Key].Slots[0].Name -ceq '双持船橘二咪') 'Remaining character did not start or runtime exclusion changed saved plan.'
    $batchAt=$script:rotation.NextAt;Step-RotationTest $batchAt
    Assert-Ui ($script:rotation.Active[$a.Key].Index -eq 2) 'Global batch selected the excluded character.'
    $now=$batchAt+300;Complete-RotationTest ([ref]$now)
    $script:scheduler.CompletedCycles[$a.Key]=0
    Close-WorkerGame $a '角色死亡'
    Assert-Ui (-not $script:rotation.Active.ContainsKey($a.Key) -and $script:pendingGameExits.ContainsKey($a.Key) -and
        $script:workerClosed.Count -eq $closedBefore+1 -and $b.State.Running) 'Final dead character after bag exclusion did not close only its own process.'
    Stop-AllRows;Save-RotationConfiguration -Plans $savedPlans
    # Death is terminal for the current runtime character, in either detector mode.
    $deathPlanHash=(Get-FileHash $script:rotation.Path).Hash
    Start-Row $a;Start-Row $b
    $now=330000L;Complete-RotationTest ([ref]$now)
    $closedBefore=$script:workerClosed.Count;$keysBefore=$script:workerKeys.Count
    $a.State.Mode='Wait';$a.State.UseAudio=$true;$a.State.DeathCheckAt=$now+1000
    $a.Process.ScanColor='dead'
    Invoke-FishingDeathChecks ($now+999)
    Assert-Ui ($script:rotation.Active[$a.Key].Index -eq 0 -and $a.State.Running) 'Death poll ignored its one-second schedule.'
    $now+=1000;$script:schedulerClock.ElapsedMilliseconds=$now
    Invoke-FishingDeathChecks $now
    Assert-Ui ($script:rotation.Active[$a.Key].Index -eq 2 -and
        $script:rotation.Active[$a.Key].ExcludedNames -ccontains '双持船橘二咪' -and
        -not $a.State.Running -and $b.State.Running -and $script:workerClosed.Count -eq $closedBefore -and
        $script:workerKeys.Count -eq $keysBefore) 'Fishing death during audio wait failed to skip one role without input or affecting another process.'
    $a.Process.ScanColor='red';Complete-RotationTest ([ref]$now)
    Assert-Ui ($a.TaskMode -eq 'fight' -and $a.FightRow.Session) 'Remaining combat role did not start after fishing death.'
    $sendsBefore=[WowAutoFight.Native]::Sends
    [WowAutoFight.Native]::Current.Action='dead';[WowAutoFight.Native]::Current.Combat=$false
    [WowAutoFight.Native]::Current.Busy=$false;[WowAutoFight.Native]::Current.Recovery='none'
    [WowAutoFight.Native]::Current.Flavor=$a.Client.Flavor
    [WowAutoFight.Native]::Current.ClassId=$a.FightRow.Session.ClassId
    $script:schedulerClock.ElapsedMilliseconds=$now;$a.FightRow.Session.Due=$now;$script:autoFight.Pending=$null
    Invoke-AutoFightTick -PlanOnly
    Assert-Ui (-not $script:rotation.Active.ContainsKey($a.Key) -and $script:pendingGameExits.ContainsKey($a.Key) -and
        $b.State.Running -and $script:workerClosed.Count -eq $closedBefore+1 -and
        [WowAutoFight.Native]::Sends -eq $sendsBefore -and (Get-FileHash $script:rotation.Path).Hash -eq $deathPlanHash) 'Combat death did not exhaust only its own process or changed saved plans/sent an attack.'
    [WowAutoFight.Native]::Current.Action='idle'
    # Unknown pixels are not death, and a directly-started unplanned role only stops.
    $b.Process.ScanColor='unknown';$b.State.DeathCheckAt=0
    Invoke-FishingDeathChecks ($now+1000)
    Assert-Ui ($b.State.Running -and $script:rotation.Active[$b.Key].ExcludedNames.Count -eq 0) 'Unknown fishing pixels excluded a live character.'
    Stop-AllRows;$b.Process.ScanColor='red';$b.Validated=$true;Start-Row $b -TaskOnly
    $b.Process.ScanColor='dead';$closedBefore=$script:workerClosed.Count
    Invoke-FishingDeathChecks ($now+2000)
    Assert-Ui (-not (Test-UnifiedTaskRunning $b) -and -not $script:pendingGameExits.ContainsKey($b.Key) -and
        $script:workerClosed.Count -eq $closedBefore) 'Death without an active rotation closed the process.'
    $b.Process.ScanColor='red';Stop-AllRows
    # A role can already be dead when its post-login monitor is enabled.
    foreach ($deathMode in @('fish','fight')) {
        $deathPlans=$savedPlans.Clone();$deathPlan=Copy-RotationPlan $deathPlans[$a.Key]
        $deathPlan.Slots[0].Mode=$deathMode;$deathPlans[$a.Key]=$deathPlan
        Save-RotationConfiguration -Plans $deathPlans
        $now=335000L;Reach-RotationTestPhase $a 'validate' ([ref]$now)
        if ($deathMode -eq 'fish') {$a.Process.ScanColor='dead'} else {[WowAutoFight.Native]::Current.Action='dead'}
        for ($attempt=0;$attempt -lt 8 -and $script:rotation.Active[$a.Key].Index -eq 0;$attempt++) {
            Step-RotationTest $now;$now+=300
        }
        Assert-Ui ($script:rotation.Active[$a.Key].Index -eq 2 -and
            $script:rotation.Active[$a.Key].ExcludedNames -ccontains $deathPlan.Slots[0].Name -and
            -not (Test-UnifiedTaskRunning $a)) 'Death during post-login validation did not skip the role.'
        $a.Process.ScanColor='red';[WowAutoFight.Native]::Current.Action='idle';Stop-AllRows
    }
    Save-RotationConfiguration -Plans $savedPlans
    # Yellow during post-login validation must also skip that role, not wait until timeout.
    $now=340000L;Reach-RotationTestPhase $a 'validate' ([ref]$now)
    $a.Process.ScanColor='yellow'
    for ($attempt=0;$attempt -lt 8 -and $script:rotation.Active.ContainsKey($a.Key) -and $script:rotation.Active[$a.Key].Index -ne 2;$attempt++) {
        Step-RotationTest $now;$now+=300
    }
    Assert-Ui ($script:rotation.Active.ContainsKey($a.Key) -and $script:rotation.Active[$a.Key].Index -eq 2 -and
        $script:rotation.LogoutQueue.Count -gt 0 -and -not $script:rotation.Current) 'Full bag during validation did not skip to the next role.'
    $a.Process.ScanColor='red';Stop-AllRows
    # Geometry changes beyond 5% after preparation must return to OCR.
    $now=350000L;Reach-RotationTestPhase $a 'click' ([ref]$now)
    $cached=$script:rotation.Current.Entry.PreparedTarget;$deadline=$script:rotation.Current.Deadline
    $a.Process | Add-Member NoteProperty RotationWidth 900 -Force
    Step-RotationTest $now;$now+=300
    Assert-Ui (-not $script:rotation.Current -and $script:rotation.Queue.Count -eq 1 -and
        -not $script:rotation.Active[$a.Key].PreparedTarget -and
        -not @($script:rotation.Actions | Where-Object {$_.Action -eq 'tripleclick'}).Count) 'Resized window used cached coordinates.'
    Prepare-RotationTestBatch ([ref]$now) 1
    $prepared=$script:rotation.ClickQueue.Peek()
    Assert-Ui ($prepared.PreparedTarget.ClientSize.Width -eq 900 -and $cached.ClientSize.Width -eq 800 -and $prepared.SelectionDeadline -ge $deadline) 'Resize did not replace its snapshot or preserve the OCR stall deadline.'
    Click-RotationTestBatch ([ref]$now) 1;Complete-RotationTest ([ref]$now)
    $a.Process.PSObject.Properties.Remove('RotationWidth')
    # Geometry validation reads system metadata only; OCR fields and position do not participate.
    $now=360000L;Reach-RotationTestPhase $a 'click' ([ref]$now)
    $target=$script:rotation.Current.Entry.PreparedTarget
    $a.Process | Add-Member NoteProperty RotationLeft (-1920) -Force
    $a.Process | Add-Member NoteProperty RotationTop 300 -Force
    $ocrReads=$a.Process.RotationOcrReads;$sizeReads=$a.Process.RotationSizeReads
    $a.Process.RotationScreen=[pscustomobject]@{Kind='unknown';Targets=@();Width=1;Height=1}
    Assert-Ui ((Test-RotationTargetSnapshot $a $target) -and $a.Process.RotationSizeReads -eq $sizeReads+1 -and
        $a.Process.RotationOcrReads -eq $ocrReads) 'Size validation used OCR or invalidated a moved window.'
    # Both axes must stay within the original size's inclusive 5% range.
    foreach ($sizeCase in @(
        [pscustomobject]@{Width=801;Height=501;Valid=$true}
        [pscustomobject]@{Width=840;Height=525;Valid=$true}
        [pscustomobject]@{Width=864;Height=525;Valid=$false}
        [pscustomobject]@{Width=760;Height=475;Valid=$true}
        [pscustomobject]@{Width=841;Height=500;Valid=$false}
        [pscustomobject]@{Width=759;Height=500;Valid=$false}
        [pscustomobject]@{Width=800;Height=526;Valid=$false}
        [pscustomobject]@{Width=800;Height=474;Valid=$false}
        [pscustomobject]@{Width=0;Height=500;Valid=$false}
        [pscustomobject]@{Width=800;Height=0;Valid=$false}
    )) {
        $a.Process | Add-Member NoteProperty RotationWidth $sizeCase.Width -Force
        $a.Process | Add-Member NoteProperty RotationHeight $sizeCase.Height -Force
        Assert-Ui ((Test-RotationTargetSnapshot $a $target) -eq $sizeCase.Valid) ('Unexpected size tolerance result: '+$sizeCase.Width+'x'+$sizeCase.Height)
    }
    Assert-Ui ($target.ClientSize.Width -eq 800 -and $target.ClientSize.Height -eq 500) 'Tolerance checks changed the original cached size.'
    $a.Process.RotationWidth=840;$a.Process.RotationHeight=525
    Step-RotationTest $now;$now+=300
    Assert-Ui (@($script:rotation.Actions | Where-Object {$_.Action -eq 'tripleclick'}).Count -eq 1 -and
        $a.Process.RotationOcrReads -eq $ocrReads) 'Size changes within 5% did not reuse prepared coordinates.'
    $a.Process.PSObject.Properties.Remove('RotationWidth');$a.Process.PSObject.Properties.Remove('RotationHeight')
    $a.Process.PSObject.Properties.Remove('RotationLeft');$a.Process.PSObject.Properties.Remove('RotationTop')
    Complete-RotationTest ([ref]$now)
    # Stopping a row with prepared coordinates removes only that row's later stages.
    Stop-AllRows;$script:rotation.Actions=@();Start-Row $a;Start-Row $b;$now=370000L
    Prepare-RotationTestBatch ([ref]$now) 2
    $stoppedEntry=$script:rotation.Active[$a.Key]
    Stop-Row $a
    Assert-Ui ($script:rotation.ClickQueue.Count -eq 1 -and -not $stoppedEntry.PreparedTarget -and
        $stoppedEntry.PreparedSlot -eq -1 -and $script:rotation.Active.ContainsKey($b.Key)) 'Stopping cached work retained a click or removed another process.'
    Click-RotationTestBatch ([ref]$now) 1;Complete-RotationTest ([ref]$now)
    Assert-Ui (-not @($script:rotation.Actions | Where-Object {$_.Key -eq $a.Key -and $_.Action -eq 'tripleclick'}).Count -and $b.State.Running) 'Stopped cached target was clicked after another process resumed.'
    Stop-AllRows
    # A selected-row highlight can hide the configured name from OCR. Shift the
    # selection once, then require fresh OCR and the usual two stable positions.
    $script:rotation.Actions=@();$now=380000L
    Reach-RotationTestPhase $a 'find' ([ref]$now)
    $a.Process | Add-Member NoteProperty RotationMissingTarget $true -Force
    $findReadsBefore=$a.Process.RotationFindReads
    Step-RotationTest $now;$now+=300
    Assert-Ui ($script:rotation.Current.Phase -eq 'selection-up' -and
        $a.Process.RotationFindReads-$findReadsBefore -eq 1 -and
        -not @($script:rotation.Actions | Where-Object {$_.Action -eq 'up' -or $_.Action -eq 'tripleclick'}).Count) 'One missing-name OCR did not immediately queue Up.'
    for ($attempt=0;$attempt -lt 20 -and -not @($script:rotation.Actions | Where-Object {$_.Action -eq 'up'}).Count;$attempt++) {Step-RotationTest $now;$now+=300}
    Assert-Ui ($attempt -lt 20 -and $script:rotation.Current.Phase -eq 'find' -and
        @($script:rotation.Actions | Where-Object {$_.Action -eq 'up'}).Count -eq 1 -and
        $a.Process.RotationFindReads-$findReadsBefore -eq 1) 'Selected-name retry read OCR before the Up key or pressed it twice.'
    $a.Process.RotationMissingTarget=$false
    # Sparse completed OCR samples extend the stall deadline while retries progress.
    $now+=60000;Step-RotationTest $now
    $now+=60000;Step-RotationTest $now;$now+=300
    Prepare-RotationTestBatch ([ref]$now) 1
    Assert-Ui ($a.Process.RotationFindReads-$findReadsBefore -eq 3 -and
        $script:rotation.ClickQueue.Peek().PreparedTarget.Name -ceq $plan.Slots[0].Name -and
        $script:rotation.ClickQueue.Peek().PreparedTarget.MenuRow -eq 1) 'Retry used a stale or wrong character position.'
    Click-RotationTestBatch ([ref]$now) 1;Complete-RotationTest ([ref]$now)
    Assert-Ui ((@($script:rotation.Actions | Where-Object {$_.Action -eq 'up'}).Count) -eq 1 -and
        (@($script:rotation.Actions | Where-Object {$_.Action -eq 'tripleclick'}).Count) -eq 1) 'Recovered selection repeated Up or role clicks.'
    Stop-AllRows;$script:rotation.Actions=@();$now+=10000
    Reach-RotationTestPhase $a 'find' ([ref]$now)
    $a.Process.RotationMissingTarget=$true
    $retryEntry=$script:rotation.Active[$a.Key]
    $findReadsBefore=$a.Process.RotationFindReads
    $closedBefore=$script:workerClosed.Count
    $requeued=$false
    for ($attempt=0;$attempt -lt 300 -and -not $script:pendingGameExits.ContainsKey($a.Key);$attempt++) {
        Step-RotationTest $now;$now+=300
        if (-not $requeued -and $retryEntry.RecognitionRetries -eq 10 -and
            $script:rotation.Current -and $script:rotation.Current.Phase -eq 'find') {
            Retry-RotationRecognition $script:rotation.Current '模拟窗口尺寸变化'
            $requeued=$true
        }
        if ($retryEntry.RecognitionRetries -lt 30) {
            Assert-Ui (-not $script:pendingGameExits.ContainsKey($a.Key)) 'OCR retries closed the process before 30 Up presses.'
        }
    }
    Assert-Ui ($attempt -lt 300 -and $requeued -and $retryEntry.RecognitionRetries -eq 30 -and
        $a.Process.RotationFindReads-$findReadsBefore -eq 31 -and
        -not $script:rotation.Active.ContainsKey($a.Key) -and $script:pendingGameExits.ContainsKey($a.Key) -and
        (@($script:rotation.Actions | Where-Object {$_.Action -eq 'up'}).Count) -eq 30 -and
        -not @($script:rotation.Actions | Where-Object {$_.Action -eq 'tripleclick'}).Count -and
        $script:workerClosed.Count -eq $closedBefore+1 -and $script:workerClosed[-1] -eq $a.Process.Id -and
        $script:pendingGameExits[$a.Key].Reason -match '30次') 'Permanent OCR miss did not close only its process after 30 cumulative Up retries.'
    $a.Process.PSObject.Properties.Remove('RotationMissingTarget')
    Stop-AllRows
    $a.Process.StartTime=$a.Process.StartTime.AddSeconds(1);$null=Refresh-ProcessRows
    $replacement=@($script:rows.Values | Where-Object {$_.Process.Id -eq $a.Process.Id})[0]
    Assert-Ui (-not (Test-RowHasRotation $replacement)) 'Reused PID inherited character plan.'
    Assert-Ui ([WowAuto.NativeInput]::RotationCommand('logout',0) -eq '/logout') 'Logout command mapping wrong.'
    foreach ($action in @('arm','probe','delete')) {
        $failed=$false;try {$null=[WowAuto.NativeInput]::RotationCommand($action,77)} catch {$failed=$true};Assert-Ui $failed 'Removed/arbitrary command accepted.'
    }
    # Classify real-shaped OCR output, using both spatial anchors and exact names.
    $ocr=[pscustomobject]@{Lines=@([pscustomobject]@{Text='选择服务器';X=0.82;Y=0.07;W=0.10;H=0.02},[pscustomobject]@{Text='进入魔兽世界';X=0.44;Y=0.93;W=0.13;H=0.02});Names=@(
        [pscustomobject]@{Text='双持船橘二咪';X=0.10;Y=0.20;W=0.25;H=0.02})}
    $screen=ConvertFrom-RotationOcr $ocr $plan
    Assert-Ui ($screen.Kind -eq 'menu' -and $screen.Targets[0].Name -ceq '双持船橘二咪' -and $screen.Targets[0].X -gt 0.79) 'OCR anchors did not localize configured name.'
    $ocr | Add-Member NoteProperty NamesBounds ([pscustomobject]@{X=0.70;Y=0;W=0.30;H=0.84})
    $mapped=ConvertFrom-RotationOcr $ocr $plan
    Assert-Ui ([Math]::Abs($mapped.Targets[0].X-0.85) -lt 0.00001 -and $mapped.Targets[0].MenuRow -eq 2 -and
        [Math]::Abs($mapped.Targets[0].Y-(0.119+0.0743)) -lt 0.00001) 'OCR name did not map to the fixed second character row.'
    Assert-Ui ((Get-RotationOcrLog $mapped '双持船橘二咪') -match '第2个角色槽位 双持船橘二咪；已定位第2个角色槽位') 'OCR log omitted the identified click row.'
    $ocr.Names[0].Text='双持船橘二咩'
    $corrected=ConvertFrom-RotationOcr $ocr $plan
    Assert-Ui ((Get-RotationOcrLog $corrected '双持船橘二咪') -match '双持船橘二咩→双持船橘二咪') 'OCR log concealed the original misread name.'
    $ocr.Names[0].Text='双持船橘二咪'
    $ocr.Names[0].X=0.30;$ocr.Names[0].W=0.10
    $otherWordBox=ConvertFrom-RotationOcr $ocr $plan
    Assert-Ui ($otherWordBox.Targets[0].X -eq $mapped.Targets[0].X -and $otherWordBox.Targets[0].Y -eq $mapped.Targets[0].Y) 'Character click moved with OCR word-box width.'
    $ocr.PSObject.Properties.Remove('NamesBounds')
    $anchors=$ocr.Lines
    $ocr.Lines=@($anchors[0]);Assert-Ui ((ConvertFrom-RotationOcr $ocr $plan).Kind -eq 'menu') 'Server anchor alone was rejected.'
    $ocr.Lines=@($anchors[1]);Assert-Ui ((ConvertFrom-RotationOcr $ocr $plan).Kind -eq 'menu') 'Enter-world anchor alone was rejected.'
    $ocr.Names=@();Assert-Ui ((ConvertFrom-RotationOcr $ocr $plan).Kind -eq 'menu') 'Recognized anchor without names was rejected.'
    $ocr.Names=@([pscustomobject]@{Text='双持船橘二咪';X=0.10;Y=0.20;W=0.25;H=0.02})
    $ocr.Lines=@();Assert-Ui ((ConvertFrom-RotationOcr $ocr $plan).Kind -eq 'unknown') 'Name alone accepted as menu.'
    $ocr.Lines=@([pscustomobject]@{Text='选择服务器';X=0.82;Y=0.07;W=0.10;H=0.02},[pscustomobject]@{Text='进入魔兽世界';X=0.44;Y=0.93;W=0.13;H=0.02});$ocr.Names[0].Text='双持船橘二'
    Assert-Ui (-not @((ConvertFrom-RotationOcr $ocr $plan).Targets | Where-Object {$_.Name -ceq '双持船橘二咪'}).Count) 'Partial name accepted as exact target.'
    $ocr.Lines=@([pscustomobject]@{Text='100%';X=0.04;Y=0.03},[pscustomobject]@{Text='开怪：未记录';X=0.01;Y=0.25},[pscustomobject]@{Text='1双持船橘二咪';X=0.04;Y=0.32});$ocr.Names=@()
    $screen=ConvertFrom-RotationOcr $ocr $plan
    Assert-Ui ($screen.Kind -eq 'unknown') 'Removed HUD login recognition is still active.'
    $bitmap=New-Object Drawing.Bitmap(800,500)
    try {
        $graphics=[Drawing.Graphics]::FromImage($bitmap)
        try {$graphics.Clear([Drawing.Color]::FromArgb(97,231,157))} finally {$graphics.Dispose()}
        Assert-Ui ([WowAutoRotation.Native]::Png($bitmap).Length -gt 0 -and [WowAutoRotation.Native]::NamesPng($bitmap).Length -gt 0) 'Pure OCR preprocessing failed.'
    } finally {$bitmap.Dispose()}
    $point=New-Object Drawing.Bitmap(16,16)
    try {
        $g=[Drawing.Graphics]::FromImage($point)
        try {$g.Clear([Drawing.Color]::White)} finally {$g.Dispose()}
        Assert-Ui ([WowAutoRotation.Native]::HasLoginPoint($point)) 'Solid white login point rejected.'
        $point.SetPixel(8,8,[Drawing.Color]::Black)
        Assert-Ui (-not [WowAutoRotation.Native]::HasLoginPoint($point)) 'Non-solid point accepted.'
    } finally {$point.Dispose()}
    foreach ($p in $sourceHashes.Keys) {Assert-Ui ((Get-FileHash $p).Hash -eq $sourceHashes[$p]) 'Tests changed real user configuration.'}
    Write-Output 'PASS: name/empty/single/wrap slots, ready-window OCR while another window awaits the menu, all-position preparation before clicks and all-clicks before login checks, independent system-size validation without OCR or position comparison, width/height resize/re-recognition and stopped-cache cancellation, shared deadline/all-stop batch, first-page three-click selection with precomputed random intervals and OCR row logs, foreground Up retry for a highlighted missing name, process exit after 30 unsuccessful Up retries, either menu anchor, partial/duplicate rejection, permanent-point login/no OCR after selection/loading/pending/focus/timeout/stop/settings isolation, per-role fish/fight, one-second death checks during fishing waits, combat/validation death exclusion and exhausted-only exit, counter reset, atomic drafts and PID reuse. All game input and OCR mocked.'
} finally {
    Stop-AllRows;Close-AutoFightTab
    if ([IO.File]::Exists($script:rotation.Path)) {[IO.File]::Delete($script:rotation.Path)}
    $script:rotation.Path=$oldRotationPath
    if ($savedRoots) {$script:rotation.GameDirectories=$savedRoots}
    if ($accountFixture) {
        $cleanup=[IO.Path]::GetFullPath($accountFixture)
        if (-not $cleanup.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $cleanup -Leaf) -notlike 'wowAuto-accounts-*') {throw 'Unsafe temporary fixture cleanup path.'}
        if ([IO.Directory]::Exists($cleanup)) {[IO.Directory]::Delete($cleanup,$true)}
    }
}
