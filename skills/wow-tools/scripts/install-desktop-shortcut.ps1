param(
    [Parameter(Mandatory=$true)][string]$ToolRoot,
    [Parameter(Mandatory=$true)][string]$DesktopPath,
    [Parameter(Mandatory=$true)][string]$BackupPath
)
$ErrorActionPreference = 'Stop'
$toolPath = [IO.Path]::GetFullPath($ToolRoot)
$desktopPathResolved = [IO.Path]::GetFullPath($DesktopPath)
$backupPathResolved = [IO.Path]::GetFullPath($BackupPath)
foreach ($name in @('wowAuto.bat', 'wowAuto.ps1', 'wowAuto.Engine.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $toolPath $name) -PathType Leaf)) {
        throw "Missing source runtime file: $name"
    }
}
if ($toolPath -eq $desktopPathResolved -or $backupPathResolved -eq $desktopPathResolved) {
    throw 'Source and backup must be separate from the desktop.'
}
New-Item -ItemType Directory -Path $desktopPathResolved -Force | Out-Null
New-Item -ItemType Directory -Path $backupPathResolved -Force | Out-Null
$shortcutPath = Join-Path $desktopPathResolved 'wowAuto.lnk'
if (Test-Path -LiteralPath $shortcutPath) {
    Copy-Item -LiteralPath $shortcutPath -Destination (Join-Path $backupPathResolved 'wowAuto.lnk')
}
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $toolPath 'wowAuto.bat'
$shortcut.WorkingDirectory = $toolPath
$shortcut.Arguments = ''
$shortcut.Description = 'Launch wowAuto from its source directory'
$shortcut.IconLocation = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe,0"
$shortcut.Save()
$saved = $shell.CreateShortcut($shortcutPath)
if ($saved.TargetPath -ne $shortcut.TargetPath -or $saved.WorkingDirectory -ne $toolPath -or $saved.Arguments -ne '') {
    throw 'Desktop shortcut verification failed; existing runtime files have not been removed.'
}

# Only archive the known runtime copies after the shortcut has been verified.
foreach ($name in @('wowAuto.ps1', 'wowAuto.Engine.ps1', 'wowAuto.bat',
    'wow-foreground-loop.ps1', 'wow-foreground-loop.bat')) {
    $oldPath = [IO.Path]::GetFullPath((Join-Path $desktopPathResolved $name))
    $archivePath = [IO.Path]::GetFullPath((Join-Path $backupPathResolved $name))
    if ((Split-Path $oldPath -Parent) -ne $desktopPathResolved -or
        (Split-Path $archivePath -Parent) -ne $backupPathResolved) { throw 'Desktop archive path check failed.' }
    if (Test-Path -LiteralPath $oldPath -PathType Leaf) {
        Move-Item -LiteralPath $oldPath -Destination $archivePath
    }
}
Write-Output "Desktop shortcut: $shortcutPath -> $($saved.TargetPath)"
