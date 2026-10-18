function Assert-Parallel($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Get-ParallelRoleRow($Editor,[string]$Name) {
    $matches=@(foreach($grid in $Editor.Grids){foreach($row in $grid.Rows){if($row.Cells['Name'].Value -ceq $Name){$row}}})
    Assert-Parallel ($matches.Count -eq 1) ('Expected one role row: '+$Name)
    return $matches[0]
}
function Select-ParallelSettingsPage($Dialog,$Page) {
    if($Page -eq $Dialog.Tag.DetectionPeriods -or $Page -eq $Dialog.Tag.Operations){$Dialog.Tag.Tabs.SelectedTab=$Dialog.Tag.Timing;$Dialog.Tag.Timing.Tag.Tabs.SelectedTab=$Page}
    else{$Dialog.Tag.Tabs.SelectedTab=$Page}
}
function Pump-Parallel([scriptblock]$Until,[int]$Timeout=6000) {
    $deadline=$script:parallelHub.Now+$Timeout
    do {
        [Windows.Forms.Application]::DoEvents();Update-ParallelMessages
        if(& $Until){return};[Threading.Thread]::Sleep(10)
    }while($script:parallelHub.Now -lt $deadline)
    throw ('Parallel UI timed out; '+(($script:rows.Values | ForEach-Object {$_.Process.Id.ToString()+': '+$_.StatusMessage}) -join '; '))
}
$rows=@($script:rows.Values | Sort-Object {$_.Process.Id});$a=$rows[0];$b=$rows[1];$c=$rows[2]
$script:autoFight.Profiles['forerver:1'].BuffIntervalSeconds=0;$script:autoFight.Common.JumpIntervalSeconds=0
$originalOperations=ConvertTo-TaskMap ($script:accountTasks.Config.Operations | ConvertTo-Json | ConvertFrom-Json)
Assert-Parallel ($rows.Count -eq 3 -and $script:parallelWorkers.Count -eq 3) 'Each process must have one detector runspace.'
foreach($row in $rows) {
    Assert-Parallel ($row.AccountBox.Parent -eq $row.Panel -and -not $row.PSObject.Properties['RotationButton'] -and @(Get-AccountTaskRoles $row).Count -eq 4) 'Account binding missing or process slots still limit roles.'
    Assert-Parallel ($row.Status.Bottom -eq $row.Panel.ClientSize.Height) 'Status lost bottom alignment.'
    Assert-Parallel ($row.Name.Text -notmatch '职业：') 'PID area still shows a class.'
    if($row.TaskMode -eq 'fish'){Assert-Parallel ($row.Name.Text -match '循环 0 · 无咬钩超时 0') 'Fishing row omits the initial no-bite timeout count.'}
}
$dialog=New-UnifiedSettingsDialog
try {
    $dialog.Show($form);$dialog.Tag.Tabs.SelectedTab=$dialog.Tag.Accounts;[Windows.Forms.Application]::DoEvents()
    $accountEditor=$dialog.Tag.Accounts.Tag;$editor=$accountEditor.Clients.titan;$forever=$accountEditor.Clients.forerver;$periodEditor=$dialog.Tag.DetectionPeriods.Tag
    Assert-Parallel ($dialog.Tag.Tabs.TabPages.Count -eq 5 -and ($editor.FullGrid.Rows.Count+$editor.LevelingGrid.Rows.Count) -eq 4 -and $script:parallelHub.Paused) 'Separate global period settings tab or runtime pause is missing.'
    Assert-Parallel ($dialog.Tag.DetectionPeriods.Text -eq '检测周期' -and $periodEditor.Periods.Count -eq 10 -and -not $accountEditor.PSObject.Properties['Periods']) 'Global detection controls still belong to account settings.'
    Assert-Parallel ($dialog.Tag.Timing.Text -eq '检测与操作' -and $dialog.Tag.Timing.Tag.Tabs.TabPages.Count -eq 2 -and $dialog.Tag.Operations.Tag.Values.Count -eq 22) 'Detection and queue settings are not sibling child tabs.'
    Assert-Parallel (-not $dialog.Tag.Fish.Tag.FocusRetry.Visible -and -not $dialog.Tag.Fish.Tag.ReelHold.Visible -and -not $dialog.Tag.Fight.Tag.CommandInterval.Visible -and -not $dialog.Tag.Fight.Tag.CommonNumbers.InteractionHoldMs.Visible) 'Moved timing controls remain editable in their original pages.'
    Assert-Parallel ($accountEditor.ClientTabs.TabPages.Count -eq 2 -and $editor.Page.Text -eq '时光服' -and $forever.Page.Text -eq '永恒服') 'Clients do not have separate child tabs.'
    Assert-Parallel ($editor.Accounts.Items.Count -eq 2 -and $forever.Accounts.Items.Count -eq 1 -and $editor.Selected -ceq 'titan:ACCOUNT-A' -and $forever.Selected -ceq 'forerver:ACCOUNT-A') 'Child account lists are not filtered by client.'
    Assert-Parallel ($editor.Accounts.SelectedItem -ceq 'ACCOUNT-A' -and $forever.Accounts.SelectedItem -ceq 'ACCOUNT-A' -and (Get-ParallelRoleRow $editor '角色甲').Cells['Mode'].Value -eq '钓鱼' -and (Get-ParallelRoleRow $forever '角色甲').Cells['Mode'].Value -eq '战斗') 'Same-name accounts leaked across client tabs or dropdown still contains client prefixes.'
    foreach($client in @($editor,$forever)){
        Assert-Parallel ($client.FullGrid.Bottom -lt $client.LevelingGrid.Top -and $client.FullGrid.Rows.Count -eq 1 -and
            $client.FullGrid.Rows[0].Cells['Name'].Value -ceq '角色乙' -and
            (($client.LevelingGrid.Rows | ForEach-Object {$_.Cells['Name'].Value}) -join ',') -ceq '角色丙,角色丁,角色甲') 'Full/leveling tables lost client caps, top placement, descending levels or unknown-last order.'
        $signature=Get-AccountTaskSignature $client.Draft.Accounts[$client.Selected]
        Save-AccountGridDraft $client
        Assert-Parallel ((Get-AccountTaskSignature $client.Draft.Accounts[$client.Selected]) -ceq $signature) 'Display grouping/sorting reordered saved rotation tasks.'
        Assert-Parallel ((Get-ParallelRoleRow $client '角色甲').Cells['FreeBagSlots'].Value -ceq '未知' -and (Get-ParallelRoleRow $client '角色乙').Cells['FreeBagSlots'].Value -eq 0 -and (Get-ParallelRoleRow $client '角色丙').Cells['FreeBagSlots'].Value -eq 12) 'Unknown, full and available bag snapshots are not distinguished in the role table.'
        Assert-Parallel ($client.FullGrid.Columns['Professions'].Index -eq $client.FullGrid.Columns['FreeBagSlots'].Index+1 -and
            $client.FullGrid.Columns['SecondarySkills'].Index -eq $client.FullGrid.Columns['Professions'].Index+1 -and
            $client.FullGrid.Columns['Professions'].ReadOnly -and $client.FullGrid.Columns['SecondarySkills'].ReadOnly) 'Read-only skill columns are missing after bag space.'
        Assert-Parallel ((Get-ParallelRoleRow $client '角色甲').Cells['Professions'].Value -ceq '未知' -and (Get-ParallelRoleRow $client '角色乙').Cells['Professions'].Value -ceq '未学习' -and
            (Get-ParallelRoleRow $client '角色丙').Cells['Professions'].Value -ceq "采矿 450/450`n剥皮 425/450" -and
            (Get-ParallelRoleRow $client '角色丙').Cells['SecondarySkills'].Value -ceq "烹饪 300/450`n钓鱼 450/450" -and
            (Get-ParallelRoleRow $client '角色丁').Cells['Professions'].Value -ceq '炼金术 0/75') 'Skill names/ranks, unknown or unlearned skills were not presented correctly.'
        $location=if($client.Flavor -eq 'titan'){'达拉然'}else{'奥格瑞玛'}
        Assert-Parallel ($client.FullGrid.Columns['BindLocation'].ReadOnly -and $client.FullGrid.Columns['BindLocation'].HeaderText -ceq '炉石位置' -and
            (Get-ParallelRoleRow $client '角色甲').Cells['BindLocation'].Value -ceq '未知' -and (Get-ParallelRoleRow $client '角色乙').Cells['BindLocation'].Value -ceq '未知' -and
            (Get-ParallelRoleRow $client '角色丙').Cells['BindLocation'].Value -ceq $location -and (Get-ParallelRoleRow $client '角色丁').Cells['BindLocation'].Value -ceq '未知') 'Hearthstone binding column lost old/unknown snapshots or mixed the clients.'
        Assert-Parallel (($client.FullGrid.Columns | Measure-Object -Property Width -Sum).Sum -le $client.FullGrid.Width) 'Hearthstone column requires horizontal scrolling at the default window size.'
        Assert-Parallel ($client.FullGrid.Columns['Class'].ReadOnly -and (Get-ParallelRoleRow $client '角色甲').Cells['Class'].Value -ceq '未知' -and
            (Get-ParallelRoleRow $client '角色丙').Cells['Class'].Value -ceq '法师' -and
            (Get-ParallelRoleRow $client '角色丙').Cells['Name'].Style.ForeColor.ToArgb() -eq (Get-WowClassColor 8).ToArgb() -and
            (Get-ParallelRoleRow $client '角色丁').Cells['Class'].Style.SelectionForeColor.ToArgb() -eq (Get-WowClassColor 11).ToArgb()) 'Class column, old-record unknowns or class-colored role/class selection text was lost.'
    }
    (Get-ParallelRoleRow $editor '角色乙').Cells['Mode'].Value='钓鱼'
    (Get-ParallelRoleRow $editor '角色乙').Cells['UseItem'].Value=$true
    Save-AccountGridDraft $editor
    Assert-Parallel ($editor.Draft.Accounts[$editor.Selected][1].UseItem -and $editor.Draft.Accounts[$editor.Selected][1].Mode -eq 'fish' -and
        $script:accountTasks.Config.Accounts[$editor.Selected][1].Mode -eq 'fight') 'Upper-table task/item edits did not enter the draft independently.'
    (Get-ParallelRoleRow $editor '角色乙').Cells['Mode'].Value='战斗'
    Assert-Parallel ((Get-ParallelRoleRow $editor '角色乙').Cells['UseItem'].ReadOnly -and -not (Get-ParallelRoleRow $editor '角色乙').Cells['UseItem'].Value) 'Upper-table combat task did not disable and clear its fishing item.'
    $before=(Get-FileHash $script:accountTasks.Path).Hash
    (Get-ParallelRoleRow $editor '角色甲').Cells['Enabled'].Value=$false
    $periodEditor.Periods.OcrMs.Value=50
    $dialog.Tag.Operations.Tag.Values.KeyPressMs.Value=57
    Assert-Parallel ($script:accountTasks.Config.Accounts[$editor.Selected][0].Enabled) 'Role draft applied before save.'
    if($env:WOWAUTO_PARALLEL_PREVIEW){
        foreach($preview in @(@($dialog.Tag.Accounts,$editor.Page,'account-settings.png'),@($dialog.Tag.Accounts,$forever.Page,'account-settings-forever.png'),@($dialog.Tag.DetectionPeriods,$null,'detection-periods.png'),@($dialog.Tag.Operations,$null,'operation-timings.png'))){
            Select-ParallelSettingsPage $dialog $preview[0];if($preview[1]){$accountEditor.ClientTabs.SelectedTab=$preview[1]};[Windows.Forms.Application]::DoEvents()
            $bitmap=New-Object Drawing.Bitmap($dialog.Width,$dialog.Height);try{$dialog.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$bitmap.Width,$bitmap.Height)));$bitmap.Save((Join-Path $env:WOWAUTO_PARALLEL_PREVIEW $preview[2]))}finally{$bitmap.Dispose()}
        }
    }
}finally{$dialog.Dispose()}
Assert-Parallel ((Get-FileHash $script:accountTasks.Path).Hash -eq $before -and $script:accountTasks.Config.Periods.OcrMs -eq 25 -and $script:accountTasks.Config.Operations.KeyPressMs -eq 30 -and -not $script:parallelHub.Paused) 'Cancel changed account tasks/periods/operations or left workers paused.'
$dialog=New-UnifiedSettingsDialog
try {
    $dialog.Show($form);$dialog.Tag.Tabs.SelectedTab=$dialog.Tag.Accounts;[Windows.Forms.Application]::DoEvents()
    $accountEditor=$dialog.Tag.Accounts.Tag;$editor=$accountEditor.Clients.titan;$forever=$accountEditor.Clients.forerver;$periodEditor=$dialog.Tag.DetectionPeriods.Tag
    (Get-ParallelRoleRow $editor '角色丁').Cells['Enabled'].Value=$false;$periodEditor.Periods.OcrMs.Value=50
    $operationEditor=$dialog.Tag.Operations.Tag
    $operationEditor.Values.KeyPressMs.Value=17;$operationEditor.Values.ForegroundSettleMs.Value=75;$operationEditor.Values.UiRefreshMs.Value=40
    $locked=[IO.File]::Open($script:accountTasks.Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try{$accountEditor.Save.PerformClick();Select-ParallelSettingsPage $dialog $dialog.Tag.DetectionPeriods;$periodEditor.Save.PerformClick();Select-ParallelSettingsPage $dialog $dialog.Tag.Operations;$operationEditor.Save.PerformClick()}finally{$locked.Dispose()}
    Assert-Parallel ($script:accountTasks.Config.Accounts['titan:ACCOUNT-A'][3].Enabled -and $script:accountTasks.Config.Periods.OcrMs -eq 25 -and (Get-FileHash $script:accountTasks.Path).Hash -eq $before) 'Locked save partly applied either settings page.'
    $operationEditor.Values.ClickMinMs.Value=1000;$operationEditor.Save.PerformClick()
    Assert-Parallel ((Get-FileHash $script:accountTasks.Path).Hash -eq $before -and $script:accountTasks.Config.Operations.KeyPressMs -eq 30) 'Invalid click interval partly saved queue settings.'
    $operationEditor.Values.ClickMinMs.Value=100;$operationEditor.Save.PerformClick()
    Assert-Parallel ($script:accountTasks.Config.Operations.KeyPressMs -eq 17 -and $script:accountTasks.Config.Periods.OcrMs -eq 25 -and $script:accountTasks.Config.Accounts['titan:ACCOUNT-A'][3].Enabled -and $script:parallelHub.Timing.KeyPressMs -eq 30) 'Queue save applied another draft or changed active operations before dialog close.'
    $operationEditor.Values.KeyPressMs.Value=99
    Select-ParallelSettingsPage $dialog $dialog.Tag.DetectionPeriods
    $periodEditor.Save.PerformClick()
    Assert-Parallel ($script:accountTasks.Config.Accounts['titan:ACCOUNT-A'][3].Enabled -and $script:accountTasks.Config.Periods.OcrMs -eq 50) 'Saving global periods applied the unsaved role draft.'
    $periodEditor.Periods.OcrMs.Value=75;$dialog.Tag.Tabs.SelectedTab=$dialog.Tag.Accounts;$accountEditor.Save.PerformClick()
    Assert-Parallel (-not $script:accountTasks.Config.Accounts['titan:ACCOUNT-A'][3].Enabled -and $script:accountTasks.Config.Periods.OcrMs -eq 50 -and $script:accountTasks.Config.Accounts['forerver:ACCOUNT-A'][3].Enabled) 'Role save applied unsaved periods, reverted saved periods or changed the other client.'
    (Get-ParallelRoleRow $editor '角色丁').Cells['Enabled'].Value=$true;$accountEditor.ClientTabs.SelectedTab=$forever.Page;(Get-ParallelRoleRow $forever '角色丙').Cells['UseItem'].Value=$true
    $accountEditor.ClientTabs.SelectedTab=$editor.Page;$editor.Accounts.SelectedItem='ACCOUNT-B'
    Assert-Parallel (-not $script:accountTasks.Config.Accounts['titan:ACCOUNT-A'][3].Enabled) 'Further edits after Save shared the active configuration object.'
    $editor.Accounts.SelectedItem='ACCOUNT-A'
    Assert-Parallel ((Get-ParallelRoleRow $editor '角色丁').Cells['Enabled'].Value -and (Get-ParallelRoleRow $forever '角色丙').Cells['UseItem'].Value -and $forever.Selected -ceq 'forerver:ACCOUNT-A') 'Changing account/client tabs discarded another tab draft or selection.'
    $accountEditor.Save.PerformClick();Select-ParallelSettingsPage $dialog $dialog.Tag.DetectionPeriods;$periodEditor.Periods.OcrMs.Value=25;$periodEditor.Save.PerformClick()
    Assert-Parallel ($script:accountTasks.Config.Accounts['titan:ACCOUNT-A'][3].Enabled -and $script:accountTasks.Config.Accounts['forerver:ACCOUNT-A'][2].UseItem -and $script:accountTasks.Config.Periods.OcrMs -eq 25) 'Saving periods reverted the latest saved roles in another client.'
    $dialog.Tag.Tabs.SelectedTab=$dialog.Tag.Accounts;$accountEditor.ClientTabs.SelectedTab=$forever.Page;(Get-ParallelRoleRow $forever '角色丙').Cells['UseItem'].Value=$false;$accountEditor.Save.PerformClick()
    $savedSettings=[IO.File]::ReadAllText($script:accountTasks.Path) | ConvertFrom-Json
    Assert-Parallel ($savedSettings.Periods.OcrMs -eq 25 -and $savedSettings.Accounts.'titan:ACCOUNT-A'[3].Enabled -and -not $savedSettings.Accounts.'forerver:ACCOUNT-A'[2].UseItem) 'Separate settings pages did not persist their latest values.'
    Assert-Parallel ($savedSettings.Operations.KeyPressMs -eq 17 -and $script:accountTasks.Config.Operations.KeyPressMs -eq 17) 'Role/period saves changed saved operation timing or applied a later unsaved draft.'
}finally{$dialog.Dispose()}
Assert-Parallel ($script:parallelHub.Timing.KeyPressMs -eq 17 -and $script:parallelHub.Timing.ForegroundSettleMs -eq 75 -and $timer.Interval -eq 40) 'Saved operation timings were not applied on dialog close.'
$dialog=New-UnifiedSettingsDialog
try {
    $dialog.Show($form);Select-ParallelSettingsPage $dialog $dialog.Tag.Operations
    foreach($key in $originalOperations.Keys){$dialog.Tag.Operations.Tag.Values[$key].Value=$originalOperations[$key]}
    $dialog.Tag.Operations.Tag.Save.PerformClick()
}finally{$dialog.Dispose()}
# Updating a fixture on disk must be reflected by the real Refresh button,
# including moving a newly capped role from the lower table to the upper one.
$snapshotRole=Join-Path $script:rotation.GameDirectories.titan 'WTF\Account\ACCOUNT-A\测试服\角色丙'
$snapshotFile=Join-Path $snapshotRole 'SavedVariables\wow_tools.lua'
$snapshotBytes=[IO.File]::ReadAllBytes($snapshotFile)
try {
    Write-TestCharacterRecord $snapshotRole '角色丙' '测试服' -Version 5 -Level 80 -FreeBagSlots 7 -BindLocation '铁炉堡' -RecordedAt 1792300060
    $refreshButton.PerformClick();Pump-Parallel {-not $script:scanning}
    $freshRecord=@($script:accountTasks.Catalog['titan:ACCOUNT-A'].Characters | Where-Object Name -ceq '角色丙')[0]
    Assert-Parallel ($freshRecord.Level -eq 80 -and $freshRecord.FreeBagSlots -eq 7 -and $freshRecord.BindLocation -ceq '铁炉堡' -and $freshRecord.RecordedAt -eq 1792300060) 'Refresh reused old disk metadata.'
    $dialog=New-UnifiedSettingsDialog
    try {
        $client=$dialog.Tag.Accounts.Tag.Clients.titan
        $roleRow=Get-ParallelRoleRow $client '角色丙'
        Assert-Parallel ($client.FullGrid.Rows.Count -eq 2 -and $client.LevelingGrid.Rows.Count -eq 2 -and $roleRow.DataGridView -eq $client.FullGrid -and
            $roleRow.Cells['FreeBagSlots'].Value -eq 7 -and $roleRow.Cells['BindLocation'].Value -ceq '铁炉堡') 'Refreshed metadata or level grouping did not reach the role tables.'
    }finally{$dialog.Dispose()}
}finally{
    [IO.File]::WriteAllBytes($snapshotFile,$snapshotBytes);Update-AccountTaskCatalog
}
Assert-Parallel (@($rows | Where-Object Validated).Count -eq 3) 'Independent scan/operation acknowledgements did not validate every row.'
$startAllButton.PerformClick()
Pump-Parallel {[ParallelFixture]::Ocr[101] -eq 1 -and [ParallelFixture]::Ocr[202] -gt 0} 2000
Assert-Parallel ([ParallelFixture]::Clicks -eq 0) 'A process clicked before all OCR positions were ready.'
Pump-Parallel {@($rows | Where-Object {$_.CurrentRole -eq '角色甲'}).Count -eq 3}
Assert-Parallel ([ParallelFixture]::EarlyOcr -eq 0 -and [ParallelFixture]::EarlyClicks -eq 0) 'Logout/position barriers were broken.'
Assert-Parallel (@([ParallelFixture]::ReadThread.Values | Sort-Object -Unique).Count -eq 3 -and @([ParallelFixture]::OpThread.Values | Sort-Object -Unique).Count -eq 1) 'Detection is not per-process or operations are not serialized.'
foreach($id in @(101,202,303)){Assert-Parallel ([ParallelFixture]::ReadThread[$id] -eq [ParallelFixture]::OcrThread[$id]) 'OCR ran outside its detector thread.'}
Assert-Parallel (-not ([Threading.Thread]::CurrentThread.ManagedThreadId -in [ParallelFixture]::ReadThread.Values)) 'UI thread performed detection.'
Assert-Parallel ($script:parallelHub.OperatorThreadId -in [ParallelFixture]::OpThread.Values -and
    $script:parallelHub.OperatorThreadId -ne [Threading.Thread]::CurrentThread.ManagedThreadId -and
    $script:wowAutoLog.Writer.ThreadId -ne $script:parallelHub.OperatorThreadId -and
    $script:wowAutoLog.Writer.ThreadId -notin [ParallelFixture]::ReadThread.Values -and
    [object]::ReferenceEquals($script:parallelHub.Logger,$script:wowAutoLog.Writer)) 'The UI, operator, detector and single log-writer thread ownership overlapped.'
$rejected=$false;try{$null=$script:parallelHub.NextOperation()}catch{$rejected=$true}
Assert-Parallel $rejected 'UI thread was allowed to dequeue game operations.'
[ParallelFixture]::BlockPid=101;[ParallelFixture]::Release.Reset()
Pump-Parallel {[ParallelFixture]::BlockedPid -eq 101}
$readsA=[ParallelFixture]::Reads[101];$readsB=[ParallelFixture]::Reads[202]
[Threading.Thread]::Sleep(160);Update-ParallelMessages
Assert-Parallel ([ParallelFixture]::Reads[101] -eq $readsA -and [ParallelFixture]::Reads[202] -gt $readsB) 'A waiting operation did not pause only its own detector.'
$actionsA=[ParallelFixture]::Actions[101];$a.Stop.PerformClick();[Threading.Thread]::Sleep(80);[ParallelFixture]::Release.Set();[ParallelFixture]::BlockPid=0
Pump-Parallel {-not $a.RuntimeRunning}
Assert-Parallel ([ParallelFixture]::Actions[101] -eq $actionsA -and $b.RuntimeRunning -and $c.RuntimeRunning) 'Stop allowed a stale operation or stopped another process.'
$a.Validated=$true;Set-RowControls $a;[ParallelFixture]::FailFocusPid=101;$a.DirectStart.PerformClick()
Pump-Parallel {$a.Status.Text -match '继续后台检测'}
$reads=[ParallelFixture]::Reads[101];[Threading.Thread]::Sleep(180);Update-ParallelMessages
Assert-Parallel ([ParallelFixture]::Reads[101] -gt $reads -and $a.RuntimeRunning) 'Focus retry paused detection/death checks instead of only input.'
Stop-AllRows;Pump-Parallel {@($rows | Where-Object RuntimeRunning).Count -eq 0}
$startAllButton.PerformClick();Pump-Parallel {@($rows | Where-Object {$_.CurrentRole -eq '角色甲'}).Count -eq 3}
foreach($expected in @('角色乙','角色丙','角色丁','角色甲')) {
    $script:parallelNextAt=$script:parallelHub.Now
    Pump-Parallel {@($rows | Where-Object {$_.CurrentRole -eq $expected}).Count -eq 3}
    Assert-Parallel (@($rows | Where-Object {$_.Name.Text -match '职业：'}).Count -eq 0) 'Role rotation restored a class line in the PID area.'
}
Assert-Parallel ($a.RotationSwitchCount -ge 4 -and $b.RotationSwitchCount -ge 4) 'Main-thread global rotation did not cycle through all four account roles.'
Stop-AllRows;Pump-Parallel {@($rows | Where-Object RuntimeRunning).Count -eq 0}
$beforeA=$a.ExecutionRound;$beforeB=$b.ExecutionRound
$a.Validated=$true;$b.Validated=$true;Set-RowControls $a;Set-RowControls $b;$a.DirectStart.PerformClick();$b.DirectStart.PerformClick()
Pump-Parallel {$a.ExecutionRound -gt $beforeA -and $b.ExecutionRound -gt $beforeB}
Assert-Parallel ($a.RuntimeDirect -and $b.RuntimeDirect) 'Direct start did not remain independent.'
if($env:WOWAUTO_PARALLEL_PREVIEW){$bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height);try{$form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$bitmap.Width,$bitmap.Height)));$bitmap.Save((Join-Path $env:WOWAUTO_PARALLEL_PREVIEW 'parallel-main.png'))}finally{$bitmap.Dispose()}}
Stop-AllRows;Set-VersionWaitRanges 25 25 25 25 -Persist $false -JumpEveryCycles 1
[ParallelFixture]::AutoFish=$true;$a.Validated=$true;Set-RowControls $a;$a.DirectStart.PerformClick()
Pump-Parallel {[ParallelFixture]::Reels -eq 1 -and $a.CycleCount -eq 1}
$a.Stop.PerformClick();Assert-Parallel ([ParallelFixture]::Jumps -eq 0) 'Jump interrupted the first reel cooldown.'
$a.DirectStart.PerformClick();Pump-Parallel {[ParallelFixture]::Reels -ge 2}
Assert-Parallel ([ParallelFixture]::Jumps -eq 0) 'Inherited jump request executed before the new successful reel finished its cooldown.'
Pump-Parallel {[ParallelFixture]::Jumps -eq 1}
Assert-Parallel ([ParallelFixture]::EarlyJumps -eq 0 -and [ParallelFixture]::Reels -ge 2) 'Cycle jump did not wait for a successful reel and full cooldown.'
[ParallelFixture]::AutoFish=$false;[ParallelFixture]::Colors[101]='red'
Stop-AllRows
$cycles=$a.CycleCount;[ParallelFixture]::NoBitePid=101;[ParallelFixture]::Colors[101]='green'
$a.Validated=$true;Set-RowControls $a;$a.DirectStart.PerformClick()
Pump-Parallel {$a.BiteTimeoutCount -eq 1}
Assert-Parallel ($a.CycleCount -eq $cycles -and $b.BiteTimeoutCount -eq 0 -and $c.BiteTimeoutCount -eq 0 -and
    $a.Name.Text -match ('循环 '+$cycles+' · 无咬钩超时 1') -and $a.Name.Text -notmatch '职业：') 'Detector timeout did not reach its own UI counter or changed the successful cycle count.'
$a.Stop.PerformClick();[ParallelFixture]::NoBitePid=0;[ParallelFixture]::Colors[101]='red'
$before=$a.ExecutionRound;$a.DirectStart.PerformClick();Pump-Parallel {$a.ExecutionRound -gt $before}
Assert-Parallel ($a.BiteTimeoutCount -eq 1 -and $a.Name.Text -match '无咬钩超时 1') 'Stopping/restarting lost the no-bite timeout count in task-start messages.'
Stop-AllRows;$startAllButton.PerformClick();Pump-Parallel {@($rows | Where-Object {$_.CurrentRole -eq '角色甲'}).Count -eq 3}
$configurationHash=(Get-FileHash $script:accountTasks.Path).Hash
[ParallelFixture]::Colors[101]='dead'
Pump-Parallel {$a.Exited} 10000
Assert-Parallel ($a.ExcludedNames.Count -eq 4 -and [ParallelFixture]::ExitRequests -eq 1 -and $b.RuntimeRunning -and $c.RuntimeRunning -and (Get-FileHash $script:accountTasks.Path).Hash -eq $configurationHash) 'Death exclusion did not exhaust only its own account role cycle without editing settings.'
Stop-AllRows;[ParallelFixture]::MissingPid=202;$b.Start.PerformClick()
Pump-Parallel {$b.Exited} 12000
Assert-Parallel ([ParallelFixture]::UpCount -eq 30 -and [ParallelFixture]::ExitRequests -eq 2 -and [ParallelFixture]::KillRequests -eq 0) 'Missing-name retries were not one arrow/one OCR exactly thirty times before normal exit.'
Stop-AllRows;Update-WowAutoRunInfo
Sync-WowAutoLogging
$info=[IO.File]::ReadAllText($script:wowAutoLog.InfoPath) | ConvertFrom-Json
Assert-Parallel ($info.ProcessCount -eq 3 -and $info.Processes[0].Roles.Count -eq 4 -and -not $info.Processes[0].PSObject.Properties['Slots']) 'Info snapshot still describes three process slots.'
$log=@([IO.File]::ReadAllLines($script:wowAutoLog.LogPath) | ForEach-Object {$_ | ConvertFrom-Json})
Assert-Parallel (@($log | Where-Object {$_.Kind -eq 'audio-timeout' -and $_.Pid -eq 101 -and $_.Message -match '保护 1000 ms' -and
    $_.Message -match '最高峰值 0.90%' -and $_.Message -match '已比较候选 0' -and $_.Message -match '模板 titan-' -and $_.Message -match '自适应音量门槛 0.340%'}).Count -eq 1) 'No-bite timeout did not log one per-process adaptive audio diagnostic snapshot.'
Assert-Parallel (@($log | Where-Object {$_.Kind -eq 'status' -and $_.Pid -and $_.ThreadId -in [ParallelFixture]::ReadThread.Values}).Count -gt 0) 'Detection threads did not write PID-associated logs.'
Assert-Parallel (@($log.WriterThreadId | Sort-Object -Unique).Count -eq 1 -and $log[0].WriterThreadId -eq $script:wowAutoLog.Writer.ThreadId) 'Startup/UI/detector/operator logs were not written by one dedicated log thread.'
Write-Output 'PASS: per-process detector/OCR threads, one operator, request acknowledgement pauses only its detector, parallel OCR/batch barriers, cancellation isolation, independent direct starts, client child tabs and independent atomic account/period saves, global four-role wraparound, death exhaustion isolated to one process, exactly thirty arrow/OCR retries, UI-only updates and PID/thread logs. All frames/OCR/inputs/process exits are substitutes.'
${function:Get-WowAutoRestartOptions}={return @{FilePath='mock-wowAuto-restart';WorkingDirectory=$PSScriptRoot;WindowStyle='Hidden';ErrorAction='Stop';ArgumentList=@()}}
${function:Show-WowAutoRestartError}={param([string]$Message) [ParallelFixture]::RestartError=$Message}
function global:Start-Process([string]$FilePath,[string]$WorkingDirectory,[string]$WindowStyle,[string[]]$ArgumentList,[string]$ErrorAction) {
    Assert-Parallel ($script:restartCleanupComplete -and $script:parallelHub.Closing -and $script:parallelWorkers.Count -eq 0 -and $script:parallelOperator.Async.IsCompleted) 'Restart launched before the worker/operator cleanup barrier.'
    Assert-Parallel (-not $script:wowAutoLog.Writer.IsAlive) 'Restart launched before the log queue drained and the log thread stopped.'
    [ParallelFixture]::RestartLaunched=$true
}
$before=$c.ExecutionRound;$c.Validated=$true;Set-RowControls $c;$c.DirectStart.PerformClick();Pump-Parallel {$c.ExecutionRound -gt $before}
[ParallelFixture]::BlockPid=303;[ParallelFixture]::Release.Reset();Pump-Parallel {[ParallelFixture]::BlockedPid -eq 303}
Request-WowAutoRestart
if(-not $script:restartRequested){[ParallelFixture]::RestartError='Restart request rejected: '+$countLabel.Text}
