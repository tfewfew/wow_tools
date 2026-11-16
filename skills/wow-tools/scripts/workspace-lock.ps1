param(
    [ValidateSet('Hold', 'Status')][string]$Action = 'Hold',
    [string]$Workspace = 'C:\code\wow_tools',
    [string]$Owner = 'Codex maintenance'
)
$ErrorActionPreference = 'Stop'
$workspacePath = (Resolve-Path -LiteralPath $Workspace).ProviderPath
$lockDirectory = Join-Path $workspacePath '.local-backups'
[IO.Directory]::CreateDirectory($lockDirectory) | Out-Null
$lockPath = Join-Path $lockDirectory 'workspace.lock'

# Keep the file in place. The open handle supplies ownership and crash recovery.
try {
    $stream = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
} catch [IO.IOException] {
    $code = $_.Exception.HResult -band 0xFFFF
    if ($code -notin @(32, 33)) { throw }
    [ordered]@{ state = 'busy'; workspace = $workspacePath; lock = $lockPath } | ConvertTo-Json -Compress
    exit 2
}

try {
    if ($Action -eq 'Status') {
        [ordered]@{ state = 'available'; workspace = $workspacePath; lock = $lockPath } | ConvertTo-Json -Compress
        return
    }
    $metadata = [ordered]@{
        state = 'acquired'
        workspace = $workspacePath
        owner = $Owner
        pid = $PID
        acquiredAt = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($metadata)
    $stream.SetLength(0)
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush($true)
    Write-Output $metadata
    # Run Hold in a persistent exec session, then send release + newline to that session.
    while (($line = [Console]::ReadLine()) -ne $null) {
        if ($line -ceq 'release') { break }
    }
} finally {
    $stream.Dispose()
}
if ($Action -eq 'Hold') {
    [ordered]@{ state = 'released'; workspace = $workspacePath } | ConvertTo-Json -Compress
}
