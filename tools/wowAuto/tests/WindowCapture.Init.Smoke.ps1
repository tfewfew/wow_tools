$ErrorActionPreference='Stop'
# Capture only a temporary window owned by this test process. Never touch WoW or emit input.
$tool=Split-Path $PSScriptRoot -Parent
Add-Type -AssemblyName System.Windows.Forms
$captureSource=[IO.File]::ReadAllText((Join-Path $tool 'wowAuto.Capture.cs'))
$fixtureSource=@'
namespace WindowCaptureTest {
using System;
using System.Diagnostics;
using System.Reflection;
using System.Threading;
using WowAutoCapture;
public static class WindowCaptureInitFixture {
    public static string Run(IntPtr window) {
        Type native=typeof(Native);
        Type sourceType=native.GetNestedType("Source",BindingFlags.NonPublic);
        object source=Activator.CreateInstance(sourceType,true);
        using(var process=Process.GetCurrentProcess())
            sourceType.GetField("Identity").SetValue(source,new RestoreRequest {
                ProcessId=process.Id,StartTicks=process.StartTime.Ticks,
                Path=process.MainModule.FileName,Window=window
            });
        sourceType.GetField("RequestedAt").SetValue(source,(long)(Stopwatch.GetTimestamp()*1000.0/Stopwatch.Frequency));
        MethodInfo run=native.GetMethod("Run",BindingFlags.NonPublic|BindingFlags.Static);
        Exception failure=null;
        Thread worker=new Thread(()=>{try {run.Invoke(null,new object[]{source});} catch(Exception error) {failure=error;}});
        worker.IsBackground=true;
        worker.SetApartmentState(ApartmentState.MTA);
        worker.Start();
        if(!worker.Join(8000)) {
            sourceType.GetField("Stop").SetValue(source,true);
            throw new Exception("WGC initialization did not finish in 8 seconds.");
        }
        if(failure!=null) throw failure;
        return (string)sourceType.GetField("Error").GetValue(source);
    }
}
}
'@
Add-Type -TypeDefinition ($captureSource+"`n"+$fixtureSource) -ReferencedAssemblies System.Drawing
$form=New-Object Windows.Forms.Form
$form.Text='WGC test window'
$form.Width=320
$form.Height=240
$form.ShowInTaskbar=$false
try {
    $form.Show()
    $itemType=[type]::GetType('Windows.Graphics.Capture.GraphicsCaptureItem, Windows.Graphics.Capture, ContentType=WindowsRuntime',$true)
    $itemInterface=$itemType.GetInterfaces() | Where-Object FullName -eq 'Windows.Graphics.Capture.IGraphicsCaptureItem'
    if ($itemInterface.GUID -ne [guid]'79c3f95b-31f7-4ec2-a464-632ef5d30760') {throw 'Installed WinRT metadata has an unexpected capture item IID.'}
    $method=[WowAutoCapture.Native].GetMethod('Item',[Reflection.BindingFlags]'NonPublic,Static')
    try {
        $item=$method.Invoke($null,@($form.Handle))
        if ($item.GetType().FullName -ne 'Windows.Graphics.Capture.GraphicsCaptureItem') {throw 'CreateForWindow returned the wrong WinRT type.'}
    } finally {if ($item -and [Runtime.InteropServices.Marshal]::IsComObject($item)) {$null=[Runtime.InteropServices.Marshal]::ReleaseComObject($item)}}
    $result=[WindowCaptureTest.WindowCaptureInitFixture]::Run($form.Handle)
    if ($result -notmatch '窗口捕获客户端版本不符') {throw "WGC initialization failed before the test-process identity check: $result"}
    Write-Output 'PASS: CreateForWindow, D3D11 device, frame pool and capture session initialize for this temporary window.'
} finally {
    $form.Close()
    $form.Dispose()
}
