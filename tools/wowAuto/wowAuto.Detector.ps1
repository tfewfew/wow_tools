param($Hub,$Endpoint,[string]$ToolRoot,[string]$MockSource='')
$ErrorActionPreference='Stop'
. (Join-Path $ToolRoot 'wowAuto.Engine.ps1')
. (Join-Path $ToolRoot 'autoFight.Engine.ps1')
. (Join-Path $ToolRoot 'autoTame.Engine.ps1')
. (Join-Path $ToolRoot 'wowAuto.Rotation.Match.ps1')
. (Join-Path $ToolRoot 'wowAuto.AccountDiscovery.ps1')
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
    $priorityKey=switch($Kind){'Process.Exit'{'Process.Close'}'Rotation.Up'{'Rotation.Select'}'Rotation.ParkCursor'{'Rotation.Select'}default{$Kind}}
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
    $loginMode=[WowAutoRotation.Native]::ReadLoginMode($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path)
    if($loginMode -eq 'unknown'){return [pscustomobject]@{Login=$false;Mode=$loginMode;Color='unknown';Packet=$null;Lure='unknown'}}
    if($script:direct -and $loginMode -eq 'dead'){return [pscustomobject]@{Login=$true;Mode=$loginMode;Color='dead';Packet=$null;Lure='unknown'}}
    if($script:mode -in @('rest','shop')) {
        return [pscustomobject]@{Login=$true;Mode=$loginMode;Color='';Packet=$null;Lure='unknown'}
    }
    if($script:mode -eq 'tame') {
        return [pscustomobject]@{Login=$true;Color='';Packet=([WowAutoFight.Native]::ReadTame((Get-DetectorClient)));Lure='unknown'}
    }
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
    if($Endpoint.Flavor -eq 'forerver') {
        $reply=Request-DetectorOperation Rotation.ParkCursor Rotation
        if(-not $reply -or -not $reply.Executed){return [pscustomobject]@{Kind='pending';Targets=@()}}
    }
    $size=[WowAutoRotation.Native]::ReadClientSize($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path)
    $ocrTimeoutMs=[WowAutoRotation.Native]::OcrTimeoutMs($Endpoint.Flavor)
    $started=$Hub.Now
    $bitmap=[WowAutoRotation.Native]::Capture($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path,$size.Width,$size.Height)
    try {$bytes=[WowAutoRotation.Native]::Png($bitmap)} finally {$bitmap.Dispose()}
    # Synchronous invocation stays on this process's detector runspace, never on the UI/operator thread.
    try {$result=& (Join-Path $ToolRoot 'wowAuto.Rotation.Ocr.ps1') -ScreenBytes $bytes -OcrOwner $Endpoint -OcrVersion $script:version -Flavor $Endpoint.Flavor}
    catch {if(-not (Test-DetectorCurrent) -or $_.Exception.Message -match 'OCR sample timed out'){return [pscustomobject]@{Kind='pending';Targets=@()}};throw}
    if(-not (Test-DetectorCurrent) -or $Hub.Now-$started -gt $ocrTimeoutMs){return [pscustomobject]@{Kind='pending';Targets=@()}}
    $current=[WowAutoRotation.Native]::ReadClientSize($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path)
    if(-not [WowAutoRotation.Native]::ClientSizeWithinTolerance($size.Width,$size.Height,$current.Width,$current.Height)){return [pscustomobject]@{Kind='pending';Targets=@()}}
    $ocrRoles=if($script:discoverAccount){@($script:accountCandidates | ForEach-Object {$_.Names} | Sort-Object -Unique | ForEach-Object {[pscustomobject]@{Name=$_}})}else{$script:roles}
    $ocrNames=@($script:accountCandidates | ForEach-Object {$_.OcrNames})
    $screen=ConvertFrom-RotationOcr ($result | ConvertFrom-Json) ([pscustomobject]@{Slots=$ocrRoles;OcrNames=$ocrNames}) -Flavor $Endpoint.Flavor
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
        if($script:fish.ReelDelayExceededProtection){
            $Hub.Log($Endpoint,$script:version,'audio-delay-timeout',('随机收竿延迟超过保护：保护截止 '+$script:fish.AudioProtectionDeadline+' ms；计划收竿 '+$script:fish.Deadline+' ms；本轮随机延迟 '+$script:fish.ReelDelayMs+' ms；已计入无咬钩超时。'))
            Publish-Detector counters @{Cycles=(Get-WowAutoCycleCount $script:scheduler $Endpoint.Key);BiteTimeouts=(Get-WowAutoBiteTimeoutCount $script:scheduler $Endpoint.Key)}
        }
        Write-Detector $script:fish.Status
    }
}
function Get-DetectorObservationReady {
    $until=$Hub.Now+[WowAutoCapture.Native]::FrameWaitMs
    while(Test-DetectorCurrent) {
        try {return Get-DetectorObservation}
        catch {
            if(-not [WowAutoCapture.Native]::IsPending($_.Exception) -or $Hub.Now -ge $until){throw}
            Repair-DetectorCapture;$null=Wait-Detector $script:config.Periods.CaptureRetryMs
        }
    }
    return $null
}
function Invoke-DetectorScan([switch]$ForStart) {
    if($script:mode -ne 'shop' -and ($script:mode -ne 'rest' -or $ForStart)) {
        $reply=Request-DetectorOperation Scan.Enable Scan @{Mode=$script:mode}
        if(-not $reply -or -not $reply.Executed){throw '监控开启命令未完成。'}
    }
    $null=Wait-Detector $script:config.Periods.LoginMs
    $until=$Hub.Now+5000;$valid=$false
    while(Test-DetectorCurrent) {
        $observation=Get-DetectorObservationReady
        if($script:direct -and $observation.Color -eq 'dead'){throw '角色死亡，直接开始任务已停止。'}
        $valid=($script:mode -eq 'fish' -and $observation.Color -in @('red','green')) -or
            ($script:mode -eq 'fight' -and $observation.Packet -and $observation.Packet.Action -ne 'dead') -or
            ($script:mode -eq 'tame' -and $observation.Packet -and $observation.Packet.State -in @('idle','matched')) -or
            ($script:mode -eq 'rest' -and $observation.Login -and (-not $ForStart -or $observation.Mode -eq 'rest')) -or
            ($script:mode -eq 'shop' -and $observation.Login)
        if($valid -or $Hub.Now -ge $until){break};$null=Wait-Detector $script:config.Periods.CaptureRetryMs
    }
    if(-not (Test-DetectorCurrent)){return}
    if($ForStart){
        if(-not $valid){throw '无法验证所选任务。请确认角色已登录，插件已启用，且当前状态可开始。'}
        return $true
    }
    Publish-Detector scanned @{Valid=$valid;Mode=$script:mode}
    Write-Detector $(if($valid){'检测通过，可以开始。'}else{'未识别到有效色块，请恢复插件后刷新。'})
}
function Invoke-DetectorEquipRod {
    if([string]::IsNullOrWhiteSpace([string]$script:config.Keys.EquipRod)){throw '请先在钓鱼全局设置中配置“装备鱼竿”按键，再开始钓鱼任务。'}
    $kind=if($script:direct){'Fish.EquipRod'}else{'Rotation.EquipRod'}
    $domain=if($script:direct){'Fish'}else{'Rotation'}
    $reply=Request-DetectorOperation $kind $domain @{Mode='fish';Key=$script:config.Keys.EquipRod}
    if(-not (Test-DetectorCurrent)){return $false}
    if(-not $reply -or -not $reply.Executed){throw '装备鱼竿按键未发送，已停止本进程钓鱼任务。'}
    Write-Detector ('已发送一次装备鱼竿按键：'+$script:config.Keys.EquipRod)
    return $true
}
function Start-DetectorTask {
    Stop-DetectorAudio
    $script:fishColorRetryAt=0L;$now=$Hub.Now;$script:nextColor=0L;$script:nextDeath=0L;$script:nextBait=0L;$script:nextAudio=0L;$script:nextFishPoll=0L;$script:retryAt=0L;$script:observation=$null
    if($script:mode -eq 'fish') {
        $script:fish=Add-WowAutoTask $script:scheduler $Endpoint.Key $script:config.MinimumMs $script:config.MaximumMs $now -UseItem $script:useItem -UseAudio $script:config.UseAudio -AudioTimeoutMs $script:config.AudioTimeoutMs
        if($script:config.UseAudio) {
            if($Hub.Simulation){throw 'Simulation cannot open live audio.'}
            $template=[WowAuto.Audio.AudioTemplate]::LoadFeatures($script:config.FeaturePath)
            $notification=$Hub.CreateAudioNotifier($Endpoint,$script:version)
            $script:audio=New-Object WowAuto.Audio.ProcessCapture($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path,$template,($script:config.AudioThreshold/100.0),$notification)
            $script:audioFeature=$script:config.FeaturePath;$script:audioSession=-1L
        }
    } elseif($script:mode -eq 'tame') {
        $script:tameConfig=ConvertTo-AutoTameConfig $script:config.Tame -RequireKey
        $script:tame=New-AutoTameSession $now $script:tameConfig
    } elseif($script:mode -eq 'rest') {
        if(-not $script:direct -and $Endpoint.Flavor -cne 'forerver'){throw '角色编排放号仅支持无限服。'}
        $script:restSession=@{RemainingMs=([long]$script:restSettings.DurationSeconds*1000);ObservedAt=$now;
            Login=$false;Started=$false;Deadline=0L;NextJumpAt=$now;Round=([int]$script:restVisits[$script:roleName]+1)}
    } elseif($script:mode -eq 'shop') {
        $settings=$script:shopSettings
        $script:shopSession=@{Deadline=$now+[long]$settings.DurationSeconds*1000;PrepareRequested=$false;FinishUntil=0L;State='';StateDueAt=0L;NextActionAt=$now;Visits=0;
            NextJumpAt=$now+[long]$settings.JumpIntervalSeconds*1000}
    } else {
        $observation=Get-DetectorObservationReady
        if(-not $observation.Packet){throw '战斗协议不可读，不能开始。'}
        $script:combat=New-AutoFightSession $now $observation.Packet.ClassId
        $profile=Get-DetectorProfile $script:combat.ClassId
        Set-AutoFightBuffSchedule $script:combat $profile $now -AfterLogin
    }
    $script:running=$true;$script:round++
    if(-not $script:direct){$script:runLogins++}
    Publish-Detector taskstart @{Role=$script:roleName;Index=$script:index;Mode=$script:mode;UseItem=$script:useItem;Round=$script:round;Direct=$script:direct;SwitchCount=([Math]::Max(0,$script:runLogins-1));Cycles=(Get-WowAutoCycleCount $script:scheduler $Endpoint.Key);BiteTimeouts=(Get-WowAutoBiteTimeoutCount $script:scheduler $Endpoint.Key);ClassId=$(if($script:combat -and $script:mode -eq 'fight'){$script:combat.ClassId}else{0});RestRound=$(if($script:mode -eq 'rest'){$script:restSession.Round}else{0});RestRounds=$(if($script:mode -eq 'rest'){if($script:direct){1}else{$script:restSettings.Rounds}}else{0})}
    $progress=if($script:mode -eq 'rest' -and -not $script:direct){'放号轮次 '+$script:restSession.Round+' / '+$script:restSettings.Rounds}else{'执行轮次 '+$script:round}
    Write-Detector ('已开始'+@{fight='战斗';fish='钓鱼';tame='抓宠';rest='放号';shop='购物'}[$script:mode]+'；角色：'+$script:roleName+'；'+$progress)
    if($script:mode -eq 'shop'){Publish-DetectorMetrics}
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
        $role=$script:roles[$index]
        if($role.Name -cin $script:excluded){continue}
        if($role.Mode -eq 'rest' -and [int]$script:restVisits[$role.Name] -ge $script:restSettings.Rounds){continue}
        if($role.Mode -eq 'shop' -and $script:shopCompleted.ContainsKey($role.Name)){continue}
        $script:index=$index;$script:roleName=$role.Name;$script:mode=$role.Mode;$script:useItem=$role.UseItem
        return $true
    }
    return $false
}
function Invoke-DetectorRotation {
    $script:running=$false;Stop-DetectorAudio
    if($script:discoverAccount){$script:roleName='';$script:mode='fish'}
    elseif(-not (Select-DetectorRole)){Exit-DetectorProcess '当前子战网所有启用角色均已移出本次轮转';return}
    Publish-Detector switching @{TargetRole=$script:roleName;Mode=$script:mode;Index=$script:index}
    $script:batch.Clear($Endpoint.Key,15)
    Write-Detector $(if($script:discoverAccount){'首次返回选角界面，准备OCR自动识别子战网。'}else{'开始切换到“'+$script:roleName+'”，等待选角界面后由本进程线程执行OCR。'})
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
            if($script:discoverAccount) {
                $resolution=Resolve-OcrAccount $screen $script:accountCandidates
                if($resolution.Account) {
                    $account=@($script:accountCandidates | Where-Object {$_.Account -ceq $resolution.Account})[0]
                    $script:account=$account.Account;$script:roles=@($account.Roles);$script:discoverAccount=$false
                    Publish-Detector account @{Account=$script:account;Matches=$resolution.Matches}
                    Write-Detector ('OCR已识别子战网：'+$script:account+'；匹配角色：'+($resolution.Matches -join '、')+'。')
                    if(-not $script:roles.Count){throw ('已识别子战网“'+$script:account+'”，没有可执行的启用角色，请在设置中配置。')}
                    if(-not (Select-DetectorRole)){throw '已识别子战网，但没有可执行角色。'}
                    Publish-Detector switching @{TargetRole=$script:roleName;Mode=$script:mode;Index=$script:index}
                    continue
                }
            }
            if($menuStable -lt 3){$menuStable++;continue}
            Write-Detector (Get-RotationOcrLog $screen $(if($script:discoverAccount){'子战网待识别'}else{$script:roleName}))
            $targets=@(if(-not $script:discoverAccount){$screen.Targets | Where-Object {$_.Name -ceq $script:roleName -and -not $_.Ambiguous}})
            if($targets.Count -gt 1){throw '列表出现多个相同角色名称，停止本进程编排。'}
            if($targets.Count -eq 0) {
                if($retries -ge 30){Exit-DetectorProcess $(if($script:discoverAccount){'选角页按↑后重识别30次仍未唯一确认子战网'}else{'角色“'+$script:roleName+'”按↑后重识别30次仍未找到'});return}
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
    $stable=0;$rodEquipped=$false
    while(Test-DetectorCurrent) {
        if($Hub.Now -ge $deadline){throw '登录超过180秒，已停止本进程编排。'}
        try {
            $observation=Get-DetectorObservation
            if($observation.Login){$stable++}else{$stable=0}
            if($stable -ge 3) {
                if($script:mode -eq 'fish' -and -not $rodEquipped) {
                    if(-not (Invoke-DetectorEquipRod)){return}
                    $rodEquipped=$true
                }
                if($script:mode -ne 'shop') {
                    $null=Request-DetectorOperation Rotation.Enable Rotation @{Mode=$script:mode}
                    $null=Wait-Detector $script:config.Periods.LoginMs
                }
                $observation=Get-DetectorObservation
                if($observation.Color -eq 'dead' -or ($observation.Packet -and $observation.Packet.Action -eq 'dead')){Remove-DetectorRole '角色死亡';return}
                if($script:mode -eq 'fish' -and $observation.Color -eq 'yellow'){Remove-DetectorRole '背包已满';return}
                if(($script:mode -eq 'fish' -and $observation.Color -in @('red','green')) -or ($script:mode -eq 'fight' -and $observation.Packet) -or
                    ($script:mode -eq 'rest' -and $observation.Mode -eq 'rest') -or
                    ($script:mode -eq 'shop' -and $observation.Login)) {
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
    if($script:direct){
        Stop-DetectorShoppingVisit
        if(-not (Test-DetectorCurrent)){return}
        Write-Detector ($Reason+'，直接开始任务已停止。')
        Publish-Detector stopped @{Reason=$Reason;Exited=$false}
        return
    }
    Write-Detector ($Reason+'：'+$script:roleName+'，移出本进程本次子战网轮转。')
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
function Complete-DetectorRestVisit {
    $script:running=$false;$script:restSession.Deadline=0L;$script:restSession.RemainingMs=0L
    if($script:direct){
        $reason='单次放号完成，已停止当前角色的任务。'
        Write-Detector $reason
        Publish-Detector stopped @{Reason=$reason;Exited=$false}
        return
    }
    $script:restVisits[$script:roleName]=[int]$script:restVisits[$script:roleName]+1
    $remaining=@($script:roles | Where-Object {
        $_.Name -cnotin $script:excluded -and ($_.Mode -ne 'rest' -or [int]$script:restVisits[$_.Name] -lt $script:restSettings.Rounds) -and
            ($_.Mode -ne 'shop' -or -not $script:shopCompleted.ContainsKey($_.Name))
    })
    if($remaining.Count) {
        Write-Detector ('角色“'+$script:roleName+'”完成第 '+$script:restSession.Round+' / '+$script:restSettings.Rounds+' 次放号，准备切换下一角色。')
        Publish-Detector rotate-needed @{Reason='放号单次时间已完成'}
    } else {
        if($script:batch){$script:batch.Drop($Endpoint.Key)}
        $reason='指定角色已全部完成 '+$script:restSettings.Rounds+' 轮放号。'
        Write-Detector $reason
        Publish-Detector stopped @{Reason=$reason;Exited=$false}
    }
}
function Invoke-DetectorRest {
    $now=$Hub.Now
    if($now -lt $script:nextColor){return}
    $script:nextColor=$now+$script:config.Periods.LoginMs
    $observation=Get-DetectorObservation
    if($script:direct -and $observation.Color -eq 'dead'){Remove-DetectorRole '角色死亡';return}
    $session=$script:restSession
    $inRestMode=$observation.Mode -eq 'rest'
    # Only consecutive observations in rest mode contribute to the duration.
    if($session.Started -and $session.Login -and $inRestMode) {
        $session.RemainingMs=[Math]::Max(0L,$session.RemainingMs-($now-$session.ObservedAt))
    }
    $session.ObservedAt=$now;$session.Login=$inRestMode
    $session.Deadline=if($session.Started -and $session.Login){$now+$session.RemainingMs}else{0L}
    if(-not $inRestMode){Write-Detector '等待右下角放号色块，放号计时和跳跃暂停。';return}
    if($session.Started -and $session.RemainingMs -le 0){Complete-DetectorRestVisit;return}
    if($now -lt $session.NextJumpAt -or $now -lt $script:retryAt){return}
    $reply=Request-DetectorOperation Rest.Jump Rest @{Deadline=$session.Deadline;Direct=$script:direct}
    if($reply -and $reply.Expired -and $session.Started) {Complete-DetectorRestVisit;return}
    if($reply -and $reply.Executed) {
        if(-not $session.Started) {
            $session.Started=$true;$session.ObservedAt=[long]$reply.SentAt
            $session.Deadline=$session.ObservedAt+$session.RemainingMs
        }
        $session.NextJumpAt=[long]$reply.SentAt+[long]$script:restSettings.JumpIntervalSeconds*1000
        $period=if($script:direct){'直接放号'}else{'放号第 '+$session.Round+' / '+$script:restSettings.Rounds+' 轮'}
        Write-Detector ($period+'，单次 '+$script:restSettings.DurationSeconds+' 秒，跳跃间隔 '+$script:restSettings.JumpIntervalSeconds+' 秒。')
    } else {
        $session.Login=$false;$session.Deadline=0L;$session.ObservedAt=$Hub.Now
    }
}
function Stop-DetectorShoppingVisit {
    if($script:shopSession -and $script:shopSession.PrepareRequested) {
        try {
            $reply=Request-DetectorOperation Shop.Stop Shop @{Deadline=($Hub.Now+5000L)}
            if((Test-DetectorCurrent) -and (-not $reply -or -not $reply.Executed)){
                Write-Detector '未能向插件发送停止购物命令。' error
            }
        } catch {
            Write-Detector ('未能向插件发送停止购物命令：'+$_.Exception.Message) error
        }
    }
    if(Test-DetectorCurrent){$script:shopSession=$null}
}
function Exit-DetectorAfterShopPurchase {
    $reason='已买到清单中的商品'
    $script:running=$false
    if($script:batch){$script:batch.Drop($Endpoint.Key)}
    Publish-Detector exiting @{Reason=$reason}
    Write-Detector ($reason+'，正在确认下线条件。')
    $reply=Request-DetectorOperation Shop.Logout Process @{Deadline=($Hub.Now+10000)}
    if(-not (Test-DetectorCurrent)){return}
    if(-not $reply.Confirmed){throw '购得状态未能复核，已停止购物。'}

    if($reply.Executed) {
        Write-Detector '已发送下线命令，等待角色离开游戏。'
        $until=$Hub.Now+30000
        $outOfWorld=0
        while((Test-DetectorCurrent) -and $Hub.Now -lt $until -and (Test-DetectorAlive)) {
            try {
                if((Get-DetectorObservation).Login){$outOfWorld=0}else{$outOfWorld++}
                if($outOfWorld -ge 2){break}
            } catch {
                $outOfWorld=0
                if([WowAutoCapture.Native]::IsPending($_.Exception)){Repair-DetectorCapture}
            }
            if(-not (Wait-Detector ([Math]::Min(500,[int]$script:config.Periods.LoginMs)))){return}
        }
    }
    if(-not (Test-DetectorCurrent)){return}
    Write-Detector ($reason+'，正在正常关闭该游戏客户端。')
    $reply=Request-DetectorOperation Process.Shutdown Process
    if(-not (Test-DetectorCurrent)){return}
    if(-not $reply.Exited){throw '购物完成后未能确认该客户端已关闭。'}
    $script:shopSession=$null
    $reason+='，已关闭该游戏客户端。'
    Write-Detector $reason
    Publish-Detector stopped @{Reason=$reason;Exited=$true}
    $Endpoint.Finish()
}
function Publish-DetectorMetrics {
    $shop=if($script:mode -eq 'shop'){$script:shopSession}
    $script:nextMetrics=$Hub.Now+250L
    $metrics=@{
        Deadline=$(if($script:mode -eq 'fish'){$script:fish.Deadline}elseif($script:mode -eq 'rest'){$script:restSession.Deadline}elseif($shop){$shop.Deadline}else{0L})
        RestRemainingSeconds=$(if($script:mode -eq 'rest'){[Math]::Ceiling($script:restSession.RemainingMs/1000.0)}else{0})
        Cycles=(Get-WowAutoCycleCount $script:scheduler $Endpoint.Key)
        BiteTimeouts=(Get-WowAutoBiteTimeoutCount $script:scheduler $Endpoint.Key)
        Audio=[bool]$script:audio
        Similarity=$(if($script:audio){$script:audio.Similarity}else{0.0})
        Peak=$(if($script:audio){$script:audio.Peak}else{0.0})
    }
    if($shop){
        $metrics.ShopState=$shop.State
        $metrics.ShopStateDueAt=$shop.StateDueAt
    }
    Publish-Detector metrics $metrics
}
function Invoke-DetectorShop {
    $now=$Hub.Now
    $session=$script:shopSession
    $expired=$now -ge $session.Deadline
    if(-not $expired -and ($now -lt $script:retryAt -or $now -lt $script:nextColor)){return}
    $pollMs=[Math]::Min(100,[int]$script:config.Periods.LoginMs)
    $script:nextColor=$now+$pollMs
    $state='unknown'
    if($session.PrepareRequested -or $script:direct) {
        try {$state=[WowAutoRotation.Native]::ReadShoppingState($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path,$script:direct)}
        catch {
            if(-not $expired -or -not [WowAutoCapture.Native]::IsPending($_.Exception)){throw}
        }
        if($state -eq 'dead'){Remove-DetectorRole '角色死亡';return}
        if(-not $session.PrepareRequested){$state='unknown'}
        if($state -eq 'bought' -and $session.Visits -gt 0){Exit-DetectorAfterShopPurchase;return}
    }
    if($expired) {
        if($session.PrepareRequested -and -not $session.FinishUntil){
            # End new purchases and let the plugin report an already-submitted receipt.
            try {
                $reply=Request-DetectorOperation Shop.Stop Shop @{Finish=$true;Deadline=($Hub.Now+5000L)}
                if(-not (Test-DetectorCurrent)){return}
                if($reply -and $reply.Executed){
                    $session.FinishUntil=$Hub.Now+5000L
                    return
                }
            } catch {
                if(-not (Test-DetectorCurrent)){return}
                Write-Detector '未能正常结束购物，正在尝试取消。'
            }
        }
        if($session.FinishUntil -and $now -lt $session.FinishUntil){
            $mode='unknown'
            if($state -eq 'unknown'){
                try {$mode=[WowAutoRotation.Native]::ReadLoginMode($Endpoint.Pid,$Endpoint.StartTicks,$Endpoint.Path)}
                catch {if(-not [WowAutoCapture.Native]::IsPending($_.Exception)){throw}}
            }
            if($mode -notin @('rest','fish','fight')){
                $null=Wait-Detector $pollMs
                return
            }
            $session.PrepareRequested=$false
        }
        $script:running=$false
        Stop-DetectorShoppingVisit
        if(-not (Test-DetectorCurrent)){return}
        $reason='达到最大购物时长，已停止购物。'
        Write-Detector $reason
        if(-not $script:direct) {
            $script:shopCompleted[$script:roleName]=$true
            $remaining=@($script:roles | Where-Object {
                $_.Name -cnotin $script:excluded -and ($_.Mode -ne 'shop' -or -not $script:shopCompleted.ContainsKey($_.Name)) -and
                    ($_.Mode -ne 'rest' -or [int]$script:restVisits[$_.Name] -lt $script:restSettings.Rounds)
            })
            if($remaining.Count){Publish-Detector rotate-needed @{Reason=$reason};return}
        }
        if($script:batch){$script:batch.Drop($Endpoint.Key)}
        Publish-Detector stopped @{Reason=$reason;Exited=$false}
        return
    }
    if($state -notin @('closed','open')) {
        if(-not $session.State -and $now -ge $session.NextActionAt){
            if($session.PrepareRequested){
                Write-Detector '未确认购物模式和商店状态。请选中商人，确认已更新插件并保存购物清单。'
            }
            $session.PrepareRequested=$true
            $null=Request-DetectorOperation Shop.Prepare Shop @{Deadline=$session.Deadline}
            $session.NextActionAt=$Hub.Now+1500L
        } elseif($session.State) {
            Write-Detector '等待购物插件确认商店状态。'
        }
        return
    }
    $settings=$script:shopSettings
    if($state -ne $session.State){
        # Draw one interval when the actual merchant state changes.
        $session.State=$state
        $baseMs=if($state -eq 'open'){[long]$settings.CloseDelayMs}else{[long]$settings.ReopenDelayMs}
        $jitterMs=[long]$settings.JitterMs
        $delay=Get-Random -Minimum ([Math]::Max(1L,($baseMs-$jitterMs))) -Maximum ($baseMs+$jitterMs+1L)
        $session.StateDueAt=$Hub.Now+$delay
        $session.NextActionAt=0L
        Write-Detector $(if($state -eq 'open'){'商店已打开，开始关店倒计时。'}else{'商店已关闭，开始开店倒计时。'})
        Publish-DetectorMetrics
        return
    }
    if($now -lt $session.NextActionAt){return}
    if($now -ge $session.StateDueAt){
        if($state -eq 'open'){
            $null=Request-DetectorOperation Shop.Close Shop @{Deadline=$session.Deadline}
            $session.NextActionAt=$Hub.Now+250L
            return
        }
        $reply=Request-DetectorOperation Shop.Visit Shop @{Key=$settings.InteractKey;Deadline=$session.Deadline;JumpOnVisit=$settings.JumpOnVisit}
        if($reply -and $null -ne $reply.JumpedAt){
            $session.NextJumpAt=[long]$reply.JumpedAt+[long]$settings.JumpIntervalSeconds*1000
        }
        $retryDelay=250L
        if($reply -and $reply.Interacted){
            $session.Visits++
            $retryDelay=4000L
            if($reply.Executed){
                $inputDescription=if($null -ne $reply.JumpedAt){'交互键和空格'}else{'交互键'}
                Write-Detector ('第 '+$session.Visits+' 次购物访问已发送'+$inputDescription+'，等待插件处理购买。')
            }
        }
        $session.NextActionAt=$Hub.Now+$retryDelay
    } elseif($state -eq 'closed' -and $settings.JumpIntervalSeconds -gt 0 -and $now -ge $session.NextJumpAt){
        $reply=Request-DetectorOperation Shop.Jump Shop @{Deadline=$session.Deadline}
        if($reply -and $reply.Executed){$session.NextJumpAt=[long]$reply.SentAt+[long]$settings.JumpIntervalSeconds*1000}
    }
}
function Invoke-DetectorTaskCore {
    $now=$Hub.Now
    if($script:mode -eq 'rest'){Invoke-DetectorRest;return}
    if($script:mode -eq 'shop'){Invoke-DetectorShop;return}
    if($script:mode -eq 'tame') {
        if($now -lt $script:nextColor){return}
        $script:nextColor=$now+100
        $observation=Get-DetectorObservation
        if($script:direct -and $observation.Color -eq 'dead'){Remove-DetectorRole '角色死亡';return}
        $packet=if($observation.Login){$observation.Packet}else{$null}
        if($packet -and $packet.State -eq 'dead'){throw '角色死亡或处于灵魂状态，抓宠已停止。'}
        $action=Get-AutoTameAction $script:tame $packet $script:tameConfig $now
        if($action -and $now -ge $script:retryAt) {
            $kind=if($action.Stage -eq 'Jump'){'Tame.Jump'}else{'Tame.Key'}
            $reply=Request-DetectorOperation $kind Tame @{Keys=@($action.Key);TargetId=$action.TargetId;RequireCombat=$action.RequireCombat;Stage=$action.Stage;KeyHoldMs=$action.KeyHoldMs;ExpectedState=$action.ExpectedState;ExpectedCombat=$action.ExpectedCombat}
            if($reply -and $reply.CombatObserved){$script:tame.SeenCombat=$true}
            if($reply -and $reply.Executed){Complete-AutoTameAction $script:tame $action $script:tameConfig $reply.SentAt}
            elseif($reply -and $reply.TameInterrupted){
                $script:tame.FinishedTarget=$action.TargetId
                $script:tame.Active=$false
                $script:tame.Status='后退已中断并松键，等待更换目标或重新开始。'
                if($reply.Error){$script:tame.Status+=' '+$reply.Error}
            }
        }
        Write-Detector $script:tame.Status
        return
    }
    if($script:fishColorRetryAt -gt $now){
        # Retry delays fishing actions only; terminal signals still receive their normal poll.
        if($now -ge $script:nextDeath){
            $terminal=Get-DetectorObservation
            $script:nextDeath=$now+$script:config.Periods.DeathMs
            if($terminal.Color -eq 'dead'){Remove-DetectorRole '角色死亡';return}
            if($terminal.Color -eq 'yellow'){Remove-DetectorRole '背包已满';return}
        }
        return
    }
    if($now -ge $script:nextColor -or $now -ge $script:nextDeath) {
        $observation=Get-DetectorObservation
        if($observation.Color -eq 'dead' -or ($observation.Packet -and $observation.Packet.Action -eq 'dead')){Remove-DetectorRole '角色死亡';return}
        if($script:mode -eq 'fish' -and $observation.Color -eq 'yellow'){Remove-DetectorRole '背包已满';return}
        if($script:mode -eq 'fish' -and $script:fish.UseAudio -and $observation.Login -and $observation.Color -notin @('red','green')){
            Reset-WowAutoColorRetry $script:scheduler $Endpoint.Key
            $script:observation=$null
            $script:fishColorRetryAt=$now+$script:config.Operations.FishColorRetryMs
            $script:nextDeath=$now+$script:config.Periods.DeathMs
            Write-Detector ('钓鱼检测关闭或颜色未知，等待 '+$script:config.Operations.FishColorRetryMs+'ms 后重试。')
            return
        }
        $script:fishColorRetryAt=0L
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
            $detail=('无咬钩保护诊断：保护 {0} ms；采集 {1}；最高峰值 {2:F2}%；已比较候选 {3}；最高相似度 {4:F1}%；匹配门槛 {5}%；模板 {6}；自适应音量门槛 {7:F3}%。' -f
                ($state.Deadline-$state.FishingStartedAt),$script:audio.Status,($script:audio.MaximumPeak*100),$script:audio.ComparedCandidates,
                ($script:audio.BestSimilarity*100),$script:config.AudioThreshold,([IO.Path]::GetFileName($script:config.FeaturePath)),($script:audio.CandidatePeakThreshold*100))
            $Hub.Log($Endpoint,$script:version,'audio-timeout',$detail)
        }
        Complete-WowAutoAudioTimeout $script:scheduler $Endpoint.Key $now '无咬钩声音超时，重新抛竿，不计成功收竿循环。'
        Publish-Detector counters @{Cycles=(Get-WowAutoCycleCount $script:scheduler $Endpoint.Key);BiteTimeouts=(Get-WowAutoBiteTimeoutCount $script:scheduler $Endpoint.Key)}
        Write-Detector $state.Status;return
    }
    if($work.Kind -eq 'FocusRetry'){Resume-WowAutoFocus $script:scheduler $Endpoint.Key;return}
    if(-not $script:observation -or -not $script:observation.Login){Write-Detector '等待插件登录色块和钓鱼色块。';return}
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
$script:account='';$script:accountCandidates=@();$script:discoverAccount=$false
$script:restSettings=$null;$script:restVisits=@{};$script:restSession=$null
$script:shopSettings=$null;$script:shopCompleted=@{};$script:shopSession=$null
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
                Stop-DetectorShoppingVisit
                if(-not (Test-DetectorCurrent)){continue}
                if($command.Kind -eq 'Stop'){
                    Stop-WowAutoTask $script:scheduler $Endpoint.Key
                    $script:scheduler.ReelHoldUntil=0L;$script:scheduler.ItemHoldUntil=0L
                    Write-Detector '已停止，本进程待执行操作已取消。';Publish-Detector stopped @{Reason='已停止';Exited=$false};continue
                }
                $body=$command.Json | ConvertFrom-Json;$script:config=$body.Config;$script:roles=@($body.Roles);$script:direct=[bool]$body.Direct
                $script:account=[string]$body.Account;$script:accountCandidates=@($body.AccountCandidates)
                $script:discoverAccount=$command.Kind -eq 'Start' -and -not $script:direct
                Set-DetectorScheduler
                if($command.Kind -eq 'Scan') {
                    $script:mode=$body.Mode
                    Invoke-DetectorScan
                    continue
                }
                if($command.Kind -eq 'Start') {
                    $script:excluded=@();$script:index=-1;$script:runLogins=0;$script:round=[Math]::Max($script:round,[int]$body.RoundBase)
                    $script:restSettings=$body.Config.Rest;$script:restVisits=@{};$script:restSession=$null
                    $script:shopSettings=$body.Config.Shop;$script:shopCompleted=@{};$script:shopSession=$null
                }
                if($script:direct) {
                    $script:roleName='';$script:index=-1;$script:mode=$body.Mode;$script:useItem=[bool]$body.UseItem
                    $script:batch=$null
                    if($script:mode -cnotin ((Get-WowAutoDirectTaskModes) + 'tame')){throw '不支持的直接开始任务。'}
                    $observation=Get-DetectorObservationReady
                    if(-not (Test-DetectorCurrent)){continue}
                    if($observation.Color -eq 'dead'){Remove-DetectorRole '角色死亡';continue}
                    if($script:mode -eq 'fish' -and -not (Invoke-DetectorEquipRod)){continue}
                    if($script:mode -eq 'tame'){
                        Invoke-DetectorScan
                        if(-not (Test-DetectorCurrent)){continue}
                    } elseif(-not (Invoke-DetectorScan -ForStart)){continue}
                    Start-DetectorTask
                }
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
                Publish-DetectorMetrics
            }
        } catch {
            if(-not (Test-DetectorCurrent)){continue}
            if([WowAutoCapture.Native]::IsPending($_.Exception)){
                if($script:mode -eq 'rest' -and $script:restSession){$script:restSession.Login=$false;$script:restSession.Deadline=0L}
                Repair-DetectorCapture;$null=Wait-Detector $script:config.Periods.CaptureRetryMs;continue
            }
            if($script:running -and $_.Exception.Message -match '前台保护时间') {
                $script:retryAt=$Hub.Now+$script:config.FocusRetryMs
                if($script:mode -eq 'fish'){Suspend-WowAutoFocus $script:scheduler $Endpoint.Key $Hub.Now '窗口操作暂时失败。'}elseif($script:mode -eq 'fight'){$script:combat.Due=$script:retryAt}
                Write-Detector ('窗口操作失败，继续后台检测，等待 '+$script:config.FocusRetryMs+'ms 后重试操作。');continue
            }
            $reason=$_.Exception.Message
            $script:running=$false;Stop-DetectorAudio
            Stop-DetectorShoppingVisit
            if(-not (Test-DetectorCurrent)){continue}
            if($script:batch){$script:batch.Drop($Endpoint.Key)}
            Write-Detector ('检测线程停止：'+$reason) error
            Publish-Detector stopped @{Reason=$reason;Exited=$false}
        }
    }
} finally {Stop-DetectorAudio;if($script:batch){$script:batch.Drop($Endpoint.Key)}}
