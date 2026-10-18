# Pure shared scheduler. Native window/input operations are performed by the GUI adapter.
function New-WowAutoState {
    param([int]$MinimumMs, [int]$MaximumMs)
    if ($MinimumMs -lt 1 -or $MaximumMs -gt 3600000 -or $MinimumMs -gt $MaximumMs) {
        throw '等待范围需满足：1 ≤ 最小值 ≤ 最大值 ≤ 3600000 ms。'
    }
    [pscustomobject]@{
        Running=$true; Mode='Ready'; NextDue=0L; Deadline=0L; DeathCheckAt=0L
        MinimumMs=$MinimumMs; MaximumMs=$MaximumMs; LastInterval=-1; ForceNextCast=$false; ReelDelayMs=0
        AwaitingFishingTransition=$false; SawIdle=$false
        CheckReelGreen=$false; CycleJumpPending=$false; PostReelJumpAllowed=$false
        UseItem=$false; ItemDue=0L; ItemRetryAt=0L; InitialItemPending=$false
        ItemConfirmUntil=0L; ItemDetectionDisabled=$false
        ItemStatus=''
        FocusRetryAt=0L; FocusResumeStatus=''
        UseAudio=$false; AudioReady=$true; AudioSession=0L; FishingStartedAt=0L; AudioReelPending=$false; AudioTimeoutMs=35000
        Status='已加入统一调度队列。'
    }
}
function Stop-WowAutoState {
    param($State, [string]$Reason='已停止。')
    $State.Running=$false; $State.Mode='Stopped'; $State.Deadline=0L; $State.Status=$Reason
    $State.FocusRetryAt=0L; $State.FocusResumeStatus=''
    $State.AudioReelPending=$false; $State.ReelDelayMs=0
    $State.PostReelJumpAllowed=$false
}
function Suspend-WowAutoFocus($Scheduler, [string]$Key, [long]$Now, [string]$Reason) {
    $state=$Scheduler.Tasks[$Key]
    if ($null -eq $state -or -not $state.Running) { return }
    if ($state.FocusRetryAt -eq 0) { $state.FocusResumeStatus=$state.Status }
    $state.FocusRetryAt=$Now+$Scheduler.FocusRetryIntervalMs
    $state.Status="$Reason 已暂停此行，保留任务并等待重试焦点。"
    if ($Scheduler.ActiveKey -eq $Key) { $Scheduler.ActiveKey=$null }
}
function Resume-WowAutoFocus($Scheduler, [string]$Key) {
    $state=$Scheduler.Tasks[$Key]
    if ($null -eq $state -or -not $state.Running -or $state.FocusRetryAt -eq 0) { return }
    $state.FocusRetryAt=0L
    $state.Status=$state.FocusResumeStatus
    $state.FocusResumeStatus=''
}
function Get-WowAutoInterval {
    param([int]$Previous)
    if ($Previous -lt 300) { return (Get-Random -Minimum 300 -Maximum 601) }
    $value=Get-Random -Minimum 300 -Maximum 600
    if ($value -ge $Previous) { $value++ }
    return $value
}
function New-WowAutoScheduler {
    [pscustomobject]@{
        Tasks=@{}; CompletedCycles=@{}; CyclesSinceJump=@{}; JumpEveryCycles=0; Order=(New-Object 'System.Collections.Generic.List[string]')
        Events=(New-Object System.Collections.ArrayList)
        Cursor=0; ActiveKey=$null; Sequence=0L; ReelHoldUntil=0L; ReelHoldMs=100
        ItemHoldUntil=0L; ItemHoldMs=3000; FocusRetryIntervalMs=30000
    }
}
function Set-WowAutoHoldDuration($Scheduler, [ValidateRange(0,60000)][int]$Milliseconds) {
    $Scheduler.ReelHoldMs=$Milliseconds
}
function Set-WowAutoJumpInterval($Scheduler, [ValidateRange(0,1000000)][int]$Cycles) {
    if ($Scheduler.JumpEveryCycles -eq $Cycles) { return }
    $Scheduler.JumpEveryCycles=$Cycles
    $Scheduler.CyclesSinceJump.Clear()
    foreach ($state in $Scheduler.Tasks.Values) { $state.CycleJumpPending=$false }
}
function Set-WowAutoFocusRetryInterval($Scheduler, [ValidateRange(1000,3600000)][int]$Milliseconds) {
    # Apply to the next failure, leaving already scheduled retries unchanged.
    $Scheduler.FocusRetryIntervalMs=$Milliseconds
}
function Set-WowAutoItemEnabled($Scheduler, [string]$Key, [bool]$Enabled, [long]$Now) {
    $state=$Scheduler.Tasks[$Key]
    if ($null -eq $state -or -not $state.Running -or $state.UseItem -eq $Enabled) { return }
    $state.UseItem=$Enabled
    $state.ItemDue=if ($Enabled) { $Now } else { 0L }
    $state.ItemRetryAt=0L
    $state.InitialItemPending=$Enabled
    $state.ItemConfirmUntil=0L
    $state.ItemDetectionDisabled=$false
    $state.ItemStatus=if ($Enabled) { '等待鱼饵附魔检测。' } else { '' }
}
function Complete-WowAutoItemCheck($Scheduler, [string]$Key, [long]$Now, [string]$Lure, [string]$Color) {
    $state=$Scheduler.Tasks[$Key]
    if ($null -eq $state -or -not $state.Running -or -not $state.UseItem -or $state.ItemDetectionDisabled) { return 'Continue' }
    $state.ItemDue=$Now+1000
    if ($Color -in @('red','green') -and $Lure -eq 'present') {
        $state.InitialItemPending=$false; $state.ItemRetryAt=0L; $state.ItemConfirmUntil=0L
        $state.ItemStatus='鱼竿临时附魔有效，无需使用道具。'
        return 'Continue'
    }
    if ($state.ItemConfirmUntil -gt 0 -and $Now -ge $state.ItemConfirmUntil) {
        $state.ItemDetectionDisabled=$true; $state.InitialItemPending=$false
        $state.ItemDue=0L; $state.ItemRetryAt=0L; $state.ItemConfirmUntil=0L
        $state.ItemStatus='5秒内未确认道具使用成功，已关闭本任务道具检测。'
        return 'Continue'
    }
    if ($Color -notin @('red','green') -or $Lure -notin @('present','missing')) {
        $state.InitialItemPending=$true
        $state.ItemStatus='鱼饵检测点未知：暂停本行抛竿，等待有效检测。'
        if ($Scheduler.ActiveKey -eq $Key) { $Scheduler.ActiveKey=$null }
        return 'Wait'
    }
    if ($Color -eq 'green') {
        $state.InitialItemPending=$false
        $state.ItemStatus='缺少鱼饵附魔：本轮收竿后再使用道具。'
        return 'Continue'
    }
    $state.InitialItemPending=$true
    if ($Now -lt $state.ItemRetryAt) {
        $state.ItemStatus='尚未确认鱼饵附魔，等待使用结果。'
        if ($Scheduler.ActiveKey -eq $Key) { $Scheduler.ActiveKey=$null }
        return 'Wait'
    }
    $state.ItemStatus='缺少鱼饵附魔：使用钓鱼道具。'
    return 'UseItem'
}
function Complete-WowAutoItem($Scheduler, [string]$Key, [long]$Now, [bool]$Sent) {
    $state=$Scheduler.Tasks[$Key]
    if ($null -eq $state -or -not $state.Running -or -not $state.UseItem -or $state.ItemDetectionDisabled) { return }
    if (-not $state.ItemConfirmUntil) { $state.ItemConfirmUntil=$Now+5000 }
    if ($Sent) {
        $state.InitialItemPending=$true
        $Scheduler.ItemHoldUntil=$Now+$Scheduler.ItemHoldMs
        $state.ItemDue=$Now+$Scheduler.ItemHoldMs
        $state.ItemRetryAt=$state.ItemConfirmUntil
        $state.ItemStatus='道具键已发送，等待确认鱼竿附魔。'
    } else {
        $state.ItemRetryAt=[Math]::Min($Now+500,$state.ItemConfirmUntil)
        $state.ItemDue=$state.ItemRetryAt
        $state.ItemStatus='道具键发送失败，限时重试。'
    }
}
function Get-WowAutoCycleCount($Scheduler, [string]$Key) {
    if ($Scheduler.CompletedCycles.ContainsKey($Key)) { return [long]$Scheduler.CompletedCycles[$Key] }
    return 0L
}
function Remove-WowAutoEvents($Scheduler, [string]$Key) {
    for ($i=$Scheduler.Events.Count-1; $i -ge 0; $i--) {
        if ($Scheduler.Events[$i].Key -eq $Key) { $Scheduler.Events.RemoveAt($i) }
    }
}
function Stop-WowAutoTask($Scheduler, [string]$Key, [string]$Reason='已停止，定时事件已取消。') {
    if ($Scheduler.Tasks.ContainsKey($Key)) {
        Stop-WowAutoState $Scheduler.Tasks[$Key] $Reason
        $Scheduler.Tasks.Remove($Key)
    }
    Remove-WowAutoEvents $Scheduler $Key
    $index=$Scheduler.Order.IndexOf($Key)
    if ($index -ge 0) {
        $Scheduler.Order.RemoveAt($index)
        if ($index -lt $Scheduler.Cursor) { $Scheduler.Cursor-- }
        if ($Scheduler.Cursor -ge $Scheduler.Order.Count) { $Scheduler.Cursor=0 }
    }
    if ($Scheduler.ActiveKey -eq $Key) { $Scheduler.ActiveKey=$null }
}
function Add-WowAutoTask($Scheduler, [string]$Key, [int]$MinimumMs, [int]$MaximumMs, [long]$Now, [bool]$UseItem=$false, [bool]$UseAudio=$false, [ValidateRange(1000,3600000)][int]$AudioTimeoutMs=35000) {
    $state=New-WowAutoState $MinimumMs $MaximumMs
    Stop-WowAutoTask $Scheduler $Key
    $state.NextDue=$Now
    $state.UseAudio=$UseAudio; $state.AudioReady=-not $UseAudio
    $state.AudioTimeoutMs=$AudioTimeoutMs
    $state.CycleJumpPending=$Scheduler.JumpEveryCycles -gt 0 -and [long]$Scheduler.CyclesSinceJump[$Key] -ge $Scheduler.JumpEveryCycles
    $Scheduler.Tasks[$Key]=$state
    $Scheduler.Order.Add($Key)
    Set-WowAutoItemEnabled $Scheduler $Key $UseItem $Now
    return $state
}
function Add-WowAutoEvent($Scheduler, [string]$Key, [string]$Kind, [long]$Due) {
    $Scheduler.Sequence++
    [void]$Scheduler.Events.Add([pscustomobject]@{
        Key=$Key; Kind=$Kind; Due=$Due; Sequence=$Scheduler.Sequence; State=$Scheduler.Tasks[$Key]
    })
}
function Get-WowAutoWork($Scheduler, [long]$Now) {
    # No task, even an overdue reel, may take the foreground during this hold.
    if ($Now -lt $Scheduler.ReelHoldUntil -or $Now -lt $Scheduler.ItemHoldUntil) { return $null }
    # Remove obsolete events before selecting an action. An event retains its session identity.
    for ($i=$Scheduler.Events.Count-1; $i -ge 0; $i--) {
        $event=$Scheduler.Events[$i]
        $state=$Scheduler.Tasks[$event.Key]
        if ($null -eq $state -or -not $state.Running -or -not [object]::ReferenceEquals($event.State,$state)) {
            $Scheduler.Events.RemoveAt($i)
        }
        elseif ($state.FocusRetryAt -eq 0 -and $event.Kind -eq 'Cooldown' -and $event.Due -le $Now) {
            $state.Mode='Ready'; $state.Deadline=0L; $state.NextDue=$Now
            $state.Status='收竿后等待结束，重新排队下竿。'
            $Scheduler.Events.RemoveAt($i)
        }
    }
    $due=@($Scheduler.Events | Where-Object {
        $_.Kind -eq 'Reel' -and $_.Due -le $Now -and $Scheduler.Tasks[$_.Key].FocusRetryAt -eq 0
    } | Sort-Object Due,Sequence)
    if ($due.Count -gt 0) {
        return [pscustomobject]@{ Key=$due[0].Key; Kind='Reel'; Due=$due[0].Due }
    }
    $timeouts=@($Scheduler.Events | Where-Object {
        $_.Kind -eq 'AudioTimeout' -and $_.Due -le $Now -and $Scheduler.Tasks[$_.Key].FocusRetryAt -eq 0
    } | Sort-Object Due,Sequence)
    if ($timeouts.Count -gt 0) {
        return [pscustomobject]@{ Key=$timeouts[0].Key; Kind='AudioTimeout'; Due=$timeouts[0].Due }
    }
    $item=@($Scheduler.Order | Where-Object {
        $s=$Scheduler.Tasks[$_]
        $s.Running -and $s.AudioReady -and $s.UseItem -and -not $s.ItemDetectionDisabled -and $s.FocusRetryAt -eq 0 -and $s.Mode -in @('Ready','Casting') -and $s.ItemDue -le $Now
    } | Sort-Object { $Scheduler.Tasks[$_].ItemDue })
    if ($item.Count -gt 0) {
        return [pscustomobject]@{ Key=$item[0]; Kind='Item'; Due=$Scheduler.Tasks[$item[0]].ItemDue }
    }
    # Suspended rows retain their fishing/item deadlines but cannot monopolize overdue work.
    $retry=@($Scheduler.Order | Where-Object {
        $s=$Scheduler.Tasks[$_]
        $s.Running -and $s.FocusRetryAt -gt 0 -and $s.FocusRetryAt -le $Now
    } | Sort-Object { $Scheduler.Tasks[$_].FocusRetryAt })
    if ($retry.Count -gt 0) {
        return [pscustomobject]@{ Key=$retry[0]; Kind='FocusRetry'; Due=$Scheduler.Tasks[$retry[0]].FocusRetryAt }
    }
    if ($null -ne $Scheduler.ActiveKey) {
        $active=$Scheduler.Tasks[$Scheduler.ActiveKey]
        if ($null -ne $active -and $active.Running -and $active.AudioReady -and $active.FocusRetryAt -eq 0 -and -not $active.InitialItemPending -and $active.Mode -in @('Ready','Casting')) {
            if ($active.NextDue -le $Now) { return [pscustomobject]@{ Key=$Scheduler.ActiveKey; Kind='Poll'; Due=$active.NextDue } }
            return $null # Keep this window until green, unless a Reel event preempts it.
        }
        $Scheduler.ActiveKey=$null
    }
    $count=$Scheduler.Order.Count
    for ($offset=0; $offset -lt $count; $offset++) {
        $index=($Scheduler.Cursor+$offset)%$count
        $key=$Scheduler.Order[$index]
        $state=$Scheduler.Tasks[$key]
        if ($state.Running -and $state.AudioReady -and $state.FocusRetryAt -eq 0 -and -not $state.InitialItemPending -and $state.Mode -in @('Ready','Casting') -and $state.NextDue -le $Now) {
            $Scheduler.Cursor=($index+1)%$count
            $Scheduler.ActiveKey=$key
            return [pscustomobject]@{ Key=$key; Kind='Poll'; Due=$state.NextDue }
        }
    }
    return $null
}
function Test-WowAutoPollNeedsInput($State,[string]$Color) {
    if (-not $State -or -not $State.Running) {return $false}
    return $Color -eq 'red' -or ($Color -eq 'green' -and $State.ForceNextCast) -or
        ($State.PostReelJumpAllowed -and $State.Mode -in @('Ready','Casting') -and
         $Color -in @('red','green') -and ($State.CycleJumpPending -or ($State.CheckReelGreen -and $Color -eq 'green')))
}
function Complete-WowAutoPoll($Scheduler, [string]$Key, [long]$Now, [string]$Color) {
    $state=$Scheduler.Tasks[$Key]
    if ($null -eq $state -or -not $state.Running) { return 'None' }
    if ($Color -eq 'yellow') {
        Stop-WowAutoTask $Scheduler $Key '背包已满，停止当前钓鱼任务。'
        return 'Stop'
    }
    if ($Color -eq 'red') { $state.SawIdle=$true; $state.CheckReelGreen=$false }
    # A periodic/recovery jump belongs to a successfully reeled session only. Reaching
    # the count, inheriting a count on restart, or an audio timeout cannot interrupt fishing.
    if ($state.PostReelJumpAllowed -and $state.Mode -in @('Ready','Casting') -and
        $Color -in @('red','green') -and ($state.CycleJumpPending -or ($state.CheckReelGreen -and $Color -eq 'green'))) {
        $state.Mode='Casting'
        $state.LastInterval=Get-WowAutoInterval $state.LastInterval
        $state.NextDue=$Now+$state.LastInterval
        $state.Status=if ($state.CycleJumpPending) { "已完成 $($Scheduler.JumpEveryCycles) 次循环：跳跃一次后继续抛竿。" }
            else { '收竿后仍为绿色：发送一次空格跳跃，再继续抛竿检测。' }
        return 'Jump'
    }
    if ($Color -eq 'green' -and -not $state.ForceNextCast) {
        if ($state.AwaitingFishingTransition -and -not $state.SawIdle) {
            $state.Mode='Casting'
            $state.LastInterval=Get-WowAutoInterval $state.LastInterval
            $state.NextDue=$Now+$state.LastInterval
            $state.Status='等待本轮红色→绿色确认：当前仍为绿色，尚未检测到红色，不开始倒计时。'
            return 'None'
        }
        $state.AwaitingFishingTransition=$false
        if ($state.UseAudio) {
            Remove-WowAutoEvents $Scheduler $Key
            $Scheduler.Sequence++
            $state.AudioSession=$Scheduler.Sequence
            $state.FishingStartedAt=$Now
            $state.AudioReelPending=$false; $state.ReelDelayMs=0
            $state.Mode='Wait'; $state.Deadline=$Now+$state.AudioTimeoutMs
            $state.Status='已确认钓鱼：监听本进程音频，匹配后随机等待再收竿。'
            Add-WowAutoEvent $Scheduler $Key 'AudioTimeout' $state.Deadline
            $Scheduler.ActiveKey=$null
            return 'None'
        }
        $delay=Get-Random -Minimum $state.MinimumMs -Maximum ($state.MaximumMs+1)
        Remove-WowAutoEvents $Scheduler $Key
        $state.Mode='Wait'; $state.Deadline=$Now+$delay; $state.ReelDelayMs=$delay
        $state.Status="已钓鱼：登记 $delay ms 收竿事件，切换下一个窗口。"
        Add-WowAutoEvent $Scheduler $Key 'Reel' $state.Deadline
        $Scheduler.ActiveKey=$null
        return 'None'
    }
    if ($Color -eq 'red' -or ($Color -eq 'green' -and $state.ForceNextCast)) {
        $state.Mode='Casting'
        $state.LastInterval=Get-WowAutoInterval $state.LastInterval
        $state.NextDue=$Now+$state.LastInterval
        $state.Status=if ($state.ForceNextCast) { '收竿后首次抛竿：强制发送 抛竿键，再恢复颜色检测。' } else { '未钓鱼：重复 抛竿键，等待变绿；到期收竿优先。' }
        return 'Ctrl1'
    }
    $state.Mode='Ready'; $state.NextDue=$Now+500
    $state.Status='灰色或未知：暂不按键，稍后重新排队检测。'
    $Scheduler.ActiveKey=$null
    return 'None'
}
function Complete-WowAutoAudioBite($Scheduler, [string]$Key, [long]$Now, [long]$Session) {
    $state=$Scheduler.Tasks[$Key]
    if ($null -eq $state -or -not $state.Running -or -not $state.UseAudio -or $state.Mode -ne 'Wait' -or
        $Session -eq 0 -or $state.AudioSession -ne $Session -or $Now -lt $state.FishingStartedAt+1000) { return $false }
    if (@($Scheduler.Events | Where-Object { $_.Key -eq $Key -and $_.Kind -eq 'Reel' }).Count -gt 0) { return $false }
    $delay=Get-Random -Minimum $state.MinimumMs -Maximum ($state.MaximumMs+1)
    Remove-WowAutoEvents $Scheduler $Key
    $state.AudioReelPending=$true
    $state.Deadline=$Now+$delay; $state.ReelDelayMs=$delay
    $state.Status="音频匹配成功：随机等待 $delay ms 后收竿，已登记收竿事件。"
    Add-WowAutoEvent $Scheduler $Key 'Reel' $state.Deadline
    return $true
}
function Reset-WowAutoAudioWait($Scheduler, [string]$Key, [long]$Now, [string]$Reason) {
    $state=$Scheduler.Tasks[$Key]
    if ($null -eq $state -or -not $state.Running -or -not $state.UseAudio) { return }
    Remove-WowAutoEvents $Scheduler $Key
    $state.AudioSession=0L; $state.AudioReelPending=$false; $state.ReelDelayMs=0; $state.Mode='Ready'; $state.Deadline=0L; $state.NextDue=$Now
    $state.ForceNextCast=$true; $state.CheckReelGreen=$false; $state.PostReelJumpAllowed=$false
    $state.AwaitingFishingTransition=$true; $state.SawIdle=$false
    $state.Status=$Reason
    if ($Scheduler.ActiveKey -eq $Key) { $Scheduler.ActiveKey=$null }
}
function Complete-WowAutoJump($Scheduler, [string]$Key, [bool]$Sent) {
    $state=$Scheduler.Tasks[$Key]
    if ($Sent -and $null -ne $state -and $state.Running) {
        $state.CheckReelGreen=$false; $state.CycleJumpPending=$false; $state.PostReelJumpAllowed=$false
        $Scheduler.CyclesSinceJump[$Key]=0L
    }
}
function Complete-WowAutoCast($Scheduler, [string]$Key, [bool]$Sent) {
    $state=$Scheduler.Tasks[$Key]
    if ($Sent -and $null -ne $state -and $state.Running -and $state.Mode -eq 'Casting') {
        $state.ForceNextCast=$false
        $state.PostReelJumpAllowed=$false; $state.CheckReelGreen=$false
    }
}
function Complete-WowAutoReel($Scheduler, [string]$Key, [long]$Now, [bool]$Sent) {
    $state=$Scheduler.Tasks[$Key]
    if ($null -eq $state -or -not $state.Running) { return }
    if (-not $Sent) { return } # Keep the overdue event; the adapter will retry or stop this row.
    # Count only a successfully sent, registered reel action, once per fishing wait.
    $registered=@($Scheduler.Events | Where-Object {
        $_.Key -eq $Key -and $_.Kind -eq 'Reel' -and [object]::ReferenceEquals($_.State,$state)
    })
    if ($state.Mode -ne 'Wait' -or $registered.Count -eq 0) { return }
    $state.PostReelJumpAllowed=$true
    $Scheduler.CompletedCycles[$Key]=(Get-WowAutoCycleCount $Scheduler $Key)+1
    if ($Scheduler.JumpEveryCycles -gt 0) {
        $Scheduler.CyclesSinceJump[$Key]=[long]$Scheduler.CyclesSinceJump[$Key]+1
        $state.CycleJumpPending=$Scheduler.CyclesSinceJump[$Key] -ge $Scheduler.JumpEveryCycles
    }
    $state.AudioReelPending=$false; $state.ReelDelayMs=0
    $state.ForceNextCast=$true
    $state.CheckReelGreen=$true
    $state.AwaitingFishingTransition=$true
    $state.SawIdle=$false
    $holdMs=$Scheduler.ReelHoldMs
    $Scheduler.ReelHoldUntil=$Now+$holdMs
    Remove-WowAutoEvents $Scheduler $Key
    $cooldownMs=[Math]::Max(1000,$holdMs)
    $state.Mode='Cooldown'; $state.Deadline=$Now+$cooldownMs
    $state.Status="收竿键 已发送：保持窗口 $holdMs ms，$cooldownMs ms后重新入队。"
    Add-WowAutoEvent $Scheduler $Key 'Cooldown' $state.Deadline
    if ($Scheduler.ActiveKey -eq $Key) { $Scheduler.ActiveKey=$null }
}
