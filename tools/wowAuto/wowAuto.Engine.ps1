# State transitions only. No screen capture, keyboard input, or process termination.
function New-WowAutoState {
    param([int]$MinimumMs, [int]$MaximumMs)
    if ($MinimumMs -lt 1 -or $MaximumMs -gt 3600000 -or $MinimumMs -gt $MaximumMs) {
        throw '等待范围需满足：1 ≤ 最小值 ≤ 最大值 ≤ 3600000 ms。'
    }
    [pscustomobject]@{
        Running = $true; Mode = 'Detect'; NextDue = 0L; Deadline = 0L
        MinimumMs = $MinimumMs; MaximumMs = $MaximumMs; LastInterval = -1
        Status = '已开始，等待游戏进入前台。'
    }
}

function Stop-WowAutoState {
    param($State, [string]$Reason = '已停止。')
    $State.Running = $false
    $State.Mode = 'Stopped'
    $State.Deadline = 0L
    $State.Status = $Reason
}

function Get-WowAutoInterval {
    param([int]$Previous)
    if ($Previous -lt 300) { return (Get-Random -Minimum 300 -Maximum 601) }
    $value = Get-Random -Minimum 300 -Maximum 600
    if ($value -ge $Previous) { $value++ }
    return $value
}

function Invoke-WowAutoState {
    param($State, [long]$Now, [bool]$Foreground, [string]$Color)
    if (-not $State.Running -or $Now -lt $State.NextDue) { return 'None' }
    if (-not $Foreground) {
        $State.Mode = 'Detect'
        $State.Deadline = 0L
        $State.NextDue = $Now + 500
        $State.Status = '已暂停：游戏不在前台；切回后重新检测。'
        return 'None'
    }
    if ($State.Mode -eq 'Cooldown') {
        if ($Now -lt $State.Deadline) {
            $State.NextDue = [Math]::Min($Now + 500, $State.Deadline)
            return 'None'
        }
        $State.Mode = 'Detect'
        $State.NextDue = $Now
        $State.Status = '收竿后等待结束，恢复颜色检测。'
        return 'None'
    }
    if ($Color -eq 'yellow') {
        Stop-WowAutoState $State '背包已满，正在结束选中的游戏进程。'
        return 'ExitGame'
    }
    if ($State.Mode -eq 'Wait') {
        if ($Now -ge $State.Deadline) {
            # Complete-WowAutoInteraction starts the cooldown after key release.
            return 'Ctrl2'
        }
        $State.NextDue = [Math]::Min($Now + 500, $State.Deadline)
        return 'None'
    }
    if ($Color -eq 'green') {
        $delay = Get-Random -Minimum $State.MinimumMs -Maximum ($State.MaximumMs + 1)
        $State.Mode = 'Wait'
        $State.Deadline = $Now + $delay
        $State.NextDue = [Math]::Min($Now + 500, $State.Deadline)
        $State.Status = "绿色：等待 $delay ms 后发送 Ctrl+2。"
        return 'None'
    }
    $State.LastInterval = Get-WowAutoInterval $State.LastInterval
    $State.NextDue = $Now + $State.LastInterval
    if ($Color -eq 'red') {
        $State.Status = "红色：发送 Ctrl+1；下次检测间隔 $($State.LastInterval) ms。"
        return 'Ctrl1'
    }
    $State.Status = '灰色或未知颜色：等待插件启动并显示色块。'
    return 'None'
}

function Complete-WowAutoInteraction {
    param($State, [long]$Now, [bool]$Sent)
    if (-not $State.Running) { return }
    if ($Sent) {
        $State.Mode = 'Cooldown'
        $State.Deadline = $Now + 1000
        $State.NextDue = $Now + 500
        $State.Status = 'Ctrl+2 已发送，等待 1000 ms 后恢复检测。'
    }
    else {
        $State.Mode = 'Detect'
        $State.Deadline = 0L
        $State.NextDue = $Now + 500
        $State.Status = '焦点已变化，未发送 Ctrl+2；等待重新检测。'
    }
}
