# Pure shared scheduler. Native window/input operations are performed by the GUI adapter.
function New-WowAutoState {
    param([int]$MinimumMs, [int]$MaximumMs)
    if ($MinimumMs -lt 1 -or $MaximumMs -gt 3600000 -or $MinimumMs -gt $MaximumMs) {
        throw '等待范围需满足：1 ≤ 最小值 ≤ 最大值 ≤ 3600000 ms。'
    }
    [pscustomobject]@{
        Running=$true; Mode='Ready'; NextDue=0L; Deadline=0L
        MinimumMs=$MinimumMs; MaximumMs=$MaximumMs; LastInterval=-1; ForceNextCast=$false
        AwaitingFishingTransition=$false; SawIdle=$false
        ItemDue=0L; ItemRetryAt=0L
        Status='已加入统一调度队列。'
    }
}
function Stop-WowAutoState {
    param($State, [string]$Reason='已停止。')
    $State.Running=$false; $State.Mode='Stopped'; $State.Deadline=0L; $State.Status=$Reason
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
        Tasks=@{}; CompletedCycles=@{}; Order=(New-Object 'System.Collections.Generic.List[string]')
        Events=(New-Object System.Collections.ArrayList)
        Cursor=0; ActiveKey=$null; Sequence=0L; ReelHoldUntil=0L; ReelHoldMs=100; UseItem=$false
    }
}
function Set-WowAutoHoldDuration($Scheduler, [ValidateRange(0,60000)][int]$Milliseconds) {
    $Scheduler.ReelHoldMs=$Milliseconds
}
function Set-WowAutoItemEnabled($Scheduler, [bool]$Enabled, [long]$Now) {
    if ($Scheduler.UseItem -eq $Enabled) { return }
    $Scheduler.UseItem=$Enabled
    foreach ($state in $Scheduler.Tasks.Values) {
        $state.ItemDue=if ($Enabled) { $Now+600000 } else { 0L }
        $state.ItemRetryAt=0L
    }
}
function Complete-WowAutoItem($Scheduler, [string]$Key, [long]$Now, [bool]$Sent) {
    $state=$Scheduler.Tasks[$Key]
    if ($null -eq $state -or -not $state.Running -or -not $Scheduler.UseItem) { return }
    if ($Sent) {
        $state.ItemDue=$Now+600000
        $state.ItemRetryAt=0L
    } else { $state.ItemRetryAt=$Now+500 }
}
function Get-WowAutoCycleCount($Scheduler, [string]$Key) {
    if ($Scheduler.CompletedCycles.ContainsKey($Key)) { return [long]$Scheduler.CompletedCycles[$Key] }
    return 0L
}
function Test-WowAutoExitAllowed($Scheduler, [string]$Key) {
    return (Get-WowAutoCycleCount $Scheduler $Key) -gt 500
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
function Add-WowAutoTask($Scheduler, [string]$Key, [int]$MinimumMs, [int]$MaximumMs, [long]$Now) {
    $state=New-WowAutoState $MinimumMs $MaximumMs
    Stop-WowAutoTask $Scheduler $Key
    $state.NextDue=$Now
    if ($Scheduler.UseItem) { $state.ItemDue=$Now+600000 }
    $Scheduler.Tasks[$Key]=$state
    $Scheduler.Order.Add($Key)
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
    if ($Now -lt $Scheduler.ReelHoldUntil) { return $null }
    # Remove obsolete events before selecting an action. An event retains its session identity.
    for ($i=$Scheduler.Events.Count-1; $i -ge 0; $i--) {
        $event=$Scheduler.Events[$i]
        $state=$Scheduler.Tasks[$event.Key]
        if ($null -eq $state -or -not $state.Running -or -not [object]::ReferenceEquals($event.State,$state)) {
            $Scheduler.Events.RemoveAt($i)
        }
        elseif ($event.Kind -eq 'Cooldown' -and $event.Due -le $Now) {
            $state.Mode='Ready'; $state.Deadline=0L; $state.NextDue=$Now
            $state.Status='收竿后等待结束，重新排队下竿。'
            $Scheduler.Events.RemoveAt($i)
        }
    }
    $due=@($Scheduler.Events | Where-Object { $_.Kind -eq 'Reel' -and $_.Due -le $Now } | Sort-Object Due,Sequence)
    if ($due.Count -gt 0) {
        return [pscustomobject]@{ Key=$due[0].Key; Kind='Reel'; Due=$due[0].Due }
    }
    if ($Scheduler.UseItem) {
        $item=@($Scheduler.Order | Where-Object {
            $s=$Scheduler.Tasks[$_]
            $s.Running -and $s.ItemDue -le $Now -and $s.ItemRetryAt -le $Now
        } | Sort-Object { $Scheduler.Tasks[$_].ItemDue })
        if ($item.Count -gt 0) {
            return [pscustomobject]@{ Key=$item[0]; Kind='Item'; Due=$Scheduler.Tasks[$item[0]].ItemDue }
        }
    }
    if ($null -ne $Scheduler.ActiveKey) {
        $active=$Scheduler.Tasks[$Scheduler.ActiveKey]
        if ($null -ne $active -and $active.Running -and $active.Mode -in @('Ready','Casting')) {
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
        if ($state.Running -and $state.Mode -in @('Ready','Casting') -and $state.NextDue -le $Now) {
            $Scheduler.Cursor=($index+1)%$count
            $Scheduler.ActiveKey=$key
            return [pscustomobject]@{ Key=$key; Kind='Poll'; Due=$state.NextDue }
        }
    }
    return $null
}
function Complete-WowAutoPoll($Scheduler, [string]$Key, [long]$Now, [string]$Color) {
    $state=$Scheduler.Tasks[$Key]
    if ($null -eq $state -or -not $state.Running) { return 'None' }
    if ($Color -eq 'yellow') {
        $canExit=Test-WowAutoExitAllowed $Scheduler $Key
        $reason=if ($canExit) { '背包已满且有效循环超过500次，正在结束此进程。' } else { '背包已满，有效循环未超过500次；保留进程并停止本行。' }
        Stop-WowAutoTask $Scheduler $Key $reason
        if ($canExit) { return 'ExitGame' }
        return 'Stop'
    }
    if ($Color -eq 'red') { $state.SawIdle=$true }
    if ($Color -eq 'green' -and -not $state.ForceNextCast) {
        if ($state.AwaitingFishingTransition -and -not $state.SawIdle) {
            $state.Mode='Casting'
            $state.LastInterval=Get-WowAutoInterval $state.LastInterval
            $state.NextDue=$Now+$state.LastInterval
            $state.Status='等待本轮红色→绿色确认：当前仍为绿色，尚未检测到红色，不开始倒计时。'
            return 'None'
        }
        $state.AwaitingFishingTransition=$false
        $delay=Get-Random -Minimum $state.MinimumMs -Maximum ($state.MaximumMs+1)
        Remove-WowAutoEvents $Scheduler $Key
        $state.Mode='Wait'; $state.Deadline=$Now+$delay
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
function Complete-WowAutoCast($Scheduler, [string]$Key, [bool]$Sent) {
    $state=$Scheduler.Tasks[$Key]
    if ($Sent -and $null -ne $state -and $state.Running -and $state.Mode -eq 'Casting') {
        $state.ForceNextCast=$false
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
    $Scheduler.CompletedCycles[$Key]=(Get-WowAutoCycleCount $Scheduler $Key)+1
    $state.ForceNextCast=$true
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
