param(
    [string]$Python = 'python',
    [string]$LuaModuleRoot,
    [Alias('DungeonsForeverAddOnsRoot')][string]$AddonFixAddOnsRoot,
    [ValidateSet('titan','forerver')][string]$AddonFixFlavor = 'forerver'
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
& (Join-Path $repo 'tools\wowAuto\tests\Compatibility.Tests.ps1')
& (Join-Path $PSScriptRoot '..\tests\ClientProfiles.Tests.ps1')
$arguments = @((Join-Path $PSScriptRoot 'check-local.py'))
if ($LuaModuleRoot) { $arguments += @('--lua-module-root', $LuaModuleRoot) }
if ($AddonFixAddOnsRoot) { $arguments += @('--addon-fix-addons-root', $AddonFixAddOnsRoot, '--addon-fix-flavor', $AddonFixFlavor) }
& $Python @arguments
if ($LASTEXITCODE -ne 0) { throw "Source and client API checks failed with exit code $LASTEXITCODE." }
Write-Output 'PASS: local syntax, semantic compilation and interface compatibility checks.'
