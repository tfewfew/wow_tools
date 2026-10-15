# autoFight configuration and state transitions. No fishing dependencies.
$script:autoFightClasses = [ordered]@{
    '1'='战士'; '2'='圣骑士'; '3'='猎人'; '4'='潜行者'; '5'='牧师'; '6'='死亡骑士';
    '7'='萨满祭司'; '8'='法师'; '9'='术士'; '11'='德鲁伊'
}
function Get-AutoFightClassIds([string]$Flavor) {
    return @($script:autoFightClasses.Keys | Where-Object {$Flavor -eq 'titan' -or $_ -ne '6'} | ForEach-Object {[int]$_})
}
$script:autoFightStates = [ordered]@{
    'opening'=@{Label='选中怪物并开怪'; Key='OpeningKey'; Interval=$null}
    'combat'=@{Label='正常战斗'; Key='CombatKey'; Interval=$null}
    'move-forward'=@{Label='向前移动'; Key='MoveForwardKey'; Interval=$null}
    'move-backward'=@{Label='向后移动'; Key='MoveBackwardKey'; Interval=$null}
    'move-left'=@{Label='向左移动'; Key='MoveLeftKey'; Interval=$null}
    'move-right'=@{Label='向右移动'; Key='MoveRightKey'; Interval=$null}
    'interact'=@{Label='尸体交互'; Key='SkinKey'; Interval=$null}
    'idle'=@{Label='等待目标'; Key=$null; Interval=$null}
    'jump'=@{Label='定时跳跃'; Key='JumpKey'; Interval=$null}
    'buff'=@{Label='补 Buff'; Key='BuffKey'; Interval=$null}
    'recover'=@{Label='恢复'; Key='RecoveryKey'; Interval=$null}
}
$script:autoFightLegacyKeyFields=@('OpeningKey','CombatKey','RecoveryKey','EmergencyKey')
$script:autoFightKeyFields=@('OpeningKey','CombatKey','RecoveryKey','BuffKey')
$script:autoFightCommonKeyFields=@('MoveForwardKey','MoveBackwardKey','MoveLeftKey','MoveRightKey','SkinKey','TargetKey')
$script:autoFightCommonFields=$script:autoFightCommonKeyFields+@('MovementHoldMs','InteractionHoldMs','SkinEnabled','JumpIntervalSeconds')
$script:autoFightV6ProfileFields=@('Flavor','ClassId')+$script:autoFightLegacyKeyFields+@('CombatIntervalMs')
$script:autoFightV7ProfileFields=$script:autoFightV6ProfileFields+@('BuffKey','BuffIntervalSeconds','BuffCount')
$script:autoFightV8ProfileFields=@('Flavor','ClassId')+$script:autoFightKeyFields+@('CombatIntervalMs','BuffIntervalSeconds','BuffCount')
$script:autoFightProfileFields=@('Flavor','ClassId')+$script:autoFightKeyFields+@('RecoveryCooldownSeconds','BuffIntervalSeconds','BuffCount')
$script:autoFightLegacyFields=@('Flavor','ClassId')+$script:autoFightLegacyKeyFields+@($script:autoFightCommonKeyFields | Where-Object {$_ -ne 'TargetKey'})+
    @('OpeningIntervalMs','CombatIntervalMs','EmergencyIntervalMs','MovementHoldMs','InteractionHoldMs','SkinEnabled')
function New-AutoFightCommon {
    return [pscustomobject]@{MoveForwardKey='W';MoveBackwardKey='S';MoveLeftKey='Q';MoveRightKey='E';
        SkinKey='F7';TargetKey='Tab';MovementHoldMs=400;InteractionHoldMs=3500;SkinEnabled=$true;JumpIntervalSeconds=0}
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
    foreach ($field in $script:autoFightCommonKeyFields) {
        $fields[$field]=(ConvertFrom-AutoFightBinding $Common.$field).Text
    }
    # WoW has no keyboard separator binding; plain Space is reserved for global jumping.
    $target=ConvertFrom-AutoFightBinding $fields.TargetKey
    if ($target.Code -eq 108 -or $target.Text -eq 'Space') {throw '选目标键不支持数字键盘分隔符或单独空格。'}
    foreach ($field in $script:autoFightCommonKeyFields) {
        if ($field -ne 'TargetKey' -and $fields[$field] -eq $fields.TargetKey) {throw "选目标键不能与 $field 相同。"}
    }
    if (@($script:autoFightCommonKeyFields[0..3] | ForEach-Object {$fields[$_]} | Select-Object -Unique).Count -ne 4) {
        throw '四个移动方向必须绑定不同的按键。'
    }
    $fields.MovementHoldMs=Get-AutoFightInteger $Common.MovementHoldMs 100 2000 '移动按住时长 (ms)'
    $fields.InteractionHoldMs=Get-AutoFightInteger $Common.InteractionHoldMs 1000 60000 '交互等待 (ms)'
    if ($Common.SkinEnabled -isnot [bool]) {throw '拾取 / 剥皮交互开关必须为布尔值。'}
    $fields.SkinEnabled=$Common.SkinEnabled
    $fields.JumpIntervalSeconds=Get-AutoFightInteger $Common.JumpIntervalSeconds 0 3600 '自动跳跃间隔 (秒，0 关闭)'
    return [pscustomobject]$fields
}
function Get-AutoFightEffectiveProfile($Profile,$Common) {
    $fields=[ordered]@{}
    foreach ($field in $script:autoFightProfileFields) {$fields[$field]=$Profile.$field}
    foreach ($field in $script:autoFightCommonFields) {$fields[$field]=$Common.$field}
    $fields.JumpKey='Space'
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
        RecoveryKey='F8';RecoveryCooldownSeconds=30;BuffKey='F11';BuffIntervalSeconds=0;BuffCount=1}
}
function New-AutoFightProfiles {
    $profiles=@{}
    foreach ($flavor in @('titan','forerver')) {
        foreach ($id in (Get-AutoFightClassIds $flavor)) { $profiles["${flavor}:$id"]=New-AutoFightProfile $flavor $id }
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
function ConvertTo-AutoFightProfiles($Items,[int]$Version=9) {
    $result=@{}
    foreach ($item in @($Items)) {
        $expected=if ($Version -ge 9) {$script:autoFightProfileFields} elseif ($Version -eq 8) {$script:autoFightV8ProfileFields}
            elseif ($Version -eq 7) {$script:autoFightV7ProfileFields}
            elseif ($Version -ge 4) {$script:autoFightV6ProfileFields} else {$script:autoFightLegacyFields}
        if ($Version -eq 1) { $expected=@('Flavor','ClassId','AttackKey','SkinKey','AttackIntervalMs','InteractionHoldMs','SkinEnabled') }
        $actual=@($item.PSObject.Properties.Name)
        if ($actual.Count -ne $expected.Count -or @($actual | Where-Object { $_ -notin $expected }).Count) {
            throw 'autoFight 职业配置字段不完整或包含未知字段。'
        }
        if ($item.Flavor -notin @('titan','forerver')) { throw '未知的 autoFight 服务器。' }
        $id=Get-AutoFightInteger $item.ClassId 1 13 '职业 ID'
        if ($id -notin (Get-AutoFightClassIds $item.Flavor)) {
            if ($Version -lt 5) {continue}
            throw '该客户端不具备此职业。'
        }
        $p=$item
        if ($Version -eq 1) {
            $p=New-AutoFightProfile $item.Flavor $id
            $p.OpeningKey=$item.AttackKey; $p.CombatKey=$item.AttackKey
        }
        $fields=[ordered]@{Flavor=$p.Flavor; ClassId=$id}
        foreach ($field in $script:autoFightKeyFields) {
            $value=if ($Version -ge 7 -or $field -ne 'BuffKey') {$p.$field} else {'F11'}
            $fields[$field]=(ConvertFrom-AutoFightBinding $value).Text
        }
        if ($Version -lt 9) {
            $legacyCombatInterval=if ($Version -eq 1) {$item.AttackIntervalMs} else {$p.CombatIntervalMs}
            $null=Get-AutoFightInteger $legacyCombatInterval 100 10000 '旧正常战斗间隔 (ms)'
        }
        $fields.RecoveryCooldownSeconds=if ($Version -ge 9) {
            Get-AutoFightInteger $p.RecoveryCooldownSeconds 1 3600 '恢复冷却 (秒)'
        } else {30}
        $fields.BuffIntervalSeconds=if ($Version -ge 7) {Get-AutoFightInteger $p.BuffIntervalSeconds 0 86400 '补 Buff 间隔 (秒，0 关闭)'} else {0}
        $fields.BuffCount=if ($Version -ge 7) {Get-AutoFightInteger $p.BuffCount 1 20 '每轮补 Buff 次数'} else {1}
        if ($Version -lt 4) {
            $legacy=New-AutoFightCommon
            foreach ($field in $script:autoFightCommonFields) {
                if ($field -notin @('JumpIntervalSeconds','TargetKey') -and ($Version -gt 1 -or $field -in @('SkinKey','InteractionHoldMs','SkinEnabled'))) {$legacy.$field=$item.$field}
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
    if ($result.Count -ne 19) { throw 'autoFight 配置必须包含时光服 10 个和无限服 9 个职业的独立配置。' }
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
    if ($null -eq $document -or $document.Version -notin @(1,2,3,4,5,6,7,8,9)) {throw '无法读取 autoFight 配置版本或内容。'}
    $expected=@('Version','Profiles')
    if ($document.Version -ge 3) {$expected+='CommandIntervalMs'}
    if ($document.Version -ge 4) {$expected+='Common'}
    $actual=@($document.PSObject.Properties.Name)
    if ($actual.Count -ne $expected.Count -or @($actual | Where-Object {$_ -notin $expected}).Count -or $null -eq $document.Profiles) {
        throw 'autoFight 配置字段不完整或包含未知字段。'
    }
    $interval=500
    if ($document.Version -ge 3) {$interval=Get-AutoFightInteger $document.CommandIntervalMs 100 60000 '公共最小按键间隔 (ms)'}
    $profiles=ConvertTo-AutoFightProfiles $document.Profiles $document.Version
    $common=New-AutoFightCommon
    if ($document.Version -ge 4) {
        if ($document.Version -eq 4) {$document.Common | Add-Member NoteProperty JumpIntervalSeconds 0}
        if ($document.Version -le 5) {$document.Common | Add-Member NoteProperty TargetKey 'Tab'}
        $common=ConvertTo-AutoFightCommon $document.Common
    }
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
    Test-AutoFightTargetConflicts $profiles $common
    return [pscustomobject]@{Profiles=$profiles;Common=$common;CommandIntervalMs=$interval}
}
function Test-AutoFightTargetConflicts($Profiles,$Common) {
    foreach ($profile in $Profiles.Values) {
        foreach ($field in $script:autoFightKeyFields) {
            if ($field -eq 'BuffKey' -and $profile.BuffIntervalSeconds -eq 0) {continue}
            if ($profile.$field -eq $Common.TargetKey) {throw "选目标键与 $($profile.Flavor) 职业 $($profile.ClassId) 的 $field 冲突。"}
        }
    }
}
function Read-AutoFightProfiles([string]$Path) {return (Read-AutoFightConfiguration $Path).Profiles}
function Save-AutoFightProfiles([string]$Path,$Profiles,$CommandIntervalMs=500,$Common=(New-AutoFightCommon)) {
    $valid=ConvertTo-AutoFightProfiles @($Profiles.Values)
    $general=ConvertTo-AutoFightCommon $Common
    Test-AutoFightTargetConflicts $valid $general
    $interval=Get-AutoFightInteger $CommandIntervalMs 100 60000 '公共最小按键间隔 (ms)'
    $items=@($valid.Keys | Sort-Object | ForEach-Object {$valid[$_]})
    $json=[pscustomobject]@{Version=9;CommandIntervalMs=$interval;Common=$general;Profiles=$items} | ConvertTo-Json -Depth 5
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
        MovementRequest=''; RecoveryReadyAt=$Now;
        JumpIntervalSeconds=0;NextJumpAt=[long]::MaxValue;
        BuffIntervalSeconds=0;BuffCount=1;BuffRemaining=0;NextBuffAt=[long]::MaxValue}
}
function Set-AutoFightBuffSchedule($Session,$Profile,[long]$Now,[switch]$AfterLogin) {
    $interval=[int]$Profile.BuffIntervalSeconds
    $count=[int]$Profile.BuffCount
    if (-not $AfterLogin -and $Session.BuffIntervalSeconds -eq $interval -and $Session.BuffCount -eq $count) {return}
    $active=$Session.BuffRemaining -gt 0
    $Session.BuffIntervalSeconds=$interval; $Session.BuffCount=$count
    if ($interval -eq 0) {$Session.BuffRemaining=0;$Session.NextBuffAt=[long]::MaxValue}
    elseif ($AfterLogin) {$Session.BuffRemaining=0;$Session.NextBuffAt=$Now}
    elseif (-not $active) {$Session.NextBuffAt=$Now+[long]$interval*1000}
}
function Set-AutoFightJumpInterval($Session,[int]$Seconds,[long]$Now) {
    if ($Session.JumpIntervalSeconds -eq $Seconds) {return}
    $Session.JumpIntervalSeconds=$Seconds
    $Session.NextJumpAt=if ($Seconds -gt 0) {$Now+[long]$Seconds*1000} else {[long]::MaxValue}
}
function Get-AutoFightAction($Session,$Packet,$Profile,[long]$Now) {
    Set-AutoFightJumpInterval $Session $Profile.JumpIntervalSeconds $Now
    Set-AutoFightBuffSchedule $Session $Profile $Now
    if ($Packet.ClassId -ne $Session.ClassId -or $Packet.Flavor -ne $Profile.Flavor) { return 'identity-changed' }
    if ($Packet.Action -notin @('idle','opening','combat','interact')) { return 'identity-changed' }
    if ($Packet.Recovery -notin @('none','recover','unknown')) { return 'identity-changed' }
    if ($Packet.Action -ne 'idle' -or $Packet.Busy) {$Session.MovementRequest=''}
    if ($Now -ge $Session.RecoveryReadyAt) {
        if ($Packet.Recovery -eq 'unknown') {return 'wait'}
        if ($Packet.Recovery -eq 'recover' -and -not $Packet.Busy) {return 'recover'}
    }
    if ($Packet.Busy) {return 'wait'}
    if ($Session.NextBuffAt -le $Now -and $Packet.Action -eq 'idle' -and -not $Session.MovementRequest) {
        if ($Session.BuffRemaining -eq 0) {$Session.BuffRemaining=$Session.BuffCount}
        return 'buff'
    }
    if ($Now -ge $Session.NextJumpAt -and $Packet.Action -in @('idle','combat') -and
        -not $Session.MovementRequest) {return 'jump'}
    if ($Packet.Action -eq 'idle' -and $Session.MovementRequest) {return 'move-'+$Session.MovementRequest}
    $handler=$script:autoFightStates[$Packet.Action]
    if (-not $handler.Key) {return 'wait'}
    if ($Packet.Action -eq 'interact') {
        if (-not $Profile.SkinEnabled -or $Packet.Combat) { return 'wait' }
    }
    return $Packet.Action
}
function Complete-AutoFightAction($Session,$Profile,[string]$Action,[long]$Now) {
    if ($Action -eq 'recover') {
        $Session.RecoveryReadyAt=$Now+[long]$Profile.RecoveryCooldownSeconds*1000
        $Session.Due=$Now+100
        return
    }
    if ($Action -eq 'buff') {
        $Session.BuffRemaining--
        $Session.NextBuffAt=if ($Session.BuffRemaining -gt 0) {$Now+1000} else {$Now+[long]$Session.BuffIntervalSeconds*1000}
        $Session.Due=$Now+100
        return
    }
    if ($Action -eq 'jump') {
        $Session.NextJumpAt=$Now+[long]$Profile.JumpIntervalSeconds*1000
        $Session.Due=$Now+100
        return
    }
    if ($Action.StartsWith('move-')) {$Session.MovementRequest=''}
    $Session.Due=$Now+100
}
function Get-AutoFightHoldDuration($Profile,[string]$Action) {
    if ($Action.StartsWith('move-')) {return $Profile.MovementHoldMs}
    return $Profile.InteractionHoldMs
}
function Test-AutoFightHoldFinished($Hold,$Packet,[long]$Now) {
    if ($Hold.State -eq 'interact' -and -not $Hold.Movement) {
        # Let either looting or skinning finish even if the hint briefly disappears.
        return $Now -ge $Hold.Until -or $Packet.Combat
    }
    return $Now -ge $Hold.Until -or $Packet.Action -ne $Hold.State -or
        ($Hold.Movement -and $Packet.Busy)
}
