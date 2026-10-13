param([byte[]]$ScreenBytes,[byte[]]$NamesBytes)
$ErrorActionPreference='Stop'
# Runs in an isolated PowerShell runspace. No window input or disk image files.
$namesBounds=$null
$anchorsBytes=$null
if ('WowAutoRotation.Native' -as [type]) {
    $imageStream=New-Object IO.MemoryStream(,$ScreenBytes)
    $image=$null
    try {
        $image=New-Object Drawing.Bitmap($imageStream)
        $region=[WowAutoRotation.Native]::NamesRegion($image)
        $namesBounds=[pscustomobject]@{X=$region.X/[double]$image.Width;Y=$region.Y/[double]$image.Height;
            W=$region.Width/[double]$image.Width;H=$region.Height/[double]$image.Height}
        if (-not $NamesBytes) {$NamesBytes=[WowAutoRotation.Native]::NamesPng($image)}
        $anchorsBytes=[WowAutoRotation.Native]::AnchorsPng($image)
    }
    finally {if ($image) {$image.Dispose()};$imageStream.Dispose()}
}
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null=[Windows.Storage.Streams.InMemoryRandomAccessStream,Windows.Storage.Streams,ContentType=WindowsRuntime]
$null=[Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
$null=[Windows.Graphics.Imaging.SoftwareBitmap,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
$null=[Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime]
$null=[Windows.Media.Ocr.OcrResult,Windows.Foundation,ContentType=WindowsRuntime]
$null=[Windows.Globalization.Language,Windows.Globalization,ContentType=WindowsRuntime]
$asTask=[System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {$_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetGenericArguments().Count -eq 1 -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'} | Select-Object -First 1
function Wait-OcrOperation($Operation,[type]$ResultType) {
    $task=$asTask.MakeGenericMethod($ResultType).Invoke($null,@($Operation))
    $task.GetAwaiter().GetResult()
}
$engine=[Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage((New-Object Windows.Globalization.Language 'zh-Hans-CN'))
if (-not $engine) {throw 'Windows Chinese OCR is unavailable. Install the Simplified Chinese OCR language feature.'}
function Read-OcrImage([byte[]]$Bytes) {
    $sourceStream=New-Object IO.MemoryStream(,$Bytes)
    $sourceImage=$null
    try {
        $sourceImage=New-Object Drawing.Bitmap($sourceStream)
        $Bytes=[WowAutoRotation.Native]::OcrPng($sourceImage,[int][Windows.Media.Ocr.OcrEngine]::MaxImageDimension)
    } finally {if ($sourceImage) {$sourceImage.Dispose()};$sourceStream.Dispose()}
    $stream=New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
    $bitmap=$null
    try {
        $buffer=[System.Runtime.InteropServices.WindowsRuntime.WindowsRuntimeBufferExtensions]::AsBuffer($Bytes)
        $writeTaskMethod=[System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {$_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetGenericArguments().Count -eq 2 -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperationWithProgress`2'} | Select-Object -First 1
        $writeTask=$writeTaskMethod.MakeGenericMethod([uint32],[uint32]).Invoke($null,@($stream.WriteAsync($buffer)))
        $null=$writeTask.GetAwaiter().GetResult()
        $stream.Seek(0)
        $decoder=Wait-OcrOperation ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $bitmap=Wait-OcrOperation ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        $result=Wait-OcrOperation ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
        return @(foreach ($line in $result.Lines) {
            $words=@($line.Words);if (-not $words.Count) {continue}
            $x=($words | ForEach-Object {$_.BoundingRect.X} | Measure-Object -Minimum).Minimum
            $y=($words | ForEach-Object {$_.BoundingRect.Y} | Measure-Object -Minimum).Minimum
            $right=($words | ForEach-Object {$_.BoundingRect.X+$_.BoundingRect.Width} | Measure-Object -Maximum).Maximum
            $bottom=($words | ForEach-Object {$_.BoundingRect.Y+$_.BoundingRect.Height} | Measure-Object -Maximum).Maximum
            [pscustomobject]@{Text=($line.Text -replace '\s','');X=$x/$bitmap.PixelWidth;Y=$y/$bitmap.PixelHeight;
                W=($right-$x)/$bitmap.PixelWidth;H=($bottom-$y)/$bitmap.PixelHeight}
        })
    } finally {if ($bitmap) {$bitmap.Dispose()};$stream.Dispose()}
}
$lines=@(Read-OcrImage $ScreenBytes)
if ($anchorsBytes) {$lines+=@(Read-OcrImage $anchorsBytes)}
[pscustomobject]@{Lines=$lines;Names=@(Read-OcrImage $NamesBytes);NamesBounds=$namesBounds} | ConvertTo-Json -Depth 5 -Compress
