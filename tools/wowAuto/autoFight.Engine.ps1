# autoFight configuration and state transitions. No fishing dependencies.
$script:autoFightClasses = [ordered]@{
    '1'='战士'; '2'='圣骑士'; '3'='猎人'; '4'='潜行者'; '5'='牧师'; '6'='死亡骑士';
    '7'='萨满祭司'; '8'='法师'; '9'='术士'; '10'='武僧'; '11'='德鲁伊'; '12'='恶魔猎手'; '13'='唤魔师'
}
$script:autoFightStates = [ordered]@{
    'opening'=@{Label='开怪战斗'; Key='OpeningKey'; Interval='OpeningIntervalMs'}
    'combat'=@{Label='正常战斗'; Key='CombatKey'; Interval='CombatIntervalMs'}
    'recover'=@{Label='非战斗恢复'; Key='RecoveryKey'; Interval=$null}
    'emergency'=@{Label='战斗紧急恢复'; Key='EmergencyKey'; Interval='EmergencyIntervalMs'}
    'move-forward'=@{Label='向前移动'; Key='MoveForwardKey'; Interval=$null}
    'move-backward'=@{Label='向后移动'; Key='MoveBackwardKey'; Interval=$null}
    'move-left'=@{Label='向左移动'; Key='MoveLeftKey'; Interval=$null}
    'move-right'=@{Label='向右移动'; Key='MoveRightKey'; Interval=$null}
    'loot'=@{Label='拾取'; Key='SkinKey'; Interval='InteractionHoldMs'}
    'skin'=@{Label='剥皮'; Key='SkinKey'; Interval='InteractionHoldMs'}
    'idle'=@{Label='等待目标 / 移动间歇'; Key=$null; Interval=$null}
}
$script:autoFightKeyFields=@('OpeningKey','CombatKey','RecoveryKey','EmergencyKey','MoveForwardKey',
    'MoveBackwardKey','MoveLeftKey','MoveRightKey','SkinKey')
$script:autoFightProfileFields=@('Flavor','ClassId')+$script:autoFightKeyFields+@('OpeningIntervalMs',
    'CombatIntervalMs','EmergencyIntervalMs','MovementHoldMs','InteractionHoldMs','SkinEnabled')
function New-AutoFightBinding([int]$Code,[bool]$Ctrl,[bool]$Shift,[bool]$Alt) {
    if (-not (($Code -ge 48 -and $Code -le 57) -or ($Code -ge 65 -and $Code -le 90) -or
        ($Code -ge 96 -and $Code -le 111) -or ($Code -ge 112 -and $Code -le 135) -or
        $Code -in @(8,9,13,27,32,33,34,35,36,37,38,39,40,45,46,187,189))) { return $null }
    $parts=@()
    if ($Ctrl) { $parts+='Ctrl' }; if ($Shift) { $parts+='Shift' }; if ($Alt) { $parts+='Alt' }
    $name=([System.Windows.Forms.Keys]$Code).ToString()
    if ($Code -ge 48 -and $Code -le 57) { $name=[string]($Code-48) }
    if ($Code -eq 187) { $name='=' }; if ($Code -eq 189) { $name='-' }
    $parts+=$name
    return [pscustomobject]@{Code=$Code; Ctrl=$Ctrl; Shift=$Shift; Alt=$Alt; Text=($parts -join '+')}
}
function ConvertFrom-AutoFightBinding([string]$Text) {
    $parts=$Text.Trim().Split('+'); $mods=@{Ctrl=$false; Shift=$false; Alt=$false}
    for ($i=0;$i -lt $parts.Length-1;$i++) {
        $modifier=$parts[$i].Trim()
        if (-not $mods.ContainsKey($modifier) -or $mods[$modifier]) { throw '快捷键修饰键无效或重复。' }
        $mods[$modifier]=$true
    }
    $name=$parts[-1].Trim(); $code=0
    if ($name -match '^\d$') { $code=48+[int]$name }
    elseif ($name -eq '=') { $code=187 }
    elseif ($name -eq '-') { $code=189 }
    elseif ($name -match '^[A-Za-z][A-Za-z0-9]*$') {
        try { $code=[int][Enum]::Parse([System.Windows.Forms.Keys],$name,$true) } catch { throw "无效的快捷键：$Text" }
    }
    $binding=New-AutoFightBinding $code $mods.Ctrl $mods.Shift $mods.Alt
    if ($null -eq $binding) { throw "无效的快捷键：$Text" }
    return $binding
}
function Get-AutoFightInteger($Value,[int]$Minimum,[int]$Maximum,[string]$Label) {
    if ([string]$Value -notmatch '^\d+$') { throw "$Label 必须为整数。" }
    $number=[long]::Parse([string]$Value)
    if ($number -lt $Minimum -or $number -gt $Maximum) { throw "$Label 范围：$Minimum - $Maximum。" }
    return [int]$number
}
function New-AutoFightProfile([string]$Flavor,[int]$ClassId) {
    return [pscustomobject]@{Flavor=$Flavor; ClassId=$ClassId; OpeningKey='F5'; CombatKey='F6';
        RecoveryKey='F8'; EmergencyKey='F9'; MoveForwardKey='W'; MoveBackwardKey='S'; MoveLeftKey='Q';
        MoveRightKey='E'; SkinKey='F7'; OpeningIntervalMs=2000; CombatIntervalMs=500;
        EmergencyIntervalMs=1500; MovementHoldMs=400; InteractionHoldMs=3500; SkinEnabled=$true}
}
function New-AutoFightProfiles {
    $profiles=@{}
    foreach ($flavor in @('titan','forerver')) {
        foreach ($id in $script:autoFightClasses.Keys) { $profiles["${flavor}:$id"]=New-AutoFightProfile $flavor $id }
    }
    return $profiles
}
function Copy-AutoFightProfiles($Profiles) {
    $copy=@{}
    foreach ($key in $Profiles.Keys) {
        $fields=[ordered]@{}
        foreach ($field in $script:autoFightProfileFields) { $fields[$field]=$Profiles[$key].$field }
        $copy[$key]=[pscustomobject]$fields
    }
    return $copy
}
function ConvertTo-AutoFightProfiles($Items,[int]$Version=2) {
    $result=@{}
    foreach ($item in @($Items)) {
        $expected=$script:autoFightProfileFields
        if ($Version -eq 1) { $expected=@('Flavor','ClassId','AttackKey','SkinKey','AttackIntervalMs','InteractionHoldMs','SkinEnabled') }
        $actual=@($item.PSObject.Properties.Name)
        if ($actual.Count -ne $expected.Count -or @($actual | Where-Object { $_ -notin $expected }).Count) {
            throw 'autoFight 职业配置字段不完整或包含未知字段。'
        }
        if ($item.Flavor -notin @('titan','forerver')) { throw '未知的 autoFight 服务器。' }
        $id=Get-AutoFightInteger $item.ClassId 1 13 '职业 ID'
        $p=$item
        if ($Version -eq 1) {
            $p=New-AutoFightProfile $item.Flavor $id
            $p.OpeningKey=$item.AttackKey; $p.CombatKey=$item.AttackKey
            $p.CombatIntervalMs=$item.AttackIntervalMs; $p.SkinKey=$item.SkinKey
            $p.InteractionHoldMs=$item.InteractionHoldMs; $p.SkinEnabled=$item.SkinEnabled
        }
        $fields=[ordered]@{Flavor=$p.Flavor; ClassId=$id}
        foreach ($field in $script:autoFightKeyFields) { $fields[$field]=(ConvertFrom-AutoFightBinding $p.$field).Text }
        $directions=@($fields.MoveForwardKey,$fields.MoveBackwardKey,$fields.MoveLeftKey,$fields.MoveRightKey)
        if (@($directions | Select-Object -Unique).Count -ne 4) { throw '四个移动方向必须绑定不同的按键。' }
        if ($p.SkinEnabled -isnot [bool]) { throw '剥皮开关必须为布尔值。' }
        $fields.OpeningIntervalMs=Get-AutoFightInteger $p.OpeningIntervalMs 100 60000 '开怪重试间隔 (ms)'
        $fields.CombatIntervalMs=Get-AutoFightInteger $p.CombatIntervalMs 100 10000 '正常战斗间隔 (ms)'
        $fields.EmergencyIntervalMs=Get-AutoFightInteger $p.EmergencyIntervalMs 100 60000 '紧急恢复重试间隔 (ms)'
        $fields.MovementHoldMs=Get-AutoFightInteger $p.MovementHoldMs 100 2000 '移动按住时长 (ms)'
        $fields.InteractionHoldMs=Get-AutoFightInteger $p.InteractionHoldMs 1000 60000 '拾取 / 剥皮前台保持 (ms)'
        $fields.SkinEnabled=$p.SkinEnabled
        $key="$($p.Flavor):$id"
        if ($result.ContainsKey($key)) { throw "重复的职业配置：$key" }
        $result[$key]=[pscustomobject]$fields
    }
    if ($result.Count -ne 26) { throw 'autoFight 配置必须包含两服各 13 个职业的独立配置。' }
    return $result
}
function Read-AutoFightProfiles([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { return New-AutoFightProfiles }
    $document=[IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($null -eq $document -or $document.Version -notin @(1,2) -or
        @($document.PSObject.Properties.Name).Count -ne 2 -or $null -eq $document.Profiles) {
        throw '无法读取 autoFight 配置版本或内容。'
    }
    return ConvertTo-AutoFightProfiles $document.Profiles $document.Version
}
function Save-AutoFightProfiles([string]$Path,$Profiles) {
    $valid=ConvertTo-AutoFightProfiles @($Profiles.Values)
    $items=@($valid.Keys | Sort-Object | ForEach-Object { $valid[$_] })
    $json=[pscustomobject]@{Version=2; Profiles=$items} | ConvertTo-Json -Depth 5
    $temporary=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temporary,$json,(New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary,$Path,[System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temporary,$Path) }
    }
    finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
    return $valid
}
function New-AutoFightSession([long]$Now,[int]$ClassId) {
    return [pscustomobject]@{Id=[Guid]::NewGuid().ToString('N'); ClassId=$ClassId; Due=$Now;
        State=''; EnteredAt=$Now; EntryPending=$true; NextActionAt=$Now; NextInteractionAt=0L}
}
function Update-AutoFightState($Session,$Packet,[long]$Now) {
    $state=if ($Packet.Recovery -ne 'none') { $Packet.Recovery } else { $Packet.Action }
    if ($Session.State -eq $state) { return $false }
    $Session.State=$state; $Session.EnteredAt=$Now; $Session.EntryPending=$true
    $Session.NextActionAt=$Now
    return $true
}
function Get-AutoFightAction($Session,$Packet,$Profile,[long]$Now) {
    if ($Packet.ClassId -ne $Session.ClassId -or $Packet.Flavor -ne $Profile.Flavor) { return 'identity-changed' }
    if (-not $script:autoFightStates.Contains($Session.State)) { return 'identity-changed' }
    # Emergency macros may stop a current cast; all other handlers wait for busy to clear.
    if ($Packet.Busy -and $Session.State -ne 'emergency') { return 'wait' }
    $handler=$script:autoFightStates[$Session.State]
    if (-not $handler.Key -or $Now -lt $Session.NextActionAt) { return 'wait' }
    if ($Session.State -in @('skin','loot')) {
        if (-not $Profile.SkinEnabled -or $Packet.Combat -or $Now -lt $Session.NextInteractionAt) { return 'wait' }
    }
    if ($Session.EntryPending -or $handler.Interval) { return $Session.State }
    return 'wait'
}
function Complete-AutoFightAction($Session,$Profile,[string]$Action,[long]$Now) {
    $Session.EntryPending=$false
    $interval=$script:autoFightStates[$Action].Interval
    $Session.NextActionAt=if ($interval) { $Now+$Profile.$interval } else { [long]::MaxValue }
    if ($Action -in @('skin','loot')) { $Session.NextInteractionAt=$Session.NextActionAt }
    # Poll states independently from action cooldowns, so recovery is not delayed by combat retries.
    $Session.Due=$Now+100
}
