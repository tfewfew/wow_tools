param([string]$PreviewPath)
$ErrorActionPreference = 'Stop'
if (-not ('WowAuto.NativeInput' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Threading;

namespace WowAuto
{
    public static class NativeInput
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct INPUT { public uint type; public InputUnion data; }

        // Include MOUSEINPUT so INPUT has the correct native size on x86/x64.
        [StructLayout(LayoutKind.Explicit)]
        public struct InputUnion
        {
            [FieldOffset(0)] public KEYBDINPUT keyboard;
            [FieldOffset(0)] public MOUSEINPUT mouse;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct KEYBDINPUT
        {
            public ushort wVk, wScan;
            public uint dwFlags, time;
            public UIntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct MOUSEINPUT
        {
            public int dx, dy;
            public uint mouseData, dwFlags, time;
            public UIntPtr dwExtraInfo;
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint SendInput(uint count, INPUT[] inputs, int size);

        private static INPUT Key(ushort key, bool up)
        {
            INPUT input = new INPUT();
            input.type = 1;
            input.data.keyboard.wVk = key;
            input.data.keyboard.dwFlags = up ? 2u : 0u;
            return input;
        }

        private static void Send(INPUT[] inputs)
        {
            uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
            if (sent != inputs.Length)
                throw new Win32Exception(Marshal.GetLastWin32Error(),
                    "SendInput failed or sent only part of the input. Check target permissions.");
        }

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")]
        private static extern bool IsIconic(IntPtr window);
        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

        public static bool IsTargetForeground(int targetProcessId)
        {
            using (System.Diagnostics.Process target = System.Diagnostics.Process.GetProcessById(targetProcessId))
            {
                if (!String.Equals(target.ProcessName, "WowClassic", StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("The selected WowClassic process is no longer available.");
                IntPtr window = target.MainWindowHandle;
                if (window == IntPtr.Zero || IsIconic(window)) return false;
                IntPtr foreground = GetForegroundWindow();
                uint foregroundProcessId;
                GetWindowThreadProcessId(foreground, out foregroundProcessId);
                return foreground == window && foregroundProcessId == (uint)targetProcessId;
            }
        }


        [StructLayout(LayoutKind.Sequential)]
        private struct RECT { public int left, top, right, bottom; }
        [StructLayout(LayoutKind.Sequential)]
        private struct POINT { public int x, y; }
        [DllImport("user32.dll")]
        private static extern bool GetClientRect(IntPtr window, out RECT rect);
        [DllImport("user32.dll")]
        private static extern bool ClientToScreen(IntPtr window, ref POINT point);
        [DllImport("user32.dll")]
        private static extern IntPtr GetDC(IntPtr window);
        [DllImport("user32.dll")]
        private static extern int ReleaseDC(IntPtr window, IntPtr dc);
        [DllImport("gdi32.dll")]
        private static extern uint GetPixel(IntPtr dc, int x, int y);
        [DllImport("user32.dll")]
        private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);

        // Return red, green, or unknown; accept modest rendering color differences.
        public static string ClassifyColor(uint color)
        {
            if (color == 0xFFFFFFFF) return "unknown";
            int red = (int)(color & 255);
            int green = (int)((color >> 8) & 255);
            int blue = (int)((color >> 16) & 255);
            if (red >= 200 && green >= 200 && blue <= 80) return "yellow";
            if (red >= 200 && green <= 80 && blue <= 80) return "red";
            if (green >= 200 && red <= 80 && blue <= 80) return "green";
            return "unknown";
        }

        public static string ReadCenterColor(int targetProcessId)
        {
            using (System.Diagnostics.Process target = System.Diagnostics.Process.GetProcessById(targetProcessId))
            {
                if (!String.Equals(target.ProcessName, "WowClassic", StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("The selected WowClassic process is no longer available.");
                IntPtr window = target.MainWindowHandle;
                if (window == IntPtr.Zero || IsIconic(window) || GetForegroundWindow() != window)
                    return "unknown";
                IntPtr oldContext = SetThreadDpiAwarenessContext(new IntPtr(-4));
                IntPtr dc = IntPtr.Zero;
                try
                {
                    RECT rect;
                    if (!GetClientRect(window, out rect) || rect.right <= rect.left || rect.bottom <= rect.top)
                        return "unknown";
                    POINT point = new POINT();
                    point.x = (rect.right - rect.left) / 2;
                    point.y = (rect.bottom - rect.top) / 2;
                    if (!ClientToScreen(window, ref point)) return "unknown";
                    dc = GetDC(IntPtr.Zero);
                    if (dc == IntPtr.Zero) return "unknown";
                    uint pixel = GetPixel(dc, point.x, point.y);
                    if (GetForegroundWindow() != window) return "unknown";
                    return ClassifyColor(pixel);
                }
                finally
                {
                    if (dc != IntPtr.Zero) ReleaseDC(IntPtr.Zero, dc);
                    if (oldContext != IntPtr.Zero) SetThreadDpiAwarenessContext(oldContext);
                }
            }
        }


        public static bool PressCtrlNumber(int targetProcessId, ushort number)
        {
            if (!IsTargetForeground(targetProcessId)) return false;
            try
            {
                Send(new INPUT[] { Key(0x11, false), Key(number, false) });
                Thread.Sleep(50);
            }
            finally
            {
                Send(new INPUT[] { Key(number, true), Key(0x11, true) });
            }
            return true;
        }
    }
}
"@
}


Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'wowAuto.Engine.ps1')
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:state = $null
$script:target = $null
$script:targetStartTime = $null
$script:clock = [System.Diagnostics.Stopwatch]::StartNew()
$form = New-Object System.Windows.Forms.Form
$form.Text = 'wowAuto'
$form.ClientSize = New-Object System.Drawing.Size(640, 490)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
$form.AutoScaleMode = 'Dpi'

function Add-Label($Text, $X, $Y, $Width, $Height) {
    $control = New-Object System.Windows.Forms.Label
    $control.Text = $Text
    $control.SetBounds($X, $Y, $Width, $Height)
    $form.Controls.Add($control)
    return $control
}
$title = Add-Label 'wowAuto' 24 18 300 38
$title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 21, [System.Drawing.FontStyle]::Bold)
$null = Add-Label '前台钓鱼工具 · 配合 wowDetector 使用' 26 62 580 28
$null = Add-Label '收竿等待范围（毫秒）' 26 104 580 28
$null = Add-Label '最小值' 26 147 65 28
$minimum = New-Object System.Windows.Forms.NumericUpDown
$minimum.SetBounds(94, 143, 165, 32)
$minimum.Minimum = 1
$minimum.Maximum = 3600000
$minimum.Value = 8000
$minimum.Increment = 1
$minimum.ThousandsSeparator = $false
$form.Controls.Add($minimum)
$null = Add-Label '最大值' 313 147 65 28
$maximum = New-Object System.Windows.Forms.NumericUpDown
$maximum.SetBounds(380, 143, 165, 32)
$maximum.Minimum = 1
$maximum.Maximum = 3600000
$maximum.Value = 13000
$maximum.Increment = 1
$maximum.ThousandsSeparator = $false
$form.Controls.Add($maximum)
$null = Add-Label 'ms' 552 147 50 28

$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = '开始'
$startButton.SetBounds(26, 195, 278, 43)
$startButton.BackColor = [System.Drawing.Color]::FromArgb(35, 100, 210)
$startButton.ForeColor = [System.Drawing.Color]::White
$startButton.FlatStyle = 'Flat'
$form.Controls.Add($startButton)
$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = '停止'
$stopButton.SetBounds(320, 195, 294, 43)
$stopButton.Enabled = $false
$form.Controls.Add($stopButton)
$null = Add-Label '当前状态' 26 258 580 28
$statusBox = New-Object System.Windows.Forms.TextBox
$statusBox.SetBounds(26, 290, 588, 120)
$statusBox.Multiline = $true
$statusBox.ReadOnly = $true
$statusBox.ScrollBars = 'Vertical'
$statusBox.BackColor = [System.Drawing.Color]::White
$statusBox.Text = '尚未开始。' + "`r`n" + '请先在游戏插件中点击“启动”，再在这里点击“开始”。'
$form.Controls.Add($statusBox)
$note = Add-Label "切回游戏后自动检测；切出游戏暂停。`r`n背包黄色信号会结束选中的游戏进程；关闭本窗口会停止工具。" 26 428 588 50
$note.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$note.ForeColor = [System.Drawing.Color]::FromArgb(80, 88, 100)

function Set-RunningControls([bool]$Running) {
    $startButton.Enabled = -not $Running
    $stopButton.Enabled = $Running
    $minimum.Enabled = -not $Running
    $maximum.Enabled = -not $Running
}

function Update-StatusBox {
    if ($null -eq $script:state) { return }
    $text = $script:state.Status
    if ($script:state.Running) {
        $text += "`r`n目标：WowClassic.exe（PID $($script:target.Id)）"
        $text += "`r`n等待范围：$($script:state.MinimumMs)–$($script:state.MaximumMs) ms"
        if ($script:state.Mode -in @('Wait', 'Cooldown')) {
            $remaining = [Math]::Max(0, $script:state.Deadline - $script:clock.ElapsedMilliseconds)
            $text += "`r`n剩余：$remaining ms"
        }
    }
    if ($statusBox.Text -ne $text) { $statusBox.Text = $text }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 25
$startButton.Add_Click({
    try {
        # Read the edited text as well as Value, including edits not yet committed by the control.
        $minText = $minimum.Text.Trim()
        $maxText = $maximum.Text.Trim()
        if ($minText -notmatch '^\d+$' -or $maxText -notmatch '^\d+$') { throw '请输入整数毫秒值。' }
        $newState = New-WowAutoState -MinimumMs ([int]$minText) -MaximumMs ([int]$maxText)
        $targets = @(Get-Process -Name 'WowClassic' -ErrorAction SilentlyContinue)
        if ($targets.Count -eq 0) { throw '未找到 WowClassic.exe，请先启动游戏。' }
        if ($targets.Count -ne 1) { throw '检测到多个游戏实例，请只保留一个后重试。' }
        $script:target = $targets[0]
        $script:targetStartTime = $script:target.StartTime
        $script:state = $newState
        $script:clock.Restart()
        Set-RunningControls $true
        $timer.Start()
        Update-StatusBox
    }
    catch { $statusBox.Text = '无法开始：' + $_.Exception.Message }
})
$stopButton.Add_Click({
    $timer.Stop()
    if ($null -ne $script:state) { Stop-WowAutoState $script:state '已停止，当前等待已取消。' }
    Set-RunningControls $false
    Update-StatusBox
})
$timer.Add_Tick({
    try {
        if ($null -eq $script:state -or -not $script:state.Running) { return }
        $now = $script:clock.ElapsedMilliseconds
        if ($now -ge $script:state.NextDue) {
            $script:target.Refresh()
            if ($script:target.HasExited) { throw '游戏进程已退出。' }
            if ($script:target.ProcessName -ne 'WowClassic' -or $script:target.StartTime -ne $script:targetStartTime) {
                throw '目标进程身份已改变，工具已停止。'
            }
            $foreground = [WowAuto.NativeInput]::IsTargetForeground($script:target.Id)
            $color = 'unknown'
            if ($foreground -and $script:state.Mode -ne 'Cooldown') {
                $color = [WowAuto.NativeInput]::ReadCenterColor($script:target.Id)
            }
            $action = Invoke-WowAutoState $script:state $now $foreground $color
            switch ($action) {
                'Ctrl1' { $null = [WowAuto.NativeInput]::PressCtrlNumber($script:target.Id, 0x31) }
                'Ctrl2' {
                    $sent = [WowAuto.NativeInput]::PressCtrlNumber($script:target.Id, 0x32)
                    Complete-WowAutoInteraction $script:state $script:clock.ElapsedMilliseconds $sent
                }
                'ExitGame' {
                    $timer.Stop()
                    # Kill the retained Process object, never reselect a process by name.
                    $script:target.Refresh()
                    if (-not $script:target.HasExited) {
                        if ($script:target.StartTime -ne $script:targetStartTime) { throw '进程身份已改变，未结束任何进程。' }
                        $script:target.Kill()
                    }
                    $script:state.Status = '背包已满，已发送结束游戏进程的请求；工具已停止。'
                    Set-RunningControls $false
                }
            }
        }
        Update-StatusBox
    }
    catch {
        $timer.Stop()
        if ($null -ne $script:state) { Stop-WowAutoState $script:state ('已停止：' + $_.Exception.Message) }
        Set-RunningControls $false
        Update-StatusBox
    }
})
$form.Add_FormClosing({
    $timer.Stop()
    if ($null -ne $script:state) { Stop-WowAutoState $script:state }
})
try {
    if ($PreviewPath) {
        # Briefly render the initial, stopped UI without starting automation.
        $form.Show()
        [System.Windows.Forms.Application]::DoEvents()
        $bitmap = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
        try {
            $form.DrawToBitmap($bitmap, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
            $bitmap.Save($PreviewPath, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally { $bitmap.Dispose() }
    }
    else { [void]$form.ShowDialog() }
}
finally { $timer.Dispose(); $form.Dispose() }
