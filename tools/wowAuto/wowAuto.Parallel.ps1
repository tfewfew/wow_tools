# The UI runspace coordinates workers and consumes messages; it never performs game input.
if(-not ('WowAuto.Threading.Hub' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'wowAuto.Threading.cs') -ReferencedAssemblies System.Core}
. (Join-Path $PSScriptRoot 'wowAuto.AccountTasks.ps1')
. (Join-Path $PSScriptRoot 'wowAuto.AccountTasks.Ui.ps1')
. (Join-Path $PSScriptRoot 'wowAuto.Timing.Ui.ps1')
function New-ParallelPipeline([string]$Script,$Endpoint=$null,[string]$Mock='') {
    $runspace=[RunspaceFactory]::CreateRunspace();$runspace.ApartmentState='MTA';$runspace.ThreadOptions='ReuseThread';$runspace.Open()
    $pipeline=[PowerShell]::Create();$pipeline.Runspace=$runspace
    $null=$pipeline.AddScript([IO.File]::ReadAllText((Join-Path $PSScriptRoot $Script))).AddArgument($script:parallelHub)
    if($Endpoint){$null=$pipeline.AddArgument($Endpoint)}
    $null=$pipeline.AddArgument($PSScriptRoot).AddArgument($Mock)
    try {$async=$pipeline.BeginInvoke();return [pscustomobject]@{Pipeline=$pipeline;Runspace=$runspace;Async=$async;Endpoint=$Endpoint}}
    catch{$pipeline.Dispose();$runspace.Dispose();throw}
}
function Get-ParallelConfig($Row) {
    $range=$script:versionRanges[$Row.Client.Flavor];$recording=Get-AudioRecording $Row.Client.Flavor $script:audioRecordingSelections[$Row.Client.Flavor]
    $operations=$script:accountTasks.Config.Operations
    $common=ConvertTo-TaskMap $script:autoFight.Common;$common.InteractionHoldMs=$operations.InteractionHoldMs
    return @{MinimumMs=$range.MinimumMs;MaximumMs=$range.MaximumMs;AudioTimeoutMs=$range.AudioTimeoutMs;
        FocusRetryMs=$operations.FocusRetryMs;ReelHoldMs=$operations.ReelHoldMs;JumpEveryCycles=$script:scheduler.JumpEveryCycles;
        UseAudio=$script:audioDetectionEnabled;FeaturePath=(Join-Path $script:audioFeatureDirectory $recording.Feature);AudioThreshold=$script:audioThresholds[$Row.Client.Flavor];
        Keys=@{Cast=$script:keyBindings.Cast.Text;Reel=$script:keyBindings.Reel.Text;Item=$script:keyBindings.Item.Text};
        Profiles=$script:autoFight.Profiles;ProfilesReady=$script:autoFight.ConfigReady;Common=$common;CommandIntervalMs=$operations.CommandIntervalMs;
        Operations=$operations;Periods=$script:accountTasks.Config.Periods;Priorities=$script:gameActions.Priorities}
}
function Apply-ParallelTimings {
    $values=$script:accountTasks.Config.Operations
    $timing=New-Object WowAuto.Threading.QueueTimings
    foreach($key in $values.Keys){$timing.$key=[int]$values[$key]}
    $script:parallelHub.ConfigureTiming($timing);$timer.Interval=$values.UiRefreshMs
    $script:scheduler.FocusRetryIntervalMs=$values.FocusRetryMs;$script:scheduler.ReelHoldMs=$values.ReelHoldMs
    $script:autoFight.CommandGate.IntervalMs=$values.CommandIntervalMs;$script:autoFight.Common.InteractionHoldMs=$values.InteractionHoldMs
    Update-VersionSummary
}
function Ensure-ParallelWorker($Row) {
    if($script:parallelWorkers.ContainsKey($Row.Key) -and $script:parallelWorkers[$Row.Key].Endpoint.Closed){
        $script:parallelHub.Remove($Row.Key);$script:parallelRetired+=,$script:parallelWorkers[$Row.Key];$script:parallelWorkers.Remove($Row.Key)
    }
    if($script:parallelWorkers.ContainsKey($Row.Key)){return $script:parallelWorkers[$Row.Key].Endpoint}
    $endpoint=$script:parallelHub.Register($Row.Key,$Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath,$Row.Client.Flavor)
    $script:parallelWorkers[$Row.Key]=New-ParallelPipeline 'wowAuto.Detector.ps1' $endpoint $script:parallelMockDetector
    $endpoint.Notify('Configure',((Get-ParallelConfig $Row) | ConvertTo-Json -Depth 15 -Compress))
    return $endpoint
}
function Send-ParallelCommand($Row,[string]$Kind,[string]$BatchId='',[bool]$Direct=$false) {
    $endpoint=Ensure-ParallelWorker $Row
    $payload=@{Config=(Get-ParallelConfig $Row);Roles=@(Get-AccountTaskRoles $Row);BatchId=$BatchId;Direct=$Direct;Mode=$Row.TaskMode;UseItem=$Row.SlotUseItem;RoundBase=$Row.ExecutionRound}
    $endpoint.Notify('Configure',($payload.Config | ConvertTo-Json -Depth 15 -Compress))
    $null=$endpoint.Send($Kind,($payload | ConvertTo-Json -Depth 15 -Compress))
}
function Start-ParallelBatch($Rows,[string]$Kind='Rotate') {
    $participants=@($Rows | Where-Object {$_ -and -not $_.Exited -and @(Get-AccountTaskRoles $_).Count})
    if(-not $participants.Count){return}
    if($script:parallelHub.Batch -and -not $script:parallelHub.Batch.All(8)) {
        foreach($row in $participants){$script:parallelPending[$row.Key]=$Kind;$row.RuntimeRunning=$true;Set-RowStatusText $row '等待当前角色切换批次完成。'}
        return
    }
    $script:parallelHub.Batch=New-Object WowAuto.Threading.RotationBatch(,[string[]]@($participants | ForEach-Object Key))
    foreach($row in $participants){$row.RuntimeRunning=$true;$row.RuntimeDirect=$false;Send-ParallelCommand $row $Kind $script:parallelHub.Batch.Id;Set-RowControls $row}
    $script:parallelNextAt=if($script:rotation.IntervalSeconds){$script:parallelHub.Now+[long]$script:rotation.IntervalSeconds*1000}else{0L}
    $script:parallelHub.ActiveTasks=@($script:rows.Values | Where-Object RuntimeRunning).Count
}
function Stop-ParallelRuntime {
    if(-not $script:parallelHub){return}
    $script:parallelHub.Close()
    foreach($worker in @($script:parallelWorkers.Values)+@($script:parallelRetired)+@($script:parallelOperator)) {
        if(-not $worker){continue}
        if(-not $worker.Async.AsyncWaitHandle.WaitOne(5000)){$worker.Pipeline.Stop()}
        try {$null=$worker.Pipeline.EndInvoke($worker.Async)}catch{}
        $worker.Pipeline.Dispose();$worker.Runspace.Dispose()
    }
    $script:parallelWorkers.Clear();[WowAutoCapture.Native]::Shutdown()
}
function Update-ParallelMessages {
    $logError=$script:wowAutoLog.Writer.TakeError()
    if($logError){$settingsSummary.Text='日志写入失败：'+$logError}
    for($i=0;$i -lt 500;$i++) {
        $notice=$script:parallelHub.NextNotice();if(-not $notice){break}
        $row=$script:rows[$notice.Key]
        if(-not $row -or -not $script:parallelWorkers.ContainsKey($notice.Key) -or $script:parallelWorkers[$notice.Key].Endpoint.Version -ne $notice.Version){continue}
        if($notice.Kind -eq 'status'){Set-RowStatusText $row $notice.Json -FromWorker;continue}
        $data=$notice.Json | ConvertFrom-Json
        switch($notice.Kind) {
            'position' {$row.Position=$data.Text;Update-RowName $row}
            'scanned' {$row.Validated=$data.Valid;$row.RuntimeScanning=$false;Set-RowControls $row}
            'switching' {$row.CurrentRole='';$row.CurrentIndex=-1;$row.Metrics=$null;$row.TargetRole=$data.TargetRole;$row.RuntimePhase='switching';Update-WowAutoRunInfo}
            'taskstart' {$row.RuntimeRunning=$true;$row.RuntimeExiting=$false;$row.RuntimePhase='running';$row.Validated=$true;$row.Metrics=$null;$row.TargetRole='';$row.CurrentRole=$data.Role;$row.CurrentIndex=$data.Index;$row.ExecutionRound=$data.Round;$row.TaskMode=$data.Mode;$row.SlotUseItem=$data.UseItem;$row.RuntimeDirect=$data.Direct;$row.RotationSwitchCount=$data.SwitchCount;$row.CycleCount=$data.Cycles;$row.BiteTimeoutCount=$data.BiteTimeouts;$row.CurrentClassId=$data.ClassId;Update-RowName $row;Update-WowAutoRunInfo}
            'metrics' {$row.Metrics=$data;$row.CycleCount=$data.Cycles;$row.BiteTimeoutCount=$data.BiteTimeouts;Update-RowName $row}
            'counters' {$row.CycleCount=$data.Cycles;$row.BiteTimeoutCount=$data.BiteTimeouts;Update-RowName $row}
            'exiting' {$row.RuntimeRunning=$false;$row.RuntimeExiting=$true;$row.RuntimePhase='exiting';Set-RowControls $row;Update-WowAutoRunInfo}
            'stopped' {$row.RuntimeRunning=$false;$row.RuntimeScanning=$false;$row.RuntimeExiting=$false;$row.RuntimePhase='stopped';$row.TargetRole='';$row.CurrentRole='';$row.CurrentIndex=-1;if($data.Exited){$row.Exited=$true};Set-RowControls $row;Update-WowAutoRunInfo}
            'excluded' {$row.ExcludedNames+=,$data.Name;Update-WowAutoRunInfo}
            'rotate-needed' {$script:parallelPending[$row.Key]='Rotate'}
        }
    }
    foreach($key in @($script:parallelWorkers.Keys)) {
        $worker=$script:parallelWorkers[$key]
        if($worker.Async.IsCompleted -and -not $worker.Endpoint.Closed) {
            try{$null=$worker.Pipeline.EndInvoke($worker.Async);$detail=$worker.Pipeline.Streams.Error | Out-String}catch{$detail=$_.Exception.Message}
            $worker.Endpoint.Close()
            if($script:rows.ContainsKey($key)){$row=$script:rows[$key];$row.RuntimeRunning=$false;$row.RuntimeScanning=$false;Set-RowStatusText $row ('检测线程异常结束：'+$detail)}
        }
        if($worker.Async.IsCompleted -and $worker.Endpoint.Closed -and $script:rows.ContainsKey($key) -and $script:rows[$key].Exited){
            $script:parallelHub.Remove($key);$script:parallelRetired+=,$worker;$script:parallelWorkers.Remove($key)
        }
    }
    $retained=@()
    foreach($worker in $script:parallelRetired) {
        if($worker.Async.IsCompleted){try{$null=$worker.Pipeline.EndInvoke($worker.Async)}catch{};$worker.Pipeline.Dispose();$worker.Runspace.Dispose()}
        else{$retained+=,$worker}
    }
    $script:parallelRetired=$retained
    if($script:parallelOperator.Async.IsCompleted -and -not $script:parallelHub.Closing) {
        Stop-AllRows;$script:parallelHub.Close();$settingsSummary.Text='操作线程已结束，所有任务已停止，请重启脚本。'
    }
    $script:parallelHub.ActiveTasks=@($script:rows.Values | Where-Object RuntimeRunning).Count
    if($script:scanning -and -not @($script:rows.Values | Where-Object RuntimeScanning).Count) {
        $script:scanning=$false
        if($script:parallelOriginal -ne [IntPtr]::Zero -and $script:rows.Count) {
            $row=@($script:rows.Values)[0];$endpoint=Ensure-ParallelWorker $row
            $null=$script:parallelHub.Request($endpoint,$endpoint.Version,'Scan.Restore','Restore',90,(@{Window=$script:parallelOriginal.ToInt64()} | ConvertTo-Json -Compress))
        }
        $script:parallelOriginal=[IntPtr]::Zero
    }
    if(-not $script:editingSettings -and -not $script:parallelHub.Paused -and (-not $script:parallelHub.Batch -or $script:parallelHub.Batch.All(8))) {
        if($script:parallelPending.Count) {
            $pending=$script:parallelPending.Clone();$script:parallelPending.Clear()
            $startRows=@($pending.Keys | Where-Object {$pending[$_] -eq 'Start'} | ForEach-Object {$script:rows[$_]})
            if($startRows.Count){Start-ParallelBatch $startRows Start;foreach($key in $pending.Keys){if($pending[$key] -ne 'Start'){$script:parallelPending[$key]=$pending[$key]}}}
            else {Start-ParallelBatch @($pending.Keys | ForEach-Object {$script:rows[$_]})}
        } elseif($script:parallelNextAt -and $script:parallelHub.Now -ge $script:parallelNextAt -and -not $script:editingSettings) {
            Start-ParallelBatch @($script:rows.Values | Where-Object {$_.RuntimeRunning -and -not $_.RuntimeDirect})
        }
    }
    foreach($row in $script:rows.Values){Update-RotationRow $row;Update-ParallelStatusDisplay $row}
    Update-BatchControls
}
function Initialize-ParallelRuntime {
    $script:parallelWorkers=@{};$script:parallelRetired=@();$script:parallelPending=@{};$script:parallelNextAt=0L;$script:parallelOriginal=[IntPtr]::Zero
    $script:parallelMockDetector='';$mockOperator=''
    if($UiTest) {
        if(-not $env:WOWAUTO_PARALLEL_OPERATOR_MOCK -or -not $env:WOWAUTO_PARALLEL_DETECTOR_MOCK){throw 'Parallel UI tests require explicit input/detection substitutes.'}
        $mockOperator=[IO.File]::ReadAllText($env:WOWAUTO_PARALLEL_OPERATOR_MOCK);$script:parallelMockDetector=[IO.File]::ReadAllText($env:WOWAUTO_PARALLEL_DETECTOR_MOCK)
        if($env:WOWAUTO_PARALLEL_FIXTURE_ROOT){foreach($flavor in @('titan','forerver')){$script:rotation.GameDirectories[$flavor]=Join-Path $env:WOWAUTO_PARALLEL_FIXTURE_ROOT $(if($flavor -eq 'titan'){'_classic_titan_'}else{'_cn_beta_'})}}
        $script:rotation.Path=Join-Path $env:WOWAUTO_PARALLEL_FIXTURE_ROOT 'rotation.json'
        [IO.File]::WriteAllText($script:rotation.Path,(@{Version=2;IntervalSeconds=$script:rotation.IntervalSeconds;OcrIntervalMs=$script:rotation.OcrIntervalMs;Plans=$script:rotation.Plans;GameDirectories=$script:rotation.GameDirectories;NameHistory=$script:rotation.NameHistory} | ConvertTo-Json -Depth 12))
        $fightFixture=Join-Path $env:WOWAUTO_PARALLEL_FIXTURE_ROOT 'fight.json';[IO.File]::Copy($script:autoFight.ConfigPath,$fightFixture);$script:autoFight.ConfigPath=$fightFixture
    }
    $accountPath=if($UiTest){$env:WOWAUTO_PARALLEL_CONFIG_PATH}else{Join-Path $PSScriptRoot 'account-tasks.config.json'}
    $accountError=''
    try{Initialize-AccountTasks $accountPath}
    catch{
        $accountError=$_.Exception.Message
        $script:accountTasks=[pscustomobject]@{Path=$accountPath;Config=@{Version=1;Accounts=@{};Bindings=@{};Periods=(New-DetectionPeriods);Operations=(Get-LegacyOperationTimings)};Catalog=@{};Warnings=@('子战网配置读取失败：'+$accountError+'；所有角色保持停用，请核对后保存。')}
        Update-AccountTaskCatalog
        foreach($roles in $script:accountTasks.Config.Accounts.Values){foreach($role in $roles){$role.Enabled=$false}}
    }
    [WowAutoFight.Native]::FrameReader=[WowAutoCapture.Native]::FrameReader
    [WowAutoFight.Native]::CapturePending=[WowAutoCapture.Native]::PendingReader
    $script:parallelHub=New-Object WowAuto.Threading.Hub($script:wowAutoLog.Writer)
    $script:parallelHub.Simulation=[bool]$UiTest
    Apply-ParallelTimings
    $script:parallelOperator=New-ParallelPipeline 'wowAuto.Operator.ps1' -Mock $mockOperator
    $intro.Text='每个进程绑定一个子战网；在设置中启用角色并配置任务。“开始”按账号角色轮转，“直接开始”使用当前已登录角色。'
    $footer.Text='检测与OCR按进程独立运行；操作线程执行按键和点击，日志线程统一写文件。角色死亡或包满时移出本次轮转，耗尽才退出该进程。'
    $script:parallelHub.Log($null,0,'system','独立检测线程 / 专用操作线程 / 专用日志线程 / UI消息模式已初始化。')
    if($accountError){$settingsSummary.Text='子战网配置读取失败，角色已停用，请打开设置核对：'+$accountError;$script:parallelHub.Log($null,0,'error',$settingsSummary.Text)}
}
