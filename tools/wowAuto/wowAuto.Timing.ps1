function Get-OperationTimingSpecs {
    return [ordered]@{
        OperatorIdleMs=@('操作线程空闲等待',25,1,1000,'线程与界面');CommandReceiveMs=@('检测线程命令等待',10,1,1000,'线程与界面')
        ReplyCheckMs=@('等待回执的取消检查',25,1,1000,'线程与界面');WaitCheckMs=@('操作等待的取消检查',25,1,1000,'线程与界面')
        DetectorWaitMs=@('检测等待检查间隔',20,1,1000,'线程与界面');UiRefreshMs=@('界面消息刷新',25,10,1000,'线程与界面')
        ForegroundSettleMs=@('前台稳定等待',200,0,5000,'前台与重试');ForegroundRetryMs=@('普通动作前台重试',100,1,60000,'前台与重试')
        ForegroundTimeoutMs=@('普通动作前台超时',800,1,60000,'前台与重试');RotationFocusRetryMs=@('换角前台重试',500,1,60000,'前台与重试')
        RotationFocusTimeoutMs=@('换角前台超时',5000,1,60000,'前台与重试');FocusRetryMs=@('前台失败后的操作重试',30000,1000,3600000,'前台与重试')
        KeyPressMs=@('普通按键按下时长',30,1,5000,'按键与动作等待');ChatKeyPressMs=@('聊天及方向键按下时长',50,1,5000,'按键与动作等待')
        CommandIntervalMs=@('战斗公共最小按键间隔',500,100,60000,'按键与动作等待');ReelHoldMs=@('收竿后等待',100,0,60000,'按键与动作等待')
        ItemHoldMs=@('钓鱼道具后等待',3000,0,4000,'按键与动作等待');InteractionHoldMs=@('拾取 / 剥皮交互后等待',3500,1000,60000,'按键与动作等待')
        ClickMinMs=@('三连击随机间隔下限',100,1,2000,'点击与画面重试');ClickMaxMs=@('三连击随机间隔上限',250,1,2000,'点击与画面重试')
        ClickGuardMs=@('三连击后跨进程保护',1000,0,60000,'点击与画面重试');CaptureRetryMs=@('操作线程新帧重试',100,1,60000,'点击与画面重试')
    }
}
function New-OperationTimings {
    $values=@{};$specs=Get-OperationTimingSpecs
    foreach($key in $specs.Keys){$values[$key]=[int]$specs[$key][1]}
    return $values
}
function Get-LegacyOperationTimings {
    $values=New-OperationTimings
    if($script:scheduler){$values.FocusRetryMs=[int]$script:scheduler.FocusRetryIntervalMs;$values.ReelHoldMs=[int]$script:scheduler.ReelHoldMs}
    if($script:autoFight){$values.CommandIntervalMs=[int]$script:autoFight.CommandGate.IntervalMs;$values.InteractionHoldMs=[int]$script:autoFight.Common.InteractionHoldMs}
    return $values
}
function Test-OperationTimings($Values) {
    $specs=Get-OperationTimingSpecs
    if($Values -isnot [Collections.IDictionary] -or $Values.Count -ne $specs.Count){throw '操作队列时间配置不完整。'}
    foreach($key in $specs.Keys){
        $spec=$specs[$key];$value=$Values[$key]
        if($value -isnot [int] -or $value -lt $spec[2] -or $value -gt $spec[3]){throw ($spec[0]+'须为'+$spec[2]+'–'+$spec[3]+'ms整数。')}
    }
    if($Values.ClickMinMs -gt $Values.ClickMaxMs){throw '三连击随机间隔下限不能大于上限。'}
    if($Values.ForegroundRetryMs -gt $Values.ForegroundTimeoutMs -or $Values.RotationFocusRetryMs -gt $Values.RotationFocusTimeoutMs){throw '前台重试间隔不能大于对应超时时间。'}
}
