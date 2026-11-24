[CmdletBinding()]
param([string]$DotNet = 'dotnet.exe')

$ErrorActionPreference = 'Stop'

$dotnetCommand = Get-Command -Name $DotNet -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $dotnetCommand) {
    throw 'Install the .NET 10 SDK or pass its dotnet.exe path with -DotNet.'
}
$dotnetPath = $dotnetCommand.Source

$publishRoot = Join-Path $PSScriptRoot 'publish'
$desktopTarget = @{ Name = 'Desktop'; Project = 'Desktop\Desktop.csproj'; Executable = 'WowAuto.exe' }
$targets = @(
    $desktopTarget
    @{ Name = 'Cli'; Project = 'Cli\Cli.csproj'; Executable = 'wowauto-cli.exe' }
)
$publishArguments = @(
    '-c', 'Release', '-r', 'win-x64', '--self-contained', 'true',
    '-p:PublishSingleFile=true', '-p:DebugType=None'
)

Push-Location -LiteralPath $PSScriptRoot
try {
    $sdkVersion = & $dotnetPath --version | Select-Object -Last 1
    $version = $null
    $versionPrefix = ([string]$sdkVersion).Split('-')[0]
    if ($LASTEXITCODE -ne 0 -or -not [version]::TryParse($versionPrefix, [ref]$version) -or $version.Major -lt 10) {
        throw 'Install the .NET 10 SDK or pass its dotnet.exe path with -DotNet.'
    }

    $executables = foreach ($target in $targets) {
        $projectPath = Join-Path $PSScriptRoot $target.Project
        $outputPath = Join-Path $publishRoot $target.Name
        & $dotnetPath publish $projectPath @publishArguments --output $outputPath | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet publish failed for $($target.Name) with exit code $LASTEXITCODE."
        }
        $executable = Join-Path $outputPath $target.Executable
        if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
            throw "Published executable is missing at $executable."
        }
        $executable
    }

    $desktopPath = [Environment]::GetFolderPath('Desktop')
    if (-not $desktopPath) {
        throw 'Windows did not report a desktop folder for the current user.'
    }
    $desktopOutput = Join-Path $publishRoot $desktopTarget.Name
    $desktopExecutable = Join-Path $desktopOutput $desktopTarget.Executable
    $shortcutPath = Join-Path $desktopPath 'wowAuto C#.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $desktopExecutable
    $shortcut.WorkingDirectory = $desktopOutput
    $shortcut.Description = 'Launch the wowAuto desktop client'
    $shortcut.Save()
    $saved = $shell.CreateShortcut($shortcutPath)
    if ($saved.TargetPath -ne $desktopExecutable -or $saved.WorkingDirectory -ne $desktopOutput) {
        throw 'The wowAuto desktop shortcut could not be verified.'
    }
    Write-Host "Desktop shortcut saved at $shortcutPath"
    $executables
}
finally {
    Pop-Location
}
