# Parse SavedVariables as literal data. Never execute a settings file.
function Read-WowLuaData([string]$Text) {
    if ($Text.Length -gt 16MB) { throw 'SavedVariables exceeds the migration size limit.' }
    $pattern = '\G(?:(?<space>\s+|--[^\r\n]*)|(?<string>"(?:[^"\\]|\\.)*"|''(?:[^''\\]|\\.)*'')|(?<number>-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)|(?<name>[A-Za-z_]\w*)|(?<symbol>[{}\[\]=,;]))'
    $reader = [regex]::new($pattern, [Text.RegularExpressions.RegexOptions]::None, [timespan]::FromSeconds(2))
    $tokens = [Collections.Generic.List[object]]::new()
    $position = 0
    while ($position -lt $Text.Length) {
        $match = $reader.Match($Text, $position)
        if (-not $match.Success -or $match.Index -ne $position) { throw 'Settings contain non-literal Lua.' }
        if (-not $match.Groups['space'].Success) {
            $kind = if ($match.Groups['string'].Success) { 'string' }
                elseif ($match.Groups['number'].Success) { 'number' }
                elseif ($match.Groups['name'].Success) { 'name' } else { 'symbol' }
            $tokens.Add([pscustomobject]@{Kind=$kind; Text=$match.Value; Start=$position; End=$position+$match.Length})
        }
        $position += $match.Length
    }
    $cursor = [pscustomobject]@{Tokens=$tokens; Index=0}
    $assignments = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    while ($cursor.Index -lt $tokens.Count) {
        $name = $tokens[$cursor.Index++]
        if ($name.Kind -ne 'name' -or $assignments.ContainsKey($name.Text)) { throw 'Invalid settings assignment.' }
        Assert-WowLuaToken $cursor '='
        $assignments.Add($name.Text, (Read-WowLuaValue $cursor 0))
    }
    return ,$assignments
}

function Assert-WowLuaToken($Cursor, [string]$Expected) {
    if ($Cursor.Index -ge $Cursor.Tokens.Count -or $Cursor.Tokens[$Cursor.Index].Text -cne $Expected) {
        throw "Expected Lua token $Expected."
    }
    $Cursor.Index++
}

function Read-WowLuaValue($Cursor, [int]$Depth) {
    if ($Depth -gt 64 -or $Cursor.Index -ge $Cursor.Tokens.Count) { throw 'Invalid settings nesting.' }
    $token = $Cursor.Tokens[$Cursor.Index++]
    if ($token.Text -ceq '{') {
        $fields = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        $arrayIndex = 0
        while ($Cursor.Index -lt $Cursor.Tokens.Count -and $Cursor.Tokens[$Cursor.Index].Text -cne '}') {
            $key = $Cursor.Tokens[$Cursor.Index]
            if ($key.Text -ceq '[') {
                $Cursor.Index++
                $key = $Cursor.Tokens[$Cursor.Index++]
                if ($key.Kind -notin @('string','number')) { throw 'Invalid settings table key.' }
                Assert-WowLuaToken $Cursor ']'
                Assert-WowLuaToken $Cursor '='
                $fieldName = $key.Text.Trim('"', "'")
            } elseif ($key.Kind -eq 'name' -and $Cursor.Index+1 -lt $Cursor.Tokens.Count -and
                $Cursor.Tokens[$Cursor.Index+1].Text -ceq '=') {
                $Cursor.Index += 2
                $fieldName = $key.Text
            } else {
                $fieldName = '#' + (++$arrayIndex)
            }
            $value = Read-WowLuaValue $Cursor ($Depth+1)
            if ($fields.ContainsKey($fieldName)) { throw 'Duplicate settings table key.' }
            $fields.Add($fieldName, $value)
            if ($Cursor.Index -lt $Cursor.Tokens.Count -and $Cursor.Tokens[$Cursor.Index].Text -cin @(',', ';')) {
                $Cursor.Index++
            } elseif ($Cursor.Index -ge $Cursor.Tokens.Count -or $Cursor.Tokens[$Cursor.Index].Text -cne '}') {
                throw 'Missing settings table separator.'
            }
        }
        $needsSeparator = $Cursor.Tokens[$Cursor.Index-1].Text -cnotin @('{', ',', ';')
        Assert-WowLuaToken $Cursor '}'
        return [pscustomobject]@{Kind='table'; Start=$token.Start; End=$Cursor.Tokens[$Cursor.Index-1].End; Fields=$fields; NeedsSeparator=$needsSeparator}
    }
    if ($token.Kind -notin @('string','number') -and $token.Text -cnotin @('true','false','nil')) {
        throw 'Settings value is not literal data.'
    }
    return [pscustomobject]@{Kind=$token.Kind; Start=$token.Start; End=$token.End; Fields=$null}
}

function Merge-WowAddonSettingsGroup([string]$SavedPath, [string]$BackupPath, [string]$GroupKey, $LegacyMappings) {
    $target = Join-Path $SavedPath 'wow_tools.lua'
    $text = if (Test-Path -LiteralPath $target) { [IO.File]::ReadAllText($target) } else { '' }
    $tables = Read-WowLuaData $text
    $detector = $tables['wowDetectorDB']
    if ($detector -and $detector.Kind -ne 'table') { throw 'wowDetectorDB must be a literal table.' }
    if ($detector -and $detector.Fields.ContainsKey($GroupKey)) { return $false }
    $entries = @()
    foreach ($legacy in $LegacyMappings) {
        $source = Join-Path $SavedPath $legacy.File
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
        $sourceText = [IO.File]::ReadAllText($source)
        $legacyTables = Read-WowLuaData $sourceText
        $node = $legacyTables[$legacy.Global]
        if (-not $node) { continue }
        if ($node.Kind -ne 'table') { throw "Legacy $($legacy.Global) must be a literal table." }
        $entries += '["' + $legacy.Key + '"] = ' + $sourceText.Substring($node.Start, $node.End-$node.Start)
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        $copy = Join-Path $BackupPath $legacy.File
        Copy-Item -LiteralPath $source -Destination $copy
        if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $copy).Hash) {
            throw 'Legacy addon settings backup verification failed.'
        }
    }
    if (-not $entries.Count) { return $false }
    $data = '["' + $GroupKey + '"] = {' + "`n" + ($entries -join ",`n") + ",`n" + '["migrationVersion"] = 1,' + "`n}"
    if ($detector) {
        $separator = if ($detector.NeedsSeparator) { ',' } else { '' }
        $merged = $text.Insert($detector.End-1, $separator + "`n" + $data + ",`n")
    } else { $merged = $text + "`nwowDetectorDB = {`n" + $data + "`n}`n" }
    $null = Read-WowLuaData $merged
    New-Item -ItemType Directory -Path $SavedPath -Force | Out-Null
    $temporary = Join-Path $SavedPath ('wow_tools-migrate-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporary, $merged, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $target) {
            if ([IO.File]::ReadAllText($target) -cne $text) { throw 'Settings changed during addon migration. Retry sync.' }
            Copy-Item -LiteralPath $target -Destination (Join-Path $BackupPath 'wow_tools.lua')
            if ((Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath (Join-Path $BackupPath 'wow_tools.lua')).Hash) {
                throw 'Existing wow_tools settings backup verification failed.'
            }
            [IO.File]::Replace($temporary, $target, [Management.Automation.Language.NullString]::Value)
        } else { [IO.File]::Move($temporary, $target) }
        if ([IO.File]::ReadAllText($target) -cne $merged) { throw 'Addon settings migration verification failed.' }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    }
    return $true
}

function Merge-WowBigFootSettings([string]$SavedPath, [string]$BackupPath) {
    return Merge-WowAddonSettingsGroup $SavedPath $BackupPath 'bigfootChannel' @(
        @{File='BigFootChat.lua'; Global='BFCDB'; Key='chat'},
        @{File='ChannelFilter.lua'; Global='ChannelFilter_Config'; Key='filter'}
    )
}

function Merge-WowLsToastsSettings([string]$SavedPath, [string]$BackupPath) {
    return Merge-WowAddonSettingsGroup $SavedPath $BackupPath 'lsToasts' @(
        @{File='ls_Toasts.lua'; Global='LS_TOASTS_GLOBAL_CONFIG'; Key='db'}
    )
}
