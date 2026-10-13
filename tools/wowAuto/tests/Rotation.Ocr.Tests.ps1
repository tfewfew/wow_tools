param([string]$SampleDirectory)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$tool=Split-Path $PSScriptRoot -Parent
Add-Type -Path (Join-Path $tool 'wowAuto.Rotation.Native.cs') -ReferencedAssemblies System.Drawing
$parseTokens=$null;$parseErrors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $tool 'wowAuto.Rotation.ps1'),[ref]$parseTokens,[ref]$parseErrors)
foreach ($name in @('New-RotationPlan','ConvertFrom-RotationOcr')) {
    $fn=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    if (-not $fn) {throw 'OCR classifier function missing.'}
    Invoke-Expression $fn.Extent.Text
}
$plan=New-RotationPlan;$plan.Slots[0].Name='双持船橘二咪';$plan.Slots[1].Name='咆史呀嘞'
$source=[IO.File]::ReadAllText((Join-Path $tool 'wowAuto.Rotation.Ocr.ps1'))
function Read-TestImage($Bitmap) {
    $pipeline=[powershell]::Create()
    try {
        $null=$pipeline.AddScript($source).AddArgument([WowAutoRotation.Native]::Png($Bitmap))
        $async=$pipeline.BeginInvoke();$watch=[Diagnostics.Stopwatch]::StartNew()
        while (-not $async.IsCompleted) {if ($watch.ElapsedMilliseconds -gt 10000) {throw 'OCR exceeded test timeout.'};Start-Sleep -Milliseconds 25}
        $result=$pipeline.EndInvoke($async)
        if ($pipeline.Streams.Error.Count) {throw $pipeline.Streams.Error[0].ToString()}
        ConvertFrom-RotationOcr ($result[0] | ConvertFrom-Json) $plan
    } finally {$pipeline.Stop();$pipeline.Dispose()}
}
if ($SampleDirectory) {
    $samples=@(@(22,'menu',''),@(33,'menu',''),@(27,'world','双持船橘二咪'),@(39,'world','咆史呀嘞'),@(23,'unknown',''))
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
        $graphics.DrawString('系统公告',$font,[Drawing.Brushes]::White,80,300)
        $graphics.DrawString('双持船橘二咪',$font,[Drawing.Brushes]::Yellow,1940,260)
        $graphics.DrawString('咆史呀嘞',$font,[Drawing.Brushes]::Yellow,1940,450)
        $screen=Read-TestImage $bitmap
        if ($screen.Kind -ne 'menu' -or @($screen.Targets | Where-Object {$_.Name -cin @('双持船橘二咪','咆史呀嘞')}).Count -ne 2) {throw 'Generated Chinese OCR anchors failed.'}
        Write-Output 'PASS: production asynchronous Windows Chinese OCR and name preprocessing. Generated image only; no game capture or input.'
    } finally {$font.Dispose();$graphics.Dispose();$bitmap.Dispose()}
}
