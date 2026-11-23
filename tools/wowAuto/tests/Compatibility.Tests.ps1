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

    if ([WowAutoRotation.Native]::OcrTimeoutMs('forerver') -ne 10000 -or
        [WowAutoRotation.Native]::OcrTimeoutMs('titan') -ne 3000) {
        throw 'Client-specific OCR sample timeout contract is incompatible.'
    }
    Write-Output 'PASS: client-specific OCR sample timeout interface contract.'

    $parking=[WowAutoRotation.Native]::CursorParkPoint(3559,2105)
    if ($parking.X -ne 1779 -or $parking.Y -ne 1052) {
        throw 'OCR cursor parking coordinates must resolve to the client center.'
    }
    Write-Output 'PASS: OCR cursor parking coordinate interface contract.'

    $hotkeyType = 'WowAuto.ScreenshotHotkey' -as [type]
    $hotkeyConstructor = $hotkeyType.GetConstructor([type[]]@([int], [bool], [bool], [bool]))
    if (-not $hotkeyConstructor -or -not [IDisposable].IsAssignableFrom($hotkeyType) -or
        $hotkeyType.GetEvent('Pressed').EventHandlerType -ne [EventHandler]) {
        throw 'Screenshot hotkey constructor, event or disposal contract is incompatible.'
    }
    $hubType = 'WowAuto.Threading.Hub' -as [type]
    if ($hubType.GetMethod('PauseAndWait', [type[]]@([int])).ReturnType -ne [bool] -or
        $hubType.GetMethod('FinishOperation', [type[]]@()).ReturnType -ne [void]) {
        throw 'Screenshot operator pause contract is incompatible.'
    }
    Write-Output 'PASS: screenshot listener and operator pause interface compatibility.'

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
    & (Join-Path $PSScriptRoot 'Accounts.Compatibility.Tests.ps1')
    & (Join-Path $PSScriptRoot 'Rest.Compatibility.Tests.ps1')

    . (Join-Path $tool 'autoFight.Engine.ps1')
    . (Join-Path $tool 'wowAuto.AccountTasks.ps1')
    $shopping=@{Version=1;Accounts=@{};Bindings=@{};Periods=(New-DetectionPeriods);Shop=(New-ShopTaskSettings)}
    foreach($flavor in @('titan','forerver')) {
        $shopping.Accounts[$flavor+':TEST']=@(@{Name='购物角色';Realm='测试';Mode='shop';Enabled=$true;UseItem=$false})
    }
    $shopping=ConvertTo-TaskMap ($shopping | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
    Test-AccountTaskConfiguration $shopping
    $legacyShop=@{VisitIntervalSeconds=[int]::MaxValue;CloseDelaySeconds=5;JumpIntervalSeconds=60;DurationSeconds=600;InteractKey='F'}
    $convertedShop=ConvertTo-ShopTaskSettings $legacyShop
    $legacyShop.Remove('CloseDelaySeconds')
    $withoutCloseDelay=ConvertTo-ShopTaskSettings $legacyShop
    $previousShop=$shopping.Shop.Clone()
    $previousShop.Remove('JitterMs')
    $previousShop.Remove('JumpOnVisit')
    $legacyDefaults=ConvertTo-ShopTaskSettings $previousShop
    $customShop=$legacyDefaults.Clone()
    $customShop.JitterMs=100
    $customShop.JumpOnVisit=$false
    $customShop=ConvertTo-ShopTaskSettings (ConvertTo-TaskMap ($customShop | ConvertTo-Json | ConvertFrom-Json))
    if((Get-AccountTaskModeLabel 'shop') -cne '购物' -or $shopping.Shop.ReopenDelayMs -ne 1000 -or
        $shopping.Shop.CloseDelayMs -ne 1000 -or $convertedShop.ReopenDelayMs -ne 2147483647000L -or
        $convertedShop.CloseDelayMs -ne 5000 -or $withoutCloseDelay.CloseDelayMs -ne 1000 -or
        -not $legacyShop.ContainsKey('VisitIntervalSeconds') -or $legacyDefaults.JitterMs -ne 0 -or
        $previousShop.ContainsKey('JitterMs') -or $previousShop.ContainsKey('JumpOnVisit') -or
        -not $legacyDefaults.JumpOnVisit -or -not $shopping.Shop.JumpOnVisit -or $customShop.JumpOnVisit -or
        [WowAuto.NativeInput]::ShoppingCommand('prepare',1500) -cne '/autoshop preparems 1500' -or
        [WowAuto.NativeInput]::ShoppingCommand('buy',0) -cne '/autoshop buy' -or
        [WowAuto.NativeInput]::ShoppingCommand('close',0) -cne '/autoshop close' -or
        [WowAuto.NativeInput]::ShoppingCommand('cancel',0) -cne '/autoshop cancel' -or
        [WowAuto.NativeInput]::DetectorCommand('rest') -cne '/wowrest') {
        throw 'Automatic shopping timing settings or slash command contract is incompatible.'
    }
    $frameReader=[WowAutoRotation.Native]::FrameReader
    $frame=New-Object Drawing.Bitmap 97,99
    try {
        $bounds=[WowAutoRotation.Native]::LoginPointBounds($frame.Width,$frame.Height)
        if($bounds.X -ne 65 -or $bounds.Y -ne 67 -or $bounds.Width -ne 16 -or $bounds.Height -ne 16){
            throw 'The shared mode marker must use the existing login-point client coordinates.'
        }
        [WowAutoRotation.Native]::FrameReader=[Func[int,long,string,Drawing.Bitmap]]{
            param($pidValue,$ticks,$path)
            return $frame.Clone()
        }
        foreach($spec in @(@('rest',255,255,255),@('fish',64,170,255),@('fight',255,112,76),@('shop',181,104,255))){
            $color=[Drawing.Color]::FromArgb($spec[1],$spec[2],$spec[3])
            for($y=$bounds.Top+2;$y -lt $bounds.Bottom-2;$y++){
                for($x=$bounds.Left+2;$x -lt $bounds.Right-2;$x++){$frame.SetPixel($x,$y,$color)}
            }
            if([WowAutoRotation.Native]::ReadLoginMode($frame) -cne $spec[0] -or
                -not [WowAutoRotation.Native]::LoginPoint(0,0,'')){
                throw "Login mode must identify $($spec[0]) as in world."
            }
        }
        foreach($spec in @(@('closed',52,120,230),@('open',154,211,67),@('bought',71,218,181))){
            $color=[Drawing.Color]::FromArgb($spec[1],$spec[2],$spec[3])
            for($y=47;$y -le 51;$y++){
                for($x=46;$x -le 50;$x++){$frame.SetPixel($x,$y,$color)}
            }
            if([WowAutoRotation.Native]::ReadShoppingState(0,0,'') -cne $spec[0]){
                throw 'The closed, open and purchase-completed color signals must decode from the same frame as the mode marker.'
            }
        }
        $frame.SetPixel(46,47,[Drawing.Color]::Black)
        if([WowAutoRotation.Native]::ReadShoppingState(0,0,'') -cne 'unknown'){
            throw 'An incomplete center marker must not decode as a shopping phase.'
        }
        $frame.SetPixel(46,47,$color)
        $frame.SetPixel($bounds.Left+2,$bounds.Top+2,[Drawing.Color]::Black)
        if([WowAutoRotation.Native]::LoginPoint(0,0,'') -or [WowAutoRotation.Native]::ReadShoppingState(0,0,'') -cne 'unknown'){
            throw 'An incomplete mode marker must not confirm login or authorize a shopping phase.'
        }
        for($y=$bounds.Top+2;$y -lt $bounds.Bottom-2;$y++){
            for($x=$bounds.Left+2;$x -lt $bounds.Right-2;$x++){$frame.SetPixel($x,$y,[Drawing.Color]::White)}
        }
        if(-not [WowAutoRotation.Native]::LoginPoint(0,0,'') -or [WowAutoRotation.Native]::ReadShoppingState(0,0,'') -cne 'unknown'){
            throw 'The white login marker must confirm login without authorizing shopping.'
        }
    } finally {
        [WowAutoRotation.Native]::FrameReader=$frameReader
        $frame.Dispose()
    }
    Write-Output 'PASS: shared in-world mode palette, shopping settings, slash commands and three same-frame shopping states.'

    . (Join-Path $tool 'wowAuto.Engine.ps1')
    $directModes=Get-WowAutoDirectTaskModes
    $directLabels=@($directModes | ForEach-Object {Get-AccountTaskModeLabel $_})
    if(($directLabels -join ',') -cne '放号,战斗,购物,钓鱼'){throw 'The direct-start task labels do not match the mode list.'}
    $launcher=$asts | Where-Object {$_.Extent.File -eq (Join-Path $tool 'wowAuto.ps1')}
    $readIni=$launcher.Find({param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Read-WowAutoSettingsIni'
    },$true)
    . ([scriptblock]::Create($readIni.Extent.Text))
    $ini=Join-Path ([IO.Path]::GetTempPath()) ('wow-tools-direct-mode-'+[guid]::NewGuid().ToString('N')+'.ini')
    $temporaryFiles+=$ini
    [IO.File]::WriteAllLines($ini,[string[]]@('Mode_100_638000000000000001=fish','Mode_101_638000000000000002=fight',
        'Mode_102_638000000000000003=shop','Mode_103_638000000000000004=rest'))
    $script:audioSettingsKeys=@()
    $script:audioTimeoutSettingsKeys=@()
    $script:recordingSettingsKeys=@()
    $script:preferenceSettingsKeys=@()
    $readModes=(Read-WowAutoSettingsIni $ini).ProcessModePreferences
    if($readModes.Count -ne 4 -or $readModes['100:638000000000000001'] -cne 'fish' -or
        $readModes['101:638000000000000002'] -cne 'fight' -or $readModes['102:638000000000000003'] -cne 'shop' -or
        $readModes['103:638000000000000004'] -cne 'rest'){
        throw 'The direct-start task modes did not load by PID and start time.'
    }
    Write-Output 'PASS: direct-start task labels and per-process INI compatibility.'
} finally {
    foreach ($path in $temporaryFiles) { Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue }
}
