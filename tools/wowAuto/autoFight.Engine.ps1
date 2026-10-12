# autoFight configuration and decisions. No fishing state or input dependencies.
$script:autoFightClasses = [ordered]@{
    '1'='战士'; '2'='圣骑士'; '3'='猎人'; '4'='潜行者'; '5'='牧师'; '6'='死亡骑士';
    '7'='萨满祭司'; '8'='法师'; '9'='术士'; '10'='武僧'; '11'='德鲁伊'; '12'='恶魔猎手'; '13'='唤魔师'
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
    return [pscustomobject]@{Flavor=$Flavor; ClassId=$ClassId; AttackKey='F6'; SkinKey='F7';
        AttackIntervalMs=500; InteractionHoldMs=3500; SkinEnabled=$true}
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
        $p=$Profiles[$key]
        $copy[$key]=[pscustomobject]@{Flavor=$p.Flavor; ClassId=$p.ClassId; AttackKey=$p.AttackKey;
            SkinKey=$p.SkinKey; AttackIntervalMs=$p.AttackIntervalMs; InteractionHoldMs=$p.InteractionHoldMs; SkinEnabled=$p.SkinEnabled}
    }
    return $copy
}
function ConvertTo-AutoFightProfiles($Items) {
    $result=@{}
    foreach ($p in @($Items)) {
        $expected=@('Flavor','ClassId','AttackKey','SkinKey','AttackIntervalMs','InteractionHoldMs','SkinEnabled')
        $actual=@($p.PSObject.Properties.Name)
        if ($actual.Count -ne $expected.Count -or @($actual | Where-Object { $_ -notin $expected }).Count) {
            throw 'autoFight 职业配置字段不完整或包含未知字段。'
        }
        if ($p.Flavor -notin @('titan','forerver')) { throw '未知的 autoFight 服务器。' }
        $id=Get-AutoFightInteger $p.ClassId 1 13 '职业 ID'
        $attack=ConvertFrom-AutoFightBinding $p.AttackKey
        $skin=ConvertFrom-AutoFightBinding $p.SkinKey
        if ($attack.Text -eq $skin.Text) { throw '战斗键和剥皮交互键不能相同。' }
        if ($p.SkinEnabled -isnot [bool]) { throw '剥皮开关必须为布尔值。' }
        $interval=Get-AutoFightInteger $p.AttackIntervalMs 100 10000 '战斗按键间隔 (ms)'
        $hold=Get-AutoFightInteger $p.InteractionHoldMs 1000 60000 '拾取 / 剥皮前台保持 (ms)'
        $key="$($p.Flavor):$id"
        if ($result.ContainsKey($key)) { throw "重复的职业配置：$key" }
        $result[$key]=[pscustomobject]@{Flavor=$p.Flavor; ClassId=$id; AttackKey=$attack.Text; SkinKey=$skin.Text;
            AttackIntervalMs=$interval; InteractionHoldMs=$hold; SkinEnabled=$p.SkinEnabled}
    }
    if ($result.Count -ne 26) { throw 'autoFight 配置必须包含两服各 13 个职业的独立配置。' }
    return $result
}
function Read-AutoFightProfiles([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { return New-AutoFightProfiles }
    $document=[IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($null -eq $document -or $document.Version -ne 1 -or
        @($document.PSObject.Properties.Name).Count -ne 2 -or $null -eq $document.Profiles) {
        throw '无法读取 autoFight 配置版本或内容。'
    }
    return ConvertTo-AutoFightProfiles $document.Profiles
}
function Save-AutoFightProfiles([string]$Path,$Profiles) {
    $valid=ConvertTo-AutoFightProfiles @($Profiles.Values)
    $items=@($valid.Keys | Sort-Object | ForEach-Object { $valid[$_] })
    $json=[pscustomobject]@{Version=1; Profiles=$items} | ConvertTo-Json -Depth 5
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
        NextAttackAt=0L; NextInteractionAt=0L}
}
function Get-AutoFightAction($Session,$Packet,$Profile,[long]$Now) {
    if ($Packet.ClassId -ne $Session.ClassId -or $Packet.Flavor -ne $Profile.Flavor) { return 'identity-changed' }
    if ($Packet.Action -eq 'fight' -and $Now -ge $Session.NextAttackAt) { return 'attack' }
    if ($Profile.SkinEnabled -and -not $Packet.Combat -and $Packet.Action -in @('skin','loot') -and
        $Now -ge $Session.NextInteractionAt) { return 'interact' }
    return 'wait'
}
