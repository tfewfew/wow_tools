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
        $kind=if ($Screen -ne 'automatic') {$Screen} elseif ($work.Phase -in @('menu','first','select')) {'menu'} elseif ($work.Phase -eq 'login' -and -not $work.Armed -and -not $work.ProbeSent) {'unknown'} else {'world'}
        $work.Row.Process.RotationScreen=[pscustomobject]@{Kind=$kind;Token=$work.Entry.Token}
        if ($work.Row.TaskMode -eq 'fight') {[WowAutoFight.Native]::Current.Flavor=$work.Row.Client.Flavor;[WowAutoFight.Native]::Current.ClassId=1}
    }
    $null=Invoke-RotationTick $Now
}
function Complete-RotationTest([ref]$Now) {
    $iterations=0
    while (($script:rotation.Current -or $script:rotation.Queue.Count) -and $iterations++ -lt 200) {Step-RotationTest $Now.Value;$Now.Value+=300}
    Assert-Ui ($iterations -lt 200) 'Rotation failed to finish.'
}
try {
    $script:mockProcesses=@($script:mockProcesses | Select-Object -First 2)
    foreach ($process in $script:mockProcesses) {
        $process.FocusAllowed=$true;$process.CommandAllowed=$true;$process.ScanColor='red'
        $process | Add-Member NoteProperty RotationScreen ([pscustomobject]@{Kind='world';Token=0}) -Force
    }
    $null=Refresh-ProcessRows
    $clients=@($script:rows.Values | Sort-Object {$_.Process.Id});$a=$clients[0];$b=$clients[1]
    $menu=[pscustomobject]@{Count=8;Aspect=1.6;FirstX=0.8;FirstY=0.2;X=0.1;Y=0.8;W=0.3;H=0.1;Pixels=@(1..384 | ForEach-Object {($_%2)*255})}
    $plan=New-RotationPlan;$plan.Menu=$menu;$plan.Slots[0].Character=2;$plan.Slots[2].Character=5;$plan.Slots[2].Mode='fight'
    $single=New-RotationPlan;$single.Menu=$menu;$single.Slots[1].Character=3
    Assert-Ui ((Get-RotationNextSlot $plan -1) -eq 0 -and (Get-RotationNextSlot $plan 0) -eq 2 -and (Get-RotationNextSlot $plan 2) -eq 0) 'Empty slot not skipped/wrapped.'
    Assert-Ui ((Get-RotationNextSlot $single 1) -eq 1 -and (Get-RotationNextSlot (New-RotationPlan) -1) -eq -1) 'Single/all-empty slot behavior wrong.'
    $plans=@{};$plans[$a.Key]=$plan;$plans[$b.Key]=$single
    Save-RotationConfiguration 20 $plans
    $hash=(Get-FileHash $script:rotation.Path).Hash;$script:rotation.Plans=@{};Import-RotationConfiguration
    Assert-Ui ($script:rotation.ConfigReady -and $script:rotation.Plans[$a.Key].Slots[2].Character -eq 5 -and (Get-FileHash $script:rotation.Path).Hash -eq $hash) 'Saved rotation config did not reload read-only.'
    $locked=[IO.File]::Open($script:rotation.Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try {$failed=$false;try {Save-RotationConfiguration 30} catch {$failed=$true};Assert-Ui ($failed -and $script:rotation.IntervalSeconds -eq 20) 'Locked config applied interval.'} finally {$locked.Dispose()}
    $draft=Copy-RotationPlan $plan;$draft.Slots[0].Character=9
    $rejected=$false;try {Test-RotationPlan $draft} catch {$rejected=$true};Assert-Ui $rejected 'Out-of-list role accepted.'
    $draft.Slots[0].Character=-1;$rejected=$false;try {Test-RotationPlan $draft} catch {$rejected=$true};Assert-Ui $rejected 'Negative role accepted.'
    $script:scheduler.CompletedCycles[$a.Key]=501;$script:scheduler.CyclesSinceJump[$a.Key]=5
    Start-Row $a;Start-Row $b
    Assert-Ui ($script:rotation.Active.Count -eq 2 -and -not (Test-UnifiedTaskRunning $a) -and $script:rotation.NextAt -eq 20000) 'Start bypassed role selection or timers are not global.'
    $now=0L;Complete-RotationTest ([ref]$now)
    Assert-Ui ((Test-UnifiedTaskRunning $a) -and (Test-UnifiedTaskRunning $b) -and (Get-WowAutoCycleCount $script:scheduler $a.Key) -eq 0 -and [long]$script:scheduler.CyclesSinceJump[$a.Key] -eq 0) 'Initial role login/task start or character counter reset failed.'
    $actions=@($script:rotation.Actions | Where-Object {$_.Key -eq $a.Key})
    Assert-Ui (($actions.Action -join ',') -eq 'arm,logout,top,first,down,enter') 'Role 2 input ordering wrong.'
    $oldCount=$script:rotation.Actions.Count
    Step-RotationTest 19999
    Assert-Ui ($script:rotation.Actions.Count -eq $oldCount -and -not $script:rotation.Current) 'Switched before global deadline.'
    Step-RotationTest 20000
    Assert-Ui (-not (Test-UnifiedTaskRunning $a) -and -not (Test-UnifiedTaskRunning $b) -and $script:rotation.Active[$a.Key].Index -eq 2 -and $script:rotation.Active[$b.Key].Index -eq 1) 'Batch did not stop all tasks or cycle slots atomically.'
    $now=20300L;Complete-RotationTest ([ref]$now)
    Assert-Ui ($a.TaskMode -eq 'fight' -and $a.FightRow.Session -and $b.State.Running) 'Per-slot task modes not started.'
    $actions=@($script:rotation.Actions | Select-Object -Skip $oldCount | Where-Object {$_.Key -eq $b.Key})
    Assert-Ui (@($actions | Where-Object {$_.Action -eq 'logout'}).Count -eq 1 -and @($actions | Where-Object {$_.Action -eq 'enter'}).Count -eq 1) 'Single configured character did not log out and log back in.'
    # Combat/unknown screens never receive navigation or login keys.
    Stop-AllRows;$script:rotation.Actions=@();Start-Row $a
    Step-RotationTest 30000;Step-RotationTest 30300 'world';Step-RotationTest 30600 'combat'
    Assert-Ui (($script:rotation.Actions.Action -join ',') -eq 'arm') 'Combat received logout/navigation.'
    Step-RotationTest 30900 'world';Step-RotationTest 31200 'unknown'
    Assert-Ui (($script:rotation.Actions.Action -join ',') -eq 'arm,logout') 'Unknown/loading screen received keys.'
    $script:editingSettings=$true;$before=$script:rotation.Actions.Count;Step-RotationTest 40000 'menu';$script:editingSettings=$false
    Assert-Ui ($script:rotation.Actions.Count -eq $before) 'Settings failed to pause orchestration.'
    Step-RotationTest 210000 'unknown'
    Assert-Ui (-not $script:rotation.Active.ContainsKey($a.Key) -and -not (Test-UnifiedTaskRunning $a)) 'Timeout restarted work.'
    Start-Row $b;Step-RotationTest 211000;$script:workerFocus=-1;Step-RotationTest 211300
    Assert-Ui (-not $script:rotation.Active.ContainsKey($b.Key)) 'Lost focus did not stop transition.'
    Stop-AllRows;$script:rotation.Actions=@();Start-Row $a;Stop-Row $a;Step-RotationTest 212000
    Assert-Ui (-not $script:rotation.Current -and -not $script:rotation.Actions.Count) 'Stopped queued work still ran.'
    # Starting from an already open menu does not type chat commands into the menu.
    Stop-AllRows;$script:rotation.Actions=@();Start-Row $b
    Step-RotationTest 213000;Step-RotationTest 213300 'menu'
    $now=213600L
    while ($script:rotation.Current.Phase -ne 'login') {Step-RotationTest $now;$now+=300}
    $probeAt=$script:rotation.Current.ProbeAt
    Step-RotationTest $probeAt 'menu'
    Assert-Ui (-not @($script:rotation.Actions | Where-Object {$_.Action -eq 'probe'}).Count) 'Readiness probe typed into verified menu.'
    Step-RotationTest ($probeAt+300) 'unknown'
    Assert-Ui (@($script:rotation.Actions | Where-Object {$_.Action -eq 'probe'}).Count -eq 1 -and -not $b.State.Running) 'Initial menu login skipped explicit readiness request.'
    $script:rotation.Current.Row.Process.RotationScreen=[pscustomobject]@{Kind='world';Token=0}
    $null=Invoke-RotationTick ($probeAt+600)
    Assert-Ui (-not $b.State.Running -and $script:rotation.Current.Phase -eq 'login') 'Legacy token zero started monitoring.'
    Step-RotationTest ($probeAt+900) 'unknown'
    Assert-Ui (@($script:rotation.Actions | Where-Object {$_.Action -eq 'probe'}).Count -eq 1) 'Readiness requests were not throttled.'
    Step-RotationTest ($probeAt+3300) 'unknown'
    Assert-Ui (@($script:rotation.Actions | Where-Object {$_.Action -eq 'probe'}).Count -eq 2) 'Loading ignored request was not retried.'
    $now=$probeAt+3600;Complete-RotationTest ([ref]$now)
    Assert-Ui ($b.State.Running -and -not @($script:rotation.Actions | Where-Object {$_.Action -in @('arm','logout')}).Count) 'Initial menu start typed logout/arm into menu.'
    $deadline=$script:rotation.NextAt;Save-RotationConfiguration 20
    Assert-Ui ($script:rotation.NextAt -eq $deadline) 'Saving unchanged interval reset global deadline.'
    Save-RotationConfiguration 0
    Assert-Ui ($script:rotation.NextAt -eq 0 -and $b.State.Running -and $script:rotation.Active.Count -eq 1) 'Disabling timer stopped current role or retained deadline.'
    Save-RotationConfiguration 20;Stop-AllRows
    $b.Process.CommandAllowed=$false;Start-Row $b;$now=220000L;Complete-RotationTest ([ref]$now)
    Assert-Ui (-not $script:rotation.Active.ContainsKey($b.Key) -and -not (Test-UnifiedTaskRunning $b)) 'Failed monitor command started character task.'
    $b.Process.CommandAllowed=$true
    # Embedded settings and editor use isolated drafts; saves require atomic persistence.
    $dialog=New-RotationEditor $a
    try {
        $dialog.Tag.Slots[0].Character.Value=4;Assert-Ui ($script:rotation.Plans[$a.Key].Slots[0].Character -eq 2) 'Editor draft leaked.'
        if ($env:WOWAUTO_UNIFIED_PREVIEW_DIRECTORY) {
            $dialog.Show($form);[System.Windows.Forms.Application]::DoEvents()
            $image=New-Object Drawing.Bitmap($dialog.Width,$dialog.Height)
            try {$dialog.DrawToBitmap($image,(New-Object Drawing.Rectangle(0,0,$image.Width,$image.Height)));$image.Save((Join-Path $env:WOWAUTO_UNIFIED_PREVIEW_DIRECTORY 'rotation-editor.png'),[Drawing.Imaging.ImageFormat]::Png)} finally {$image.Dispose()}
        }
    } finally {$dialog.Dispose()}
    $dialog=New-UnifiedSettingsDialog
    try {
        $dialog.Show($form);[System.Windows.Forms.Application]::DoEvents()
        Assert-Ui ($dialog.Tag.Rotation.Value.Value -eq 20 -and $dialog.Tag.Tabs.TabPages.Count -eq 2 -and $dialog.Tag.Tabs.Top -ge 52) 'Global interval missing/covered or settings tabs changed.'
    } finally {$dialog.Dispose()}
    $a.Process.StartTime=$a.Process.StartTime.AddSeconds(1);$null=Refresh-ProcessRows
    $replacement=@($script:rows.Values | Where-Object {$_.Process.Id -eq $a.Process.Id})[0]
    Assert-Ui (-not (Test-RowHasRotation $replacement)) 'Reused PID inherited character plan.'
    Assert-Ui ([WowAuto.NativeInput]::RotationCommand('arm',200) -eq '/wowrotate arm 200' -and [WowAuto.NativeInput]::RotationCommand('logout',0) -eq '/logout') 'Rotation command mapping wrong.'
    Assert-Ui ([WowAuto.NativeInput]::RotationCommand('probe',77) -eq '/wowrotate arm 77') 'Readiness-only command mapping wrong.'
    $bitmap=New-Object Drawing.Bitmap(800,500)
    try {
        $graphics=[Drawing.Graphics]::FromImage($bitmap)
        try {$graphics.Clear([Drawing.Color]::Black);$graphics.FillRectangle([Drawing.Brushes]::White,80,400,120,50)} finally {$graphics.Dispose()}
        $fingerprint=[WowAutoRotation.Native]::Fingerprint($bitmap,0.1,0.8,0.3,0.1)
        Assert-Ui ([WowAutoRotation.Native]::Matches($fingerprint,$fingerprint)) 'Native visual fingerprint rejected structured patch.'
        Assert-Ui (-not [WowAutoRotation.Native]::Matches((New-Object int[] 384),(New-Object int[] 384))) 'Black screenshot accepted as menu.'
        $graphics=[Drawing.Graphics]::FromImage($bitmap)
        try {$graphics.Clear([Drawing.Color]::FromArgb(97,231,157))} finally {$graphics.Dispose()}
        Assert-Ui ([WowAutoRotation.Native]::ReadyToken($bitmap) -eq 77) 'World-entry native RGB token mismatches Lua.'
        $bitmap.SetPixel(400,250,[Drawing.Color]::FromArgb(20,231,157))
        Assert-Ui ([WowAutoRotation.Native]::ReadyToken($bitmap) -eq -1) 'Legacy automatic token zero accepted.'
    } finally {$bitmap.Dispose()}
    $failed=$false;try {$null=[WowAuto.NativeInput]::RotationCommand('delete',1)} catch {$failed=$true};Assert-Ui $failed 'Arbitrary rotation command accepted.'
    foreach ($p in $sourceHashes.Keys) {Assert-Ui ((Get-FileHash $p).Hash -eq $sourceHashes[$p]) 'Tests changed real user configuration.'}
    Write-Output 'PASS: three-slot empty/single/wrap behavior, shared deadline/all-stop batch, initial login/per-role fishing/combat, logout/menu/navigation/login/monitor ordering, combat/loading/focus/timeout/stop/settings isolation, counter reset, atomic persistence/drafts and PID reuse. All game input and screens mocked.'
} finally {
    Stop-AllRows;Close-AutoFightTab
    if ([IO.File]::Exists($script:rotation.Path)) {[IO.File]::Delete($script:rotation.Path)}
    $script:rotation.Path=$oldRotationPath
}
