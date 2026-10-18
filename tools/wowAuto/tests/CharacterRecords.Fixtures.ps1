function Write-TestCharacterRecord([string]$Directory,[string]$Name,[string]$Realm,[int]$Level=80,[int]$FreeBagSlots=12,[long]$RecordedAt=1792200000,[int]$Version=1,[string]$Professions='?',[string]$SecondarySkills='?',[string]$BindLocation='?',[int]$MaxLevel=0) {
    $saved=Join-Path $Directory 'SavedVariables';[void][IO.Directory]::CreateDirectory($saved)
    $fields=[ordered]@{version=$Version;name=$Name;realm=$Realm;level=$Level;freeBagSlots=$FreeBagSlots;recordedAt=$RecordedAt}
    if($Version -in @(2,3,4)){$fields.professions=$Professions;$fields.secondarySkills=$SecondarySkills}
    if($Version -in @(3,4)){$fields.bindLocation=$BindLocation}
    if($Version -eq 4){$fields.maxLevel=$MaxLevel}
    $lines=@('wowToolsCharacterRecord = {')
    foreach ($key in $fields.Keys) {
        $value=$fields[$key]
        if ($value -is [string]) {$value='"'+$value.Replace('\','\\').Replace('"','\"')+'"'}
        $lines+=('    ["{0}"] = {1},' -f $key,$value)
    }
    [IO.File]::WriteAllText((Join-Path $saved 'wow_tools.lua'),(($lines+@('}')) -join "`r`n"),(New-Object Text.UTF8Encoding($false)))
}
