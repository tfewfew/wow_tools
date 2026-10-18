param($Hub,[string]$ToolRoot,[string]$MockSource='')
$ErrorActionPreference='Stop'
. (Join-Path $ToolRoot 'autoFight.Engine.ps1')
function Wait-Operator($Request,[int]$Milliseconds) {
    $until=$Hub.Now+$Milliseconds
    while ($Hub.Now -lt $until) {
        if ($Hub.Closing -or -not $Request.Current) {return $false}
        [Threading.Thread]::Sleep([Math]::Min($Request.Timing.WaitCheckMs,[Math]::Max(1,$until-$Hub.Now)))
    }
    return $Request.Current
}
function Get-OperatorClient($Endpoint) {
    $client=New-Object WowAutoFight.Client
    $client.ProcessId=$Endpoint.Pid;$client.StartTicks=$Endpoint.StartTicks;$client.Path=$Endpoint.Path;$client.Flavor=$Endpoint.Flavor
    return $client
}
function Assert-OperatorIdentity($Endpoint) {
    $process=[Diagnostics.Process]::GetProcessById($Endpoint.Pid)
    try {
        if ($process.HasExited -or $process.StartTime.Ticks -ne $Endpoint.StartTicks -or
            -not [string]::Equals($process.MainModule.FileName,$Endpoint.Path,[StringComparison]::OrdinalIgnoreCase) -or
            [WowAuto.NativeInput]::GetClientFlavor($Endpoint.Path,[Diagnostics.FileVersionInfo]::GetVersionInfo($Endpoint.Path).FileVersion) -ne $Endpoint.Flavor) {throw '操作前进程身份已变化。'}
    } finally {$process.Dispose()}
}
function Invoke-OperatorAdapter([string]$Action,$Endpoint,$Data=$null,[int]$DurationMs=30) {
    $Hub.AssertOperatorThread()
    if($Hub.Simulation){throw 'Simulation requires an explicit operator adapter; native input is forbidden.'}
    switch($Action) {
        'Identity' {Assert-OperatorIdentity $Endpoint;return $true}
        'Foreground' {return [WowAuto.NativeInput]::IsTargetForeground($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path)}
        'Activate' {return [WowAuto.NativeInput]::ActivateForScan($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path)}
        'Login' {return [WowAutoRotation.Native]::LoginPoint($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path)}
        'Color' {return [WowAuto.NativeInput]::ReadCenterColor($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path)}
        'Lure' {return [WowAuto.NativeInput]::ReadLureColor($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path)}
        'Packet' {return [WowAutoFight.Native]::Observe((Get-OperatorClient $Endpoint))}
        'Press' {$binding=ConvertFrom-AutoFightBinding ([string]$Data);return [WowAutoFight.Native]::Press((Get-OperatorClient $Endpoint),$binding.Code,$binding.Ctrl,$binding.Shift,$binding.Alt,$DurationMs)}
        'Up' {return [WowAuto.NativeInput]::PressChord($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path,38,$false,$false,$false,$DurationMs)}
        'Enable' {return [WowAuto.NativeInput]::SendDetectorCommand($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path,$Data.Mode,$DurationMs)}
        'Logout' {return [WowAuto.NativeInput]::SendRotationCommand($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path,'logout',0,$DurationMs)}
        'Click' {return [WowAutoRotation.Native]::ClickCharacter($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path,$Data.X,$Data.Y,$Data.Width,$Data.Height,$Data.FirstDelay,$Data.SecondDelay,$Data.MinimumMs,$Data.MaximumMs)}
        'Restore' {return [WowAuto.NativeInput]::RestoreAfterScan([IntPtr][long]$Data.Window)}
        'Capture.Restore' {$restore=@([WowAutoCapture.Native]::PendingRestores() | Where-Object Key -eq $Endpoint.Key | Select-Object -First 1);if($restore.Count){[WowAutoCapture.Native]::RestoreMinimized($restore[0])};return $true}
        'Exit' {$process=[Diagnostics.Process]::GetProcessById($Endpoint.Pid);try{$null=$process.CloseMainWindow()}finally{$process.Dispose()};return $true}
        'Kill' {$process=[Diagnostics.Process]::GetProcessById($Endpoint.Pid);try{$process.Kill()}finally{$process.Dispose()};return $true}
        default {throw 'Unknown operator adapter action.'}
    }
}
function Invoke-OperatorRequest($Request) {
    $endpoint=$Request.Owner;$body=$Request.Json | ConvertFrom-Json;$timing=$Request.Timing
    if($Request.Kind -eq 'Scan.Restore') {
        if($Hub.ActiveTasks -eq 0){$null=Invoke-OperatorAdapter Restore $endpoint $body}
        return @{Executed=($Hub.ActiveTasks -eq 0);SentAt=$Hub.Now}
    }
    $null=Invoke-OperatorAdapter Identity $endpoint
    if ($Request.Kind -eq 'Capture.Restore') {
        $null=Invoke-OperatorAdapter Capture.Restore $endpoint
        return @{Executed=$true;SentAt=$Hub.Now}
    }
    if($Request.Kind -in @('Process.Exit','Process.Kill')) {
        $null=Invoke-OperatorAdapter $(if($Request.Kind -eq 'Process.Exit'){'Exit'}else{'Kill'}) $endpoint
        return @{Executed=$true;SentAt=$Hub.Now}
    }
    # The operator owns the foreground and all key holds. Activation waits yield to higher priorities.
    if($script:lastClickKey -and $script:lastClickKey -ne $endpoint.Key -and $Hub.Now -lt $script:clickUntil) {
        $Hub.Requeue($Request,[int]($script:clickUntil-$Hub.Now));return $null
    }
    $foreground=Invoke-OperatorAdapter Foreground $endpoint
    if(-not $foreground) {
        if(-not $Request.FocusUntil){$Request.FocusUntil=$Hub.Now+$(if($Request.Domain -eq 'Rotation'){$timing.RotationFocusTimeoutMs}else{$timing.ForegroundTimeoutMs})}
        if($Hub.Now -ge $Request.FocusUntil){throw '操作线程未能在前台保护时间内取得窗口。'}
        if($Hub.Now -ge $Request.NextActivateAt) {
            $null=Invoke-OperatorAdapter Activate $endpoint
            $Request.NextActivateAt=$Hub.Now+$(if($Request.Domain -eq 'Rotation'){$timing.RotationFocusRetryMs}else{$timing.ForegroundRetryMs})
        }
        $Request.ReadyAt=$Hub.Now+$timing.ForegroundSettleMs;$Hub.Focus=$Request;$Hub.Requeue($Request,$timing.WaitCheckMs);return $null
    }
    if(-not $Request.ReadyAt){$Request.ReadyAt=$Hub.Now+$timing.ForegroundSettleMs}
    if($Hub.Now -lt $Request.ReadyAt){$Hub.Focus=$Request;$Hub.Requeue($Request,[int]($Request.ReadyAt-$Hub.Now));return $null}
    if(-not $Request.Current){return @{Executed=$false;SentAt=$Hub.Now}}
    if($Request.Kind -eq 'Rotation.Click') {
        if(Invoke-OperatorAdapter Login $endpoint){return @{Executed=$false;SentAt=$Hub.Now}}
        $body | Add-Member NoteProperty MinimumMs $timing.ClickMinMs -Force;$body | Add-Member NoteProperty MaximumMs $timing.ClickMaxMs -Force
        $sent=Invoke-OperatorAdapter Click $endpoint $body
        if($sent){$script:lastClickKey=$endpoint.Key;$script:clickUntil=$Hub.Now+$timing.ClickGuardMs}
        return @{Executed=$sent;SentAt=$Hub.Now}
    }
    if($Request.Kind -eq 'Rotation.Up') {
        if(Invoke-OperatorAdapter Login $endpoint){return @{Executed=$false;SentAt=$Hub.Now}}
        $sent=Invoke-OperatorAdapter Up $endpoint $null $timing.ChatKeyPressMs
        return @{Executed=$sent;SentAt=$Hub.Now}
    }
    if(-not (Invoke-OperatorAdapter Login $endpoint)){throw '操作前未检测到插件右下角登录白点。'}
    if($Request.Kind -eq 'Rotation.EquipRod') {
        if($body.Mode -cne 'fish' -or [string]::IsNullOrWhiteSpace([string]$body.Key)){throw '装备鱼竿需要钓鱼任务和已配置的按键。'}
        $null=ConvertFrom-AutoFightBinding ([string]$body.Key)
        return @{Executed=(Invoke-OperatorAdapter Press $endpoint ([string]$body.Key) $timing.KeyPressMs);SentAt=$Hub.Now}
    }
    if($Request.Kind -eq 'Rotation.Logout') {
        return @{Executed=(Invoke-OperatorAdapter Logout $endpoint $null $timing.ChatKeyPressMs);SentAt=$Hub.Now}
    }
    if($Request.Kind -in @('Scan.Enable','Rotation.Enable')) {
        return @{Executed=(Invoke-OperatorAdapter Enable $endpoint $body $timing.ChatKeyPressMs);SentAt=$Hub.Now}
    }
    if($Request.Domain -eq 'Fight') {
        $observation=Invoke-OperatorAdapter Packet $endpoint;$packet=$observation.Packet
        if(-not $packet -or $packet.ClassId -ne $body.ClassId -or $packet.Busy){return @{Executed=$false;SentAt=$Hub.Now}}
        $allowed=switch($body.Action) {
            'recover' {$packet.Recovery -eq 'recover'}
            'buff' {$packet.Action -eq 'idle'}
            'jump' {$packet.Action -in @('idle','combat')}
            default {$packet.Action -eq $body.Action}
        }
        if($packet.Recovery -eq 'unknown' -and $Hub.Now -ge $body.RecoveryReadyAt){$allowed=$false}
        if($packet.Recovery -eq 'recover' -and $Hub.Now -ge $body.RecoveryReadyAt -and $body.Action -ne 'recover'){$allowed=$false}
        if(-not $allowed){return @{Executed=$false;SentAt=$Hub.Now}}
    } else {
        $color=Invoke-OperatorAdapter Color $endpoint
        if($color -notin @('red','green') -or ($body.RequireGreen -and $color -ne 'green') -or
            ($Request.Kind -eq 'Fish.Cast' -and $color -ne 'red' -and -not $body.AllowGreen)){return @{Executed=$false;SentAt=$Hub.Now}}
        if($Request.Kind -eq 'Fish.Item' -and ($color -ne 'red' -or (Invoke-OperatorAdapter Lure $endpoint) -ne 'missing')){return @{Executed=$false;SentAt=$Hub.Now}}
    }
    if($Request.Domain -eq 'Fight' -and $Hub.Now -lt $script:commandReadyAt){$Hub.Requeue($Request,[int]($script:commandReadyAt-$Hub.Now));return $null}
    $sent=$true
    foreach($key in @($body.Keys)) {
        if(-not $Request.Current){$sent=$false;break}
        $sent=Invoke-OperatorAdapter Press $endpoint $key $timing.KeyPressMs
        if(-not $sent){break}
    }
    $sentAt=$Hub.Now
    if($sent -and $Request.Domain -eq 'Fight'){$script:commandReadyAt=$sentAt+$timing.CommandIntervalMs}
    if($sent -and $body.HoldMs -gt 0){$null=Wait-Operator $Request $body.HoldMs}
    return @{Executed=$sent;SentAt=$sentAt}
}
if($MockSource){. ([scriptblock]::Create($MockSource))}
$script:commandReadyAt=0L;$script:lastClickKey='';$script:clickUntil=0L
$Hub.BindOperator()
try {
    while(-not $Hub.Closing) {
        $request=$Hub.NextOperation()
        if(-not $request){$null=$Hub.Wake.WaitOne($Hub.Timing.OperatorIdleMs);continue}
        try {
            if(-not $request.Current){$request.Complete($false,$false,$null,'cancelled');continue}
            $result=Invoke-OperatorRequest $request
            if($null -eq $result){continue}
            if([object]::ReferenceEquals($Hub.Focus,$request)){$Hub.Focus=$null}
            $request.Complete($true,[bool]$result.Executed,($result | ConvertTo-Json -Compress),$null)
            try{$Hub.Log($request.Owner,$request.Version,'action',('操作完成：'+$request.Kind+'；已执行='+$result.Executed))}
            catch{$Hub.Publish($request.Owner,$request.Version,'status',('操作已完成，但日志写入失败：'+$_.Exception.Message))}
        } catch {
            if([WowAutoCapture.Native]::IsPending($_.Exception) -and $request.Current) {$Hub.Requeue($request,$request.Timing.CaptureRetryMs);continue}
            if([object]::ReferenceEquals($Hub.Focus,$request)){$Hub.Focus=$null}
            $request.Complete($false,$false,$null,$_.Exception.Message)
            try{$Hub.Log($request.Owner,$request.Version,'error',('操作失败：'+$request.Kind+'：'+$_.Exception.Message))}
            catch{$Hub.Publish($request.Owner,$request.Version,'status',('操作失败，日志不可写：'+$_.Exception.Message))}
        }
    }
} finally {if([WowAutoFight.Native]::IsHolding){[WowAutoFight.Native]::ReleaseHold()}}
