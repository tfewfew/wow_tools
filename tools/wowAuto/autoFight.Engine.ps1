# autoFight configuration and state transitions. No fishing dependencies.
$script:autoFightClasses = [ordered]@{
    '1'='战士'; '2'='圣骑士'; '3'='猎人'; '4'='潜行者'; '5'='牧师'; '6'='死亡骑士';
    '7'='萨满祭司'; '8'='法师'; '9'='术士'; '10'='武僧'; '11'='德鲁伊'; '12'='恶魔猎手'; '13'='唤魔师'
}
$script:autoFightStates = [ordered]@{
    'opening'=@{Label='发现怪物，开怪'; Key='OpeningKey'; Interval=$null}
    'waiting'=@{Label='等待怪物接近'; Key=$null; Interval=$null}
    'combat'=@{Label='正常战斗'; Key='CombatKey'; Interval='CombatIntervalMs'}
    'recover'=@{Label='非战斗恢复'; Key='RecoveryKey'; Interval=$null}
    'emergency'=@{Label='战斗紧急恢复'; Key='EmergencyKey'; Interval=$null}
    'move-forward'=@{Label='向前移动'; Key='MoveForwardKey'; Interval=$null}
    'move-backward'=@{Label='向后移动'; Key='MoveBackwardKey'; Interval=$null}
    'move-left'=@{Label='向左移动'; Key='MoveLeftKey'; Interval=$null}
    'move-right'=@{Label='向右移动'; Key='MoveRightKey'; Interval=$null}
    'loot'=@{Label='拾取'; Key='SkinKey'; Interval='InteractionHoldMs'}
    'skin'=@{Label='剥皮'; Key='SkinKey'; Interval='InteractionHoldMs'}
    'idle'=@{Label='等待目标'; Key=$null; Interval=$null}
}
$script:autoFightKeyFields=@('OpeningKey','CombatKey','RecoveryKey','EmergencyKey')
$script:autoFightCommonKeyFields=@('MoveForwardKey','MoveBackwardKey','MoveLeftKey','MoveRightKey','SkinKey')
$script:autoFightCommonFields=$script:autoFightCommonKeyFields+@('MovementHoldMs','InteractionHoldMs','SkinEnabled')
$script:autoFightProfileFields=@('Flavor','ClassId')+$script:autoFightKeyFields+@('CombatIntervalMs')
$script:autoFightLegacyFields=@('Flavor','ClassId')+$script:autoFightKeyFields+$script:autoFightCommonKeyFields+
    @('OpeningIntervalMs','CombatIntervalMs','EmergencyIntervalMs','MovementHoldMs','InteractionHoldMs','SkinEnabled')
function New-AutoFightCommon {
    return [pscustomobject]@{MoveForwardKey='W';MoveBackwardKey='S';MoveLeftKey='Q';MoveRightKey='E';
        SkinKey='F7';MovementHoldMs=400;InteractionHoldMs=3500;SkinEnabled=$true}
}
function Copy-AutoFightCommon($Common) {
    $fields=[ordered]@{}
    foreach ($field in $script:autoFightCommonFields) {$fields[$field]=$Common.$field}
    return [pscustomobject]$fields
}
function ConvertTo-AutoFightCommon($Common) {
    $actual=@($Common.PSObject.Properties.Name)
    if ($actual.Count -ne $script:autoFightCommonFields.Count -or @($actual | Where-Object {$_ -notin $script:autoFightCommonFields}).Count) {
        throw 'autoFight 通用配置字段不完整或包含未知字段。'
    }
    $fields=[ordered]@{}
    foreach ($field in $script:autoFightCommonKeyFields) {$fields[$field]=(ConvertFrom-AutoFightBinding $Common.$field).Text}
    if (@($script:autoFightCommonKeyFields[0..3] | ForEach-Object {$fields[$_]} | Select-Object -Unique).Count -ne 4) {
        throw '四个移动方向必须绑定不同的按键。'
    }
    $fields.MovementHoldMs=Get-AutoFightInteger $Common.MovementHoldMs 100 2000 '移动按住时长 (ms)'
    $fields.InteractionHoldMs=Get-AutoFightInteger $Common.InteractionHoldMs 1000 60000 '交互前台保持 (ms)'
    if ($Common.SkinEnabled -isnot [bool]) {throw '拾取 / 剥皮交互开关必须为布尔值。'}
    $fields.SkinEnabled=$Common.SkinEnabled
    return [pscustomobject]$fields
}
function Get-AutoFightEffectiveProfile($Profile,$Common) {
    $fields=[ordered]@{}
    foreach ($field in $script:autoFightProfileFields) {$fields[$field]=$Profile.$field}
    foreach ($field in $script:autoFightCommonFields) {$fields[$field]=$Common.$field}
    return [pscustomobject]$fields
}
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
    return [pscustomobject]@{Flavor=$Flavor;ClassId=$ClassId;OpeningKey='F5';CombatKey='F6';
        RecoveryKey='F8';EmergencyKey='F9';CombatIntervalMs=500}
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
function ConvertTo-AutoFightProfiles($Items,[int]$Version=4) {
    $result=@{}
    foreach ($item in @($Items)) {
        $expected=if ($Version -eq 4) {$script:autoFightProfileFields} else {$script:autoFightLegacyFields}
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
            $p.CombatIntervalMs=$item.AttackIntervalMs
        }
        $fields=[ordered]@{Flavor=$p.Flavor; ClassId=$id}
        foreach ($field in $script:autoFightKeyFields) { $fields[$field]=(ConvertFrom-AutoFightBinding $p.$field).Text }
        $fields.CombatIntervalMs=Get-AutoFightInteger $p.CombatIntervalMs 100 10000 '正常战斗间隔 (ms)'
        if ($Version -lt 4) {
            $legacy=New-AutoFightCommon
            foreach ($field in $script:autoFightCommonFields) {
                if ($Version -gt 1 -or $field -in @('SkinKey','InteractionHoldMs','SkinEnabled')) {$legacy.$field=$item.$field}
            }
            $null=ConvertTo-AutoFightCommon $legacy
            if ($Version -gt 1) {
                $null=Get-AutoFightInteger $item.OpeningIntervalMs 100 60000 '旧开怪间隔'
                $null=Get-AutoFightInteger $item.EmergencyIntervalMs 100 60000 '旧紧急恢复间隔'
            }
        }
        $key="$($p.Flavor):$id"
        if ($result.ContainsKey($key)) { throw "重复的职业配置：$key" }
        $result[$key]=[pscustomobject]$fields
    }
    if ($result.Count -ne 26) { throw 'autoFight 配置必须包含两服各 13 个职业的独立配置。' }
    return $result
}
function New-AutoFightCommandGate([int]$IntervalMs=500) {
    $interval=Get-AutoFightInteger $IntervalMs 100 60000 '公共最小按键间隔 (ms)'
    return [pscustomobject]@{IntervalMs=$interval; LastSentAt=-1L}
}
function Test-AutoFightCommandReady($Gate,[long]$Now) {
    return $Gate.LastSentAt -lt 0 -or $Now-$Gate.LastSentAt -ge $Gate.IntervalMs
}
function Complete-AutoFightCommand($Gate,[long]$Now,[bool]$Sent) {
    if ($Sent) { $Gate.LastSentAt=$Now }
}
function Read-AutoFightConfiguration([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { return [pscustomobject]@{Profiles=(New-AutoFightProfiles);Common=(New-AutoFightCommon);CommandIntervalMs=500} }
    $document=[IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($null -eq $document -or $document.Version -notin @(1,2,3,4)) {throw '无法读取 autoFight 配置版本或内容。'}
    $expected=@('Version','Profiles')
    if ($document.Version -ge 3) {$expected+='CommandIntervalMs'}
    if ($document.Version -eq 4) {$expected+='Common'}
    $actual=@($document.PSObject.Properties.Name)
    if ($actual.Count -ne $expected.Count -or @($actual | Where-Object {$_ -notin $expected}).Count -or $null -eq $document.Profiles) {
        throw 'autoFight 配置字段不完整或包含未知字段。'
    }
    $interval=500
    if ($document.Version -ge 3) {$interval=Get-AutoFightInteger $document.CommandIntervalMs 100 60000 '公共最小按键间隔 (ms)'}
    $profiles=ConvertTo-AutoFightProfiles $document.Profiles $document.Version
    $common=New-AutoFightCommon
    if ($document.Version -eq 4) {$common=ConvertTo-AutoFightCommon $document.Common}
    else {
        # Prefer a unique user customization over untouched defaults. Ambiguous old values need correction.
        foreach ($field in $script:autoFightCommonFields) {
            $values=@($document.Profiles | Where-Object {$null -ne $_.$field -and $_.$field -ne $common.$field} |
                ForEach-Object {$_.$field} | Select-Object -Unique)
            if ($values.Count -gt 1) {throw "旧配置的 $field 有多个不同设置，请在通用设置中统一后保存。"}
            if ($values.Count -eq 1) {$common.$field=$values[0]}
        }
        $common=ConvertTo-AutoFightCommon $common
    }
    return [pscustomobject]@{Profiles=$profiles;Common=$common;CommandIntervalMs=$interval}
}
function Read-AutoFightProfiles([string]$Path) {return (Read-AutoFightConfiguration $Path).Profiles}
function Save-AutoFightProfiles([string]$Path,$Profiles,$CommandIntervalMs=500,$Common=(New-AutoFightCommon)) {
    $valid=ConvertTo-AutoFightProfiles @($Profiles.Values)
    $general=ConvertTo-AutoFightCommon $Common
    $interval=Get-AutoFightInteger $CommandIntervalMs 100 60000 '公共最小按键间隔 (ms)'
    $items=@($valid.Keys | Sort-Object | ForEach-Object {$valid[$_]})
    $json=[pscustomobject]@{Version=4;CommandIntervalMs=$interval;Common=$general;Profiles=$items} | ConvertTo-Json -Depth 5
    $temporary=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temporary,$json,(New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($Path)) {[IO.File]::Replace($temporary,$Path,[System.Management.Automation.Language.NullString]::Value)}
        else {[IO.File]::Move($temporary,$Path)}
    } finally {if ([IO.File]::Exists($temporary)) {[IO.File]::Delete($temporary)}}
    return $valid
}
function New-AutoFightSession([long]$Now,[int]$ClassId) {
    return [pscustomobject]@{Id=[Guid]::NewGuid().ToString('N'); ClassId=$ClassId; Due=$Now;
        State=''; EnteredAt=$Now; EntryPending=$true; NextActionAt=$Now; NextInteractionAt=0L; LastInteractionState='';
        EncounterId=-1; OpeningSent=$false;RecoveryState='none';RecoverySent=$false;MovementRequest=''}
}
function Update-AutoFightState($Session,$Packet,[long]$Now) {
    if ($Session.RecoveryState -ne $Packet.Recovery) {
        $Session.RecoveryState=$Packet.Recovery; $Session.RecoverySent=$false
    }
    $changed=$Session.EncounterId -ne $Packet.EncounterId
    if ($changed) { $Session.EncounterId=$Packet.EncounterId; $Session.OpeningSent=$false }
    $state=if ($Packet.Action -eq 'waiting' -or ($Packet.Action -eq 'opening' -and $Session.OpeningSent)) { 'waiting' }
        elseif ($Packet.Recovery -ne 'none') { $Packet.Recovery }
        elseif ($Packet.Action -eq 'idle' -and -not $Packet.Busy -and $Session.MovementRequest) {'move-'+$Session.MovementRequest}
        else { $Packet.Action }
    if ($Packet.Action -ne 'idle' -or $Packet.Recovery -ne 'none' -or $Packet.Busy) {$Session.MovementRequest=''}
    if ($Session.State -eq $state -and -not $changed) { return $false }
    $Session.State=$state; $Session.EnteredAt=$Now; $Session.EntryPending=$true
    $Session.NextActionAt=$Now
    return $true
}
function Get-AutoFightAction($Session,$Packet,$Profile,[long]$Now) {
    if ($Packet.ClassId -ne $Session.ClassId -or $Packet.Flavor -ne $Profile.Flavor) { return 'identity-changed' }
    if (-not $script:autoFightStates.Contains($Session.State)) { return 'identity-changed' }
    # Waiting is deliberately quiet, including recovery keys. Key releases remain immediate.
    if ($Packet.Action -eq 'waiting' -or ($Packet.Action -eq 'opening' -and $Session.OpeningSent)) { return 'wait' }
    if ($Session.State -in @('recover','emergency') -and $Session.RecoverySent) {return 'wait'}
    # Emergency macros may stop a current cast; all other handlers wait for busy to clear.
    if ($Packet.Busy -and $Session.State -ne 'emergency') { return 'wait' }
    $handler=$script:autoFightStates[$Session.State]
    if (-not $handler.Key -or $Now -lt $Session.NextActionAt) { return 'wait' }
    if ($Session.State -in @('skin','loot')) {
        if (-not $Profile.SkinEnabled -or $Packet.Combat) { return 'wait' }
        # A confirmed loot -> skin (or skin -> loot) transition starts a fresh interaction phase.
        # Re-entering the same phase after idle or recovery still respects its retry deadline.
        if ($Session.LastInteractionState -eq $Session.State -and $Now -lt $Session.NextInteractionAt) { return 'wait' }
    }
    if ($Session.EntryPending -or $handler.Interval) { return $Session.State }
    return 'wait'
}
function Complete-AutoFightAction($Session,$Profile,[string]$Action,[long]$Now) {
    $Session.EntryPending=$false
    if ($Action -in @('recover','emergency')) {$Session.RecoverySent=$true}
    if ($Action.StartsWith('move-')) {$Session.MovementRequest=''}
    if ($Action -eq 'opening') { $Session.OpeningSent=$true }
    $interval=$script:autoFightStates[$Action].Interval
    $Session.NextActionAt=if ($interval) { $Now+$Profile.$interval } else { [long]::MaxValue }
    if ($Action -in @('skin','loot')) {
        $Session.LastInteractionState=$Action
        $Session.NextInteractionAt=$Session.NextActionAt
    }
    # Poll states independently from action cooldowns, so recovery is not delayed by combat retries.
    $Session.Due=$Now+100
}
