$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$tool = Join-Path $repo 'tools\wowAuto'
$asts = @()
$inlineSources = @()
$temporaryFiles = @()
$files = @(Get-ChildItem -LiteralPath (Join-Path $repo 'tools'), (Join-Path $repo 'skills'), (Join-Path $repo 'addon_fix') -Filter '*.ps1' -Recurse -File |
    Where-Object { $_.FullName -notmatch '[\\/]\.runtime[\\/]' })

try {
    foreach ($file in $files) {
        $tokens = $null
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
        $asts += $ast
        foreach ($node in $ast.FindAll({ param($node)
            ($node -is [Management.Automation.Language.StringConstantExpressionAst] -or
                $node -is [Management.Automation.Language.ExpandableStringExpressionAst]) -and
                $node.Value -match '(?m)^\s*using System' -and $node.Value -match '(?m)^\s*namespace WowAuto'
        }, $true)) {
            $inlineSources += $node.Value
        }
    }
    Write-Output "PASS: PowerShell syntax ($($files.Count) files)."

    $sources = @(Get-ChildItem -LiteralPath $tool -Filter '*.cs' -File | ForEach-Object { $_.FullName })
    foreach ($source in $inlineSources) {
        $path = Join-Path ([IO.Path]::GetTempPath()) ('wow-tools-compile-' + [guid]::NewGuid().ToString('N') + '.cs')
        [IO.File]::WriteAllText($path, $source, (New-Object Text.UTF8Encoding($false)))
        $temporaryFiles += $path
        $sources += $path
    }
    if (-not $inlineSources.Count) { throw 'The embedded NativeInput C# source was not found.' }
    Add-Type -Path $sources -ReferencedAssemblies System.Core, System.Drawing, System.Windows.Forms
    Write-Output "PASS: C# compilation and type binding ($($sources.Count) compilation units)."

    $checked = 0
    $flags = [Reflection.BindingFlags]'Public,Static,FlattenHierarchy'
    foreach ($ast in $asts) {
        foreach ($node in $ast.FindAll({ param($node)
            $node -is [Management.Automation.Language.MemberExpressionAst] -and $node.Static -and
                $node.Expression -is [Management.Automation.Language.TypeExpressionAst] -and
                $node.Expression.TypeName.FullName -match '^WowAuto'
        }, $true)) {
            $typeName = $node.Expression.TypeName.FullName
            $type = $typeName -as [type]
            if (-not $type) { throw "Unknown production type $typeName at $($node.Extent)." }
            if ($node.Member -isnot [Management.Automation.Language.StringConstantExpressionAst]) { continue }
            $name = $node.Member.Value
            if ($node -is [Management.Automation.Language.InvokeMemberExpressionAst]) {
                $methods = @($type.GetMethods($flags) | Where-Object { $_.Name -eq $name })
                if ($name -eq 'new') { $methods = @($type.GetConstructors()) }
                $matching = @($methods | Where-Object {
                    $parameters = @($_.GetParameters())
                    $minimum = @($parameters | Where-Object { -not $_.IsOptional -and
                        -not $_.IsDefined([ParamArrayAttribute], $false) }).Count
                    $variadic = $parameters.Count -gt 0 -and $parameters[-1].IsDefined([ParamArrayAttribute], $false)
                    $node.Arguments.Count -ge $minimum -and ($variadic -or $node.Arguments.Count -le $parameters.Count)
                })
                if (-not $matching.Count) { throw "No compatible $typeName.$name overload at $($node.Extent)." }
            } elseif (-not $type.GetMember($name, $flags).Count) {
                throw "Unknown static member $typeName.$name at $($node.Extent)."
            }
            $checked++
        }
    }
    Write-Output "PASS: PowerShell/C# static member and call-arity compatibility ($checked references)."
} finally {
    foreach ($path in $temporaryFiles) { Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue }
}
