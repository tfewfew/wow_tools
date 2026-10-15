$originalLogSize=$script:logMaxSizeMB
$originalIni=if ([IO.File]::Exists($script:settingsPath)) {[IO.File]::ReadAllText($script:settingsPath)} else {$null}
try {
    $t=$script:versionRanges.titan;$f=$script:versionRanges.forerver
    Set-VersionWaitRanges $t.MinimumMs $t.MaximumMs $f.MinimumMs $f.MaximumMs -LogMaxSizeMB 2
    Assert-Ui ($script:logMaxSizeMB -eq 2 -and $script:wowAutoLog.MaxSizeMB -eq 2 -and
        (Read-WowAutoSettingsIni $script:settingsPath).LogMaxSizeMB -eq 2) 'INI size setting was not persisted and applied.'
    $saved=[IO.File]::ReadAllText($script:settingsPath)
    foreach ($bad in @('0','1025','1.5')) {
        $rejected=$false
        try {Set-VersionWaitRanges $t.MinimumMs $t.MaximumMs $f.MinimumMs $f.MaximumMs -LogMaxSizeMB $bad} catch {$rejected=$true}
        Assert-Ui ($rejected -and $script:logMaxSizeMB -eq 2 -and
            [IO.File]::ReadAllText($script:settingsPath) -ceq $saved) 'Invalid size setting partially applied.'
    }
    $legacy=$saved -replace '(?m)^LogMaxSizeMB=.*\r?\n?',''
    [IO.File]::WriteAllText($script:settingsPath,$legacy)
    Assert-Ui ((Read-WowAutoSettingsIni $script:settingsPath).LogMaxSizeMB -eq 2 -and
        [IO.File]::ReadAllText($script:settingsPath) -ceq $legacy) 'Old INI without file-log size was rewritten or rejected.'
    Write-Output 'PASS: file-log MB setting persists, rejects invalid drafts and reads old INI without rewriting. Temporary configuration only.'
}
finally {
    $script:logMaxSizeMB=$originalLogSize
    $null=Set-WowAutoLogSizeMB $originalLogSize
    if ($null -eq $originalIni) {if ([IO.File]::Exists($script:settingsPath)) {[IO.File]::Delete($script:settingsPath)}}
    else {[IO.File]::WriteAllText($script:settingsPath,$originalIni)}
}
