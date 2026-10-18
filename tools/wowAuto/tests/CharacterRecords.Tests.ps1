$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../wowAuto.Accounts.ps1')
. (Join-Path $PSScriptRoot 'CharacterRecords.Fixtures.ps1')
function Assert-Record($Value,[string]$Message) {if (-not $Value) {throw $Message}}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-records-'+[guid]::NewGuid())
try {
    $role=Join-Path $fixture 'WTF/Account/ACCOUNT#1/服务器甲/角色甲'
    Write-TestCharacterRecord $role '角色甲' '服务器甲' 80 0
    $path=Join-Path $role 'SavedVariables/wow_tools.lua'
    $text=[IO.File]::ReadAllText($path);$hash=(Get-FileHash $path).Hash
    $record=Read-WowCharacterRecord $role '角色甲' '服务器甲'
    Assert-Record ($record.Level -eq 80 -and $record.FreeBagSlots -eq 0 -and $record.RecordedAt -eq 1792200000) 'Snapshot lost level, zero free slots or timestamp.'
    Assert-Record ($null -eq $record.Professions -and $null -eq $record.SecondarySkills -and (Format-WowCharacterSkills $record.Professions) -ceq '未知') 'Legacy records invented known skills or disappeared.'
    Assert-Record (-not (Read-WowCharacterRecord $role '其他角色' '服务器甲') -and -not (Read-WowCharacterRecord $role '角色甲' '其他服务器')) 'Mismatched directory identity was accepted.'
    foreach ($bad in @($text.Replace('= 80','= 1001'),$text.Replace('= 0,','= -2,'),$text.Replace('= 1,','= 2,'),
        $text.Replace('["level"]','["unexpected"]'),$text.Replace('["level"]','["version"]'),$text.Substring(0,$text.Length-2),
        ($text+"`nmalicious()"),$text.Replace('= 80','= os.execute("bad")'),$text.Replace('= 80','= "80"'),('x'*65537))) {
        Assert-Record (-not (ConvertFrom-WowCharacterRecord $bad)) 'Malformed, oversized or executable SavedVariables was accepted.'
    }
    $unknown=ConvertFrom-WowCharacterRecord ($text.Replace('= 80,','= 0,').Replace('["freeBagSlots"] = 0,','["freeBagSlots"] = -1,'))
    Assert-Record ($unknown -and $null -eq $unknown.Level -and $null -eq $unknown.FreeBagSlots) 'Unknown API values were reported as real zero values.'
    $escaped=ConvertFrom-WowCharacterRecord ($text.Replace('服务器甲','Realm\032One'))
    Assert-Record ($escaped.Realm -eq 'Realm One') 'Lua string escape was not decoded.'
    $unrecorded=Join-Path $fixture 'WTF/Account/ACCOUNT#1/服务器甲/无记录角色';[void][IO.Directory]::CreateDirectory($unrecorded)
    $partial=Join-Path $fixture 'WTF/Account/ACCOUNT#1/服务器甲/损坏记录';Write-TestCharacterRecord $partial '损坏记录' '服务器甲'
    [IO.File]::WriteAllText((Join-Path $partial 'SavedVariables/wow_tools.lua'),'wowToolsCharacterRecord = {')
    Write-TestCharacterRecord (Join-Path $fixture 'WTF/Account/ACCOUNT#2/服务器甲/角色乙') '角色乙' '服务器甲' 60 23
    $catalog=@(Get-WowAccountCatalog $fixture)
    $account=@($catalog | Where-Object Name -eq 'ACCOUNT#1')[0]
    Assert-Record ($catalog.Count -eq 2 -and $account.Characters.Count -eq 1 -and $account.Characters[0].Name -ceq '角色甲' -and
        $account.Characters[0].FreeBagSlots -eq 0 -and (Get-FileHash $path).Hash -eq $hash) 'Catalog mixed accounts, invented records or changed SavedVariables.'
    Write-TestCharacterRecord $role '角色甲' '服务器甲' 81 7 1792200060
    $latest=@(Get-WowAccountCatalog $fixture | Where-Object Name -eq 'ACCOUNT#1')[0].Characters[0]
    Assert-Record ($latest.Level -eq 81 -and $latest.FreeBagSlots -eq 7 -and $latest.RecordedAt -eq 1792200060) 'Fresh logout snapshot was hidden by a stale cache.'
    $primary='186|采矿|450|450;393|剥皮|0|75';$secondary='185|烹饪|300|450;356|钓鱼|450|450;794|考古学|1|75'
    Write-TestCharacterRecord $role '角色甲' '服务器甲' -Version 2 -Professions $primary -SecondarySkills $secondary
    $skillsText=[IO.File]::ReadAllText($path);$skills=Read-WowCharacterRecord $role '角色甲' '服务器甲'
    Assert-Record ($skills -and $skills.Professions.Count -eq 2 -and $skills.Professions[1].Rank -eq 0 -and $skills.SecondarySkills.Count -eq 3 -and
        (Format-WowCharacterSkills $skills.Professions) -ceq "采矿 450/450`n剥皮 0/75") 'Version 2 skill names/ranks or formatting were lost.'
    foreach($bad in @($skillsText.Replace($primary,'129|急救|1|75'),$skillsText.Replace($primary,'185|烹饪|1|75'),
        $skillsText.Replace($primary,'186|采矿|451|450'),$skillsText.Replace($primary,'186|采矿|-1|450'),$skillsText.Replace($primary,'186|采矿|1|0'),
        $skillsText.Replace($primary,'186|采矿|1|75;186|采矿|2|75'),$skillsText.Replace($primary,'186|采矿|1'),
        $skillsText.Replace($secondary,'129|急救|375|450'),$skillsText.Replace($primary,'?;186|采矿|1|75'),
        $skillsText.Replace($primary,('x'*4097)),$skillsText.Replace('["professions"]','["level"]'),$skillsText.Replace('["version"] = 2,','["version"] = 3,'))) {
        Assert-Record (-not (ConvertFrom-WowCharacterRecord $bad)) 'Invalid, duplicate, cross-group or first-aid skill data was accepted.'
    }
    Write-TestCharacterRecord $role '角色甲' '服务器甲' -Version 2 -Professions '' -SecondarySkills '?'
    $empty=Read-WowCharacterRecord $role '角色甲' '服务器甲'
    Assert-Record ($empty -and $null -ne $empty.Professions -and $empty.Professions.Count -eq 0 -and $null -eq $empty.SecondarySkills -and
        (Format-WowCharacterSkills $empty.Professions) -ceq '未学习' -and (Format-WowCharacterSkills $empty.SecondarySkills) -ceq '未知') 'Unlearned and unknown skills were confused.'
    $fresh=@(Get-WowAccountCatalog $fixture | Where-Object Name -eq 'ACCOUNT#1')[0].Characters[0]
    Assert-Record ($fresh -and $fresh.Professions.Count -eq 0 -and $null -eq $fresh.SecondarySkills) 'Catalog filtered a valid version 2 role.'
    Assert-Record ($null -eq $fresh.BindLocation) 'Legacy v2 record invented a hearthstone binding.'
    Write-TestCharacterRecord $role '角色甲' '服务器甲' -Version 3 -Professions $primary -SecondarySkills $secondary -BindLocation '达拉然'
    $bindText=[IO.File]::ReadAllText($path);$bound=Read-WowCharacterRecord $role '角色甲' '服务器甲'
    Assert-Record ($bound -and $bound.BindLocation -ceq '达拉然' -and $bound.Professions.Count -eq 2 -and $bound.FreeBagSlots -eq 12) 'v3 binding corrupted other role metadata.'
    $catalogBound=@(Get-WowAccountCatalog $fixture | Where-Object Name -eq 'ACCOUNT#1')[0].Characters[0]
    Assert-Record ($catalogBound.BindLocation -ceq '达拉然') 'Catalog did not expose the binding snapshot.'
    Write-TestCharacterRecord $role '角色甲' '服务器甲' -Version 3 -BindLocation 'Lion''s Pride "Inn"'
    $quoted=Read-WowCharacterRecord $role '角色甲' '服务器甲'
    Assert-Record ($quoted.BindLocation -ceq 'Lion''s Pride "Inn"') 'Localized binding with quotes did not round trip.'
    Write-TestCharacterRecord $role '角色甲' '服务器甲' -Version 3 -BindLocation '?'
    $unbound=Read-WowCharacterRecord $role '角色甲' '服务器甲'
    Assert-Record ($unbound -and $null -eq $unbound.BindLocation) 'Unknown binding hid a valid role or invented a location.'
    foreach($bad in @($bindText.Replace('["bindLocation"]','["professions"]'),$bindText.Replace('"达拉然"','12'),
        $bindText.Replace('达拉然',''),$bindText.Replace('达拉然','   '),$bindText.Replace('达拉然',('x'*257)),
        $bindText.Replace('达拉然','bad\nlocation'),$bindText.Replace('达拉然','{bad}'),
        $bindText.Replace('["version"] = 3,','["version"] = 2,'),$bindText.Replace('["version"] = 3,','["version"] = 4,'),
        ($bindText+"`nmalicious()"))) {
        Assert-Record (-not (ConvertFrom-WowCharacterRecord $bad)) 'Invalid binding, extra field, unknown schema or executable data was accepted.'
    }
    Assert-Record ($null -eq $bound.MaxLevel) 'Legacy v3 record invented a level cap.'
    Write-TestCharacterRecord $role '角色甲' '服务器甲' -Version 4 -Level 80 -MaxLevel 80 -BindLocation '达拉然' -Professions $primary -SecondarySkills $secondary
    $maxText=[IO.File]::ReadAllText($path);$maxed=Read-WowCharacterRecord $role '角色甲' '服务器甲'
    Assert-Record ($maxed.MaxLevel -eq 80 -and $maxed.Level -eq 80 -and $maxed.BindLocation -ceq '达拉然' -and $maxed.Professions.Count -eq 2) 'v4 lost the level cap or earlier metadata.'
    $noCap=ConvertFrom-WowCharacterRecord ($maxText.Replace('["maxLevel"] = 80,','["maxLevel"] = 0,'))
    Assert-Record ($noCap -and $null -eq $noCap.MaxLevel) 'Unknown cap hid a valid character or became a real cap.'
    foreach($bad in @($maxText.Replace('["maxLevel"] = 80,','["maxLevel"] = -1,'),$maxText.Replace('["maxLevel"] = 80,','["maxLevel"] = 1001,'),
        $maxText.Replace('["maxLevel"] = 80,','["maxLevel"] = "80",'),$maxText.Replace('["maxLevel"]','["level"]'),
        $maxText.Replace('["version"] = 4,','["version"] = 3,'),$maxText.Replace('["version"] = 4,','["version"] = 5,'))){
        Assert-Record (-not (ConvertFrom-WowCharacterRecord $bad)) 'Malformed/duplicate/extra/unsupported level-cap data was accepted.'
    }
    $groupRecords=@(
        [pscustomobject]@{Name='旧角色';Realm='服务器甲';Level=85;MaxLevel=$null},
        [pscustomobject]@{Name='低级角色';Realm='服务器甲';Level=20;MaxLevel=80},
        [pscustomobject]@{Name='满级角色';Realm='服务器甲';Level=60;MaxLevel=60},
        [pscustomobject]@{Name='高级角色';Realm='服务器甲';Level=79;MaxLevel=80},
        [pscustomobject]@{Name='同级角色';Realm='服务器甲';Level=79;MaxLevel=80},
        [pscustomobject]@{Name='未知角色';Realm='服务器甲';Level=$null;MaxLevel=80})
    $groupRoles=@($groupRecords | ForEach-Object {@{Name=$_.Name;Realm=$_.Realm}})
    $groups=Get-WowCharacterLevelGroups $groupRoles $groupRecords
    Assert-Record ($groups.Full.Count -eq 1 -and $groups.Full[0].Role.Name -ceq '满级角色' -and
        (($groups.Leveling | ForEach-Object {$_.Role.Name}) -join ',') -ceq '旧角色,高级角色,同级角色,低级角色,未知角色') 'Level groups guessed a cap, lost stable descending order or failed to put unknown levels last.'
    $emptyGroups=Get-WowCharacterLevelGroups @() @()
    Assert-Record ($emptyGroups.Full.Count -eq 0 -and $emptyGroups.Leveling.Count -eq 0) 'Empty groups lost their array shape.'
    Write-Output 'PASS: strict read-only v1-v4 parsing, client level caps, stable descending level groups/unknowns, hearthstone/skills, invalid data rejection, identity/account isolation and no SavedVariables execution.'
} finally {
    $cleanup=[IO.Path]::GetFullPath($fixture)
    if (-not $cleanup.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $cleanup -Leaf) -notlike 'wowAuto-records-*') {throw 'Unsafe fixture cleanup.'}
    if ([IO.Directory]::Exists($cleanup)) {[IO.Directory]::Delete($cleanup,$true)}
}
