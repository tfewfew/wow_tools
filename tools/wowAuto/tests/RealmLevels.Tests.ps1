$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../wowAuto.Accounts.ps1')
. (Join-Path $PSScriptRoot 'CharacterRecords.Fixtures.ps1')
function Assert-Realm($Value,[string]$Message){if(-not $Value){throw $Message}}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-realm-levels-'+[guid]::NewGuid().ToString('N'))
try {
    $titan=Join-Path $fixture '_classic_titan_';$forever=Join-Path $fixture '_cn_beta_'
    $a=Join-Path $titan 'WTF/Account/A';$b=Join-Path $titan 'WTF/Account/B';$other=Join-Path $forever 'WTF/Account/A'
    Write-TestRealmLevels $a @{'服务器甲'=80;'服务器乙'=60}
    $path=Join-Path $a 'SavedVariables/wow_tools.lua';$text=[IO.File]::ReadAllText($path);$hash=(Get-FileHash $path).Hash
    $levels=ConvertFrom-WowRealmLevels $text
    Assert-Realm ($levels.Count -eq 2 -and $levels['服务器甲'].MaxLevel -eq 80 -and $levels['服务器乙'].MaxLevel -eq 60) 'Realm cap parser read other SavedVariables or lost a realm.'
    $quoted=ConvertFrom-WowRealmLevels ($text.Replace('服务器甲','Realm \"One\"'))
    Assert-Realm ($quoted.ContainsKey('Realm "One"')) 'Quoted realm name was not decoded.'
    $empty=ConvertFrom-WowRealmLevels 'wowToolsRealmLevels = {}'
    Assert-Realm ($null -ne $empty -and $empty.Count -eq 0) 'Empty global realm table was invalid.'
    foreach($bad in @($text.Replace('= 80,','= 0,'),$text.Replace('= 80,','= -1,'),$text.Replace('= 80,','= 1001,'),
        $text.Replace('= 80,','= "80",'),$text.Replace('["maxLevel"]','["recordedAt"]'),
        $text.Replace('["maxLevel"]','["unknown"]'),$text.Replace('服务器乙','服务器甲'),$text.Replace('服务器甲','bad\nrealm'),
        $text.Replace('= 80','= execute()'),$text.Replace('= 80','= { 80 }'),$text.Replace('= 1792200000','= 0'),
        $text.Replace('wowToolsRealmLevels = {','wowToolsRealmLevels = nil'),($text+"`r`nwowToolsRealmLevels = {}"),('x'*(1MB+1)))){
        Assert-Realm ($null -eq (ConvertFrom-WowRealmLevels $bad)) 'Malformed/duplicate/executable/oversized realm metadata was accepted.'
    }
    # One API reading supplies all characters, including legacy records and other accounts.
    Write-TestCharacterRecord (Join-Path $a '服务器甲/角色甲') '角色甲' '服务器甲' -Version 5 -Level 80
    Write-TestCharacterRecord (Join-Path $a '服务器甲/角色乙') '角色乙' '服务器甲' -Version 4 -Level 80 -MaxLevel 12
    Write-TestCharacterRecord (Join-Path $b '服务器甲/角色丙') '角色丙' '服务器甲' -Version 1 -Level 79
    Write-TestCharacterRecord (Join-Path $b '服务器乙/角色丁') '角色丁' '服务器乙' -Version 5 -Level 60
    Write-TestCharacterRecord (Join-Path $b '未知服务器/未知角色') '未知角色' '未知服务器' -Version 4 -Level 99 -MaxLevel 99
    Write-TestRealmLevels $b @{'服务器甲'=60} 1792190000
    $catalog=@(Get-WowAccountCatalog $titan);$first=@($catalog | Where-Object Name -eq 'A')[0];$second=@($catalog | Where-Object Name -eq 'B')[0]
    Assert-Realm ($first.RealmLevels['服务器甲'].MaxLevel -eq 80 -and $second.RealmLevels['服务器甲'].MaxLevel -eq 80 -and
        -not @($first.Characters | Where-Object {$_.PSObject.Properties['MaxLevel']}).Count) 'Cap still belongs to a character/account or an older global reading replaced a newer one.'
    $roles=@($first.Characters | ForEach-Object {@{Name=$_.Name;Realm=$_.Realm}})
    $groups=Get-WowCharacterLevelGroups $roles $first.Characters $first.RealmLevels
    Assert-Realm ($groups.Full.Count -eq 2 -and $groups.Leveling.Count -eq 0) 'Legacy per-character cap overrode the shared realm cap.'
    $roles=@($second.Characters | ForEach-Object {@{Name=$_.Name;Realm=$_.Realm}})
    $groups=Get-WowCharacterLevelGroups $roles $second.Characters $second.RealmLevels
    Assert-Realm ($groups.Full.Count -eq 1 -and $groups.Full[0].Role.Name -ceq '角色丁' -and $groups.Leveling.Count -eq 2) 'Different/unknown realms inherited another realm or a legacy character cap.'
    Write-TestRealmLevels $other @{'服务器甲'=60}
    Write-TestCharacterRecord (Join-Path $other '服务器甲/角色戊') '角色戊' '服务器甲' -Version 5 -Level 60
    $foreign=@(Get-WowAccountCatalog $forever)[0]
    Assert-Realm ($foreign.RealmLevels['服务器甲'].MaxLevel -eq 60 -and $first.RealmLevels['服务器甲'].MaxLevel -eq 80) 'Same realm name leaked between clients.'
    # Fresh disk reads apply globally; equal-time conflicting records stay unknown.
    Write-TestRealmLevels $b @{'服务器甲'=90} 1792300000
    $fresh=@(Get-WowAccountCatalog $titan | Where-Object Name -eq 'A')[0]
    $groups=Get-WowCharacterLevelGroups @($fresh.Characters | ForEach-Object {@{Name=$_.Name;Realm=$_.Realm}}) $fresh.Characters $fresh.RealmLevels
    Assert-Realm ($fresh.RealmLevels['服务器甲'].MaxLevel -eq 90 -and $groups.Full.Count -eq 0) 'Refreshing a realm cap did not regroup all characters.'
    Write-TestRealmLevels $a @{'服务器甲'=80} 1792300000
    $tied=@(Get-WowAccountCatalog $titan)[0]
    Assert-Realm ($null -eq $tied.RealmLevels['服务器甲'].MaxLevel) 'Conflicting equal-time caps were arbitrarily selected.'
    Write-TestRealmLevels $a @{'服务器甲'=90} 1792300001
    Assert-Realm (@(Get-WowAccountCatalog $titan)[0].RealmLevels['服务器甲'].MaxLevel -eq 90) 'A newer reading did not resolve an older conflict.'
    [IO.File]::WriteAllText($path,$text,(New-Object Text.UTF8Encoding($false)))
    [void](Get-WowAccountCatalog $titan)
    Assert-Realm ((Get-FileHash $path).Hash -eq $hash) 'Read-only catalog modified account SavedVariables.'
    Write-Output 'PASS: safe global realm-cap parsing, legacy/v5 role compatibility, shared caps across characters/accounts, client/realm isolation, timestamp refresh/conflicts and no Lua execution or game actions.'
}finally{
    $target=[IO.Path]::GetFullPath($fixture)
    if(-not $target.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $target -Leaf) -notlike 'wowAuto-realm-levels-*'){throw 'Unsafe fixture cleanup.'}
    if([IO.Directory]::Exists($target)){[IO.Directory]::Delete($target,$true)}
}
