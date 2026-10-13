param([string]$SampleDirectory,[string]$ImagePath,[switch]$Generated)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$tool=Split-Path $PSScriptRoot -Parent
Add-Type -Path (Join-Path $tool 'wowAuto.Rotation.Native.cs') -ReferencedAssemblies System.Drawing
$parseTokens=$null;$parseErrors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $tool 'wowAuto.Rotation.ps1'),[ref]$parseTokens,[ref]$parseErrors)
foreach ($name in @('New-RotationPlan','Resolve-RotationOcrName','ConvertFrom-RotationOcr')) {
    $fn=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    if (-not $fn) {throw 'OCR classifier function missing.'}
    Invoke-Expression $fn.Extent.Text
}
$plan=New-RotationPlan;$plan.Slots[0].Name='双持船橘二咪';$plan.Slots[1].Name='咆史呀嘞'
$oneError=Resolve-RotationOcrName '咆史呀嘞' @('吔史呀嘞')
$twoErrors=Resolve-RotationOcrName '咆史呀吼' @('吔史呀嘞')
$shortName=Resolve-RotationOcrName '史呀嘞' @('吔史呀嘞')
$ambiguous=Resolve-RotationOcrName '咆史呀嘞' @('吔史呀嘞','咆史呀嘞')
if ($oneError.Name -cne '吔史呀嘞' -or $oneError.Ambiguous -or $twoErrors.Name -cne '咆史呀吼' -or
    $shortName.Name -cne '史呀嘞' -or -not $ambiguous.Ambiguous) {throw 'N-1 OCR name matching accepted a wrong length, two errors, or an ambiguous name.'}
$ambiguousPlan=New-RotationPlan;$ambiguousPlan.Slots[0].Name='吔史呀嘞';$ambiguousPlan.Slots[1].Name='咆史呀嘞'
$fakeOcr=[pscustomobject]@{Lines=@([pscustomobject]@{Text='选择服务器';X=0.86;Y=0.08},[pscustomobject]@{Text='进入魔兽世界';X=0.45;Y=0.91});
    Names=@([pscustomobject]@{Text='咆史呀嘞';X=0.20;Y=0.40;W=0.10;H=0.03});NamesBounds=[pscustomobject]@{X=0.79;Y=0;W=0.21;H=0.84}}
$ambiguousScreen=ConvertFrom-RotationOcr $fakeOcr $ambiguousPlan
if ($ambiguousScreen.Kind -ne 'menu' -or @($ambiguousScreen.Targets | Where-Object {-not $_.Ambiguous}).Count) {throw 'Ambiguous OCR text could become a selectable target.'}
$anchors=$fakeOcr.Lines
foreach ($anchor in $anchors) {
    $fakeOcr.Lines=@($anchor)
    if ((ConvertFrom-RotationOcr $fakeOcr $ambiguousPlan).Kind -ne 'menu') {throw 'A single positioned menu anchor was rejected.'}
}
$fakeOcr.Lines=$anchors
$source=[IO.File]::ReadAllText((Join-Path $tool 'wowAuto.Rotation.Ocr.ps1'))
function Read-TestOcr($Bitmap) {
    $pipeline=[powershell]::Create()
    try {
        $null=$pipeline.AddScript($source).AddArgument([WowAutoRotation.Native]::Png($Bitmap))
        $async=$pipeline.BeginInvoke();$watch=[Diagnostics.Stopwatch]::StartNew()
        while (-not $async.IsCompleted) {if ($watch.ElapsedMilliseconds -gt 10000) {throw 'OCR exceeded test timeout.'};Start-Sleep -Milliseconds 25}
        $result=$pipeline.EndInvoke($async)
        if ($pipeline.Streams.Error.Count) {throw $pipeline.Streams.Error[0].ToString()}
        return ($result[0] | ConvertFrom-Json)
    } finally {$pipeline.Stop();$pipeline.Dispose()}
}
function Read-TestImage($Bitmap) {ConvertFrom-RotationOcr (Read-TestOcr $Bitmap) $plan}
function Assert-ScreenshotOcr($Ocr,$Screen,[double]$Scale) {
    $server=@($Ocr.Lines | Where-Object {$_.Text -match '^[0一_—\-口□]*选择服务器[一_—\-口□]*$' -and $_.X -gt 0.65 -and $_.Y -lt 0.15})
    $enter=@($Ocr.Lines | Where-Object {$_.Text -match '^[0一_—\-口□]*进入魔兽世界[一_—\-口□]*$' -and $_.X -gt 0.25 -and $_.X -lt 0.70 -and $_.Y -gt 0.85})
    if (-not $server.Count -or -not $enter.Count) {
        $candidates=@($Ocr.Lines | Where-Object {($_.X -gt 0.65 -and $_.Y -lt 0.15) -or ($_.X -gt 0.25 -and $_.X -lt 0.70 -and $_.Y -gt 0.85)} | ForEach-Object {$_.Text})
        throw ('Screenshot button anchors were not recognized at scale '+$Scale+': '+($candidates -join '|'))
    }
    $first=@($Screen.Targets | Where-Object {$_.Name -ceq '双持船橘二咪' -and -not $_.Ambiguous})
    $second=@($Screen.Targets | Where-Object {$_.Name -ceq '吔史呀嘞' -and -not $_.Ambiguous})
    # The 0.67x downsample drops source glyph pixels; it must remain fail-closed.
    $expectedSecond=if ($Scale -eq 0.67) {0} else {1}
    if ($Screen.Kind -ne 'menu' -or $first.Count -ne 1 -or $second.Count -ne $expectedSecond) {
        throw ('Screenshot character names were not recognized at scale '+$Scale+': '+($Screen | ConvertTo-Json -Depth 4 -Compress))
    }
}
if (-not $ImagePath -and -not $SampleDirectory -and -not $Generated) {$ImagePath=Join-Path $PSScriptRoot 'fixtures/titan-character-select-20261014.png'}
if ($ImagePath) {
    $plan.Slots[1].Name='吔史呀嘞'
    $original=New-Object Drawing.Bitmap($ImagePath)
    try {
        foreach ($scale in @(1.0,0.67,1.5)) {
            $bitmap=New-Object Drawing.Bitmap($original,(New-Object Drawing.Size([int]($original.Width*$scale),[int]($original.Height*$scale))))
            try {
                $ocr=Read-TestOcr $bitmap;$screen=ConvertFrom-RotationOcr $ocr $plan
                Assert-ScreenshotOcr $ocr $screen $scale
                $status=if ($scale -eq 0.67) {'unreadable second name safely withheld'} else {'both names resolved'}
                Write-Output ('PASS: attached menu screenshot at scale '+$scale+' matches both button anchors; '+$status+'.')
            } finally {$bitmap.Dispose()}
        }
    } finally {$original.Dispose()}
} elseif ($SampleDirectory) {
    $samples=@(@(22,'menu',''),@(33,'menu',''),@(27,'unknown',''),@(39,'unknown',''),@(23,'unknown',''))
    foreach ($sample in $samples) {
        $original=New-Object Drawing.Bitmap((Join-Path $SampleDirectory ('frame-{0:D3}.jpg' -f [int]$sample[0])))
        try {
            foreach ($scale in @(1.0,0.67)) {
                $bitmap=New-Object Drawing.Bitmap($original,(New-Object Drawing.Size([int]($original.Width*$scale),[int]($original.Height*$scale))))
                try {
                    $screen=Read-TestImage $bitmap
                    if ($screen.Kind -ne $sample[1] -or ($sample[2] -and ($scale -eq 1 -or $screen.RoleName) -and $screen.RoleName -cne $sample[2])) {throw ('Unexpected OCR result for frame '+$sample[0]+' scale '+$scale+': '+($screen | ConvertTo-Json -Depth 4 -Compress))}
                    if ($screen.Kind -eq 'menu' -and @($screen.Targets | Where-Object {$_.Name -cin @('双持船橘二咪','咆史呀嘞')}).Count -ne 2) {throw ('Demonstration names were not both recognized exactly: '+($screen | ConvertTo-Json -Depth 4 -Compress))}
                    Write-Output ('PASS: demonstration frame '+$sample[0]+' scale '+$scale+' => '+$screen.Kind+' '+$screen.RoleName)
                } finally {$bitmap.Dispose()}
            }
        } finally {$original.Dispose()}
    }
} else {
    $bitmap=New-Object Drawing.Bitmap(2400,1400);$graphics=[Drawing.Graphics]::FromImage($bitmap)
    $font=New-Object Drawing.Font('Microsoft YaHei',30)
    try {
        $graphics.Clear([Drawing.Color]::Black)
        $graphics.DrawString('选择服务器',$font,[Drawing.Brushes]::Yellow,1980,80)
        $graphics.DrawString('进入魔兽世界',$font,[Drawing.Brushes]::Yellow,1030,1280)
        $graphics.DrawString('双持船橘二咪',$font,[Drawing.Brushes]::Yellow,1940,260)
        $graphics.DrawString('咆史呀嘞',$font,[Drawing.Brushes]::Yellow,1940,450)
        $screen=Read-TestImage $bitmap
        if ($screen.Kind -ne 'menu' -or @($screen.Targets | Where-Object {$_.Name -cin @('双持船橘二咪','咆史呀嘞')}).Count -ne 2) {throw 'Generated Chinese OCR anchors failed.'}
        Write-Output 'PASS: production asynchronous Windows Chinese OCR and name preprocessing. Generated image only; no game capture or input.'
    } finally {$font.Dispose();$graphics.Dispose();$bitmap.Dispose()}
}
