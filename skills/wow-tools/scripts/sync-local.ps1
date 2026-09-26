param(
    [string]$GameRoot = 'C:\Program Files (x86)\World of Warcraft\_classic_titan_'
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$status = & git -C $repo status --porcelain
if ($LASTEXITCODE -ne 0) { throw 'Cannot read Git status.' }
if ($status) { throw 'Commit and push all intended changes before syncing; working tree must be clean.' }
$branch = & git -C $repo symbolic-ref --quiet --short HEAD
if ($LASTEXITCODE -ne 0) { throw 'A named branch is required.' }
$headCommit = & git -C $repo rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'No commit available.' }
$remoteRef = & git -C $repo ls-remote --exit-code origin "refs/heads/$branch"
if ($LASTEXITCODE -ne 0 -or -not $remoteRef) { throw 'Cannot verify remote branch. Push successfully before syncing.' }
$remoteCommit = ($remoteRef -split '\s+')[0]
if ($remoteCommit -ne $headCommit) { throw 'Local HEAD is not the current remote branch commit; push before syncing.' }

$gamePath = [IO.Path]::GetFullPath($GameRoot)
if (-not (Test-Path -LiteralPath (Join-Path $gamePath 'WowClassic.exe'))) { throw 'GameRoot must contain WowClassic.exe.' }
$addonsPath = [IO.Path]::GetFullPath((Join-Path $gamePath 'Interface\AddOns'))
$targetAddon = Join-Path $addonsPath 'wowDetector'
$desktop = [Environment]::GetFolderPath('Desktop')
$backup = Join-Path $repo ('.local-backups\' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null

function Copy-Verified([string]$Source, [string]$Destination, [string]$BackupName) {
    if (Test-Path -LiteralPath $Destination) {
        Copy-Item -LiteralPath $Destination -Destination (Join-Path $backup $BackupName)
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    if ((Get-FileHash -LiteralPath $Source).Hash -ne (Get-FileHash -LiteralPath $Destination).Hash) {
        throw "Copy verification failed: $Destination"
    }
}

New-Item -ItemType Directory -Path $targetAddon -Force | Out-Null
foreach ($name in @('wowDetector.lua', 'wowDetector.toc')) {
    Copy-Verified (Join-Path $repo "addon\wowDetector\$name") (Join-Path $targetAddon $name) $name
}
foreach ($name in @('wowAuto.ps1', 'wowAuto.bat')) {
    Copy-Verified (Join-Path $repo "tools\wowAuto\$name") (Join-Path $desktop $name) $name
}

# Retire the old addon only after the new files have been copied and verified.
$legacyAddon = [IO.Path]::GetFullPath((Join-Path $addonsPath 'FishingState'))
$legacyBackup = [IO.Path]::GetFullPath((Join-Path $backup 'FishingState'))
if ((Split-Path $legacyAddon -Parent) -ne $addonsPath -or
    (Split-Path $legacyBackup -Parent) -ne $backup) { throw 'Legacy addon archive path check failed.' }
if (Test-Path -LiteralPath $legacyAddon) {
    Move-Item -LiteralPath $legacyAddon -Destination $legacyBackup
}

# Keep familiar desktop entry points while maintaining only one implementation.
$legacyPs = Join-Path $desktop 'wow-foreground-loop.ps1'
$legacyBat = Join-Path $desktop 'wow-foreground-loop.bat'
foreach ($path in @($legacyPs, $legacyBat)) {
    if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination (Join-Path $backup (Split-Path $path -Leaf)) }
}
Set-Content -LiteralPath $legacyPs -Encoding UTF8 -Value '& (Join-Path $PSScriptRoot ''wowAuto.ps1'')'
Set-Content -LiteralPath $legacyBat -Encoding ASCII -Value "@echo off`r`ncall `"%~dp0wowAuto.bat`""
Write-Output "Synced pushed commit $headCommit to $targetAddon and $desktop."
Write-Output "Backups: $backup"
