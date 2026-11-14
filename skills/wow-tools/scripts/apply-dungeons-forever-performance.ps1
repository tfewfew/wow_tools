param(
    [string]$GameRoot = 'C:\Program Files (x86)\World of Warcraft\_forever_',
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$patchRoot = Join-Path $PSScriptRoot '..\patches\dungeons-forever-2.1.95'
$patch = [IO.Path]::GetFullPath((Join-Path $patchRoot 'performance.patch'))
$manifestPath = Join-Path $patchRoot 'manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $patch -Algorithm SHA256).Hash -ne $manifest.patchSha256) {
    throw 'Performance patch hash mismatch.'
}

. (Join-Path $PSScriptRoot 'client-profiles.ps1')
$profile = Get-WowToolsDeploymentProfiles -RepoRoot $repo -Flavor forerver -GameRoot $GameRoot
$executable = Join-Path $profile.GameRoot $profile.Executable
$version = [Diagnostics.FileVersionInfo]::GetVersionInfo($executable).FileVersion
if (-not (Test-WowToolsClientVersion $profile $version)) { throw "Wrong Forever client version $version." }
$mutex = [Threading.Mutex]::new($false, 'Local\WowTools.DungeonsForever.Performance')
$locked = $false
try {
    try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { throw 'Another DungeonsForever patch operation is running.' }
    foreach ($addon in $manifest.versions.PSObject.Properties) {
        $toc = Join-Path $profile.AddOns "$($addon.Name)\$($addon.Name).toc"
        $metadata = Get-Content -LiteralPath $toc -Encoding UTF8
        if (-not ($metadata -match ('^## Version:\s*' + [regex]::Escape($addon.Value) + '\s*$'))) {
            throw "Unsupported addon version in $toc. Rebase the maintained patch for the installed release."
        }
        $interfaces = ($metadata | Where-Object { $_ -match '^## Interface:' }) -replace '^## Interface:\s*', ''
        if (@($interfaces -split ',\s*') -notcontains [string]$profile.Interface) { throw "Forever interface missing in $toc." }
    }

    $pending = @()
    foreach ($entry in $manifest.files) {
        $target = [IO.Path]::GetFullPath((Join-Path $profile.AddOns $entry.path))
        if (-not $target.StartsWith($profile.AddOns + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Invalid patch target $target."
        }
        $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        if ($hash -eq $entry.patchedSha256) { continue }
        if ($hash -ne $entry.originalSha256) { throw "Unknown source hash for $target. Preserve and review the installed changes first." }
        $pending += $entry
    }
    if ($pending.Count -eq 0) { Write-Output "All $($manifest.files.Count) DungeonsForever performance files are already patched and verified."; return }

    if (-not $CheckOnly) {
        $branch = & git -C $repo branch --show-current
        if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Deploy the merged patch from main.' }
        & git -C $repo diff --quiet HEAD -- $patchRoot $PSCommandPath (Join-Path $PSScriptRoot 'client-profiles.ps1')
        if ($LASTEXITCODE -ne 0) { throw 'Commit the maintained patch and deployment helper before applying.' }
        $headCommit = & git -C $repo rev-parse HEAD
        if ($LASTEXITCODE -ne 0) { throw 'Cannot read the deployment commit.' }
        $remoteRef = & git -C $repo ls-remote --exit-code origin refs/heads/main
        if ($LASTEXITCODE -ne 0 -or -not $remoteRef -or ($remoteRef -split '\s+')[0] -ne $headCommit) {
            throw 'Push and synchronize main before deployment.'
        }
    }

    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $stage = Join-Path $tempRoot ('wow-tools-df-performance-' + [guid]::NewGuid().ToString('N'))
    $backup = $null
    $written = @()
    $replacementFiles = @()
    try {
        New-Item -ItemType Directory -Path $stage | Out-Null
        foreach ($entry in $pending) {
            $copy = Join-Path $stage $entry.path
            New-Item -ItemType Directory -Path (Split-Path $copy -Parent) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $profile.AddOns $entry.path) -Destination $copy
        }
        $applyArguments = @('-c', 'core.autocrlf=false', '-C', $stage, 'apply', '--whitespace=nowarn')
        foreach ($entry in $pending) { $applyArguments += "--include=$($entry.path)" }
        & git @applyArguments --check $patch
        if ($LASTEXITCODE -ne 0) { throw 'Patch preflight failed.' }
        & git @applyArguments $patch
        if ($LASTEXITCODE -ne 0) { throw 'Patch staging failed.' }
        foreach ($entry in $pending) {
            if ((Get-FileHash -LiteralPath (Join-Path $stage $entry.path) -Algorithm SHA256).Hash -ne $entry.patchedSha256) {
                throw "Patched hash mismatch for $($entry.path)."
            }
        }
        if ($CheckOnly) { Write-Output "Verified patch applicability and output hashes for $($pending.Count) files. Game files were read only."; return }

        $backup = Join-Path $repo ('.local-backups\dungeons-forever\' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $backup 'manifest.json')
        foreach ($entry in $pending) {
            $saved = Join-Path $backup $entry.path
            New-Item -ItemType Directory -Path (Split-Path $saved -Parent) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $profile.AddOns $entry.path) -Destination $saved
            if ((Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash -ne $entry.originalSha256) {
                throw "Backup hash mismatch for $($entry.path)."
            }
        }
        foreach ($entry in $pending) {
            $target = Join-Path $profile.AddOns $entry.path
            if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $entry.originalSha256) {
                throw "Source changed during deployment for $($entry.path)."
            }
            $replacement = $target + '.wow-tools-' + [guid]::NewGuid().ToString('N')
            $replacementFiles += $replacement
            Copy-Item -LiteralPath (Join-Path $stage $entry.path) -Destination $replacement
            [IO.File]::Replace($replacement, $target, [Management.Automation.Language.NullString]::Value)
            $written += $entry
        }
        foreach ($entry in $manifest.files) {
            if ((Get-FileHash -LiteralPath (Join-Path $profile.AddOns $entry.path) -Algorithm SHA256).Hash -ne $entry.patchedSha256) {
                throw "Deployment verification failed for $($entry.path)."
            }
        }
        Write-Output "Applied and verified $($pending.Count) DungeonsForever performance files from main $headCommit."
        Write-Output "Backups saved in $backup"
        Write-Output 'Reload the game UI to load the new scan intervals.'
    } catch {
        $failure = $_
        foreach ($entry in $written) {
            $target = Join-Path $profile.AddOns $entry.path
            try {
                $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
                if ($hash -eq $entry.originalSha256) { continue }
                if ($hash -ne $entry.patchedSha256) { throw 'The file changed externally after deployment.' }
                Copy-Item -LiteralPath (Join-Path $backup $entry.path) -Destination $target -Force
                if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $entry.originalSha256) { throw 'Restored hash mismatch.' }
            } catch {
                Write-Warning "Restore failed for $target. Backup directory is $backup. $($_.Exception.Message)"
            }
        }
        throw $failure
    } finally {
        foreach ($path in $replacementFiles) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        }
        $resolvedStage = [IO.Path]::GetFullPath($stage)
        if ([IO.Path]::GetDirectoryName($resolvedStage) -ne $tempRoot -or
            -not [IO.Path]::GetFileName($resolvedStage).StartsWith('wow-tools-df-performance-')) { throw 'Unsafe temporary cleanup path.' }
        if (Test-Path -LiteralPath $resolvedStage) { Remove-Item -LiteralPath $resolvedStage -Recurse -Force }
    }
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
