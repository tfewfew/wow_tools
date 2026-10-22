# The UI only owns the monotonic countdown and submits exits to the operator.
$script:shutdownState=@{Deadline=0L;Started=$false;DialogOpen=$false;Operations=@()}
function Get-WowAutoShutdownRemaining([long]$Now=$script:schedulerClock.ElapsedMilliseconds) {
    if($script:shutdownState.Deadline -le 0){return 0L}
    return [long][Math]::Max(0,[Math]::Ceiling(($script:shutdownState.Deadline-$Now)/1000.0))
}
function Set-WowAutoShutdownCountdown($Seconds,[long]$Now=$script:schedulerClock.ElapsedMilliseconds) {
    $value=0
    if(-not [int]::TryParse([string]$Seconds,[ref]$value) -or $value -lt 1){throw '结束时间须为大于0的整数秒。'}
    if($script:shutdownState.Started -or $script:restartRequested){return}
    $script:shutdownState.Deadline=$Now+[long]$value*1000
    $shutdownButton.Text='倒计时：'+$value+'秒'
    Write-WowAutoLog ('已设置结束倒计时：'+$value+'秒；到期退出所有游戏进程，脚本保持运行。') -Kind system
}
function Cancel-WowAutoShutdownCountdown {
    if($script:shutdownState.Started){return}
    if($script:shutdownState.Deadline -gt 0){Write-WowAutoLog '已取消结束倒计时。' -Kind system}
    $script:shutdownState.Deadline=0L;$shutdownButton.Text='结束倒计时'
}
function New-WowAutoShutdownDialog {
    $dialog=New-Object WowAuto.DimForm
    $dialog.Text='结束倒计时';$dialog.Font=$form.Font;$dialog.AutoScaleMode='Dpi'
    $dialog.BackColor=$script:uiColors.Background;$dialog.ForeColor=$script:uiColors.Text
    $dialog.ClientSize=New-Object Drawing.Size(470,180);$dialog.FormBorderStyle='FixedDialog'
    $dialog.StartPosition='CenterParent';$dialog.MinimizeBox=$false;$dialog.MaximizeBox=$false;$dialog.ShowInTaskbar=$false
    $label=New-Object Windows.Forms.Label;$label.Text='多久后退出全部游戏（秒）';$label.SetBounds(18,18,430,30)
    $seconds=New-Object Windows.Forms.NumericUpDown;$seconds.SetBounds(18,55,430,34)
    $seconds.Minimum=1;$seconds.Maximum=[int]::MaxValue;$seconds.DecimalPlaces=0
    $seconds.BackColor=$script:uiColors.Input;$seconds.ForeColor=$script:uiColors.Text
    $seconds.Value=if($script:shutdownState.Deadline -gt 0){[Math]::Max(1,(Get-WowAutoShutdownRemaining))}else{3600}
    $start=New-Object WowAuto.DimButton;$start.Text='开始倒计时';$start.SetBounds(18,116,140,38);Set-UiButtonStyle $start $true
    $start.DialogResult='OK'
    $cancel=New-Object WowAuto.DimButton;$cancel.Text='取消倒计时';$cancel.SetBounds(168,116,140,38);Set-UiButtonStyle $cancel
    $cancel.Enabled=$script:shutdownState.Deadline -gt 0;$cancel.DialogResult='Yes'
    $back=New-Object WowAuto.DimButton;$back.Text='返回';$back.SetBounds(318,116,130,38);Set-UiButtonStyle $back;$back.DialogResult='Cancel'
    $dialog.AcceptButton=$start;$dialog.CancelButton=$back
    $dialog.Controls.AddRange([Windows.Forms.Control[]]@($label,$seconds,$start,$cancel,$back))
    $dialog.Tag=@{Seconds=$seconds;Start=$start;Cancel=$cancel;Back=$back}
    return $dialog
}
function Show-WowAutoShutdownDialog {
    $dialog=New-WowAutoShutdownDialog
    try {
        $result=$dialog.ShowDialog($form)
        if($result -eq 'OK'){return @{Seconds=[int]$dialog.Tag.Seconds.Value;Cancel=$false}}
        if($result -eq 'Yes'){return @{Cancel=$true}}
    } finally {$dialog.Dispose()}
}
function Request-WowAutoShutdownCountdown {
    if($script:shutdownState.Started -or $script:shutdownState.DialogOpen -or $script:editingSettings -or $script:restartRequested){return}
    $script:shutdownState.DialogOpen=$true
    $wasPaused=if($script:useWorkers){$script:parallelHub.Paused}else{$false}
    if($script:useWorkers){$script:parallelHub.Paused=$true}
    try {
        Update-BatchControls
        $choice=Show-WowAutoShutdownDialog
        if($script:shutdownState.Started -or -not $choice){return}
        if($choice.Cancel){Cancel-WowAutoShutdownCountdown}else{Set-WowAutoShutdownCountdown $choice.Seconds}
    } finally {
        if($script:useWorkers){$script:parallelHub.Paused=$wasPaused -and -not $script:shutdownState.Started}
        $script:shutdownState.DialogOpen=$false;Update-BatchControls
    }
}
function Update-WowAutoShutdownControls {
    if(-not $script:shutdownState){return}
    $shutdownButton.Enabled=-not $script:editingSettings -and -not $script:restartRequested -and -not $script:shutdownState.Started -and -not $script:shutdownState.DialogOpen
    if($script:shutdownState.DialogOpen){$restartButton.Enabled=$false}
    if($script:shutdownState.Started){
        foreach($button in @($refreshButton,$startAllButton,$stopAllButton,$settingsButton,$restartButton,$shutdownButton)){$button.Enabled=$false}
        $tabs.Enabled=$false
    }
}
function Start-WowAutoGameShutdown {
    if(-not $script:useWorkers){throw '结束倒计时需要操作线程。'}
    Stop-AllRows
    $script:parallelHub.Paused=$false
    $operations=@()
    foreach($process in @(Get-WowAutoProcesses)) {
        $endpoint=$null
        try {
            $process.Refresh();if($process.HasExited){continue}
            $ticks=$process.StartTime.Ticks;$client=$process.WowAutoClient
            $endpoint=$script:parallelHub.Register(('shutdown:'+$process.Id+':'+$ticks),$process.Id,$ticks,$client.ExecutablePath,$client.Flavor)
            $script:parallelHub.Log($endpoint,$endpoint.Version,'shutdown','结束倒计时归零，排队退出此游戏进程。')
            $operations+=,$script:parallelHub.Request($endpoint,$endpoint.Version,'Process.Shutdown','Process',[int]$script:gameActions.Priorities['Process.Shutdown'],'{}')
        } catch {
            # Preserve the PID even when this process disappears during enumeration.
            if(-not $endpoint){$endpoint=New-Object WowAuto.Threading.Endpoint;$endpoint.Pid=$process.Id}
            $script:parallelHub.Log($endpoint,0,'error',('无法排队退出此游戏进程：'+$_.Exception.Message))
        }
    }
    return $operations
}
function Complete-WowAutoGameShutdown {
    foreach($operation in $script:shutdownState.Operations) {
        if(-not $operation.Success){
            if($script:useWorkers){$script:parallelHub.Log($operation.Owner,$operation.Version,'error',('倒计时退出未完成：'+$operation.Error))}
            else{Write-WowAutoLog ('倒计时退出未完成：'+$operation.Error) -Kind error}
        } elseif($operation.Result) {
            $result=$operation.Result | ConvertFrom-Json
            $row=$script:rows[([string]$operation.Owner.Pid+':'+$operation.Owner.StartTicks)]
            if($row -and $result.Exited){$row.Exited=$true}
        }
        if($script:useWorkers){$script:parallelHub.Remove($operation.Owner.Key)}
    }
    foreach($row in $script:rows.Values){$row.Validated=$false}
    $script:shutdownState.Operations=@();$script:shutdownState.Deadline=0L;$script:shutdownState.Started=$false
    $shutdownButton.Text='结束倒计时';$tabs.Enabled=$true
    $refreshButton.Enabled=-not $script:scanning -and -not $script:editingSettings
    Write-WowAutoLog '倒计时退出处理完成，脚本继续运行，可刷新进程或重新设置倒计时。' -Kind system
    Update-WowAutoRunInfo;Update-BatchControls
}
function Invoke-WowAutoShutdownTick([long]$Now=$script:schedulerClock.ElapsedMilliseconds) {
    if(-not $script:shutdownState.Deadline -or $script:restartRequested){return}
    if(-not $script:shutdownState.Started) {
        $remaining=Get-WowAutoShutdownRemaining $Now
        $shutdownButton.Text='倒计时：'+$remaining+'秒'
        if($Now -lt $script:shutdownState.Deadline){return}
        $script:shutdownState.Started=$true
        foreach($owned in @($form.OwnedForms)){$owned.Close()}
        Update-WowAutoShutdownControls
        Write-WowAutoLog '结束倒计时归零，停止全部任务并退出游戏。' -Kind system
        try {$script:shutdownState.Operations=@(Start-WowAutoGameShutdown)}
        catch {Write-WowAutoLog ('结束倒计时退出失败：'+$_.Exception.Message) -Kind error}
    }
    if(@($script:shutdownState.Operations | Where-Object {-not $_.Done.IsSet}).Count){return}
    Complete-WowAutoGameShutdown
}
