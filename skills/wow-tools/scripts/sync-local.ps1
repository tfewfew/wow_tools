param(
    [ValidateSet('all','titan','forerver')][string]$Flavor='all',
    [string]$GameRoot,
    [string]$TitanGameRoot='C:\Program Files (x86)\World of Warcraft\_classic_titan_',
    [string]$ForerverGameRoot='C:\Program Files (x86)\World of Warcraft\_cn_beta_'
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

. (Join-Path $PSScriptRoot 'client-profiles.ps1')
$profiles=@(Get-WowToolsDeploymentProfiles -RepoRoot $repo -Flavor $Flavor -GameRoot $GameRoot -TitanGameRoot $TitanGameRoot -ForerverGameRoot $ForerverGameRoot)
# Validate all requested clients and sources before writing to either installation.
foreach ($profile in $profiles) {
    $clientExe=Join-Path $profile.GameRoot $profile.Executable
    if (-not (Test-Path -LiteralPath $clientExe -PathType Leaf)) { throw "Client executable missing: $clientExe" }
    $version=[Diagnostics.FileVersionInfo]::GetVersionInfo($clientExe).FileVersion
    if (-not (Test-WowToolsClientVersion $profile $version)) { throw "Wrong client for $($profile.Flavor): $version" }
    $toc=Join-Path $profile.Source 'wow_tools.toc'
    if (-not (Test-Path -LiteralPath $toc -PathType Leaf)) { throw "Addon source missing: $toc" }
    if (-not (Select-String -LiteralPath $toc -Pattern "^## Interface:\s*$($profile.Interface)\s*$" -Quiet)) {
        throw "Source TOC does not match $($profile.Flavor) interface $($profile.Interface)."
    }
}
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

foreach ($profile in $profiles) {
    New-Item -ItemType Directory -Path $profile.Target -Force | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $profile.Source -File -Recurse) {
        $relative=$file.FullName.Substring($profile.Source.Length + 1)
        Copy-Verified $file.FullName (Join-Path $profile.Target $relative) (Join-Path "$($profile.Flavor)\wow_tools" $relative)
    }
    # Retire the exact former login-marker module after the new TOC is verified.
    $retiredRotation=Join-Path $profile.Target 'Rotation.lua'
    if (-not (Test-Path -LiteralPath (Join-Path $profile.Source 'Rotation.lua')) -and (Test-Path -LiteralPath $retiredRotation -PathType Leaf)) {
        $retiredBackup=Join-Path $backup "$($profile.Flavor)\retired-Rotation.lua"
        Copy-Item -LiteralPath $retiredRotation -Destination $retiredBackup
        if ((Get-FileHash -LiteralPath $retiredRotation).Hash -ne (Get-FileHash -LiteralPath $retiredBackup).Hash) {throw 'Retired rotation marker backup failed.'}
        Remove-Item -LiteralPath $retiredRotation
    }
}
& (Join-Path $PSScriptRoot 'install-desktop-shortcut.ps1') `
    -ToolRoot (Join-Path $repo 'tools\wowAuto') -DesktopPath $desktop -BackupPath (Join-Path $backup 'Desktop')

# The addon filename changed, but the saved table remains wowDetectorDB.
# Import existing on-disk settings once; never overwrite newer wow_tools settings.
foreach ($profile in $profiles) {
    $accountsPath=Join-Path $profile.GameRoot 'WTF\Account'
    if (Test-Path -LiteralPath $accountsPath) {
        foreach ($account in Get-ChildItem -LiteralPath $accountsPath -Directory) {
            $savedPath = Join-Path $account.FullName 'SavedVariables'
            $oldSettings = Join-Path $savedPath 'wowDetector.lua'
            $newSettings = Join-Path $savedPath 'wow_tools.lua'
            if ((Test-Path -LiteralPath $oldSettings) -and -not (Test-Path -LiteralPath $newSettings)) {
                Copy-Verified $oldSettings $newSettings (Join-Path "$($profile.Flavor)\SavedVariables\$($account.Name)" 'wow_tools.lua')
            }
        }
    }
}

# Retire standalone addons only after new files have been copied and verified.
foreach ($profile in $profiles) {
    $profileBackup=[IO.Path]::GetFullPath((Join-Path $backup $profile.Flavor))
    if ((Split-Path $profileBackup -Parent) -ne $backup) { throw 'Client backup path check failed.' }
    New-Item -ItemType Directory -Path $profileBackup -Force | Out-Null
    foreach ($legacyName in @('FishingState', 'wowDetector', 'Inner_graphic_config')) {
        $legacyAddon = [IO.Path]::GetFullPath((Join-Path $profile.AddOns $legacyName))
        $legacyBackup = [IO.Path]::GetFullPath((Join-Path $profileBackup $legacyName))
        if ((Split-Path $legacyAddon -Parent) -ne $profile.AddOns -or
            (Split-Path $legacyBackup -Parent) -ne $profileBackup) { throw 'Legacy addon archive path check failed.' }
        if (Test-Path -LiteralPath $legacyAddon) {
            Move-Item -LiteralPath $legacyAddon -Destination $legacyBackup
        }
    }
}

foreach ($profile in $profiles) { Write-Output "Synced pushed commit $headCommit ($($profile.Flavor)) to $($profile.Target)." }
Write-Output "Desktop shortcut updated: $desktop."
Write-Output "Backups: $backup"
