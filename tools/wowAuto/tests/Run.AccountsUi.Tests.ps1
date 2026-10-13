param([string]$PreviewDirectory)
$ErrorActionPreference='Stop'
$tool=Split-Path $PSScriptRoot -Parent
$source=[IO.File]::ReadAllText((Join-Path $tool 'wowAuto.ps1'))
$quotedTool=$tool.Replace("'","''")
$source=$source.Replace('param([string]$PreviewPath, [switch]$UiTest)',('param([string]$PreviewPath, [switch]$UiTest)'+"`r`n"+'$PSScriptRoot='''+$quotedTool+''''))
$selected=@('Layout.UiTests.ps1','Refresh.UiTests.ps1','Unified.UiTests.ps1','Rotation.UiTests.ps1','Accounts.UiTests.ps1')
$source=[regex]::Replace($source,"(?m)^\s*\. \(Join-Path \`$PSScriptRoot 'tests\\([^']+)'\)\s*`$",{
    param($match)
    if ($match.Groups[1].Value -in $selected) {return $match.Value}
    return ''
})
# Install the existing combat mock before initializing the production unified UI.
$tokens=$null;$errors=$null
$mockAst=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $tool 'tests/AutoFight.UiTests.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) {throw 'Combat mock test source failed to parse.'}
$mock=$mockAst.Find({param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $node.Value.Contains('namespace WowAutoFight')},$true)
if (-not $mock) {throw 'Combat mock is missing; cannot run safely.'}
Add-Type -TypeDefinition $mock.Value
$rotationLine=". (Join-Path `$PSScriptRoot 'wowAuto.Rotation.ps1')"
$source=$source.Replace($rotationLine,$rotationLine+"`r`nif (`$UiTest) {Set-VersionWaitRanges 300 600 300 600 -Persist `$true; . (Join-Path `$PSScriptRoot 'autoFight.ps1'); Initialize-AutoFightTab `$tabs `$form -Unified}")
$oldPreview=$env:WOWAUTO_UNIFIED_PREVIEW_DIRECTORY
try {
    if ($PreviewDirectory) {
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($PreviewDirectory))
        $env:WOWAUTO_UNIFIED_PREVIEW_DIRECTORY=[IO.Path]::GetFullPath($PreviewDirectory)
    }
    & ([scriptblock]::Create($source)) -UiTest
} finally {$env:WOWAUTO_UNIFIED_PREVIEW_DIRECTORY=$oldPreview}
