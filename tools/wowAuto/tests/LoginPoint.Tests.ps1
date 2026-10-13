$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -Path (Join-Path $PSScriptRoot '..\wowAuto.Rotation.Native.cs') -ReferencedAssemblies System.Drawing
foreach ($size in @(@(800,600),@(1280,720),@(1579,937),@(3840,2160))) {
    $bounds=[WowAutoRotation.Native]::LoginPointBounds($size[0],$size[1])
    if ($bounds.X -ne 16 -or $size[1]-$bounds.Bottom -ne 16 -or $bounds.Width -ne 16 -or $bounds.Height -ne 16) {throw 'Inset sampling geometry differs from addons.'}
}
$clipped=New-Object Drawing.Bitmap(16,16)
$client=New-Object Drawing.Bitmap(160,120)
$graphics=[Drawing.Graphics]::FromImage($clipped)
try {
    $graphics.Clear([Drawing.Color]::White)
    # A rounded corner clips an interior pixel, so the old edge sample is rejected.
    $clipped.SetPixel(2,13,[Drawing.Color]::Black)
    if ([WowAutoRotation.Native]::HasLoginPoint($clipped)) {throw 'Clipped corner accepted.'}
    $graphics.Dispose();$graphics=[Drawing.Graphics]::FromImage($client)
    $graphics.Clear([Drawing.Color]::Black)
    $bounds=[WowAutoRotation.Native]::LoginPointBounds($client.Width,$client.Height)
    $graphics.FillRectangle([Drawing.Brushes]::White,$bounds)
    $sample=$client.Clone($bounds,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {if (-not [WowAutoRotation.Native]::HasLoginPoint($sample)) {throw 'Inset point rejected.'}} finally {$sample.Dispose()}
    $oldBounds=New-Object Drawing.Rectangle(0,104,16,16)
    $sample=$client.Clone($oldBounds,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {if ([WowAutoRotation.Native]::HasLoginPoint($sample)) {throw 'Old corner incorrectly accepted.'}} finally {$sample.Dispose()}
    $client.SetPixel($bounds.X+8,$bounds.Y+8,[Drawing.Color]::Gray)
    $sample=$client.Clone($bounds,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {if ([WowAutoRotation.Native]::HasLoginPoint($sample)) {throw 'Occluded point accepted.'}} finally {$sample.Dispose()}
} finally {$graphics.Dispose();$clipped.Dispose();$client.Dispose()}
Write-Output 'PASS: physical inset across client sizes, rounded-corner rejection, relocated white point and occlusion rejection. Synthetic bitmaps only; no game capture/input.'
