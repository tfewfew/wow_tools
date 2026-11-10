# Pet taming configuration and transitions. All times use the host's monotonic clock.
function New-AutoTameConfig {
    return [pscustomobject]@{
        Version=1
        TrapKey=''
        OpeningKey=''
        BackwardKey=''
        TameKey=''
        TrapWaitMs=1000
        OpeningWaitMs=1000
        BackwardWaitMs=1000
        BackwardHoldMs=0
        TameWaitMs=10000
        JumpKey='Space'
        JumpIntervalSeconds=0
    }
}
function ConvertTo-AutoTameConfig($Value,[switch]$RequireKey) {
    if($Value.Version -ne 1){
        throw '抓宠配置版本无效。'
    }
    $result=New-AutoTameConfig
    foreach($field in @('TrapKey','OpeningKey','BackwardKey','TameKey')) {
        $text=([string]$Value.$field).Trim()
        $result.$field=if($text){(ConvertFrom-AutoFightBinding $text).Text}else{''}
    }
    if($RequireKey -and -not $result.TameKey){
        throw '请配置必选的捕捉按键。'
    }
    foreach($field in @('TrapWaitMs','OpeningWaitMs','BackwardWaitMs','TameWaitMs')) {
        $minimum=if($field -eq 'TameWaitMs'){100}else{0}
        $result.$field=Get-AutoFightInteger $Value.$field $minimum 600000 '抓宠等待时间（ms）'
    }
    if($null -ne $Value.BackwardHoldMs){
        $result.BackwardHoldMs=Get-AutoFightInteger $Value.BackwardHoldMs 0 60000 '后退按住时长（ms）'
    }
    if($null -ne $Value.JumpIntervalSeconds){
        $result.JumpIntervalSeconds=Get-AutoFightInteger $Value.JumpIntervalSeconds 0 3600 '自动跳跃间隔（秒）'
    }
    if($null -ne $Value.JumpKey){
        $text=([string]$Value.JumpKey).Trim()
        $result.JumpKey=if($text){(ConvertFrom-AutoFightBinding $text).Text}else{''}
    }
    if($result.JumpIntervalSeconds -gt 0 -and -not $result.JumpKey){
        throw '启用自动跳跃时，请配置跳跃按键。'
    }
    return $result
}
function Read-AutoTameConfig([string]$Path) {
    if(-not [IO.File]::Exists($Path)){
        return New-AutoTameConfig
    }
    return ConvertTo-AutoTameConfig ([IO.File]::ReadAllText($Path) | ConvertFrom-Json)
}
function Save-AutoTameConfig([string]$Path,$Value) {
    $valid=ConvertTo-AutoTameConfig $Value -RequireKey
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temporary,($valid | ConvertTo-Json),(New-Object Text.UTF8Encoding($true)))
        if([IO.File]::Exists($Path)){
            [IO.File]::Replace($temporary,$Path,[Management.Automation.Language.NullString]::Value)
        }else{
            [IO.File]::Move($temporary,$Path)
        }
    } finally {
        if([IO.File]::Exists($temporary)){
            [IO.File]::Delete($temporary)
        }
    }
    return $valid
}
function New-AutoTameSession([long]$Now=0,$Config=$null) {
    return [pscustomobject]@{
        TargetId=-1
        FinishedTarget=-1
        Active=$false
        Stage=0
        Due=0L
        SeenCombat=$false
        TameSent=$false
        NextJumpAt=$(if($Config -and $Config.JumpIntervalSeconds -gt 0){$Now+[long]$Config.JumpIntervalSeconds*1000}else{0L})
        ActionReadyAt=0L
        AdvanceAfterJump=$false
        Status='等待名单中的当前目标。'
    }
}
function Get-AutoTameJumpAction($Session,$Packet,$Config,[long]$Now) {
    if($Config.JumpIntervalSeconds -le 0 -or -not $Session.NextJumpAt -or
        $Now -lt $Session.NextJumpAt -or $Now -lt $Session.ActionReadyAt){return $null}
    if(-not $Packet -or $Packet.State -notin @('idle','matched')){return $null}
    if($Session.TameSent -and $Now -lt $Session.Due){return $null}
    if(-not $Session.Active -and $Packet.Combat){return $null}
    return [pscustomobject]@{
        Stage='Jump'
        Key=$Config.JumpKey
        TargetId=$Packet.TargetId
        ExpectedState=$Packet.State
        ExpectedCombat=[bool]$Packet.Combat
        KeyHoldMs=0
    }
}
function Get-AutoTameAction($Session,$Packet,$Config,[long]$Now) {
    if(-not $Packet -or $Packet.State -eq 'unknown'){
        $Session.Status='抓宠色块暂不可读，暂停操作。'
        return $null
    }
    if($Packet.State -ne 'matched') {
        $Session.Active=$false
        $Session.Status='等待名单中的当前目标。'
        return Get-AutoTameJumpAction $Session $Packet $Config $Now
    }
    if($Session.FinishedTarget -eq $Packet.TargetId){
        $Session.Status='本目标抓宠已结束，等待更换目标。'
        return Get-AutoTameJumpAction $Session $Packet $Config $Now
    }
    if(-not $Session.Active -or $Session.TargetId -ne $Packet.TargetId) {
        $Session.TargetId=$Packet.TargetId
        $Session.Active=$true
        $Session.Stage=0
        $Session.Due=$Now
        $Session.SeenCombat=$false
        $Session.TameSent=$false
    }
    if($Packet.Combat){
        $Session.SeenCombat=$true
    }
    # Allow the initial capture to establish combat before enforcing combat on repeats.
    if(-not $Packet.Combat -and ($Session.SeenCombat -or ($Session.TameSent -and $Now -ge $Session.Due))) {
        $Session.FinishedTarget=$Session.TargetId
        $Session.Active=$false
        $Session.Status='已脱离战斗，本目标抓宠结束。'
        return Get-AutoTameJumpAction $Session $Packet $Config $Now
    }
    $stages=@('Trap','Opening','Backward','Tame')
    while($Session.Stage -lt 3 -and -not $Config.($stages[$Session.Stage]+'Key')){
        $Session.Stage++
    }
    $stage=$stages[$Session.Stage]
    if($Now -lt $Session.Due){
        $Session.Status='等待上一阶段结束。'
        return $null
    }
    if($Now -lt $Session.ActionReadyAt){
        $Session.Status='等待跳跃结束后继续抓宠。'
        return $null
    }
    if(-not $Session.AdvanceAfterJump){
        $jump=Get-AutoTameJumpAction $Session $Packet $Config $Now
        if($jump){return $jump}
    }
    return [pscustomobject]@{
        Stage=$stage
        Key=$Config.($stage+'Key')
        TargetId=$Session.TargetId
        RequireCombat=($Session.SeenCombat -or $Session.TameSent)
        KeyHoldMs=$(if($stage -eq 'Backward'){$Config.BackwardHoldMs}else{0})
    }
}
function Complete-AutoTameAction($Session,$Action,$Config,[long]$SentAt) {
    if($Action.Stage -eq 'Jump'){
        $Session.NextJumpAt=$SentAt+[long]$Config.JumpIntervalSeconds*1000
        $Session.ActionReadyAt=$SentAt+1000
        $Session.AdvanceAfterJump=$true
        $Session.Status='已自动跳跃，等待落地后继续抓宠。'
        return
    }
    if(-not $Session.Active -or $Session.TargetId -ne $Action.TargetId){
        return
    }
    $Session.Due=$SentAt+$Config.($Action.Stage+'WaitMs')
    $Session.AdvanceAfterJump=$false
    if($Action.Stage -eq 'Tame'){
        $Session.TameSent=$true
        $Session.Status='已发送捕捉，等待执行时长后重试。'
    }else{
        $Session.Stage++
        $Session.Status='已发送'+@{Trap='陷阱';Opening='开怪';Backward='后退'}[$Action.Stage]+'，等待下一阶段。'
    }
}
