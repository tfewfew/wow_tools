$ErrorActionPreference='Stop'
# Synthetic frames only. Never request WGC, restore a window, emit input or inspect a real process.
$tool=Split-Path $PSScriptRoot -Parent
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $tool 'wowAuto.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) {throw ($errors | Out-String)}
$native=$ast.Find({param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.Value.Contains('namespace WowAuto')},$true)
Add-Type -TypeDefinition $native.Value
Add-Type -Path @((Join-Path $tool 'wowAuto.Capture.cs'),(Join-Path $tool 'wowAuto.Rotation.Native.cs'),(Join-Path $tool 'autoFight.Native.cs')) -ReferencedAssemblies System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
public static class CaptureFixture {
    public static Bitmap Canvas=new Bitmap(800,500);
    public static int Frames, Sizes, LastPid, LastOffset;
    public static long LastTicks;
    public static string LastPath;
    public static bool Pending;
    static Bitmap Read(int pid,long ticks,string path) {
        Frames++;LastPid=pid;LastTicks=ticks;LastPath=path;
        if(Pending) throw new InvalidOperationException("[CAPTURE_PENDING] synthetic restore/first-frame wait");
        return (Bitmap)Canvas.Clone();
    }
    static Size ReadSize(int pid,long ticks,string path) {Sizes++;return new Size(800,500);}
    static uint Pixel(int pid,long ticks,string path,int offset) {
        LastOffset=offset;
        using(var frame=Read(pid,ticks,path)) {
            Color c=frame.GetPixel(frame.Width/2+offset,frame.Height/2);
            return (uint)(c.R|(c.G<<8)|(c.B<<16));
        }
    }
    public static readonly Func<int,long,string,Bitmap> FrameReader=Read;
    public static readonly Func<int,long,string,Size> SizeReader=ReadSize;
    public static readonly Func<int,long,string,int,uint> PixelReader=Pixel;
}
'@
function Assert-Capture($Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
[WowAuto.NativeInput]::WindowPixelReader=[CaptureFixture]::PixelReader
[WowAutoRotation.Native]::FrameReader=[CaptureFixture]::FrameReader
[WowAutoRotation.Native]::SizeReader=[CaptureFixture]::SizeReader
[WowAutoFight.Native]::FrameReader=[CaptureFixture]::FrameReader
[WowAutoFight.Native]::CapturePending=[WowAutoCapture.Native]::PendingReader
$fixturePath='C:\synthetic\_classic_titan_\WowClassic.exe'
try {
    $g=[Drawing.Graphics]::FromImage([CaptureFixture]::Canvas)
    try {$g.Clear([Drawing.Color]::DarkGray);$g.FillRectangle([Drawing.Brushes]::White,768,468,16,16)} finally {$g.Dispose()}
    Assert-Capture ([WowAutoRotation.Native]::LoginPoint(777,123,$fixturePath)) 'White point did not use the injected client frame.'
    [CaptureFixture]::Canvas.SetPixel(400,250,[Drawing.Color]::Red)
    [CaptureFixture]::Canvas.SetPixel(432,250,[Drawing.Color]::Blue)
    Assert-Capture ([WowAuto.NativeInput]::ReadCenterColor(777,123,$fixturePath) -eq 'red' -and [CaptureFixture]::LastOffset -eq 0) 'Fishing main point bypassed the shared source.'
    Assert-Capture ([WowAuto.NativeInput]::ReadLureColor(777,123,$fixturePath) -eq 'present' -and [CaptureFixture]::LastOffset -eq 32) 'Fishing item point bypassed the shared source.'
    $screen=[WowAutoRotation.Native]::Capture(777,123,$fixturePath,800,500)
    try {Assert-Capture ($screen.Width -eq 800 -and $screen.Height -eq 500 -and $screen.GetPixel(400,250).R -eq 255 -and [CaptureFixture]::Sizes -eq 1) 'OCR did not use the shared frame and independent size reader.'} finally {$screen.Dispose()}
    [CaptureFixture]::Canvas.SetPixel(400,250,[Drawing.Color]::FromArgb(144,2,198))
    $client=New-Object WowAutoFight.Client
    $client.ProcessId=777;$client.StartTicks=123;$client.Path=$fixturePath;$client.Flavor='titan'
    $packet=[WowAutoFight.Native]::Read($client)
    Assert-Capture ($packet -and $packet.Action -eq 'combat' -and $packet.Combat -and $packet.EncounterId -eq 17) 'Combat did not decode the shared client frame.'
    Assert-Capture ([CaptureFixture]::LastPid -eq 777 -and [CaptureFixture]::LastTicks -eq 123 -and [CaptureFixture]::LastPath -ceq $fixturePath) 'Capture identity was not forwarded.'
    [CaptureFixture]::Pending=$true
    Assert-Capture ($null -eq [WowAutoFight.Native]::Read($client) -and [WowAutoFight.Native]::LastReadPending) 'Capture wait was treated as an invalid combat protocol.'
    $pending=$false
    try {$null=[WowAutoRotation.Native]::LoginPoint(777,123,$fixturePath)} catch {$pending=[WowAutoCapture.Native]::IsPending($_.Exception)}
    Assert-Capture $pending 'Capture wait was mistaken for an absent white point.'
    $pending=$false
    try {$null=[WowAuto.NativeInput]::ReadCenterColor(777,123,$fixturePath)} catch {$pending=[WowAutoCapture.Native]::IsPending($_.Exception)}
    Assert-Capture $pending 'Capture wait was mistaken for an unknown fishing color.'
} finally {[CaptureFixture]::Canvas.Dispose()}
Write-Output 'PASS: all native image adapters use one injected source; image coordinates, process identity and transient capture waits. No OS capture/input invoked.'
