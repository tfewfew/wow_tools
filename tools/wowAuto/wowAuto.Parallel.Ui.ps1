# These adapters run only on the dedicated STA UI thread. Workers receive JSON snapshots.
$script:legacySettingsFactory=${function:New-UnifiedSettingsDialog}
$script:legacyRotationSave=${function:Save-RotationConfiguration}
function Save-RotationConfiguration($Interval=$script:rotation.IntervalSeconds,$Plans=$script:rotation.Plans,$OcrIntervalMs=$script:rotation.OcrIntervalMs,$GameDirectories=$script:rotation.GameDirectories) {
    $old=$script:rotation.IntervalSeconds
    & $script:legacyRotationSave -Interval $Interval -Plans $Plans -OcrIntervalMs $OcrIntervalMs -GameDirectories $GameDirectories
    if($old -ne $script:rotation.IntervalSeconds){
        $script:parallelNextAt=if($script:rotation.IntervalSeconds -and @($script:rows.Values | Where-Object {$_.RuntimeRunning -and -not $_.RuntimeDirect}).Count){$script:parallelHub.Now+[long]$script:rotation.IntervalSeconds*1000}else{0L}
    }
}
function Release-AutoFightHold {return $true} # All native input, including release, belongs to the operator.
function Test-UnifiedTaskRunning($Row) {return [bool]$Row.RuntimeRunning}
function Test-UnifiedRowRunning($Row) {return [bool]$Row.RuntimeRunning}
function Read-RowWindowPosition($Row) {return $Row.Position}
function Update-WindowPositions {} # Positions arrive as detector messages.
function Add-ProcessTaskControls($Row) {
    $Row | Add-Member NoteProperty DefaultTaskMode 'fish'
    foreach($entry in @{TaskMode='fish';FightRow=$null;SlotUseItem=$false;AccountName='';RuntimeRunning=$false;RuntimeDirect=$false;RuntimeScanning=$false;RuntimeExiting=$false;RuntimePhase='stopped';TargetRole='';CurrentRole='';CurrentIndex=-1;ExecutionRound=0;ExcludedNames=@();RotationSwitchCount=0L;CycleCount=0L;BiteTimeoutCount=0L;CurrentClassId=0;Metrics=$null;RenderedStatus=''}.GetEnumerator()){$Row | Add-Member NoteProperty $entry.Key $entry.Value}
    $accountLabel=New-Object Windows.Forms.Label;$accountLabel.Text='子战网';$accountLabel.SetBounds(12,106,90,28)
    $account=New-Object Windows.Forms.Label;$account.SetBounds(110,106,400,28);$account.AutoEllipsis=$true
    $account.ForeColor=$script:uiColors.Text
    $configure=New-Object WowAuto.DimButton;$configure.Text='配置角色任务';$configure.SetBounds(520,102,178,34);Set-UiButtonStyle $configure
    $configure.Tag=$Row;$configure.Add_Click({param($sender,$e) Show-AccountTaskSettings $sender.Tag})
    $summary=New-Object Windows.Forms.Label;$summary.SetBounds(12,146,686,34);$summary.AutoEllipsis=$true
    $progress=New-Object Windows.Forms.Label;$progress.SetBounds(12,192,686,26);$progress.AutoEllipsis=$true
    $Row | Add-Member NoteProperty AccountText $account;$Row | Add-Member NoteProperty RotationLabel $summary;$Row | Add-Member NoteProperty RotationProgress $progress
    $Row | Add-Member NoteProperty AccountSettings $configure
    $Row.Panel.Controls.AddRange([Windows.Forms.Control[]]@($accountLabel,$account,$configure,$summary,$progress))
    Update-RowAccountChoices $Row
}
function Update-RowAccountChoices($Row) {
    if(-not $Row.PSObject.Properties['AccountText']){return}
    try {
        if($Row.AccountName -and -not $script:accountTasks.Catalog.ContainsKey($Row.Client.Flavor+':'+$Row.AccountName)){$Row.AccountName=''}
        $roles=@(Get-AccountTaskRoles $Row)
        $defaultMode=if($roles.Count){$roles[0].Mode}else{'fish'}
        if($defaultMode -cne $Row.DefaultTaskMode){$Row.DefaultTaskMode=$defaultMode;$Row.Validated=$false}
        if(-not $Row.RuntimeRunning -and -not $Row.Validated){$Row.TaskMode=$defaultMode;$Row.SlotUseItem=($roles.Count -gt 0 -and $roles[0].UseItem)}
        Update-RotationRow $Row
    }catch{$Row.AccountName='';Set-RowStatusText $Row ('子战网目录读取失败：'+$_.Exception.Message)}
}
function Get-ParallelRoleRecord($Row,[string]$Name=$Row.CurrentRole) {
    if(-not $Name){return $null}
    $key=$Row.Client.Flavor+':'+$Row.AccountName
    $roles=@($script:accountTasks.Config.Accounts[$key] | Where-Object {$_.Name -ceq $Name})
    if($roles.Count -ne 1){return $null}
    $records=@($script:accountTasks.Catalog[$key].Characters | Where-Object {$_.Name -ceq $Name -and $_.Realm -ceq $roles[0].Realm})
    if($records.Count -eq 1){return $records[0]}
    return $null
}
function Get-ParallelRowClassId($Row) {
    if($Row.RuntimePhase -eq 'running' -and $Row.TaskMode -eq 'fight' -and $Row.CurrentClassId -gt 0){return [int]$Row.CurrentClassId}
    $record=Get-ParallelRoleRecord $Row
    if($record){return [int]$record.ClassId}
    return 0
}
function Update-RotationRow($Row) {
    if(-not $Row.PSObject.Properties['RotationLabel']){return}
    $Row.AccountText.Text=if($Row.AccountName){$Row.AccountName}elseif($Row.RuntimeRunning -and -not $Row.RuntimeDirect){'识别中（等待选角界面）'}else{'未识别（开始任务后自动识别）'}
    $roles=@(Get-AccountTaskRoles $Row)
    $Row.RotationLabel.Text=if($Row.AccountName){'启用 '+$roles.Count+' 个角色：'+(($roles | ForEach-Object {$_.Name+' / '+$(if($_.Mode -eq 'fight'){'战斗'}else{'钓鱼'})}) -join '、')}else{'开始任务后通过选角页角色名识别子战网，并加载该子战网角色任务。'}
    $remaining=if($Row.RuntimeDirect){'直接开始'}elseif(-not $Row.RuntimeRunning){'--'}elseif($script:parallelHub.Batch -and -not $script:parallelHub.Batch.All(8)){'角色切换中'}elseif($script:parallelNextAt){[Math]::Max(0,[int][Math]::Ceiling(($script:parallelNextAt-$script:parallelHub.Now)/1000.0)).ToString()+'秒'}else{'未启用定时轮转'}
    $Row.RotationProgress.Text='当前角色：'+$(if($Row.CurrentRole){$Row.CurrentRole}elseif($Row.TargetRole){'切换至'+$Row.TargetRole}elseif($Row.RuntimeDirect -and $Row.RuntimeRunning){'当前已登录角色'}elseif($Row.RuntimeRunning){'确认中'}else{'未运行'})+'   剩余时间：'+$remaining+'   切换：'+$Row.RotationSwitchCount+'次'
    $Row.RotationProgress.ForeColor=Get-WowClassColor (Get-ParallelRowClassId $Row)
}
function Set-RowControls($Row) {
    if(-not $Row.PSObject.Properties['RuntimeRunning']){return}
    $available=-not $Row.Exited -and -not $Row.RuntimeExiting -and -not $script:scanning -and -not $script:editingSettings -and -not $script:parallelHub.Closing
    if($script:parallelWorkers.ContainsKey($Row.Key) -and $script:parallelWorkers[$Row.Key].Endpoint.Closed){$available=$false}
    $Row.Start.Enabled=$available -and -not $Row.RuntimeRunning -and (Test-AccountDiscoveryAvailable $Row)
    $Row.DirectStart.Enabled=$available -and -not $Row.RuntimeRunning -and $Row.Validated
    $Row.Stop.Enabled=$Row.RuntimeRunning -or $Row.RuntimeScanning -or $Row.RuntimeExiting
    $Row.AccountSettings.Enabled=-not $script:scanning -and -not $script:editingSettings
    Update-RotationRow $Row
}
function Set-RowStatusText($Row,[string]$Message,[switch]$FromWorker) {
    if($Row.StatusMessage -ceq $Message){return}
    $Row.StatusMessage=$Message;$Row.StatusHistory.Insert(0,('['+[datetime]::Now.ToString('HH:mm:ss')+'] '+$Message))
    while($Row.StatusHistory.Count -gt $script:statusLogLimit){$Row.StatusHistory.RemoveAt($Row.StatusHistory.Count-1)}
    $Row.Status.SetStatusText(($Row.StatusHistory -join [Environment]::NewLine))
    if(-not $FromWorker){Write-WowAutoLog $Message $Row control}
    Set-RowControls $Row
}
function Update-RowStatus($Row) {Update-RowName $Row;Set-RowControls $Row}
function Update-RowName($Row) {
    $classId=Get-ParallelRowClassId $Row
    $Row.Name.ForeColor=Get-WowClassColor $classId
    $Row.Name.Text=$Row.Caption+[Environment]::NewLine+'PID '+$Row.Process.Id+' · '+$Row.Client.Label+' · '+$Row.Position
    if($Row.TaskMode -eq 'fish'){$Row.Name.Text+=[Environment]::NewLine+'循环 '+$Row.CycleCount+' · 无咬钩超时 '+$Row.BiteTimeoutCount}
}
function Update-ParallelStatusDisplay($Row) {
    if(-not $Row.StatusHistory.Count){return}
    $first=$Row.StatusHistory[0]
    if($Row.RuntimePhase -eq 'running' -and $Row.Metrics) {
        if($Row.Metrics.Deadline -gt $script:parallelHub.Now){$first+=[Environment]::NewLine+'剩余 '+[int]($Row.Metrics.Deadline-$script:parallelHub.Now)+' ms'}
        if($Row.Metrics.Audio){$first+=[Environment]::NewLine+('音频匹配 {0:P0} · 峰值 {1:F3}' -f $Row.Metrics.Similarity,$Row.Metrics.Peak)}
    }
    $lines=@($first)+@($Row.StatusHistory | Select-Object -Skip 1);$text=$lines -join [Environment]::NewLine
    if($text -cne $Row.RenderedStatus){$Row.RenderedStatus=$text;$Row.Status.SetStatusText($text)}
}
function Start-Row($Row,[switch]$TaskOnly) {
    if($Row.RuntimeRunning -or $script:editingSettings -or $script:scanning -or $script:shutdownState.Started){return}
    if(-not (Test-AccountDiscoveryAvailable $Row)){Set-RowStatusText $Row '请在设置中为本客户端的子战网启用至少一个角色。';return}
    $Row.ExcludedNames=@();Start-ParallelBatch @($Row) Start
}
function Start-RowDirect($Row) {
    if($Row.RuntimeRunning -or -not $Row.Validated -or $script:editingSettings -or $script:scanning -or $script:shutdownState.Started){return}
    $Row.RuntimeRunning=$true;$Row.RuntimeDirect=$true
    $script:parallelHub.ActiveTasks=@($script:rows.Values | Where-Object RuntimeRunning).Count
    Send-ParallelCommand $Row Start '' $true;Set-RowControls $Row
}
function Stop-Row($Row,[string]$Reason='已停止，本进程的待执行操作已取消。',[switch]$CancelExit,[switch]$KeepRotation) {
    if($script:parallelWorkers.ContainsKey($Row.Key)){$null=$script:parallelWorkers[$Row.Key].Endpoint.Send('Stop','{}')}
    $script:parallelPending.Remove($Row.Key)
    if($script:parallelHub.Batch){$script:parallelHub.Batch.Drop($Row.Key)}
    $Row.RuntimeRunning=$false;$Row.RuntimeScanning=$false;$Row.RuntimeExiting=$false;$Row.RuntimePhase='stopped';$Row.Metrics=$null;$Row.TargetRole='';$Row.CurrentRole='';$Row.CurrentIndex=-1
    $script:parallelHub.ActiveTasks=@($script:rows.Values | Where-Object RuntimeRunning).Count
    Set-RowStatusText $Row $Reason;Update-WowAutoRunInfo
}
function Stop-AllRows {
    foreach($row in @($script:rows.Values)){Stop-Row $row}
    $script:parallelNextAt=0L;$script:scanning=$false;$script:parallelPending.Clear();Update-BatchControls
}
function Start-AllRows {
    if($script:editingSettings -or $script:scanning -or $script:shutdownState.Started){return}
    $rows=@($script:rows.Values | Where-Object {$_.Start.Enabled -and -not $_.RuntimeRunning})
    foreach($row in $rows){$row.ExcludedNames=@()};Start-ParallelBatch $rows Start
}
function Begin-RefreshScan {
    if($script:editingSettings -or $script:scanning -or $script:shutdownState.Started){return}
    Stop-AllRows;Update-AccountTaskCatalog
    $null=Refresh-ProcessRows
    foreach($key in @($script:parallelWorkers.Keys)) {if(-not $script:rows.ContainsKey($key)){$script:parallelHub.Remove($key);$script:parallelRetired+=,$script:parallelWorkers[$key];$script:parallelWorkers.Remove($key)}}
    $script:scanning=$script:rows.Count -gt 0
    $script:parallelOriginal=if($UiTest){[IntPtr]::Zero}else{[WowAuto.NativeInput]::CurrentWindow()}
    foreach($row in $script:rows.Values){$row.Validated=$false;$row.RuntimeScanning=$true;Update-RowAccountChoices $row;Send-ParallelCommand $row Scan;Set-RowStatusText $row '检测线程等待操作线程开启监控，完成后后台检测色块。'}
    Update-WowAutoRunInfo;Update-BatchControls
}
function Update-BatchControls {
    foreach($row in $script:rows.Values){Set-RowControls $row}
    $countLabel.Text='进程 '+$script:rows.Count+' · 验证通过 '+@($script:rows.Values | Where-Object Validated).Count
    $refreshButton.Enabled=-not $script:scanning -and -not $script:editingSettings
    $settingsButton.Enabled=-not $script:scanning -and -not $script:editingSettings
    $restartButton.Enabled=-not $script:editingSettings -and -not $script:restartRequested
    $startAllButton.Enabled=@($script:rows.Values | Where-Object {$_.Start.Enabled}).Count -gt 0
    $stopAllButton.Enabled=$script:scanning -or @($script:rows.Values | Where-Object {$_.RuntimeRunning -or $_.RuntimeExiting}).Count -gt 0
    Update-WowAutoShutdownControls
}
function New-UnifiedSettingsDialog {
    $script:parallelHub.Paused=$true
    try {
        $dialog=& $script:legacySettingsFactory
        $area=[Windows.Forms.Screen]::FromControl($form).WorkingArea
        $dialog.Width=[Math]::Min(1440,$area.Width)
        $page=New-AccountTaskSettingsPage;$dialog.Tag.Tabs.TabPages.Add($page);$dialog.Tag | Add-Member NoteProperty Accounts $page
        $timingPage=New-GlobalTimingSettingsPage;$dialog.Tag.Tabs.TabPages.Add($timingPage);$dialog.Tag | Add-Member NoteProperty Timing $timingPage
        $dialog.Tag | Add-Member NoteProperty DetectionPeriods $timingPage.Tag.Detection
        $dialog.Tag | Add-Member NoteProperty Operations $timingPage.Tag.Operations
        Hide-LegacyTimingInput $dialog.Tag.Fish.Tag.FocusRetry '焦点重试间隔（ms，所有进程）'
        Hide-LegacyTimingInput $dialog.Tag.Fish.Tag.ReelHold '收竿后保持（ms，所有进程）'
        Hide-LegacyTimingInput $dialog.Tag.Fight.Tag.CommandInterval '公共最小按键间隔 (ms)'
        Hide-LegacyTimingInput $dialog.Tag.Fight.Tag.CommonNumbers.InteractionHoldMs '交互等待 (ms)'
        $dialog.Tag.Fish.Tag.AudioDetection.Enabled=-not @($script:rows.Values | Where-Object {$_.RuntimeRunning -and $_.TaskMode -eq 'fish'}).Count
        # The OCR period now belongs beside all other detector periods.
        $bar=$dialog.Tag.Rotation.Value.Parent
        foreach($control in $bar.Controls){if($control.Top -ge 60 -and $control -ne $dialog.Tag.Rotation.Save){$control.Visible=$false}}
        $bar.Height=62
        $dialog.Add_Disposed({
            Apply-ParallelTimings
            Update-AccountTaskCatalog
            foreach($row in $script:rows.Values){Update-RowAccountChoices $row}
            foreach($row in $script:rows.Values){if($script:parallelWorkers.ContainsKey($row.Key)){$script:parallelWorkers[$row.Key].Endpoint.Notify('Configure',((Get-ParallelConfig $row) | ConvertTo-Json -Depth 15 -Compress))}}
            $script:parallelHub.Paused=$false
        })
        return $dialog
    }catch{$script:parallelHub.Paused=$false;throw}
}
function Show-AccountTaskSettings($Row) {
    if($script:scanning -or $script:editingSettings){return}
    $script:editingSettings=$true;$dialog=$null
    try {
        $dialog=New-UnifiedSettingsDialog;$dialog.Tag.Tabs.SelectedTab=$dialog.Tag.Accounts
        $client=$dialog.Tag.Accounts.Tag.Clients[$Row.Client.Flavor]
        $dialog.Tag.Accounts.Tag.ClientTabs.SelectedTab=$client.Page
        if($client.Accounts.Items.Contains($Row.AccountName)){$client.Accounts.SelectedItem=$Row.AccountName}
        $null=$dialog.ShowDialog($form)
    }finally{if($dialog){$dialog.Dispose()};$script:editingSettings=$false;Update-BatchControls}
}
function Get-WowAutoRunInfo {
    $processes=@(foreach($row in @($script:rows.Values | Sort-Object {$_.Process.Id})) {
        $key=$row.Client.Flavor+':'+$row.AccountName
        $roles=@(foreach($role in $script:accountTasks.Config.Accounts[$key]){@{Role=$role.Name;Realm=$role.Realm;Task=$role.Mode;Enabled=$role.Enabled;UseItem=$role.UseItem;Excluded=($role.Name -cin $row.ExcludedNames)}})
        @{Pid=$row.Process.Id;Client=$row.Client.Flavor;SubAccount=$row.AccountName;SubAccountSource=$(if($row.AccountName){'ocr'}else{'unknown'});Roles=$roles;CurrentRole=$row.CurrentRole;CurrentRoleIndex=$row.CurrentIndex;CurrentTask=$(if($row.RuntimePhase -eq 'running'){$row.TaskMode}else{''});CurrentPhase=$row.RuntimePhase;ExecutionRound=$row.ExecutionRound}
    })
    return @{StartTime=$script:wowAutoLog.StartedAt.ToString('o');ProcessCount=$processes.Count;Processes=$processes}
}
function Update-WowAutoRunInfo {
    if($script:parallelHub){try{$script:parallelHub.WriteInfo((Get-WowAutoRunInfo | ConvertTo-Json -Depth 10))}catch{$settingsSummary.Text='日志快照保存失败：'+$_.Exception.Message}}
}
function Write-WowAutoLog([string]$Message,$Row=$null,[string]$Kind='status') {
    if(-not $script:parallelHub){return}
    $endpoint=if($Row -and $script:parallelWorkers.ContainsKey($Row.Key)){$script:parallelWorkers[$Row.Key].Endpoint}else{$null}
    if($Row -and -not $endpoint){$endpoint=New-Object WowAuto.Threading.Endpoint;$endpoint.Key=$Row.Key;$endpoint.Pid=$Row.Process.Id;$endpoint.StartTicks=$Row.StartTime.Ticks;$endpoint.Path=$Row.Client.ExecutablePath;$endpoint.Flavor=$Row.Client.Flavor}
    try{$script:parallelHub.Log($endpoint,$(if($endpoint){$endpoint.Version}else{0}),$Kind,$Message)}catch{$settingsSummary.Text='日志写入失败：'+$_.Exception.Message}
}
function Set-WowAutoLogSizeMB($Value) {
    $size=0;if(-not [int]::TryParse([string]$Value,[ref]$size) -or $size -lt 1 -or $size -gt 1024){throw '日志大小须为1–1024 MB。'}
    $script:wowAutoLog.MaxSizeMB=$size;$script:parallelHub.LogMaxSizeMB=$size;return $size
}
