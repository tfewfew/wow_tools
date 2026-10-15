$ErrorActionPreference='Stop'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\wowAuto.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$source=$ast.Find({param($node)
    $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $node.Value.Contains('namespace WowAuto')
},$true)
if ($null -eq $source) { throw 'Native C# source missing.' }
Add-Type -TypeDefinition $source.Value
# ClassifyColor is pure; do not invoke any window, GDI, input or process operations.
foreach ($case in @(@(0xFFFF00,'dead'),@(0x0000FF,'red'),@(0x00FF00,'green'),@(0x00FFFF,'yellow'),@(0xFF0000,'present'),@(0xFF00FF,'missing'),@(0x808080,'unknown'),@([uint32]::MaxValue,'unknown'))) {
    if ([WowAuto.NativeInput]::ClassifyColor([uint32]$case[0]) -ne $case[1]) { throw "Color classification failed: $($case[1])" }
}
if ($null -eq [WowAuto.NativeInput].GetMethod('ReadLureColor') -or $null -eq [WowAuto.NativeInput].GetMethod('ReadCenterColor')) { throw 'Detection APIs missing.' }
Write-Output 'PASS: production C# compilation and main/lure color classification. No native OS actions invoked.'
