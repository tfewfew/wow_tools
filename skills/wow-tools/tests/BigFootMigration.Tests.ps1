$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\migrate-bigfoot.ps1')
. (Join-Path $PSScriptRoot '..\scripts\client-profiles.ps1')
function Assert-ChatMigration($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('wow-tools-chat-test-' + [guid]::NewGuid().ToString('N'))
$saved = Join-Path $temporary 'SavedVariables'
$backup = Join-Path $temporary 'Backup'
New-Item -ItemType Directory -Path $saved -Force | Out-Null
try {
    $target = Join-Path $saved 'wow_tools.lua'
    $legacy = Join-Path $saved 'BigFootChat.lua'
    $filter = Join-Path $saved 'ChannelFilter.lua'
    $original = 'wowDetectorDB = { ["soundControl"] = { ["minimapAngle"] = 315, }, }' + "`nfightDetectorDB = {}"
    [IO.File]::WriteAllText($target, $original)
    [IO.File]::WriteAllText($legacy, 'BFCDB = { ["profiles"] = { ["Default"] = { ["mute"] = true, ["enablecopy"] = false } } }' + "`nBFCSystemCacheDB = {}")
    [IO.File]::WriteAllText($filter, 'ChannelFilter_Config = { ["Enabled"] = 1, ["IgnoreWords"] = { "代练", "引号\"与}括号", -- [1]' + "`n}, }")
    Assert-ChatMigration (Merge-WowBigFootSettings $saved $backup) 'Legacy settings were not migrated.'
    $migrated = [IO.File]::ReadAllText($target)
    $data = Read-WowLuaData $migrated
    $settings = $data['wowDetectorDB'].Fields['bigfootChannel']
    Assert-ChatMigration ($settings.Fields.ContainsKey('chat') -and $settings.Fields.ContainsKey('filter')) 'Missing chat/filter settings.'
    Assert-ChatMigration ($data['wowDetectorDB'].Fields.ContainsKey('soundControl') -and $data.ContainsKey('fightDetectorDB')) 'Migration changed unrelated data.'
    Assert-ChatMigration ([IO.File]::ReadAllText((Join-Path $backup 'wow_tools.lua')) -ceq $original) 'Original settings backup differs.'
    Assert-ChatMigration (-not (Merge-WowBigFootSettings $saved $backup)) 'Repeated migration overwrote new settings.'
    Assert-ChatMigration ([IO.File]::ReadAllText($target) -ceq $migrated) 'Repeated migration changed the file.'
    foreach ($body in @('{}', '{ ["a"] = 1 }', "{ [1] = true, -- comment`n}")) {
        [IO.File]::WriteAllText($target, 'wowDetectorDB = ' + $body)
        Assert-ChatMigration (Merge-WowBigFootSettings $saved $backup) 'Empty/non-trailing-comma/commented table failed.'
    }
    Remove-Item -LiteralPath $target
    Assert-ChatMigration (Merge-WowBigFootSettings $saved $backup) 'Missing wow_tools settings were not created.'
    foreach ($invalid in @('BFCDB = os.execute("bad")', 'BFCDB = {}; print("bad")', 'BFCDB = { [foo()] = 1 }', 'BFCDB = { ["x"] = 1, ["x"] = 2 }')) {
        [IO.File]::WriteAllText($target, $original)
        [IO.File]::WriteAllText($legacy, $invalid)
        $rejected = $false
        try { $null = Merge-WowBigFootSettings $saved $backup } catch { $rejected = $true }
        Assert-ChatMigration $rejected 'Executable or malformed legacy data accepted.'
        Assert-ChatMigration ([IO.File]::ReadAllText($target) -ceq $original) 'Failed migration partially changed settings.'
    }
    $sync = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\scripts\sync-local.ps1'))
    Assert-ChatMigration ($sync.IndexOf('Merge-WowBigFootSettings') -lt $sync.IndexOf('$legacyNames =')) 'Legacy addons retired before settings migration.'
    Assert-ChatMigration ($sync.Contains('Get-WowToolsRetiredAddonNames -Flavor $profile.Flavor')) 'Sync bypasses the client-specific retirement plan.'
    $titanRetired = @(Get-WowToolsRetiredAddonNames -Flavor titan)
    Assert-ChatMigration ($titanRetired -contains 'BigFootChat' -and $titanRetired -contains 'ChannelFilter') 'Titan duplicate chat modules remain active.'
    Assert-ChatMigration ($titanRetired -notcontains 'BigFoot' -and $titanRetired -notcontains '!!!Libs') 'Titan shared dependencies would be archived.'
    Write-Output 'PASS: literal-only chat settings migration, profiles/lists/escapes, unrelated data, backup, repeat/no-target, malformed-data rejection and per-client retirement ordering.'
} finally {
    $resolved = [IO.Path]::GetFullPath($temporary)
    if ((Split-Path $resolved -Parent) -ne [IO.Path]::GetTempPath().TrimEnd('\')) { throw 'Test cleanup path mismatch.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
