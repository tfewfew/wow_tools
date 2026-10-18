param($Hub,$Endpoint,[string]$ToolRoot,[string]$MockSource='')
$ErrorActionPreference='Stop'
. (Join-Path $ToolRoot 'wowAuto.Engine.ps1')
. (Join-Path $ToolRoot 'autoFight.Engine.ps1')
. (Join-Path $ToolRoot 'wowAuto.Rotation.Match.ps1')
function Publish-Detector([string]$Kind,$Data) {$Hub.Publish($Endpoint,$script:version,$Kind,($Data | ConvertTo-Json -Depth 12 -Compress))}
function Write-Detector([string]$Text,[string]$Kind='status') {
    if($Kind -eq 'status' -and $Text -ceq $script:lastStatus){return}
    $script:lastStatus=$Text;$Hub.Log($Endpoint,$script:version,$Kind,$Text)
}
function Test-DetectorCurrent {return -not $Hub.Closing -and $Endpoint.Current($script:version)}
function Wait-Detector([int]$Milliseconds) {
    $until=$Hub.Now+$Milliseconds
    while((Test-DetectorCurrent) -and ($Hub.Now -lt $until -or $Hub.Paused)){Apply-DetectorConfiguration;[Threading.Thread]::Sleep($script:config.Operations.DetectorWaitMs)}
    return Test-DetectorCurrent
}
function Request-DetectorOperation([string]$Kind,[string]$Domain,$Body=@{}) {
    if(-not (Test-DetectorCurrent)){return $null}
    $priorityKey=switch($Kind){'Process.Exit'{'Process.Close'}'Rotation.Up'{'Rotation.Select'}default{$Kind}}
    if(-not $script:config.Priorities.PSObject.Properties[$priorityKey]){throw ('缺少操作优先级：'+$priorityKey)}
    $priority=[int]$script:config.Priorities.$priorityKey
    $request=$Hub.Request($Endpoint,$script:version,$Kind,$Domain,$priority,($Body | ConvertTo-Json -Depth 12 -Compress),$script:operationTiming)
    # No capture, OCR, or state detection is performed between submission and acknowledgement.
    while(-not $request.Done.Wait($request.Timing.ReplyCheckMs)){if(-not (Test-DetectorCurrent)){return $null}}
    if(-not (Test-DetectorCurrent)){return $null}
    if(-not $request.Success){throw $request.Error}
    return ($request.Result | ConvertFrom-Json)
}
function Get-DetectorClient {
    $client=New-Object WowAutoFight.Client
    $client.ProcessId=$Endpoint.Pid;$client.StartTicks=$Endpoint.StartTicks;$client.Path=$Endpoint.Path;$client.Flavor=$Endpoint.Flavor
    return $client
}
function Get-DetectorObservation {
    if($Hub.Simulation){throw 'Simulation requires an explicit frame adapter.'}
    $login=[WowAutoRotation.Native]::LoginPoint($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path)
    if(-not $login){return [pscustomobject]@{Login=$false;Color='unknown';Packet=$null;Lure='unknown'}}
    if($script:mode -eq 'fight') {
        $observation=[WowAutoFight.Native]::Observe((Get-DetectorClient))
        if($observation.Pending){throw (New-Object WowAutoCapture.PendingException $observation.Error)}
        return [pscustomobject]@{Login=$true;Color='';Packet=$observation.Packet;Lure='unknown';Error=$observation.Error}
    }
    return [pscustomobject]@{Login=$true;Color=([WowAuto.NativeInput]::ReadCenterColor($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path));Packet=$null;Lure='unknown'}
}
function Get-DetectorLure {if($Hub.Simulation){throw 'Simulation requires a lure adapter.'};return [WowAuto.NativeInput]::ReadLureColor($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path)}
function Get-DetectorScreen {
    if($Hub.Simulation){throw 'Simulation requires an OCR adapter.'}
    $size=[WowAutoRotation.Native]::ReadClientSize($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path)
    $started=$Hub.Now
    $bitmap=[WowAutoRotation.Native]::Capture($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path,$size.Width,$size.Height)
    try {$bytes=[WowAutoRotation.Native]::Png($bitmap)} finally {$bitmap.Dispose()}
    # Synchronous invocation stays on this process's detector runspace, never on the UI/operator thread.
    try {$result=& (Join-Path $ToolRoot 'wowAuto.Rotation.Ocr.ps1') -ScreenBytes $bytes -OcrOwner $Endpoint -OcrVersion $script:version}
    catch {if(-not (Test-DetectorCurrent) -or $_.Exception.Message -match 'OCR sample timed out'){return [pscustomobject]@{Kind='pending';Targets=@()}};throw}
    if(-not (Test-DetectorCurrent) -or $Hub.Now-$started -gt 3000){return [pscustomobject]@{Kind='pending';Targets=@()}}
    $current=[WowAutoRotation.Native]::ReadClientSize($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path)
    if(-not [WowAutoRotation.Native]::ClientSizeWithinTolerance($size.Width,$size.Height,$current.Width,$current.Height)){return [pscustomobject]@{Kind='pending';Targets=@()}}
    $screen=ConvertFrom-RotationOcr ($result | ConvertFrom-Json) ([pscustomobject]@{Slots=$script:roles})
    foreach($target in $screen.Targets){$target | Add-Member NoteProperty ClientSize $size}
    return $screen
}
function Test-DetectorAlive {
    if($Hub.Simulation){throw 'Simulation requires a process adapter.'}
    $process=$null
    try {$process=[Diagnostics.Process]::GetProcessById($Endpoint.Pid);return -not $process.HasExited -and $process.StartTime.Ticks -eq $Endpoint.StartTicks -and
        [string]::Equals($process.MainModule.FileName,$Endpoint.Path,[StringComparison]::OrdinalIgnoreCase)}catch{return $false}finally{if($process){$process.Dispose()}}
}
function Get-DetectorPosition {if($Hub.Simulation){throw 'Simulation requires a position adapter.'};return [WowAuto.NativeInput]::ReadWindowPosition($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path)}
function Stop-DetectorAudio {if($script:audio){$script:audio.Dispose();$script:audio=$null}}
function Sync-DetectorAudioSession {
    if(-not $script:audio -or $script:mode -ne 'fish' -or -not $script:fish -or $script:audioSession -eq $script:fish.AudioSession){return}
    if($script:audioFeature -cne $script:config.FeaturePath){
        $script:audio.Arm(0)
        $script:audio.SetTemplate([WowAuto.Audio.AudioTemplate]::LoadFeatures($script:config.FeaturePath),($script:config.AudioThreshold/100.0))
        $script:audioFeature=$script:config.FeaturePath
    }
    $script:audio.Arm($script:fish.AudioSession);$script:audioSession=$script:fish.AudioSession
}
function Receive-DetectorAudioBite($Command) {
    if($Command.Version -ne $script:version -or -not (Test-DetectorCurrent) -or -not $script:running -or
        $script:mode -ne 'fish' -or -not $script:audio){return}
    $data=$Command.Json | ConvertFrom-Json
    if($data.Session -le 0 -or $data.MatchedAt -lt 0 -or $data.MatchedAt -gt $Hub.Now){return}
    if(Complete-WowAutoAudioBite $script:scheduler $Endpoint.Key ([long]$data.MatchedAt) ([long]$data.Session)){
        Write-Detector $script:fish.Status
    }
}
function Get-DetectorObservationReady {
    $until=$Hub.Now+5000
    while(Test-DetectorCurrent) {
        try {return Get-DetectorObservation}
        catch {
            if(-not [WowAutoCapture.Native]::IsPending($_.Exception) -or $Hub.Now -ge $until){throw}
            Repair-DetectorCapture;$null=Wait-Detector $script:config.Periods.CaptureRetryMs
        }
    }
    return $null
}
function Invoke-DetectorScan {
    $reply=Request-DetectorOperation Scan.Enable Scan @{Mode=$script:mode}
    if(-not $reply -or -not $reply.Executed){throw '监控开启命令未完成。'}
    $null=Wait-Detector $script:config.Periods.LoginMs
    $until=$Hub.Now+5000;$valid=$false
    while(Test-DetectorCurrent) {
        $observation=Get-DetectorObservationReady
        $valid=($script:mode -eq 'fish' -and $observation.Color -in @('red','green')) -or
            ($script:mode -eq 'fight' -and $observation.Packet -and $observation.Packet.Action -ne 'dead')
        if($valid -or $Hub.Now -ge $until){break};$null=Wait-Detector $script:config.Periods.CaptureRetryMs
    }
    if(-not (Test-DetectorCurrent)){return}
    Publish-Detector scanned @{Valid=$valid;Mode=$script:mode}
    Write-Detector $(if($valid){'检测通过，可以开始。'}else{'未识别到有效色块，请恢复插件后刷新。'})
}
function Start-DetectorTask {
    Stop-DetectorAudio
    $now=$Hub.Now;$script:nextColor=0L;$script:nextDeath=0L;$script:nextBait=0L;$script:nextAudio=0L;$script:nextFishPoll=0L;$script:retryAt=0L;$script:observation=$null
    if($script:mode -eq 'fish') {
        $script:fish=Add-WowAutoTask $script:scheduler $Endpoint.Key $script:config.MinimumMs $script:config.MaximumMs $now -UseItem $script:useItem -UseAudio $script:config.UseAudio -AudioTimeoutMs $script:config.AudioTimeoutMs
        if($script:config.UseAudio) {
            if($Hub.Simulation){throw 'Simulation cannot open live audio.'}
            $template=[WowAuto.Audio.AudioTemplate]::LoadFeatures($script:config.FeaturePath)
            $notification=$Hub.CreateAudioNotifier($Endpoint,$script:version)
            $script:audio=New-Object WowAuto.Audio.ProcessCapture($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path,$template,($script:config.AudioThreshold/100.0),$notification)
            $script:audioFeature=$script:config.FeaturePath;$script:audioSession=-1L
        }
    } else {
        $observation=Get-DetectorObservationReady
        if(-not $observation.Packet){throw '战斗协议不可读，不能开始。'}
        $script:combat=New-AutoFightSession $now $observation.Packet.ClassId
        $profile=Get-DetectorProfile $script:combat.ClassId
        Set-AutoFightBuffSchedule $script:combat $profile $now -AfterLogin
    }
    $script:running=$true;$script:round++
    if(-not $script:direct){$script:runLogins++}
    Publish-Detector taskstart @{Role=$script:roleName;Index=$script:index;Mode=$script:mode;UseItem=$script:useItem;Round=$script:round;Direct=$script:direct;SwitchCount=([Math]::Max(0,$script:runLogins-1));Cycles=(Get-WowAutoCycleCount $script:scheduler $Endpoint.Key);BiteTimeouts=(Get-WowAutoBiteTimeoutCount $script:scheduler $Endpoint.Key);ClassId=$(if($script:combat -and $script:mode -eq 'fight'){$script:combat.ClassId}else{0})}
    Write-Detector ('已开始'+$(if($script:mode -eq 'fight'){'战斗'}else{'钓鱼'})+'；角色：'+$script:roleName+'；执行轮次 '+$script:round)
}
function Get-DetectorProfile([int]$ClassId) {
    if(-not $script:config.ProfilesReady){throw '战斗配置无效，请先在设置中修正。'}
    $profile=$script:config.Profiles.($Endpoint.Flavor+':'+$ClassId)
    if(-not $profile){throw '当前职业没有有效战斗配置。'}
    return Get-AutoFightEffectiveProfile $profile $script:config.Common
}
function Exit-DetectorProcess([string]$Reason) {
    Write-Detector ($Reason+'；请求正常退出游戏，30秒未退出再强制结束。')
    $script:running=$false;Stop-DetectorAudio
    if($script:batch){$script:batch.Drop($Endpoint.Key)}
    Publish-Detector exiting @{Reason=$Reason}
    $null=Request-DetectorOperation Process.Exit Process
    $until=$Hub.Now+30000
    while(Test-DetectorCurrent) {
        if(-not (Test-DetectorAlive)){break}
        if($Hub.Now -ge $until){$null=Request-DetectorOperation Process.Kill Process;break}
        if(-not (Wait-Detector $script:config.Periods.LoginMs)){return}
    }
    if(-not (Test-DetectorCurrent)){return}
    if($script:batch){$script:batch.Drop($Endpoint.Key)}
    Publish-Detector stopped @{Reason=$Reason;Exited=$true}
    $Endpoint.Finish()
}
function Select-DetectorRole {
    for($offset=1;$offset -le $script:roles.Count;$offset++) {
        $index=($script:index+$offset)%$script:roles.Count
        if($script:roles[$index].Name -cnotin $script:excluded){$script:index=$index;$script:roleName=$script:roles[$index].Name;$script:mode=$script:roles[$index].Mode;$script:useItem=$script:roles[$index].UseItem;return $true}
    }
    return $false
}
function Invoke-DetectorRotation {
    $script:running=$false;Stop-DetectorAudio
    if(-not (Select-DetectorRole)){Exit-DetectorProcess '当前子战网所有启用角色均已移出本次轮转';return}
    Publish-Detector switching @{TargetRole=$script:roleName;Mode=$script:mode;Index=$script:index}
    $script:batch.Clear($Endpoint.Key,15)
    Write-Detector ('开始切换到“'+$script:roleName+'”，等待选角界面后由本进程线程执行OCR。')
    $lastLogout=$Hub.Now
    $observation=Get-DetectorObservationReady
    if($observation.Login){$null=Request-DetectorOperation Rotation.Logout Rotation}
    $script:batch.Mark($Endpoint.Key,1)
    while((Test-DetectorCurrent) -and -not $script:batch.All(1)){$null=Wait-Detector 25}
    $deadline=$Hub.Now+180000;$menuStable=0;$targetStable=0;$candidate=$null;$retries=0;$nextOcr=0L
    while(Test-DetectorCurrent) {
        if($Hub.Now -ge $deadline){throw '角色切换超过180秒，已停止本进程编排。'}
        try {
            $observation=Get-DetectorObservation
            if($observation.Login) {
                if($Hub.Now-$lastLogout -ge 30000){$null=Request-DetectorOperation Rotation.Logout Rotation;$lastLogout=$Hub.Now}
                $null=Wait-Detector $script:config.Periods.MenuMs;continue
            }
            if($Hub.Now -lt $nextOcr){$null=Wait-Detector ([int][Math]::Min(100,$nextOcr-$Hub.Now));continue}
            $nextOcr=$Hub.Now+$script:config.Periods.OcrMs
            $screen=Get-DetectorScreen
            if(-not (Test-DetectorCurrent)){return}
            if($screen.Kind -ne 'menu'){$menuStable=0;$targetStable=0;$null=Wait-Detector $script:config.Periods.MenuMs;continue}
            $deadline=$Hub.Now+180000
            if($menuStable -lt 3){$menuStable++;continue}
            Write-Detector (Get-RotationOcrLog $screen $script:roleName)
            $targets=@($screen.Targets | Where-Object {$_.Name -ceq $script:roleName -and -not $_.Ambiguous})
            if($targets.Count -gt 1){throw '列表出现多个相同角色名称，停止本进程编排。'}
            if($targets.Count -eq 0) {
                if($retries -ge 30){Exit-DetectorProcess ('角色“'+$script:roleName+'”按↑后重识别30次仍未找到');return}
                $reply=Request-DetectorOperation Rotation.Up Rotation
                if(-not $reply -or -not $reply.Executed){continue}
                $retries++;$targetStable=0;$candidate=$null
                Write-Detector ('已按↑，等待本次OCR重识别（'+$retries+'/30）。')
                $null=Wait-Detector 500;continue
            }
            $target=$targets[0]
            if($candidate -and [Math]::Abs($target.X-$candidate.X) -lt 0.005 -and [Math]::Abs($target.Y-$candidate.Y) -lt 0.005){$targetStable++}else{$targetStable=1}
            $candidate=$target
            if($targetStable -lt 2){continue}
            $script:batch.Mark($Endpoint.Key,2)
            Write-Detector ('已定位第'+$target.MenuRow+'个角色槽位“'+$script:roleName+'”，等待所有进程识别完成。')
            while((Test-DetectorCurrent) -and -not $script:batch.All(2)){$null=Wait-Detector 25}
            # Generate both random intervals before handing one indivisible click transaction to the operator.
            $first=Get-Random -Minimum $script:config.Operations.ClickMinMs -Maximum ($script:config.Operations.ClickMaxMs+1)
            $second=Get-Random -Minimum $script:config.Operations.ClickMinMs -Maximum ($script:config.Operations.ClickMaxMs+1)
            $reply=Request-DetectorOperation Rotation.Click Rotation @{X=$target.X;Y=$target.Y;Width=$target.ClientSize.Width;Height=$target.ClientSize.Height;FirstDelay=$first;SecondDelay=$second}
            if(-not $reply){return}
            if(-not $reply.Executed){$script:batch.Clear($Endpoint.Key,2);$targetStable=0;$candidate=$null;continue}
            $script:batch.Mark($Endpoint.Key,4);break
        } catch {
            if([WowAutoCapture.Native]::IsPending($_.Exception)) {Repair-DetectorCapture;$null=Wait-Detector $script:config.Periods.CaptureRetryMs;continue}
            throw
        }
    }
    while((Test-DetectorCurrent) -and -not $script:batch.All(4)){$null=Wait-Detector 25}
    $stable=0
    while(Test-DetectorCurrent) {
        if($Hub.Now -ge $deadline){throw '登录超过180秒，已停止本进程编排。'}
        try {
            $observation=Get-DetectorObservation
            if($observation.Login){$stable++}else{$stable=0}
            if($stable -ge 3) {
                $null=Request-DetectorOperation Rotation.Enable Rotation @{Mode=$script:mode}
                $null=Wait-Detector $script:config.Periods.LoginMs
                $observation=Get-DetectorObservation
                if($observation.Color -eq 'dead' -or ($observation.Packet -and $observation.Packet.Action -eq 'dead')){Remove-DetectorRole '角色死亡';return}
                if($script:mode -eq 'fish' -and $observation.Color -eq 'yellow'){Remove-DetectorRole '背包已满';return}
                if(($script:mode -eq 'fish' -and $observation.Color -in @('red','green')) -or ($script:mode -eq 'fight' -and $observation.Packet)) {
                    $script:scheduler=New-WowAutoScheduler;Set-DetectorScheduler
                    Start-DetectorTask;$script:batch.Mark($Endpoint.Key,8)
                    while((Test-DetectorCurrent) -and -not $script:batch.All(8)){$null=Wait-Detector 25}
                    return
                }
            }
            $null=Wait-Detector $script:config.Periods.LoginMs
        } catch {if([WowAutoCapture.Native]::IsPending($_.Exception)){Repair-DetectorCapture;$null=Wait-Detector $script:config.Periods.CaptureRetryMs}else{throw}}
    }
}
function Remove-DetectorRole([string]$Reason) {
    $script:running=$false;Stop-DetectorAudio
    Write-Detector ($Reason+'：'+$script:roleName+'，移出本进程本次子战网轮转。')
    if($script:direct){Publish-Detector stopped @{Reason=$Reason;Exited=$false};return}
    $script:excluded+=,$script:roleName
    Publish-Detector excluded @{Name=$script:roleName;Reason=$Reason}
    if($script:batch){$script:batch.Drop($Endpoint.Key)}
    Publish-Detector rotate-needed @{Reason=$Reason}
}
function Repair-DetectorCapture {
    if(@([WowAutoCapture.Native]::PendingRestores() | Where-Object Key -eq $Endpoint.Key).Count){$null=Request-DetectorOperation Capture.Restore Capture}
}
function Set-DetectorScheduler {
    $script:operationTiming=New-Object WowAuto.Threading.QueueTimings
    foreach($key in $script:config.Operations.PSObject.Properties.Name){$script:operationTiming.$key=[int]$script:config.Operations.$key}
    $script:scheduler.JumpEveryCycles=$script:config.JumpEveryCycles;$script:scheduler.ReelHoldMs=$script:config.ReelHoldMs
    $script:scheduler.FocusRetryIntervalMs=$script:config.FocusRetryMs
    $script:scheduler.ItemHoldMs=$script:config.Operations.ItemHoldMs
}
function Apply-DetectorConfiguration {
    $message=$Endpoint.Configuration
    if(-not $message -or [object]::ReferenceEquals($script:lastConfiguration,$message)){return}
    $script:lastConfiguration=$message;$script:config=$message.Json | ConvertFrom-Json
    Set-DetectorScheduler
    if($script:fish){$script:fish.MinimumMs=$script:config.MinimumMs;$script:fish.MaximumMs=$script:config.MaximumMs;$script:fish.AudioTimeoutMs=$script:config.AudioTimeoutMs}
    if($script:audio){$script:audio.SetMinimumSimilarity($script:config.AudioThreshold/100.0)}
}
function Invoke-DetectorTask {
    try {Invoke-DetectorTaskCore} finally {Sync-DetectorAudioSession}
}
function Invoke-DetectorTaskCore {
    $now=$Hub.Now
    if($now -ge $script:nextColor -or $now -ge $script:nextDeath) {
        $observation=Get-DetectorObservation
        if($observation.Color -eq 'dead' -or ($observation.Packet -and $observation.Packet.Action -eq 'dead')){Remove-DetectorRole '角色死亡';return}
        if($script:mode -eq 'fish' -and $observation.Color -eq 'yellow'){Remove-DetectorRole '背包已满';return}
        if($script:mode -eq 'fish' -and $script:fish.UseAudio -and $observation.Login -and $observation.Color -notin @('red','green')){throw '钓鱼检测关闭或颜色未知，已停止本行音频任务。'}
        $script:nextDeath=$now+$script:config.Periods.DeathMs
        if($now -ge $script:nextColor){$script:observation=$observation;$script:nextColor=$now+$(if($script:mode -eq 'fight'){$script:config.Periods.FightMs}else{$script:config.Periods.FishMs})}
    }
    if($script:mode -eq 'fight') {
        if(-not $script:observation -or $now -lt $script:combat.Due){return}
        $script:combat.Due=$script:nextColor;$packet=$script:observation.Packet
        if(-not $packet){Write-Detector '战斗色块暂不可读，等待下次检测。';return}
        $profile=Get-DetectorProfile $script:combat.ClassId
        Write-Detector ('战斗主状态：'+@{idle='待机';opening='开怪';combat='战斗';interact='可交互'}[$packet.Action]+'；恢复副块：'+$packet.Recovery)
        $action=Get-AutoFightAction $script:combat $packet $profile $now
        if($action -eq 'identity-changed'){throw '职业或协议身份改变，请刷新。'}
        if($action -eq 'wait'){return}
        $keys=switch($action) {
            'opening' {@($profile.TargetKey,$profile.OpeningKey)} 'combat' {@($profile.CombatKey)}
            'recover' {@($profile.RecoveryKey)} 'buff' {@($profile.BuffKey)} 'jump' {@('Space')} 'interact' {@($profile.SkinKey)}
        }
        if(-not $keys){return}
        $kind='Fight.'+@{opening='Opening';combat='Combat';recover='Recover';buff='Buff';jump='Jump';interact='Interact'}[$action]
        $reply=Request-DetectorOperation $kind Fight @{Keys=@($keys);Action=$action;ClassId=$script:combat.ClassId;RecoveryReadyAt=$script:combat.RecoveryReadyAt;
            CommandIntervalMs=$script:config.CommandIntervalMs;HoldMs=$(if($action -eq 'interact'){$profile.InteractionHoldMs}else{0})}
        if($reply -and $reply.Executed){
            Complete-AutoFightAction $script:combat $profile $action $reply.SentAt;$script:combat.Due=$Hub.Now+$script:config.Periods.FightMs
            if($script:combat.BuffRemaining -gt 0){$script:combat.Due=[Math]::Min($script:combat.Due,$script:combat.NextBuffAt)}
        }
        return
    }
    $state=$script:fish
    if($script:audio -and $now -ge $script:nextAudio) {
        $script:nextAudio=$now+$script:config.Periods.AudioMs
        if($script:audio.Status -in @('Failed','Error')){throw $script:audio.Error}
        $state.AudioReady=$script:audio.Status -eq 'Listening'
    }
    if($state.UseItem -and -not $state.ItemDetectionDisabled -and $state.ItemConfirmUntil -gt 0 -and $now -ge $state.ItemConfirmUntil){$null=Complete-WowAutoItemCheck $script:scheduler $Endpoint.Key $now 'unknown' $script:observation.Color}
    $work=Get-WowAutoWork $script:scheduler $now
    if(-not $work){Write-Detector $state.Status;return}
    if($work.Kind -eq 'AudioTimeout'){
        if($script:audio){
            $detail=('无咬钩保护诊断：保护 {0} ms；采集 {1}；最高峰值 {2:F2}%；已比较候选 {3}；最高相似度 {4:F1}%；匹配门槛 {5}%；模板 {6}。' -f
                ($state.Deadline-$state.FishingStartedAt),$script:audio.Status,($script:audio.MaximumPeak*100),$script:audio.ComparedCandidates,
                ($script:audio.BestSimilarity*100),$script:config.AudioThreshold,([IO.Path]::GetFileName($script:config.FeaturePath)))
            $Hub.Log($Endpoint,$script:version,'audio-timeout',$detail)
        }
        Complete-WowAutoAudioTimeout $script:scheduler $Endpoint.Key $now '无咬钩声音超时，重新抛竿，不计成功收竿循环。'
        Publish-Detector counters @{Cycles=(Get-WowAutoCycleCount $script:scheduler $Endpoint.Key);BiteTimeouts=(Get-WowAutoBiteTimeoutCount $script:scheduler $Endpoint.Key)}
        Write-Detector $state.Status;return
    }
    if($work.Kind -eq 'FocusRetry'){Resume-WowAutoFocus $script:scheduler $Endpoint.Key;return}
    if(-not $script:observation -or -not $script:observation.Login){Write-Detector '等待插件登录白点和钓鱼色块。';return}
    $color=$script:observation.Color
    if($color -notin @('red','green')){Write-Detector '钓鱼色块暂不可读，等待下次后台检测。';return}
    if($state.UseItem -and -not $state.ItemDetectionDisabled -and $work.Kind -ne 'Reel' -and $now -ge $script:nextBait) {
        $script:nextBait=$now+$script:config.Periods.BaitMs
        $item=Complete-WowAutoItemCheck $script:scheduler $Endpoint.Key $now (Get-DetectorLure) $color
        if($item -eq 'Wait'){Write-Detector $state.Status;return}
        if($item -eq 'UseItem') {
            $reply=$null
            try{$reply=Request-DetectorOperation Fish.Item Fish @{Keys=@($script:config.Keys.Item);HoldMs=$script:config.Operations.ItemHoldMs}}
            finally{if(Test-DetectorCurrent){$null=Complete-WowAutoItem $script:scheduler $Endpoint.Key $(if($reply){$reply.SentAt}else{$Hub.Now}) ([bool]($reply -and $reply.Executed))}}
            return
        }
    }
    if($work.Kind -eq 'Item'){return}
    if($work.Kind -eq 'Reel') {
        $reply=Request-DetectorOperation Fish.Reel Fish @{Keys=@($script:config.Keys.Reel);HoldMs=$script:config.ReelHoldMs;RequireGreen=$state.UseAudio}
        if($reply -and $reply.Executed){Complete-WowAutoReel $script:scheduler $Endpoint.Key $reply.SentAt $true}
        elseif($state.UseAudio){Reset-WowAutoAudioWait $script:scheduler $Endpoint.Key $Hub.Now '收竿前钓鱼状态已变化，等待重新抛竿。'}
    } elseif($now -ge $script:nextFishPoll) {
        $script:nextFishPoll=$now+$script:config.Periods.FishMs
        $action=Complete-WowAutoPoll $script:scheduler $Endpoint.Key $now $color
        if($action -in @('Ctrl1','Jump')) {
            $kind=if($action -eq 'Jump'){'Fish.Jump'}else{'Fish.Cast'}
            $key=if($action -eq 'Jump'){'Space'}else{$script:config.Keys.Cast}
            $reply=Request-DetectorOperation $kind Fish @{Keys=@($key);HoldMs=0;AllowGreen=($state.ForceNextCast -or $action -eq 'Jump')}
            if($reply -and $reply.Executed){if($action -eq 'Jump'){Complete-WowAutoJump $script:scheduler $Endpoint.Key $true}else{Complete-WowAutoCast $script:scheduler $Endpoint.Key $true}}
        }
    }
    Write-Detector $state.Status
}
if($MockSource){. ([scriptblock]::Create($MockSource))}
$script:version=$Endpoint.Version;$script:running=$false;$script:audio=$null;$script:batch=$null;$script:config=$null
$script:round=0;$script:runLogins=0;$script:roleName='';$script:index=-1;$script:mode='fish';$script:useItem=$false;$script:direct=$false
$script:excluded=@();$script:lastStatus='';$script:nextPosition=0L;$script:nextFishPoll=0L;$script:retryAt=0L
$script:nextMetrics=0L
$script:lastConfiguration=$null
$script:scheduler=New-WowAutoScheduler
try {
    while(-not $Hub.Closing -and -not $Endpoint.Closed) {
        try {
            $command=$Endpoint.Receive($(if($script:config){$script:config.Operations.CommandReceiveMs}else{10}))
            Apply-DetectorConfiguration
            if($command -and $command.Kind -eq 'Audio.Bite'){
                Receive-DetectorAudioBite $command
                $command=$null
            }
            if($command) {
                if($command.Kind -eq 'Configure') {
                    $script:config=$command.Json | ConvertFrom-Json;Set-DetectorScheduler
                    if($script:fish){$script:fish.MinimumMs=$script:config.MinimumMs;$script:fish.MaximumMs=$script:config.MaximumMs;$script:fish.AudioTimeoutMs=$script:config.AudioTimeoutMs}
                    if($script:audio){$script:audio.SetMinimumSimilarity($script:config.AudioThreshold/100.0)}
                    continue
                }
                if($script:batch -and -not $script:batch.All(8)){$script:batch.Drop($Endpoint.Key)}
                $script:version=$command.Version;$script:running=$false;Stop-DetectorAudio;$script:lastStatus=''
                if($command.Kind -eq 'Stop'){
                    Stop-WowAutoTask $script:scheduler $Endpoint.Key
                    $script:scheduler.ReelHoldUntil=0L;$script:scheduler.ItemHoldUntil=0L
                    Write-Detector '已停止，本进程待执行操作已取消。';Publish-Detector stopped @{Reason='已停止';Exited=$false};continue
                }
                $body=$command.Json | ConvertFrom-Json;$script:config=$body.Config;$script:roles=@($body.Roles);$script:direct=[bool]$body.Direct
                Set-DetectorScheduler
                if($command.Kind -eq 'Scan') {
                    $script:mode=$body.Mode
                    Invoke-DetectorScan
                    continue
                }
                if($command.Kind -eq 'Start') {$script:excluded=@();$script:index=-1;$script:runLogins=0;$script:round=[Math]::Max($script:round,[int]$body.RoundBase)}
                if($script:direct) {$script:roleName='';$script:index=-1;$script:mode=$body.Mode;$script:useItem=[bool]$body.UseItem;Start-DetectorTask}
                else {
                    $script:batch=$Hub.Batch
                    if(-not $script:batch -or $script:batch.Id -ne $body.BatchId){throw '角色切换批次已失效。'}
                    Invoke-DetectorRotation
                }
            }
            if(-not $script:config -or -not (Test-DetectorCurrent)){continue}
            if($Hub.Paused){$null=Wait-Detector 25;continue}
            if($Hub.Now -ge $script:nextPosition){
                $script:nextPosition=$Hub.Now+$script:config.Periods.PositionMs
                if(-not (Test-DetectorAlive)){Publish-Detector stopped @{Reason='进程已退出或身份变化';Exited=$true};$Endpoint.Finish();break}
                Publish-Detector position @{Text=(Get-DetectorPosition)}
            }
            if($script:running){Invoke-DetectorTask}
            if($script:running -and $Hub.Now -ge $script:nextMetrics) {
                $script:nextMetrics=$Hub.Now+250
                Publish-Detector metrics @{Deadline=$(if($script:mode -eq 'fish'){$script:fish.Deadline}else{0L});
                    Cycles=(Get-WowAutoCycleCount $script:scheduler $Endpoint.Key);BiteTimeouts=(Get-WowAutoBiteTimeoutCount $script:scheduler $Endpoint.Key);Audio=[bool]$script:audio;
                    Similarity=$(if($script:audio){$script:audio.Similarity}else{0.0});Peak=$(if($script:audio){$script:audio.Peak}else{0.0})}
            }
        } catch {
            if(-not (Test-DetectorCurrent)){continue}
            if([WowAutoCapture.Native]::IsPending($_.Exception)){Repair-DetectorCapture;$null=Wait-Detector $script:config.Periods.CaptureRetryMs;continue}
            if($script:running -and $_.Exception.Message -match '前台保护时间') {
                $script:retryAt=$Hub.Now+$script:config.FocusRetryMs
                if($script:mode -eq 'fish'){Suspend-WowAutoFocus $script:scheduler $Endpoint.Key $Hub.Now '窗口操作暂时失败。'}else{$script:combat.Due=$script:retryAt}
                Write-Detector ('窗口操作失败，继续后台检测，等待 '+$script:config.FocusRetryMs+'ms 后重试操作。');continue
            }
            $script:running=$false;Stop-DetectorAudio
            if($script:batch){$script:batch.Drop($Endpoint.Key)}
            Write-Detector ('检测线程停止：'+$_.Exception.Message) error
            Publish-Detector stopped @{Reason=$_.Exception.Message;Exited=$false}
        }
    }
} finally {Stop-DetectorAudio;if($script:batch){$script:batch.Drop($Endpoint.Key)}}
