$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\sync-lstoasts.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('wow-tools-toast-sync-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $fixture 'source\ls_toasts'
$target = Join-Path $fixture 'installed\ls_toasts'
$backup = Join-Path $fixture 'backup'
try {
    New-Item -ItemType Directory -Path $source, (Join-Path $target 'core') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $source 'current.lua'), 'upstream')
    [IO.File]::WriteAllText((Join-Path $target 'current.lua'), 'upstream')
    [IO.File]::WriteAllText((Join-Path $target 'core\obsolete.lua'), 'previous patch')
    $retired = Remove-WowToolsRetiredToastFiles $source $target $backup
    if ($retired -ne 1 -or (Test-Path -LiteralPath (Join-Path $target 'core\obsolete.lua')) -or
        [IO.File]::ReadAllText((Join-Path $backup 'core\obsolete.lua')) -ne 'previous patch' -or
        [IO.File]::ReadAllText((Join-Path $target 'current.lua')) -ne 'upstream') { throw 'Upgrade cleanup lost source files or backups.' }
    if ((Remove-WowToolsRetiredToastFiles $source $target $backup) -ne 0) { throw 'Repeated sync was not idempotent.' }
    $rejected = $false
    try { Remove-WowToolsRetiredToastFiles $source $source $backup } catch { $rejected = $true }
    if (-not $rejected) { throw 'Shared source/target was accepted.' }
    [IO.File]::WriteAllText((Join-Path $target 'obsolete.lua'), 'retain on failure')
    $blockedBackup = Join-Path $fixture 'blocked-backup'
    [IO.File]::WriteAllText($blockedBackup, 'file')
    $rejected = $false
    try { Remove-WowToolsRetiredToastFiles $source $target $blockedBackup } catch { $rejected = $true }
    if (-not $rejected -or -not (Test-Path -LiteralPath (Join-Path $target 'obsolete.lua'))) { throw 'Backup failure removed installed files.' }
    Write-Output 'PASS: ls_Toasts obsolete-file backup, cleanup, repeated sync, source isolation and backup-failure protection. Temporary fixtures only.'
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    if ((Split-Path $resolved -Parent) -ne [IO.Path]::GetTempPath().TrimEnd('\')) { throw 'Fixture cleanup path check failed.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
