function Write-TestCharacterRecord([string]$Directory,[string]$Name,[string]$Realm,[int]$Level=80,[int]$FreeBagSlots=12,[long]$RecordedAt=1792200000,[int]$Version=1,[string]$Professions='?',[string]$SecondarySkills='?',[string]$BindLocation='?') {
    $saved=Join-Path $Directory 'SavedVariables';[void][IO.Directory]::CreateDirectory($saved)
    $fields=[ordered]@{version=$Version;name=$Name;realm=$Realm;level=$Level;freeBagSlots=$FreeBagSlots;recordedAt=$RecordedAt}
    if($Version -in @(2,3)){$fields.professions=$Professions;$fields.secondarySkills=$SecondarySkills}
    if($Version -eq 3){$fields.bindLocation=$BindLocation}
    $lines=@('wowToolsCharacterRecord = {')
    foreach ($key in $fields.Keys) {
        $value=$fields[$key]
        if ($value -is [string]) {$value='"'+$value.Replace('\','\\').Replace('"','\"')+'"'}
        $lines+=('    ["{0}"] = {1},' -f $key,$value)
    }
    [IO.File]::WriteAllText((Join-Path $saved 'wow_tools.lua'),(($lines+@('}')) -join "`r`n"),(New-Object Text.UTF8Encoding($false)))
}
