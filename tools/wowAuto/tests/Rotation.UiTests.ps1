# Real orchestration functions, mock clients/screens/inputs, temporary configuration only.
Stop-AllRows
Initialize-AutoFightTab $tabs $form -Unified
$sourceRotation=Join-Path (Split-Path $PSScriptRoot -Parent) 'rotation.config.json'
$sourceHashes=@{}
foreach ($p in @($sourceRotation,(Join-Path (Split-Path $PSScriptRoot -Parent) 'config.ini'),(Join-Path (Split-Path $PSScriptRoot -Parent) 'autoFight.config.json'))) {$sourceHashes[$p]=(Get-FileHash $p).Hash}
$oldRotationPath=$script:rotation.Path
$script:rotation.Path=Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-rotation-'+[Guid]::NewGuid()+'.json')
$script:rotation.Plans=@{};$script:rotation.IntervalSeconds=0;$script:rotation.Active.Clear();$script:rotation.Queue.Clear();$script:rotation.Current=$null
$script:scheduler=New-WowAutoScheduler;$script:schedulerClock=[pscustomobject]@{ElapsedMilliseconds=0L};$script:autoFight.Clock=$script:schedulerClock
function Step-RotationTest([long]$Now,[string]$Screen='automatic') {
    $script:schedulerClock.ElapsedMilliseconds=$Now
    $work=$script:rotation.Current
    if ($work) {
        $kind=if ($Screen -ne 'automatic') {$Screen} elseif ($work.Phase -in @('menu','find')) {'menu'} else {'world'}
        $work.Row.Process | Add-Member NoteProperty LoginPointPresent ($kind -eq 'world') -Force
        $work.Row.Process.RotationScreen=[pscustomobject]@{Kind=$kind;RoleName=$work.Entry.Plan.Slots[$work.Entry.Index].Name;Targets=@($work.Entry.Plan.Slots | Where-Object {$_.Name} | ForEach-Object {[pscustomobject]@{Name=$_.Name;X=0.84;Y=0.20}})}
        if ($work.Row.TaskMode -eq 'fight') {[WowAutoFight.Native]::Current.Flavor=$work.Row.Client.Flavor;[WowAutoFight.Native]::Current.ClassId=1}
    }
    $null=Invoke-RotationTick $Now
}
function Complete-RotationTest([ref]$Now) {
    $iterations=0
    while (($script:rotation.Current -or $script:rotation.Queue.Count) -and $iterations++ -lt 200) {Step-RotationTest $Now.Value;$Now.Value+=300}
    Assert-Ui ($iterations -lt 200) 'Rotation failed to finish.'
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
    Start-Row $a;Start-Row $b
    Assert-Ui ($script:rotation.Active.Count -eq 2 -and -not (Test-UnifiedTaskRunning $a) -and $script:rotation.NextAt -eq 20000) 'Start bypassed role selection or timers are not global.'
    $now=0L;Complete-RotationTest ([ref]$now)
    Assert-Ui ((Test-UnifiedTaskRunning $a) -and (Test-UnifiedTaskRunning $b) -and (Get-WowAutoCycleCount $script:scheduler $a.Key) -eq 0 -and [long]$script:scheduler.CyclesSinceJump[$a.Key] -eq 0) 'Initial role login/task start or character counter reset failed.'
    Assert-Ui ($a.State.UseItem -and -not $b.State.UseItem) 'Initial per-slot item choices did not reach engine.'
    $actions=@($script:rotation.Actions | Where-Object {$_.Key -eq $a.Key})
    Assert-Ui (($actions.Action -join ',') -eq 'logout,top,doubleclick') 'Name-based double-click ordering wrong.'
    $oldCount=$script:rotation.Actions.Count
    Step-RotationTest 19999
    Assert-Ui ($script:rotation.Actions.Count -eq $oldCount -and -not $script:rotation.Current) 'Switched before global deadline.'
    Step-RotationTest 20000
    Assert-Ui (-not (Test-UnifiedTaskRunning $a) -and -not (Test-UnifiedTaskRunning $b) -and $script:rotation.Active[$a.Key].Index -eq 2 -and $script:rotation.Active[$b.Key].Index -eq 1) 'Batch did not stop all tasks or cycle slots atomically.'
    $now=20300L;Complete-RotationTest ([ref]$now)
    Assert-Ui (-not $a.SlotUseItem) 'Combat slot inherited fishing item.'
    Assert-Ui ($a.TaskMode -eq 'fight' -and $a.FightRow.Session -and $b.State.Running) 'Per-slot task modes not started.'
    $actions=@($script:rotation.Actions | Select-Object -Skip $oldCount | Where-Object {$_.Key -eq $b.Key})
    Assert-Ui (@($actions | Where-Object {$_.Action -eq 'logout'}).Count -eq 1 -and @($actions | Where-Object {$_.Action -eq 'doubleclick'}).Count -eq 1) 'Single configured character did not log out and log back in.'
    # Unknown screens and incomplete OCR never receive navigation, chat or task input.
    Stop-AllRows;$script:rotation.Actions=@();Start-Row $a
    Step-RotationTest 30000;Step-RotationTest 30300 'unknown';Step-RotationTest 30600 'unknown'
    Assert-Ui (-not $script:rotation.Actions.Count) 'Unknown screen received input.'
    Step-RotationTest 30900 'world';Step-RotationTest 31200 'world';Step-RotationTest 31500 'unknown'
    Assert-Ui (($script:rotation.Actions.Action -join ',') -eq 'logout') 'Loading received navigation.'
    $script:editingSettings=$true;$before=$script:rotation.Actions.Count;Step-RotationTest 40000 'menu';$script:editingSettings=$false
    Assert-Ui ($script:rotation.Actions.Count -eq $before) 'Settings failed to pause orchestration.'
    Step-RotationTest 210000 'unknown'
    Assert-Ui (-not $script:rotation.Active.ContainsKey($a.Key) -and -not (Test-UnifiedTaskRunning $a)) 'Timeout restarted work.'
    Start-Row $b;Step-RotationTest 211000;$script:workerFocus=-1;$b.Process.FocusAllowed=$false;Step-RotationTest 211300
    Assert-Ui (-not $script:rotation.Active.ContainsKey($b.Key)) 'Lost focus did not stop transition.'
    $b.Process.FocusAllowed=$true
    Stop-AllRows;$script:rotation.Actions=@();Start-Row $a;Stop-Row $a;Step-RotationTest 212000
    Assert-Ui (-not $script:rotation.Current -and -not $script:rotation.Actions.Count) 'Stopped queued work still ran.'
    # Starting in the menu only scrolls and double-clicks the actual OCR name.
    Stop-AllRows;$script:rotation.Actions=@();Start-Row $b
    Step-RotationTest 213000;Step-RotationTest 213300 'menu'
    $now=213600L
    for ($i=0;$i -lt 80 -and $script:rotation.Current.Phase -ne 'login';$i++) {Step-RotationTest $now;$now+=300}
    Assert-Ui ($script:rotation.Current.Phase -eq 'login') 'Initial menu did not reach login.'
    Assert-Ui (($script:rotation.Actions.Action -join ',') -eq 'top,doubleclick' -and $script:rotation.Actions[-1].Target.Name -ceq '小船长') 'Menu login did not double-click exact name.'
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
    # Partial/duplicate names cannot receive a double-click; login uses the point, never OCR names.
    $now=230000L;Reach-RotationTestPhase $a 'find' ([ref]$now)
    for ($i=0;$i -lt 3;$i++) {
        $a.Process.RotationScreen=[pscustomobject]@{Kind='menu';RoleName=$null;Targets=@([pscustomobject]@{Name='双持船橘二';X=0.84;Y=0.2})}
        $script:schedulerClock.ElapsedMilliseconds=$now;$null=Invoke-RotationTick $now;$now+=300
    }
    Assert-Ui (-not $script:rotation.Active.ContainsKey($a.Key) -and -not @($script:rotation.Actions | Where-Object {$_.Action -eq 'doubleclick'}).Count) 'Partial/no-progress search clicked a role.'
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
    Assert-Ui ([Math]::Abs($mapped.Targets[0].X-(0.70+0.30*(0.10+0.25/2))) -lt 0.00001) 'OCR crop mapping ignored client aspect ratio.'
    $ocr.PSObject.Properties.Remove('NamesBounds')
    $anchors=$ocr.Lines
    $ocr.Lines=@($anchors[0]);Assert-Ui ((ConvertFrom-RotationOcr $ocr $plan).Kind -eq 'unknown') 'One anchor alone accepted.'
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
    Write-Output 'PASS: name/empty/single/wrap slots, shared deadline/all-stop batch, exact-name double-click, partial/duplicate/no-progress rejection, permanent-point login/no OCR after selection/loading/pending/focus/timeout/stop/settings isolation, per-role fish/fight, counter reset, atomic drafts and PID reuse. All game input and OCR mocked.'
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
