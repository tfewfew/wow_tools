param(
    [ValidateSet('all','titan','forerver')][string]$Flavor = 'all',
    [string]$GameRoot,
    [string]$TitanGameRoot = 'C:\Program Files (x86)\World of Warcraft\_classic_titan_',
    [string]$ForerverGameRoot = 'C:\Program Files (x86)\World of Warcraft\_forever_',
    [string]$Python,
    [string]$ReportPath,
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$registry = Join-Path $PSScriptRoot 'scripts\registry.py'
if (-not $Python) {
    $command = Get-Command python -ErrorAction SilentlyContinue
    if ($command -and $command.Source -notlike '*\Microsoft\WindowsApps\*') { $Python = $command.Source }
    if (-not $Python) {
        $runtimes = Get-AppxPackage -Name 'OpenAI.CodexPrimaryRuntime*' | Sort-Object Version -Descending
        $Python = $runtimes | ForEach-Object { Join-Path $_.InstallLocation 'dependencies\python\python.exe' } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    }
    if (-not $Python) { throw 'Pass -Python with an available Python 3.9+ executable.' }
}
. (Join-Path $repo 'skills\wow-tools\scripts\client-profiles.ps1')
$profiles = @(Get-WowToolsDeploymentProfiles -RepoRoot $repo -Flavor $Flavor -GameRoot $GameRoot -TitanGameRoot $TitanGameRoot -ForerverGameRoot $ForerverGameRoot)
$mutex = [Threading.Mutex]::new($false, 'Local\WowTools.AddonFix')
$locked = $false
$reports = @()
$needsReview = $false
try {
    try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { throw 'Another addon repair operation is running.' }
    foreach ($profile in $profiles) {
        $executable = Join-Path $profile.GameRoot $profile.Executable
        if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
            $reports += [pscustomobject]@{ client = $profile.Flavor; status = 'client-absent'; gameRoot = $profile.GameRoot }
            Write-Output "$($profile.Flavor): client absent in $($profile.GameRoot)."
            continue
        }
        $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($executable).FileVersion
        if (-not (Test-WowToolsClientVersion $profile $version)) { throw "Wrong $($profile.Flavor) client version $version." }
        $inspection = & $Python $registry inspect --flavor $profile.Flavor --addons-root $profile.AddOns
        if ($LASTEXITCODE -ne 0) { throw "Cannot inspect $($profile.Flavor) addons." }
        $report = $inspection | ConvertFrom-Json
        $reports += $report
        $installedCount = @($report.installed.PSObject.Properties).Count
        Write-Output "$($profile.Flavor): inspected $installedCount installed addons and $($report.patches.Count) mapped patches."
        $operations = @()
        foreach ($result in $report.patches) {
            Write-Output "$($profile.Flavor)/$($result.plugin)/$($result.patch): $($result.status) (version $($result.version))."
            if ($result.status -eq 'review') {
                $needsReview = $true
                Write-Warning $result.reason
            }
            if ($result.status -eq 'applicable') {
                $manifest = Get-Content -LiteralPath $result.manifest -Raw -Encoding UTF8 | ConvertFrom-Json
                $operations += [pscustomobject]@{ result = $result; manifest = $manifest; patch = Join-Path (Split-Path $result.manifest -Parent) $manifest.patch }
            }
        }
        if ($operations.Count -eq 0) { continue }
        if (-not $CheckOnly) {
            $branch = & git -C $repo branch --show-current
            if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Apply merged repairs from main.' }
            & git -C $repo diff --quiet HEAD -- addon_fix skills/addon-fix skills/wow-tools/scripts/client-profiles.ps1
            if ($LASTEXITCODE -ne 0) { throw 'Commit the registry and repair implementation before applying.' }
            $headCommit = & git -C $repo rev-parse HEAD
            if ($LASTEXITCODE -ne 0) { throw 'Cannot read the deployment commit.' }
            $remoteRef = & git -C $repo ls-remote --exit-code origin refs/heads/main
            if ($LASTEXITCODE -ne 0 -or -not $remoteRef -or ($remoteRef -split '\s+')[0] -ne $headCommit) { throw 'Push and synchronize main before applying.' }
        }
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
        $stage = Join-Path $tempRoot ('wow-tools-addon-fix-' + [guid]::NewGuid().ToString('N'))
        $written = @()
        $replacementFiles = @()
        $pendingFiles = @{}
        $backup = $null
        try {
            New-Item -ItemType Directory -Path $stage | Out-Null
            foreach ($operation in $operations) {
                foreach ($entry in $operation.result.pendingFiles) {
                    $copy = Join-Path $stage $entry.path
                    if (-not (Test-Path -LiteralPath $copy)) {
                        New-Item -ItemType Directory -Path (Split-Path $copy -Parent) -Force | Out-Null
                        Copy-Item -LiteralPath (Join-Path $profile.AddOns $entry.path) -Destination $copy
                    }
                    $pendingFiles[$entry.path] = $entry
                }
                $arguments = @('-c', 'core.autocrlf=false', '-C', $stage, 'apply', '--whitespace=nowarn')
                foreach ($entry in $operation.result.pendingFiles) { $arguments += "--include=$($entry.path)" }
                & git @arguments --check $operation.patch
                if ($LASTEXITCODE -ne 0) { throw "Patch preflight failed for $($operation.result.plugin)." }
                & git @arguments $operation.patch
                if ($LASTEXITCODE -ne 0) { throw "Patch staging failed for $($operation.result.plugin)." }
                foreach ($entry in $operation.result.pendingFiles) {
                    if ((Get-FileHash -LiteralPath (Join-Path $stage $entry.path) -Algorithm SHA256).Hash -ne $entry.patchedSha256) { throw "Staged hash mismatch for $($entry.path)." }
                }
            }
            if ($CheckOnly) { Write-Output "$($profile.Flavor): verified applicability and output hashes for $($pendingFiles.Count) files."; continue }
            $backup = Join-Path $repo ('.local-backups\addon_fix\' + $profile.Flavor + '\' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $backup -Force | Out-Null
            $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $backup 'plan.json') -Encoding UTF8
            foreach ($entry in $pendingFiles.Values) {
                $saved = Join-Path $backup $entry.path
                New-Item -ItemType Directory -Path (Split-Path $saved -Parent) -Force | Out-Null
                Copy-Item -LiteralPath (Join-Path $profile.AddOns $entry.path) -Destination $saved
                if ((Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash -ne $entry.originalSha256) { throw "Backup hash mismatch for $($entry.path)." }
            }
            foreach ($entry in $pendingFiles.Values) {
                $target = Join-Path $profile.AddOns $entry.path
                if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $entry.originalSha256) { throw "Source changed while applying $($entry.path)." }
                $replacement = $target + '.wow-tools-' + [guid]::NewGuid().ToString('N')
                $replacementFiles += $replacement
                Copy-Item -LiteralPath (Join-Path $stage $entry.path) -Destination $replacement
                [IO.File]::Replace($replacement, $target, [Management.Automation.Language.NullString]::Value)
                $written += $entry
            }
            foreach ($entry in $pendingFiles.Values) {
                if ((Get-FileHash -LiteralPath (Join-Path $profile.AddOns $entry.path) -Algorithm SHA256).Hash -ne $entry.patchedSha256) { throw "Applied hash mismatch for $($entry.path)." }
            }
            Write-Output "$($profile.Flavor): applied and verified $($pendingFiles.Count) files from main $headCommit. Backups in $backup"
            $inspection = & $Python $registry inspect --flavor $profile.Flavor --addons-root $profile.AddOns
            if ($LASTEXITCODE -ne 0) { throw 'Post-application inspection failed.' }
            $reports[-1] = $inspection | ConvertFrom-Json
        } catch {
            $failure = $_
            foreach ($entry in $written) {
                $target = Join-Path $profile.AddOns $entry.path
                try {
                    $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
                    if ($hash -eq $entry.originalSha256) { continue }
                    if ($hash -ne $entry.patchedSha256) { throw 'Source changed externally after application.' }
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
            if ([IO.Path]::GetDirectoryName($resolvedStage) -ne $tempRoot -or -not [IO.Path]::GetFileName($resolvedStage).StartsWith('wow-tools-addon-fix-')) { throw 'Unsafe temporary cleanup path.' }
            if (Test-Path -LiteralPath $resolvedStage) { Remove-Item -LiteralPath $resolvedStage -Recurse -Force }
        }
    }
    if ($ReportPath) {
        [IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath), (ConvertTo-Json -InputObject $reports -Depth 20), [Text.UTF8Encoding]::new($false))
    }
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
if ($needsReview) { Write-Output 'Source review remains. Follow skills/addon-fix/SKILL.md to update the mapping or rebase the repair.'; exit 2 }
