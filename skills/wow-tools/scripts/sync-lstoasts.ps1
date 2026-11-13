function Remove-WowToolsRetiredToastFiles {
    param([string]$Source, [string]$Target, [string]$BackupPath)
    $sourceRoot = [IO.Path]::GetFullPath($Source).TrimEnd('\')
    $targetRoot = [IO.Path]::GetFullPath($Target).TrimEnd('\')
    $backupRoot = [IO.Path]::GetFullPath($BackupPath).TrimEnd('\')
    if ((Split-Path $sourceRoot -Leaf) -ne 'ls_toasts' -or
        (Split-Path $targetRoot -Leaf) -ne 'ls_toasts' -or
        $sourceRoot -eq $targetRoot -or
        $backupRoot.StartsWith($targetRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $backupRoot -eq $targetRoot) {
        throw 'Invalid ls_Toasts source, target or backup directory.'
    }
    if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) { throw 'ls_Toasts source is missing.' }
    $retired = 0
    if (Test-Path -LiteralPath $targetRoot -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $targetRoot -File -Recurse) {
            if (-not $file.FullName.StartsWith($targetRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Obsolete ls_Toasts file escaped the deployment directory.'
            }
            $relative = $file.FullName.Substring($targetRoot.Length + 1)
            if (Test-Path -LiteralPath (Join-Path $sourceRoot $relative) -PathType Leaf) { continue }
            $backupFile = Join-Path $backupRoot $relative
            New-Item -ItemType Directory -Path (Split-Path $backupFile -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $backupFile
            if ((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $backupFile).Hash) {
                throw 'Obsolete ls_Toasts file backup verification failed.'
            }
            Remove-Item -LiteralPath $file.FullName
            $retired++
        }
    }
    return $retired
}
