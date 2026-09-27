param([string]$PreviewPath, [switch]$UiTest)
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
$script:rows = @{}
$script:mockProcesses = @()
$form = New-Object System.Windows.Forms.Form
$form.Text = 'wowAuto'
$form.ClientSize = New-Object System.Drawing.Size(1160, 460)
$form.MinimumSize = New-Object System.Drawing.Size(1080, 350)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
$form.AutoScaleMode = 'Dpi'

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 75
$header.Width = $form.ClientSize.Width
$title = New-Object System.Windows.Forms.Label
$title.Text = 'wowAuto'
$title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 21, [System.Drawing.FontStyle]::Bold)
$title.SetBounds(20, 14, 230, 45)
$header.Controls.Add($title)
$countLabel = New-Object System.Windows.Forms.Label
$countLabel.SetBounds(270, 27, 670, 30)
$countLabel.Anchor = 'Top, Left, Right'
$header.Controls.Add($countLabel)
$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = '刷新进程'
$refreshButton.SetBounds(1020, 20, 115, 36)
$refreshButton.Anchor = 'Top, Right'
$header.Controls.Add($refreshButton)
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$tab = New-Object System.Windows.Forms.TabPage
$tab.Text = 'autofish'
$tab.BackColor = [System.Drawing.Color]::White
$tabs.TabPages.Add($tab)
$form.Controls.Add($tabs)
$form.Controls.Add($header)

$intro = New-Object System.Windows.Forms.Label
$intro.Dock = 'Top'
$intro.Height = 44
$intro.Padding = New-Object System.Windows.Forms.Padding(12, 12, 0, 0)
$intro.Text = '每行独立控制一个游戏进程。先在游戏插件中启动检测，再点击对应行的开始。'
$headings = New-Object System.Windows.Forms.Panel
$headings.Dock = 'Top'
$headings.Height = 32
foreach ($heading in @(@('游戏进程',12,230), @('最小等待 ms',250,105), @('最大等待 ms',360,105), @('操作',475,145), @('实时状态',635,350))) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $heading[0]
    $label.SetBounds($heading[1], 3, $heading[2], 25)
    $headings.Controls.Add($label)
}
$list = New-Object System.Windows.Forms.FlowLayoutPanel
$list.Dock = 'Fill'
$list.FlowDirection = 'TopDown'
$list.WrapContents = $false
$list.AutoScroll = $true
$list.Padding = New-Object System.Windows.Forms.Padding(6, 0, 6, 0)
$footer = New-Object System.Windows.Forms.Label
$footer.Dock = 'Bottom'
$footer.Height = 43
$footer.Padding = New-Object System.Windows.Forms.Padding(12, 10, 0, 0)
$footer.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$footer.Text = '仅前台游戏发送按键；后台行暂停。黄色信号只结束对应游戏进程。关闭窗口会停止所有行。'
$tab.Controls.Add($list)
$tab.Controls.Add($headings)
$tab.Controls.Add($intro)
$tab.Controls.Add($footer)

function Get-WowAutoProcesses {
    if ($UiTest) { return $script:mockProcesses }
    return @(Get-Process -Name 'WowClassic' -ErrorAction SilentlyContinue | Sort-Object Id)
}

function Set-RowControls($Row) {
    $running = $null -ne $Row.State -and $Row.State.Running
    $Row.Start.Enabled = -not $running -and $null -ne $Row.StartTime -and -not $Row.Exited
    $Row.Stop.Enabled = $running
    $Row.Minimum.Enabled = -not $running
    $Row.Maximum.Enabled = -not $running
}

function Update-RowStatus($Row) {
    if ($null -ne $Row.State) {
        $text = $Row.State.Status
        if ($Row.State.Running -and $Row.State.Mode -in @('Wait', 'Cooldown')) {
            $left = [Math]::Max(0, $Row.State.Deadline - $Row.Clock.ElapsedMilliseconds)
            $text += "`r`n剩余 $left ms"
        }
        if ($Row.Status.Text -ne $text) { $Row.Status.Text = $text }
    }
    Set-RowControls $Row
}

function Stop-Row($Row, [string]$Reason = '已停止，当前等待已取消。') {
    if ($null -ne $Row.State) { Stop-WowAutoState $Row.State $Reason }
    else { $Row.Status.Text = $Reason }
    Update-RowStatus $Row
}

function Start-Row($Row) {
    try {
        if ($null -ne $Row.State -and $Row.State.Running) { return }
        $minText = $Row.Minimum.Text.Trim()
        $maxText = $Row.Maximum.Text.Trim()
        if ($minText -notmatch '^\d+$' -or $maxText -notmatch '^\d+$') { throw '请输入整数毫秒值。' }
        $newState = New-WowAutoState ([int]$minText) ([int]$maxText)
        $Row.Process.Refresh()
        if ($Row.Process.HasExited) { throw '该游戏进程已退出，请刷新。' }
        if ($null -eq $Row.StartTime -or $Row.Process.StartTime -ne $Row.StartTime -or $Row.Process.ProcessName -ne 'WowClassic') {
            throw '进程身份已变化，请刷新。'
        }
        $Row.State = $newState
        $Row.Clock.Restart()
        Update-RowStatus $Row
    }
    catch {
        if ($null -ne $Row.State) { Stop-WowAutoState $Row.State ('无法开始：' + $_.Exception.Message) }
        $Row.Status.Text = '无法开始：' + $_.Exception.Message
        Set-RowControls $Row
    }
}

function New-ProcessRow($Process, $StartTime, [string]$Key) {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Height = 82
    $panel.Width = [Math]::Max(1000, $list.ClientSize.Width - 32)
    $panel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
    $panel.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
    $nameLabel = New-Object System.Windows.Forms.Label
    $nameLabel.SetBounds(6, 14, 232, 56)
    $panel.Controls.Add($nameLabel)
    $minimum = New-Object System.Windows.Forms.NumericUpDown
    $minimum.SetBounds(244, 25, 100, 30)
    $minimum.Minimum = 1; $minimum.Maximum = 3600000; $minimum.Value = 8000
    $panel.Controls.Add($minimum)
    $maximum = New-Object System.Windows.Forms.NumericUpDown
    $maximum.SetBounds(354, 25, 100, 30)
    $maximum.Minimum = 1; $maximum.Maximum = 3600000; $maximum.Value = 13000
    $panel.Controls.Add($maximum)
    $start = New-Object System.Windows.Forms.Button
    $start.Text = '开始'
    $start.SetBounds(469, 21, 68, 37)
    $start.BackColor = [System.Drawing.Color]::FromArgb(35, 100, 210)
    $start.ForeColor = [System.Drawing.Color]::White
    $start.FlatStyle = 'Flat'
    $panel.Controls.Add($start)
    $stop = New-Object System.Windows.Forms.Button
    $stop.Text = '停止'
    $stop.SetBounds(543, 21, 68, 37)
    $stop.Enabled = $false
    $panel.Controls.Add($stop)
    $status = New-Object System.Windows.Forms.TextBox
    $status.SetBounds(629, 12, $panel.Width - 641, 58)
    $status.Anchor = 'Top, Left, Right'
    $status.Multiline = $true
    $status.ReadOnly = $true
    $status.ScrollBars = 'Vertical'
    $status.BackColor = [System.Drawing.Color]::White
    $status.Text = '尚未开始。'
    $panel.Controls.Add($status)
    $row = [pscustomobject]@{
        Key=$Key; Process=$Process; StartTime=$StartTime; Exited=$false
        Panel=$panel; Name=$nameLabel; Minimum=$minimum; Maximum=$maximum
        Start=$start; Stop=$stop; Status=$status; State=$null
        Clock=[System.Diagnostics.Stopwatch]::StartNew()
    }
    # Sender.Tag keeps handlers bound to their own row, not a shared loop variable.
    $start.Tag = $row
    $stop.Tag = $row
    $start.Add_Click({ param($sender, $eventArgs) Start-Row $sender.Tag })
    $stop.Add_Click({ param($sender, $eventArgs) Stop-Row $sender.Tag })
    if ($null -eq $StartTime) { $status.Text = '无法读取进程信息，请检查权限后刷新。' }
    Set-RowControls $row
    return $row
}

function Refresh-ProcessRows {
    try {
        $processes = @(Get-WowAutoProcesses)
        $next = @{}
        $ordered = @()
        foreach ($process in $processes) {
            $started = $null
            try { $started = $process.StartTime } catch { }
            $key = if ($null -ne $started) { "$($process.Id):$($started.Ticks)" } else { "$($process.Id):unknown" }
            $row = $script:rows[$key]
            if ($null -eq $row) { $row = New-ProcessRow $process $started $key }
            $caption = 'WowClassic.exe'
            try { if ($process.MainWindowTitle) { $caption = $process.MainWindowTitle } } catch { }
            $row.Name.Text = "$caption`r`nPID $($process.Id)"
            $next[$key] = $row
            $ordered += $row
        }
        foreach ($key in @($script:rows.Keys)) {
            if (-not $next.ContainsKey($key)) {
                Stop-Row $script:rows[$key] '进程已退出，已停止。'
                $script:rows[$key].Panel.Dispose()
            }
        }
        $list.SuspendLayout()
        $list.Controls.Clear()
        $script:rows = $next
        foreach ($row in $ordered) { $list.Controls.Add($row.Panel) }
        $list.ResumeLayout()
        $countLabel.Text = "检测到 $($processes.Count) 个 WowClassic.exe 进程"
        if ($processes.Count -eq 0) { $countLabel.Text += '，启动游戏后点击刷新。' }
    }
    catch { $countLabel.Text = '刷新失败：' + $_.Exception.Message }
}
$refreshButton.Add_Click({ Refresh-ProcessRows })
$list.Add_SizeChanged({
    foreach ($row in $script:rows.Values) { $row.Panel.Width = [Math]::Max(1000, $list.ClientSize.Width - 32) }
})

function Invoke-RowTick($Row) {
    try {
        if ($null -eq $Row.State -or -not $Row.State.Running) { return }
        $now = $Row.Clock.ElapsedMilliseconds
        if ($now -ge $Row.State.NextDue) {
            $Row.Process.Refresh()
            if ($Row.Process.HasExited) { $Row.Exited=$true; throw '游戏进程已退出，请刷新。' }
            if ($Row.Process.ProcessName -ne 'WowClassic' -or $Row.Process.StartTime -ne $Row.StartTime) { throw '目标进程身份已改变。' }
            $foreground = [WowAuto.NativeInput]::IsTargetForeground($Row.Process.Id)
            $color = 'unknown'
            if ($foreground -and $Row.State.Mode -ne 'Cooldown') { $color = [WowAuto.NativeInput]::ReadCenterColor($Row.Process.Id) }
            $action = Invoke-WowAutoState $Row.State $now $foreground $color
            switch ($action) {
                'Ctrl1' { $null = [WowAuto.NativeInput]::PressCtrlNumber($Row.Process.Id, 0x31) }
                'Ctrl2' {
                    $sent = [WowAuto.NativeInput]::PressCtrlNumber($Row.Process.Id, 0x32)
                    Complete-WowAutoInteraction $Row.State $Row.Clock.ElapsedMilliseconds $sent
                }
                'ExitGame' {
                    $Row.Process.Refresh()
                    if (-not $Row.Process.HasExited) {
                        if ($Row.Process.StartTime -ne $Row.StartTime) { throw '进程身份已改变，未结束任何进程。' }
                        $Row.Process.Kill()
                    }
                    $Row.Exited = $true
                    $Row.State.Status = '背包已满，已请求结束此游戏进程；本行已停止。'
                }
            }
        }
        Update-RowStatus $Row
    }
    catch { Stop-Row $Row ('已停止：' + $_.Exception.Message) }
}
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 25
$timer.Add_Tick({ foreach ($row in @($script:rows.Values)) { Invoke-RowTick $row } })
$form.Add_FormClosing({
    $timer.Stop()
    foreach ($row in $script:rows.Values) { Stop-Row $row }
})

try {
    if ($UiTest) {
        # Test fixtures are never passed to native input, capture, or termination.
        foreach ($id in @(101, 202, 303)) {
            $mock = [pscustomobject]@{ Id=$id; StartTime=[datetime]'2026-09-27'; ProcessName='WowClassic'; MainWindowTitle="测试游戏 $id"; HasExited=$false }
            $mock | Add-Member ScriptMethod Refresh { }
            $script:mockProcesses += $mock
        }
    }
    Refresh-ProcessRows
    if (-not $PreviewPath -and -not $UiTest) { $timer.Start() }
    if ($PreviewPath -or $UiTest) {
        $form.Show()
        [System.Windows.Forms.Application]::DoEvents()
        if ($UiTest) {
            # Resolve by Id rather than relying on local date parsing.
            $a = @($script:rows.Values | Where-Object { $_.Process.Id -eq 101 })[0]
            $b = @($script:rows.Values | Where-Object { $_.Process.Id -eq 202 })[0]
            if ($script:rows.Count -ne 3) { throw 'Expected three rows.' }
            if (-not $header.ClientRectangle.Contains($refreshButton.Bounds)) { throw 'Refresh button outside header.' }
            $a.Start.PerformClick()
            $b.Minimum.Value = 2345; $b.Maximum.Value = 6789
            $b.Start.PerformClick()
            if (-not $a.State.Running -or -not $b.State.Running -or $b.State.MinimumMs -ne 2345 -or $a.State.MinimumMs -ne 8000) { throw 'Independent start/range failed.' }
            $refreshButton.PerformClick()
            if ($script:rows[$a.Key] -ne $a -or -not $a.State.Running) { throw 'Refresh lost active state.' }
            $a.Stop.PerformClick()
            if ($a.State.Running -or -not $b.State.Running) { throw 'Stop affected another row.' }
            $script:mockProcesses = @($script:mockProcesses | Where-Object { $_.Id -ne 202 })
            $refreshButton.PerformClick()
            if ($script:rows.Count -ne 2 -or $b.State.Running) { throw 'Exited process not removed/stopped.' }
            # Reused PID creates a fresh row, never inherits the old session.
            $script:mockProcesses[0].StartTime = $script:mockProcesses[0].StartTime.AddSeconds(1)
            $refreshButton.PerformClick()
            $fresh = @($script:rows.Values | Where-Object { $_.Process.Id -eq 101 })[0]
            if ($fresh -eq $a -or $null -ne $fresh.State) { throw 'PID reuse retained old state.' }
            Write-Output 'PASS: independent rows/ranges, button bindings, refresh preservation, exited process removal, PID reuse. No native actions executed.'
        }
        if ($PreviewPath) {
            [System.Windows.Forms.Application]::DoEvents()
            $bitmap = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
            try {
                $form.DrawToBitmap($bitmap, (New-Object System.Drawing.Rectangle(0,0,$form.Width,$form.Height)))
                $bitmap.Save($PreviewPath, [System.Drawing.Imaging.ImageFormat]::Png)
            }
            finally { $bitmap.Dispose() }
        }
    }
    else { [void]$form.ShowDialog() }
}
finally { $timer.Dispose(); $form.Dispose() }
