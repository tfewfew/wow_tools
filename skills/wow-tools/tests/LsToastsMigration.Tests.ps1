$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\scripts\migrate-bigfoot.ps1')
function Assert-ToastsMigration($Condition,[string]$Message) {if(-not $Condition){throw $Message}}
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('wow-tools-toasts-test-'+[guid]::NewGuid().ToString('N'))
$saved=Join-Path $temporary 'SavedVariables'
$backup=Join-Path $temporary 'Backup'
New-Item -ItemType Directory -Path $saved -Force | Out-Null
try {
    $target=Join-Path $saved 'wow_tools.lua'
    $legacy=Join-Path $saved 'ls_Toasts.lua'
    $original='wowDetectorDB = { ["bigfootChannel"] = { ["chat"] = {} }, ["soundControl"] = { ["minimapAngle"] = 315 }, }'
    $old='LS_TOASTS_GLOBAL_CONFIG = { ["profileKeys"] = { ["角色 - 服务器"] = "自定义" }, ["profiles"] = { ["自定义"] = { ["skin"] = "beautycase", ["anchors"] = { { ["scale"] = 1.5 } }, ["types"] = { ["loot_items"] = { ["threshold"] = 3 } } } } }'
    [IO.File]::WriteAllText($target,$original)
    [IO.File]::WriteAllText($legacy,$old)
    Assert-ToastsMigration (Merge-WowLsToastsSettings $saved $backup) 'Toast settings were not migrated.'
    $merged=[IO.File]::ReadAllText($target)
    $data=Read-WowLuaData $merged
    $node=$data['wowDetectorDB'].Fields['lsToasts'].Fields['db']
    $oldNode=(Read-WowLuaData $old)['LS_TOASTS_GLOBAL_CONFIG']
    Assert-ToastsMigration ($merged.Substring($node.Start,$node.End-$node.Start) -ceq $old.Substring($oldNode.Start,$oldNode.End-$oldNode.Start)) 'Toast profiles or anchors changed during migration.'
    Assert-ToastsMigration ($data['wowDetectorDB'].Fields.ContainsKey('bigfootChannel') -and $data['wowDetectorDB'].Fields.ContainsKey('soundControl')) 'Other settings were changed.'
    Assert-ToastsMigration (-not (Merge-WowLsToastsSettings $saved $backup)) 'Repeated migration overwrote current toast settings.'
    Assert-ToastsMigration ([IO.File]::ReadAllText((Join-Path $backup 'wow_tools.lua')) -ceq $original) 'Original account backup differs.'
    [IO.File]::WriteAllText($target,$original)
    [IO.File]::WriteAllText($legacy,'LS_TOASTS_GLOBAL_CONFIG = loadstring("bad")()')
    $rejected=$false
    try{$null=Merge-WowLsToastsSettings $saved $backup}catch{$rejected=$true}
    Assert-ToastsMigration ($rejected -and [IO.File]::ReadAllText($target) -ceq $original) 'Executable settings were accepted or partially written.'
    Remove-Item -LiteralPath $legacy
    Assert-ToastsMigration (-not(Merge-WowLsToastsSettings $saved $backup)) 'Missing legacy settings created a new group.'
    $sync=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\scripts\sync-local.ps1'))
    Assert-ToastsMigration ($sync.IndexOf('Merge-WowLsToastsSettings') -lt $sync.IndexOf('$legacyNames =')) 'ls_Toasts retired before settings migration.'
    Write-Output 'PASS: literal-only ls_Toasts profile/anchor migration, original data and backups, other modules, retry, malformed/missing settings and retirement ordering.'
} finally {
    $resolved=[IO.Path]::GetFullPath($temporary)
    if((Split-Path $resolved -Parent) -ne [IO.Path]::GetTempPath().TrimEnd('\')){throw 'Test cleanup path mismatch.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
