$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\wowAuto.Accounts.ps1')
. (Join-Path $PSScriptRoot '..\wowAuto.AccountTasks.Ui.ps1')

function Assert-AccountRecord($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$record = @'
wowToolsCharacterRecord = {
    ["version"] = 6,
    ["name"] = "嫩牛五方",
    ["realm"] = "CN5 Realm 7 PvP",
    ["classId"] = 3,
    ["level"] = 43,
    ["freeBagSlots"] = 9,
    ["recordedAt"] = 1794842263,
    ["professions"] = "?",
    ["secondarySkills"] = "",
    ["bindLocation"] = "格罗姆高营地",
}
'@
$settings = 'wowToolsCharacterSettings = { ["raynnaBestiary"] = { ["db"] = { ["language"] = "zh", ["padding"] = "' + ('x' * 70KB) + '" } } }'
foreach ($text in @($record, ($record + "`n" + $settings), ($settings + "`n" + $record))) {
    $parsed = ConvertFrom-WowCharacterRecord $text
    Assert-AccountRecord ($parsed.Name -ceq '嫩牛五方' -and $parsed.Realm -ceq 'CN5 Realm 7 PvP' -and
        $parsed.Level -eq 43 -and $parsed.ClassId -eq 3) 'A co-located character settings table hid the snapshot.'
}
foreach ($version in 1..6) {
    $legacy = $record.Replace('["version"] = 6', '["version"] = ' + $version)
    if ($version -lt 6) { $legacy = $legacy -replace '(?m)^.*\["classId"\].*\r?\n', '' }
    if ($version -lt 3) { $legacy = $legacy -replace '(?m)^.*\["bindLocation"\].*\r?\n', '' }
    if ($version -lt 2) { $legacy = $legacy -replace '(?m)^.*\["(?:professions|secondarySkills)"\].*\r?\n', '' }
    if ($version -eq 4) { $legacy = $legacy.Replace('["level"] = 43,', '["level"] = 43, ["maxLevel"] = 60,') }
    Assert-AccountRecord ($null -ne (ConvertFrom-WowCharacterRecord $legacy)) "Snapshot version $version was rejected."
}
$invalid = @(
    ($record + "`n" + $record),
    ('wowToolsCharacterSettings = { ["nested"] = {' + $record.Substring($record.IndexOf('{') + 1) + '} }'),
    'wowToolsCharacterSettings = { ["text"] = "wowToolsCharacterRecord = {}" }',
    ($record + "`n" + 'wowToolsCharacterSettings = os.execute("invalid")'),
    $record.Replace('["level"] = 43,', '["level"] = 43, ["level"] = 44,'),
    $record.Replace('["name"] = "嫩牛五方",', '["name"] = "错误-角色",'),
    $record.Replace('["bindLocation"] = "格罗姆高营地",', '["bindLocation"] = "' + ('x' * 64KB) + '",')
)
foreach ($text in $invalid) {
    Assert-AccountRecord ($null -eq (ConvertFrom-WowCharacterRecord $text)) 'Invalid, duplicate, nested or executable snapshot data was accepted.'
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('wow-roster-' + [guid]::NewGuid().ToString('N'))
try {
    $account = Join-Path $temporaryRoot 'WTF\Account\TEST'
    foreach ($relative in @('95\嫩牛五方-真棒', '95\错误角色-真棒', '95\无后缀', '旧服务器\嫩牛五方', '旧服务器\错误角色-真棒')) {
        $saved = Join-Path (Join-Path $account $relative) 'SavedVariables'
        [IO.Directory]::CreateDirectory($saved) | Out-Null
        [IO.File]::WriteAllText((Join-Path $saved 'wow_tools.lua'), $settings + "`n" + $record)
    }
    $catalog = @(Get-WowAccountCatalog $temporaryRoot)
    Assert-AccountRecord ($catalog.Count -eq 1 -and @($catalog[0].Characters).Count -eq 1 -and
        $catalog[0].Characters[0].Name -ceq '嫩牛五方') 'Connected-realm layout did not preserve snapshot name validation.'
    Assert-AccountRecord ($catalog[0].Characters[0].FullName -ceq '嫩牛五方-真棒' -and
        $catalog[0].Characters[0].DisplayRealm -ceq '真棒' -and
        (Get-WowCharacterDisplayName $catalog[0].Characters[0]) -ceq '嫩牛五方-真棒') 'Character display names lost their realm suffix.'
    $draft = @{ Accounts = @{ TEST = @(@{Name='嫩牛五方';Realm='CN5 Realm 7 PvP';Enabled=$false;Mode='fish';UseItem=$false}) } }
    $grid = [pscustomobject]@{Rows=@([pscustomobject]@{
        Tag=$catalog[0].Characters[0]
        Cells=@{Name=@{Value='嫩牛五方-真棒'};Realm=@{Value='真棒'};Enabled=@{Value=$true};Mode=@{Value='战斗'};UseItem=@{Value=$true}}
    })}
    $grid | Add-Member ScriptMethod EndEdit { return $true }
    Save-AccountGridDraft ([pscustomobject]@{Selected='TEST';Draft=$draft;Grids=@($grid)})
    Assert-AccountRecord ($draft.Accounts.TEST[0].Name -ceq '嫩牛五方' -and
        $draft.Accounts.TEST[0].Realm -ceq 'CN5 Realm 7 PvP' -and $draft.Accounts.TEST[0].Enabled -and
        $draft.Accounts.TEST[0].Mode -ceq 'fight' -and -not $draft.Accounts.TEST[0].UseItem) 'Displayed full names changed persistent task identities.'
    $legacyPath = Join-Path $account '旧服务器\嫩牛五方\SavedVariables\wow_tools.lua'
    [IO.File]::WriteAllText($legacyPath, $record.Replace('CN5 Realm 7 PvP', '旧服务器'))
    $catalog = @(Get-WowAccountCatalog $temporaryRoot)
    Assert-AccountRecord (@($catalog[0].Characters).Count -eq 2) 'Legacy realm/name layout was rejected.'
    $legacyRecord = @($catalog[0].Characters | Where-Object Realm -ceq '旧服务器')[0]
    Assert-AccountRecord ($legacyRecord.FullName -ceq '嫩牛五方-旧服务器') 'Legacy full names lost their realm suffix.'
    $realmSaved = Join-Path $account 'SavedVariables'
    [IO.Directory]::CreateDirectory($realmSaved) | Out-Null
    [IO.File]::WriteAllText((Join-Path $realmSaved 'wow_tools.lua'), 'wowToolsRealmLevels = { ["CN5 Realm 7 PvP"] = { maxLevel = 60, recordedAt = 1794842263, }, }')
    $catalog = @(Get-WowAccountCatalog $temporaryRoot)
    Assert-AccountRecord ($catalog[0].RealmLevels['CN5 Realm 7 PvP'].MaxLevel -eq 60) 'Connected-realm snapshots lost their native realm-level key.'
} finally {
    $resolved = [IO.Path]::GetFullPath($temporaryRoot)
    if ((Split-Path $resolved -Parent) -ne [IO.Path]::GetTempPath().TrimEnd('\') -or
        (Split-Path $resolved -Leaf) -notmatch '^wow-roster-[a-f0-9]{32}$') { throw 'Unexpected temporary catalog path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
$skillRecord = ConvertFrom-WowCharacterRecord ($record.Replace('["professions"] = "?"', '["professions"] = "171|Alchemy|225|300;182|Herbalism|200|300"').Replace('["secondarySkills"] = ""', '["secondarySkills"] = "356|Fishing|175|225"'))
Assert-AccountRecord ((Format-WowCharacterSkills $skillRecord.Professions) -ceq "Alchemy 225/300`nHerbalism 200/300" -and
    (Format-WowCharacterSkills $skillRecord.SecondarySkills) -ceq 'Fishing 175/225') 'Skill snapshots did not reach the display formatter.'
Write-Output 'PASS: character snapshot literal parsing, v1-v6 compatibility and legacy/connected-realm directory contracts.'
