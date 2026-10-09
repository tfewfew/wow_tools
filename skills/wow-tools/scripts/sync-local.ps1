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
$targetAddon = Join-Path $addonsPath 'wow_tools'
$desktop = [Environment]::GetFolderPath('Desktop')
$backup = Join-Path $repo ('.local-backups\' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null

function Copy-Verified([string]$Source, [string]$Destination, [string]$BackupName) {
    New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
    if (Test-Path -LiteralPath $Destination) {
        New-Item -ItemType Directory -Path (Split-Path (Join-Path $backup $BackupName) -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $Destination -Destination (Join-Path $backup $BackupName)
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    if ((Get-FileHash -LiteralPath $Source).Hash -ne (Get-FileHash -LiteralPath $Destination).Hash) {
        throw "Copy verification failed: $Destination"
    }
}

New-Item -ItemType Directory -Path $targetAddon -Force | Out-Null
$addonSource = Join-Path $repo 'addon\wow_tools'
foreach ($file in Get-ChildItem -LiteralPath $addonSource -File -Recurse) {
    $relative = $file.FullName.Substring($addonSource.Length + 1)
    Copy-Verified $file.FullName (Join-Path $targetAddon $relative) (Join-Path 'wow_tools' $relative)
}
& (Join-Path $PSScriptRoot 'install-desktop-shortcut.ps1') `
    -ToolRoot (Join-Path $repo 'tools\wowAuto') -DesktopPath $desktop -BackupPath (Join-Path $backup 'Desktop')

# The addon filename changed, but the saved table remains wowDetectorDB.
# Import existing on-disk settings once; never overwrite newer wow_tools settings.
$accountsPath = Join-Path $gamePath 'WTF\Account'
if (Test-Path -LiteralPath $accountsPath) {
    foreach ($account in Get-ChildItem -LiteralPath $accountsPath -Directory) {
        $savedPath = Join-Path $account.FullName 'SavedVariables'
        $oldSettings = Join-Path $savedPath 'wowDetector.lua'
        $newSettings = Join-Path $savedPath 'wow_tools.lua'
        if ((Test-Path -LiteralPath $oldSettings) -and -not (Test-Path -LiteralPath $newSettings)) {
            Copy-Verified $oldSettings $newSettings (Join-Path "SavedVariables\$($account.Name)" 'wow_tools.lua')
        }
    }
}

# Retire standalone addons only after new files have been copied and verified.
foreach ($legacyName in @('FishingState', 'wowDetector', 'Inner_graphic_config')) {
    $legacyAddon = [IO.Path]::GetFullPath((Join-Path $addonsPath $legacyName))
    $legacyBackup = [IO.Path]::GetFullPath((Join-Path $backup $legacyName))
    if ((Split-Path $legacyAddon -Parent) -ne $addonsPath -or
        (Split-Path $legacyBackup -Parent) -ne $backup) { throw 'Legacy addon archive path check failed.' }
    if (Test-Path -LiteralPath $legacyAddon) {
        Move-Item -LiteralPath $legacyAddon -Destination $legacyBackup
    }
}

Write-Output "Synced pushed commit $headCommit to $targetAddon and $desktop."
Write-Output "Backups: $backup"
