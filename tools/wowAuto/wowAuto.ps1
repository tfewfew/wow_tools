param([string]$PreviewPath, [switch]$UiTest)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'wowAuto.Logging.ps1')
$script:logMaxSizeMB=50
$script:logTestDirectory=if ($UiTest) {Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-log-test-'+[guid]::NewGuid().ToString('N'))} else {$null}
Initialize-WowAutoLogging $(if ($UiTest) {$script:logTestDirectory} else {Join-Path $PSScriptRoot 'log'})
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

        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr window);
        [DllImport("user32.dll")]
        private static extern bool ShowWindowAsync(IntPtr window, int command);
        [DllImport("user32.dll")]
        private static extern bool IsWindow(IntPtr window);

        public static IntPtr CurrentWindow() { return GetForegroundWindow(); }

        // Identify the installed client, including the product directory and build family.
        // Retail uses the same Wow.exe filename and must not enter the fishing queue.
        public static string GetClientFlavor(string executablePath, string version)
        {
            if (String.IsNullOrEmpty(executablePath) || String.IsNullOrEmpty(version)) return null;
            string file = System.IO.Path.GetFileName(executablePath);
            string product = System.IO.Path.GetFileName(System.IO.Path.GetDirectoryName(executablePath));
            if (String.Equals(file, "WowClassic.exe", StringComparison.OrdinalIgnoreCase)
                && String.Equals(product, "_classic_titan_", StringComparison.OrdinalIgnoreCase)
                && version.StartsWith("3.80.", StringComparison.Ordinal)) return "titan";
            if (String.Equals(file, "Wow.exe", StringComparison.OrdinalIgnoreCase)
                && String.Equals(product, "_cn_beta_", StringComparison.OrdinalIgnoreCase)
                && version.StartsWith("1.60.", StringComparison.Ordinal)) return "forerver";
            return null;
        }

        public static bool MatchesClientIdentity(string name, long actualStart, string path, string version,
            long expectedStart, string expectedPath)
        {
            return actualStart == expectedStart && GetClientFlavor(path, version) != null
                && String.Equals(path, expectedPath, StringComparison.OrdinalIgnoreCase)
                && String.Equals(name, System.IO.Path.GetFileNameWithoutExtension(path), StringComparison.OrdinalIgnoreCase);
        }

        private static bool MatchesTarget(System.Diagnostics.Process target, long startTimeTicks, string executablePath)
        {
            string path = target.MainModule.FileName;
            string version = System.Diagnostics.FileVersionInfo.GetVersionInfo(path).FileVersion;
            return MatchesClientIdentity(target.ProcessName, target.StartTime.Ticks, path, version, startTimeTicks, executablePath);
        }

        // Foreground activation for refresh validation and the shared scheduler.
        public static bool ActivateForScan(int processId, long startTimeTicks, string executablePath)
        {
            using (System.Diagnostics.Process target = System.Diagnostics.Process.GetProcessById(processId))
            {
                if (!MatchesTarget(target, startTimeTicks, executablePath)) return false;
                IntPtr window = target.MainWindowHandle;
                if (window == IntPtr.Zero) return false;
                if (IsIconic(window)) ShowWindowAsync(window, 9);
                SetForegroundWindow(window);
                return true; // The scan verifies actual foreground ownership before sampling.
            }
        }

        public static bool RestoreAfterScan(IntPtr window)
        {
            return window != IntPtr.Zero && IsWindow(window) && SetForegroundWindow(window);
        }


        public static bool IsTargetForeground(int targetProcessId, long startTimeTicks, string executablePath)
        {
            using (System.Diagnostics.Process target = System.Diagnostics.Process.GetProcessById(targetProcessId))
            {
                if (!MatchesTarget(target, startTimeTicks, executablePath))
                    throw new InvalidOperationException("The selected WoW client identity has changed.");
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
        [StructLayout(LayoutKind.Sequential)]
        private struct MONITORINFO { public int size; public RECT monitor, work; public uint flags; }
        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr window, out RECT rect);
        [DllImport("user32.dll")]
        private static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);
        [DllImport("user32.dll")]
        private static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);
        [DllImport("user32.dll")]
        private static extern bool GetClientRect(IntPtr window, out RECT rect);
        [DllImport("user32.dll")]
        private static extern bool ClientToScreen(IntPtr window, ref POINT point);
        [DllImport("user32.dll")]
        private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);

        public static string ClassifyWindowPosition(int left, int top, int right, int bottom,
            int screenLeft, int screenTop, int screenRight, int screenBottom)
        {
            if (right <= left || bottom <= top || screenRight <= screenLeft || screenBottom <= screenTop)
                return "位置未知";
            double x = ((double)left + right) / 2, y = ((double)top + bottom) / 2;
            double middleX = ((double)screenLeft + screenRight) / 2, middleY = ((double)screenTop + screenBottom) / 2;
            if (Math.Abs(x - middleX) <= (screenRight - screenLeft) * 0.1
                && Math.Abs(y - middleY) <= (screenBottom - screenTop) * 0.1) return "居中";
            return (y < middleY ? (x < middleX ? "左上" : "右上") : (x < middleX ? "左下" : "右下"));
        }

        public static string ReadWindowPosition(int processId, long startTimeTicks, string executablePath)
        {
            using (System.Diagnostics.Process target = System.Diagnostics.Process.GetProcessById(processId))
            {
                if (!MatchesTarget(target, startTimeTicks, executablePath)) return "位置未知";
                IntPtr window = target.MainWindowHandle;
                if (window == IntPtr.Zero) return "位置未知";
                if (IsIconic(window)) return "最小化";
                IntPtr oldContext = SetThreadDpiAwarenessContext(new IntPtr(-4));
                try
                {
                    RECT rect;
                    MONITORINFO info = new MONITORINFO();
                    info.size = Marshal.SizeOf(typeof(MONITORINFO));
                    if (!GetWindowRect(window, out rect) || !GetMonitorInfo(MonitorFromWindow(window, 2), ref info)) return "位置未知";
                    return ClassifyWindowPosition(rect.left, rect.top, rect.right, rect.bottom,
                        info.monitor.left, info.monitor.top, info.monitor.right, info.monitor.bottom);
                }
                finally { if (oldContext != IntPtr.Zero) SetThreadDpiAwarenessContext(oldContext); }
            }
        }

        // Return red, green, or unknown; accept modest rendering color differences.
        public static string ClassifyColor(uint color)
        {
            if (color == 0xFFFFFFFF) return "unknown";
            int red = (int)(color & 255);
            int green = (int)((color >> 8) & 255);
            int blue = (int)((color >> 16) & 255);
            if (green >= 254 && blue >= 254 && red <= 1) return "dead";
            if (red >= 200 && green >= 200 && blue <= 80) return "yellow";
            if (red >= 200 && green <= 80 && blue <= 80) return "red";
            if (green >= 200 && red <= 80 && blue <= 80) return "green";
            if (blue >= 200 && red <= 80 && green <= 80) return "present";
            if (red >= 200 && blue >= 200 && green <= 80) return "missing";
            return "unknown";
        }

        public static string ReadCenterColor(int targetProcessId, long startTimeTicks, string executablePath)
        {
            return ReadDetectionColor(targetProcessId, startTimeTicks, executablePath, 0);
        }

        public static string ReadLureColor(int targetProcessId, long startTimeTicks, string executablePath)
        {
            return ReadDetectionColor(targetProcessId, startTimeTicks, executablePath, 32);
        }

        public static Func<int,long,string,int,uint> WindowPixelReader;
        private static string ReadDetectionColor(int targetProcessId, long startTimeTicks, string executablePath, int offsetX)
        {
            if (WindowPixelReader == null) throw new InvalidOperationException("Window capture source is not initialized.");
            return ClassifyColor(WindowPixelReader(targetProcessId,startTimeTicks,executablePath,offsetX));
        }


        public static bool PressChord(int targetProcessId, long startTimeTicks, string executablePath, ushort number, bool ctrl, bool shift, bool alt)
        {
            if (!IsTargetForeground(targetProcessId, startTimeTicks, executablePath)) return false;
            var down = new System.Collections.Generic.List<INPUT>();
            var up = new System.Collections.Generic.List<INPUT>();
            if (ctrl) down.Add(Key(0x11, false));
            if (shift) down.Add(Key(0x10, false));
            if (alt) down.Add(Key(0x12, false));
            down.Add(Key(number, false));
            up.Add(Key(number, true));
            if (alt) up.Add(Key(0x12, true));
            if (shift) up.Add(Key(0x10, true));
            if (ctrl) up.Add(Key(0x11, true));
            try
            {
                Send(down.ToArray());
                Thread.Sleep(50);
            }
            finally
            {
                Send(up.ToArray());
            }
            return true;
        }

        // Send only the two addon start commands, never arbitrary chat text or macros.
        public static bool SendDetectorCommand(int processId, long startTicks, string path, string mode)
        {
            string command = DetectorCommand(mode);
            if (!PressChord(processId,startTicks,path,13,false,false,false)) return false;
            if (!PressChord(processId,startTicks,path,65,true,false,false)) return false;
            if (!IsTargetForeground(processId,startTicks,path)) return false;
            var inputs = new System.Collections.Generic.List<INPUT>();
            foreach (char character in command) {
                INPUT down = new INPUT(); down.type=1;
                down.data.keyboard.wScan=character; down.data.keyboard.dwFlags=4;
                INPUT up=down; up.data.keyboard.dwFlags=6;
                inputs.Add(down); inputs.Add(up);
            }
            Send(inputs.ToArray());
            return PressChord(processId,startTicks,path,13,false,false,false);
        }
        public static string DetectorCommand(string mode)
        {
            if (mode=="fish") return "/wowdetector on";
            if (mode=="fight") return "/fightdetector on";
            throw new ArgumentException("Unknown detector mode.");
        }
        public static string RotationCommand(string action,int token)
        {
            if(action=="logout") return "/logout";
            throw new ArgumentException("Unknown rotation command.");
        }
        public static bool SendRotationCommand(int pid,long ticks,string path,string action,int token)
        {
            string command=RotationCommand(action,token);
            if(action=="logout" && !SendChatCommand(pid,ticks,path,"/stopcasting")) return false;
            return SendChatCommand(pid,ticks,path,command);
        }
        private static bool SendChatCommand(int pid,long ticks,string path,string command)
        {
            if(!PressChord(pid,ticks,path,13,false,false,false) || !PressChord(pid,ticks,path,65,true,false,false)) return false;
            if(!IsTargetForeground(pid,ticks,path)) return false;
            var inputs=new System.Collections.Generic.List<INPUT>();
            foreach(char c in command) {
                INPUT down=new INPUT();down.type=1;down.data.keyboard.wScan=c;down.data.keyboard.dwFlags=4;
                INPUT up=down;up.data.keyboard.dwFlags=6;inputs.Add(down);inputs.Add(up);
            }
            Send(inputs.ToArray());
            return PressChord(pid,ticks,path,13,false,false,false);
        }
    }
}
"@
}



Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'wowAuto.Capture.ps1')
if (-not ('WowAuto.DimTabControl' -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
namespace WowAuto {
    public sealed class DimForm : Form {
        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr window, int attribute,
            ref int value, int size);
        protected override void OnHandleCreated(EventArgs e) {
            base.OnHandleCreated(e);
            // Apply per-window caption colors again whenever WinForms recreates the handle.
            try {
                int dark = 1, black = 0, white = 0x00FFFFFF;
                DwmSetWindowAttribute(Handle, 20, ref dark, sizeof(int)); // Immersive dark mode.
                DwmSetWindowAttribute(Handle, 35, ref black, sizeof(int)); // Caption color.
                DwmSetWindowAttribute(Handle, 36, ref white, sizeof(int)); // Caption text color.
            }
            catch (DllNotFoundException) { }
            catch (EntryPointNotFoundException) { }
        }
    }
    public sealed class DimStatusLog : TextBox {
        [DllImport("user32.dll")]
        private static extern IntPtr SendMessage(IntPtr window, int message, IntPtr wParam, IntPtr lParam);
        public int FirstVisibleLine {
            get { return IsHandleCreated ? SendMessage(Handle, 0x00CE, IntPtr.Zero, IntPtr.Zero).ToInt32() : 0; }
        }
        public void SetStatusText(string value) {
            if (Text == value) return;
            int firstLine = FirstVisibleLine, selection = SelectionStart, length = SelectionLength;
            Text = value;
            Select(Math.Min(selection, TextLength), Math.Min(length, Math.Max(0, TextLength - selection)));
            if (IsHandleCreated)
                SendMessage(Handle, 0x00B6, IntPtr.Zero, new IntPtr(firstLine - FirstVisibleLine));
        }
    }
    // Keep disabled controls readable without changing their input permissions.
    public sealed class DimButton : Button {
        protected override void OnPaint(PaintEventArgs e) {
            base.OnPaint(e);
            if (Enabled) return;
            Rectangle bounds = ClientRectangle;
            bounds.Inflate(-1, -1);
            using (var brush = new SolidBrush(BackColor))
                e.Graphics.FillRectangle(brush, bounds);
            TextRenderer.DrawText(e.Graphics, Text, Font, bounds, ForeColor,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        }
    }
    public sealed class DimCheckBox : CheckBox {
        protected override void OnPaint(PaintEventArgs e) {
            base.OnPaint(e);
            if (Enabled) return;
            e.Graphics.Clear(BackColor);
            int size = (int)Math.Round(13 * e.Graphics.DpiX / 96);
            Rectangle glyph = new Rectangle(0, (Height - size) / 2, size, size);
            ControlPaint.DrawCheckBox(e.Graphics, glyph,
                ButtonState.Inactive | (Checked ? ButtonState.Checked : ButtonState.Normal));
            int textLeft = size + (int)Math.Round(4 * e.Graphics.DpiX / 96);
            Rectangle textBounds = new Rectangle(textLeft, 0, Math.Max(0, Width - textLeft), Height);
            TextRenderer.DrawText(e.Graphics, Text, Font, textBounds, ForeColor,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
        }
    }
    public sealed class DimTabControl : TabControl {
        public Color HeaderBackground { get; set; }
        public Color HeaderSurface { get; set; }
        public DimTabControl() {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        }
        protected override void OnPaintBackground(PaintEventArgs e) {
            e.Graphics.Clear(HeaderBackground);
        }
        protected override void OnPaint(PaintEventArgs e) {
            for (int i = 0; i < TabCount; i++) {
                Rectangle bounds = GetTabRect(i);
                using (var brush = new SolidBrush(i == SelectedIndex ? HeaderSurface : HeaderBackground))
                    e.Graphics.FillRectangle(brush, bounds);
                TextRenderer.DrawText(e.Graphics, TabPages[i].Text, Font, bounds, ForeColor,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
            }
            base.OnPaint(e);
        }
        protected override void OnSelectedIndexChanged(EventArgs e) {
            base.OnSelectedIndexChanged(e); Invalidate();
        }
    }
}
'@
}
. (Join-Path $PSScriptRoot 'wowAuto.Engine.ps1')
. (Join-Path $PSScriptRoot 'wowAuto.ActionQueue.ps1')
Initialize-GameActionQueue (Join-Path $PSScriptRoot 'action-priorities.json')
if (-not ('WowAuto.Audio.ProcessCapture' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'wowAuto.Audio.cs') }
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:rows = @{}
$script:scheduler = New-WowAutoScheduler
$script:schedulerClock = [System.Diagnostics.Stopwatch]::StartNew()
$script:pendingWork = $null
$script:pendingGameExits = @{}
$script:audioCaptures = @{}
$script:audioUseTemplate = -not $UiTest
$script:audioFeatureDirectory = if ($UiTest) { Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-features-test-'+[Guid]::NewGuid()) }
    else { Join-Path $PSScriptRoot 'audio-features' }
. (Join-Path $PSScriptRoot 'wowAuto.Recordings.ps1')
$script:workerFocus = 0
$script:workerActivations = @()
$script:workerKeys = @()
$script:workerClosed = @()
$script:workerKilled = @()
$script:mockProcesses = @()
$script:scanning = $false
$script:scanClock = [System.Diagnostics.Stopwatch]::StartNew()
$script:scanOriginalWindow = [IntPtr]::Zero
$script:scanOrder = @()
$script:scanGeneration = 0L
$script:restored = $false
$script:editingSettings = $false
$script:versionRanges = @{
    titan=[pscustomobject]@{MinimumMs=300; MaximumMs=600; AudioTimeoutMs=35000}
    forerver=[pscustomobject]@{MinimumMs=300; MaximumMs=600; AudioTimeoutMs=35000}
}
$script:audioThresholds = @{titan=86; forerver=86}
$script:statusLogLimit = 50
$script:settingsPath = if ($UiTest) { Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-test-' + [Guid]::NewGuid().ToString() + '.ini') }
    else { Join-Path $PSScriptRoot 'config.ini' }
function New-KeyBinding([int]$Code, [bool]$Ctrl, [bool]$Shift, [bool]$Alt) {
    if (-not (($Code -ge 48 -and $Code -le 57) -or ($Code -ge 65 -and $Code -le 90) -or ($Code -ge 96 -and $Code -le 111) -or
        ($Code -ge 112 -and $Code -le 135) -or $Code -in @(8,9,13,27,32,33,34,35,36,37,38,39,40,45,46,187,189))) { return $null }
    $parts=@()
    if ($Ctrl) { $parts+='Ctrl' }; if ($Shift) { $parts+='Shift' }; if ($Alt) { $parts+='Alt' }
    $name=([System.Windows.Forms.Keys]$Code).ToString()
    if ($Code -ge 48 -and $Code -le 57) { $name=[string]($Code-48) }
    if ($Code -eq 189) { $name='-' }
    if ($Code -eq 187) { $name='=' }
    $parts+=$name
    return [pscustomobject]@{ Code=$Code; Ctrl=$Ctrl; Shift=$Shift; Alt=$Alt; Text=($parts -join '+') }
}
function ConvertFrom-KeyBindingText([string]$Text) {
    $parts=$Text.Trim().Split('+'); $modifiers=@{Ctrl=$false; Shift=$false; Alt=$false}
    for ($i=0; $i -lt $parts.Length-1; $i++) {
        $modifier=$parts[$i].Trim()
        if (-not $modifiers.ContainsKey($modifier) -or $modifiers[$modifier]) { throw '快捷键修饰键无效或重复。' }
        $modifiers[$modifier]=$true
    }
    $key=$parts[-1].Trim(); $code=0
    if ($key -match '^\d$') { $code=48+[int]$key }
    elseif ($key -eq '-') { $code=189 }
    elseif ($key -eq '=') { $code=187 }
    elseif ($key -match '^[A-Za-z][A-Za-z0-9]*$') {
        try { $code=[int][System.Enum]::Parse([System.Windows.Forms.Keys],$key,$true) }
        catch { throw "无效的快捷键：$Text。" }
    }
    $binding=New-KeyBinding $code $modifiers.Ctrl $modifiers.Shift $modifiers.Alt
    if ($null -eq $binding) { throw "无效的快捷键：$Text。" }
    return $binding
}
function ConvertTo-PreferenceFlag($Value) {
    if ($Value -is [bool]) { return [int]$Value }
    if ([string]$Value -notmatch '^[01]$') { throw '开关配置必须为0或1。' }
    return [int]$Value
}
$script:keyBindings=@{
    Cast=(New-KeyBinding 48 $false $false $false)
    Reel=(New-KeyBinding 187 $false $false $false)
    Item=(New-KeyBinding 189 $false $false $false)
}
$script:audioDetectionEnabled=-not $UiTest
$script:processItemPreferences=@{}
$script:processModePreferences=@{}
$script:updatingPreferenceControls=$false
$script:requiredSettingsKeys = @('TitanMinimumMs','TitanMaximumMs','ForerverMinimumMs','ForerverMaximumMs','FocusRetryIntervalMs')
$script:audioSettingsKeys = @('TitanAudioThresholdPercent','ForerverAudioThresholdPercent')
$script:audioTimeoutSettingsKeys = @('TitanAudioTimeoutMs','ForerverAudioTimeoutMs')
$script:recordingSettingsKeys = @('TitanAudioRecordingId','ForerverAudioRecordingId')
$script:preferenceSettingsKeys = @('ReelHoldMs','CastKey','ReelKey','ItemKey','AudioDetectionEnabled')
$script:settingsKeys = $script:requiredSettingsKeys + $script:audioSettingsKeys + $script:audioTimeoutSettingsKeys + $script:recordingSettingsKeys + $script:preferenceSettingsKeys + @('StatusLogLimit','JumpEveryCycles','LogMaxSizeMB')
$script:settingsWarning = ''
function Read-WowAutoSettingsIni([string]$Path) {
    $values=@{}; $items=@{}; $modes=@{}; $seen=@{}; $lineNumber=0
    foreach ($sourceLine in [IO.File]::ReadAllLines($Path)) {
        $lineNumber++; $line=$sourceLine.Trim()
        if ($line -eq '' -or $line.StartsWith(';') -or $line.StartsWith('#')) { continue }
        if ($line -notmatch '^([A-Za-z][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') { throw "config.ini 第 $lineNumber 行格式错误，需为键=值。" }
        $key=$matches[1]; $value=$matches[2]
        if ($seen.ContainsKey($key)) { throw "config.ini 存在重复配置项：$key。" }
        $seen[$key]=$true
        if ($key -match '^Mode_([1-9]\d*)_([1-9]\d*)$') {
            $modePid=0; $modeTicks=0L
            if (-not [int]::TryParse($matches[1],[ref]$modePid) -or -not [long]::TryParse($matches[2],[ref]$modeTicks) -or
                $modeTicks -gt [datetime]::MaxValue.Ticks -or $value -cnotin @('fish','fight')) {throw '进程任务模式配置无效。'}
            $modes["${modePid}:$modeTicks"]=$value
            continue
        }
        if ($key -match '^UseItem_([1-9]\d*)_([1-9]\d*)$') {
            $pidValue=0; $ticksValue=0L
            if (-not [int]::TryParse($matches[1],[ref]$pidValue) -or -not [long]::TryParse($matches[2],[ref]$ticksValue) -or $ticksValue -gt [datetime]::MaxValue.Ticks) { throw '道具勾选的进程标识无效。' }
            $items["${pidValue}:$ticksValue"]=[bool](ConvertTo-PreferenceFlag $value)
            continue
        }
        if ($key -notin $script:settingsKeys) { throw "config.ini 存在未知配置项：$key。" }
        $values[$key]=$value
    }
    foreach ($key in $script:requiredSettingsKeys) {
        if (-not $values.ContainsKey($key)) { throw "config.ini 缺少配置项：$key。" }
    }
    $audioKeyCount=@($script:audioSettingsKeys | Where-Object { $values.ContainsKey($_) }).Count
    if ($audioKeyCount -eq 0) {
        # Read old five-key files without rewriting them on startup.
        $values.TitanAudioThresholdPercent=$script:audioThresholds.titan
        $values.ForerverAudioThresholdPercent=$script:audioThresholds.forerver
    }
    elseif ($audioKeyCount -ne 2) { throw 'config.ini 需要同时配置两服的音频匹配门槛。' }
    $timeoutKeyCount=@($script:audioTimeoutSettingsKeys | Where-Object { $values.ContainsKey($_) }).Count
    if ($timeoutKeyCount -eq 0) {
        $values.TitanAudioTimeoutMs=$script:versionRanges.titan.AudioTimeoutMs
        $values.ForerverAudioTimeoutMs=$script:versionRanges.forerver.AudioTimeoutMs
    }
    elseif ($timeoutKeyCount -ne 2) { throw 'config.ini 需要同时配置两服的无咬钩保护时间。' }
    $recordingKeyCount=@($script:recordingSettingsKeys | Where-Object {$values.ContainsKey($_)}).Count
    if ($recordingKeyCount -eq 0) {
        $values.TitanAudioRecordingId=$script:audioRecordingSelections.titan
        $values.ForerverAudioRecordingId=$script:audioRecordingSelections.forerver
    }
    elseif ($recordingKeyCount -ne 2) { throw 'config.ini 需要同时配置两服的录音序号。' }
    $preferenceKeyCount=@($script:preferenceSettingsKeys | Where-Object { $values.ContainsKey($_) }).Count
    if ($preferenceKeyCount -eq 0) {
        $values.ReelHoldMs=$script:scheduler.ReelHoldMs
        $values.CastKey=$script:keyBindings.Cast.Text; $values.ReelKey=$script:keyBindings.Reel.Text; $values.ItemKey=$script:keyBindings.Item.Text
        $values.AudioDetectionEnabled=[int]$script:audioDetectionEnabled
    }
    elseif ($preferenceKeyCount -ne $script:preferenceSettingsKeys.Count) { throw 'config.ini 需要同时配置保持时间、三个快捷键和音频检测开关。' }
    if (-not $values.ContainsKey('StatusLogLimit')) { $values.StatusLogLimit=$script:statusLogLimit }
    if (-not $values.ContainsKey('JumpEveryCycles')) { $values.JumpEveryCycles=$script:scheduler.JumpEveryCycles }
    if (-not $values.ContainsKey('LogMaxSizeMB')) { $values.LogMaxSizeMB=$script:logMaxSizeMB }
    $values.ProcessItemPreferences=$items
    $values.ProcessModePreferences=$modes
    return $values
}
function Update-VersionSummary {
    if ($null -ne $settingsSummary) {
        $t=$script:versionRanges.titan; $f=$script:versionRanges.forerver
        $settingsSummary.Text="收杆延迟区间（ms）：时光服 $($t.MinimumMs)–$($t.MaximumMs)；无限服 $($f.MinimumMs)–$($f.MaximumMs)；无咬钩保护（ms）：时光服 $($t.AudioTimeoutMs) / 无限服 $($f.AudioTimeoutMs)；焦点重试 $($script:scheduler.FocusRetryIntervalMs)。" + [Environment]::NewLine + "音频门槛：时光服 $($script:audioThresholds.titan)% / 无限服 $($script:audioThresholds.forerver)%；片段：时光服 $($script:audioRecordingSelections.titan) / 无限服 $($script:audioRecordingSelections.forerver)；定期跳跃 $($script:scheduler.JumpEveryCycles) 次（0关闭）；界面日志 $script:statusLogLimit 条；文件日志上限 $script:logMaxSizeMB MB。$script:settingsWarning"
    }
}
function Set-VersionWaitRanges($TitanMinimum, $TitanMaximum, $ForerverMinimum, $ForerverMaximum, [bool]$Persist=$true, $FocusRetryIntervalMs=$script:scheduler.FocusRetryIntervalMs,
    $TitanAudioThresholdPercent=$script:audioThresholds.titan, $ForerverAudioThresholdPercent=$script:audioThresholds.forerver,
    $ReelHoldMs=$script:scheduler.ReelHoldMs, $KeyBindings=$script:keyBindings, $AudioDetectionEnabled=$script:audioDetectionEnabled,
    $ProcessItemPreferences=$script:processItemPreferences, $ProcessModePreferences=$script:processModePreferences,
    $TitanAudioTimeoutMs=$script:versionRanges.titan.AudioTimeoutMs, $ForerverAudioTimeoutMs=$script:versionRanges.forerver.AudioTimeoutMs,
    $TitanAudioRecordingId=$script:audioRecordingSelections.titan, $ForerverAudioRecordingId=$script:audioRecordingSelections.forerver,
    $StatusLogLimit=$script:statusLogLimit, $JumpEveryCycles=$script:scheduler.JumpEveryCycles,
    $LogMaxSizeMB=$script:logMaxSizeMB) {
    # Validate the entire edit before saving or changing any active task.
    $next=@{}
    foreach ($spec in @(@('titan',$TitanMinimum,$TitanMaximum),@('forerver',$ForerverMinimum,$ForerverMaximum))) {
        foreach ($value in @($spec[1],$spec[2])) { if ([string]$value -notmatch '^\d+$') { throw '请输入整数毫秒值。' } }
        $checked=New-WowAutoState ([int]$spec[1]) ([int]$spec[2])
        $next[$spec[0]]=[pscustomobject]@{MinimumMs=$checked.MinimumMs; MaximumMs=$checked.MaximumMs}
    }
    foreach ($spec in @(@('titan',$TitanAudioTimeoutMs),@('forerver',$ForerverAudioTimeoutMs))) {
        $timeout=0
        if ([string]$spec[1] -notmatch '^\d+$' -or -not [int]::TryParse([string]$spec[1],[ref]$timeout) -or $timeout -lt 1000 -or $timeout -gt 3600000) {
            throw '无咬钩保护时间需为1000–3600000之间的整数毫秒值。'
        }
        $next[$spec[0]] | Add-Member NoteProperty AudioTimeoutMs $timeout
    }
    $retry=0
    if ([string]$FocusRetryIntervalMs -notmatch '^\d+$' -or -not [int]::TryParse([string]$FocusRetryIntervalMs,[ref]$retry) -or $retry -lt 1000 -or $retry -gt 3600000) {
        throw '焦点重试间隔需为1000–3600000之间的整数毫秒值。'
    }
    $nextThresholds=@{}
    foreach ($spec in @(@('titan',$TitanAudioThresholdPercent),@('forerver',$ForerverAudioThresholdPercent))) {
        $percent=0
        if ([string]$spec[1] -notmatch '^\d+$' -or -not [int]::TryParse([string]$spec[1],[ref]$percent) -or $percent -lt 50 -or $percent -gt 100) {
            throw '音频匹配门槛需为50–100之间的整数百分比。'
        }
        $nextThresholds[$spec[0]]=$percent
    }
    $nextHold=0
    if ([string]$ReelHoldMs -notmatch '^\d+$' -or -not [int]::TryParse([string]$ReelHoldMs,[ref]$nextHold) -or $nextHold -gt 60000) { throw '收竿后保持需为0–60000之间的整数毫秒值。' }
    $nextLogLimit=0
    if ([string]$StatusLogLimit -notmatch '^\d+$' -or -not [int]::TryParse([string]$StatusLogLimit,[ref]$nextLogLimit) -or $nextLogLimit -lt 1 -or $nextLogLimit -gt 1000) { throw '日志保留条数需为1–1000之间的整数。' }
    $nextJumpCycles=0
    if ([string]$JumpEveryCycles -notmatch '^\d+$' -or -not [int]::TryParse([string]$JumpEveryCycles,[ref]$nextJumpCycles) -or $nextJumpCycles -gt 1000000) { throw '跳跃循环间隔需为0–1000000之间的整数，0关闭定期跳跃。' }
    $nextLogSize=0
    if ([string]$LogMaxSizeMB -notmatch '^\d+$' -or -not [int]::TryParse([string]$LogMaxSizeMB,[ref]$nextLogSize) -or $nextLogSize -lt 1 -or $nextLogSize -gt 1024) {throw '日志总大小需为1–1024 MB。'}
    $nextBindings=@{}
    foreach ($action in @('Cast','Reel','Item')) { $nextBindings[$action]=ConvertFrom-KeyBindingText $KeyBindings[$action].Text }
    $nextAudio=ConvertTo-PreferenceFlag $AudioDetectionEnabled
    $nextItems=@{}
    $nextRecordings=@{titan=(Get-AudioRecording 'titan' $TitanAudioRecordingId).Id; forerver=(Get-AudioRecording 'forerver' $ForerverAudioRecordingId).Id}
    foreach ($key in $ProcessItemPreferences.Keys) {
        if ($key -notmatch '^([1-9]\d*):([1-9]\d*)$') { throw '道具勾选的进程标识无效。' }
        $pidValue=0; $ticksValue=0L
        if (-not [int]::TryParse($matches[1],[ref]$pidValue) -or -not [long]::TryParse($matches[2],[ref]$ticksValue) -or $ticksValue -gt [datetime]::MaxValue.Ticks) { throw '道具勾选的进程标识无效。' }
        $nextItems[$key]=[bool](ConvertTo-PreferenceFlag $ProcessItemPreferences[$key])
    }
    $nextModes=@{}
    foreach ($key in $ProcessModePreferences.Keys) {
        if ($key -notmatch '^([1-9]\d*):([1-9]\d*)$') {throw '进程任务模式标识无效。'}
        $modePid=0; $modeTicks=0L
        if (-not [int]::TryParse($matches[1],[ref]$modePid) -or -not [long]::TryParse($matches[2],[ref]$modeTicks) -or
            $modeTicks -gt [datetime]::MaxValue.Ticks -or $ProcessModePreferences[$key] -cnotin @('fish','fight')) {throw '进程任务模式配置无效。'}
        $nextModes[$key]=$ProcessModePreferences[$key]
    }
    if ($Persist) {
        $directory=Split-Path $script:settingsPath -Parent
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $temporary=$script:settingsPath + '.' + [Guid]::NewGuid().ToString() + '.tmp'
        try {
            $values=[ordered]@{
                TitanMinimumMs=$next.titan.MinimumMs; TitanMaximumMs=$next.titan.MaximumMs
                ForerverMinimumMs=$next.forerver.MinimumMs; ForerverMaximumMs=$next.forerver.MaximumMs
                FocusRetryIntervalMs=$retry
                TitanAudioThresholdPercent=$nextThresholds.titan; ForerverAudioThresholdPercent=$nextThresholds.forerver
                TitanAudioTimeoutMs=$next.titan.AudioTimeoutMs; ForerverAudioTimeoutMs=$next.forerver.AudioTimeoutMs
                TitanAudioRecordingId=$nextRecordings.titan; ForerverAudioRecordingId=$nextRecordings.forerver
                ReelHoldMs=$nextHold; CastKey=$nextBindings.Cast.Text; ReelKey=$nextBindings.Reel.Text; ItemKey=$nextBindings.Item.Text
                AudioDetectionEnabled=$nextAudio; StatusLogLimit=$nextLogLimit; JumpEveryCycles=$nextJumpCycles; LogMaxSizeMB=$nextLogSize
            }
            $lines=@('; wowAuto settings: ms for timing, percent for thresholds, 0/1 for switches.';
                '; Shortcuts use Ctrl/Shift/Alt plus a key; UseItem_PID_StartTicks stores process choices.')
            foreach ($key in $script:settingsKeys) { $lines += "$key=$($values[$key])" }
            foreach ($key in @($nextItems.Keys | Sort-Object)) { $lines += "UseItem_$($key.Replace(':','_'))=$([int]$nextItems[$key])" }
            foreach ($key in @($nextModes.Keys | Sort-Object)) { $lines += "Mode_$($key.Replace(':','_'))=$($nextModes[$key])" }
            [IO.File]::WriteAllText($temporary,($lines -join "`r`n")+"`r`n",(New-Object Text.UTF8Encoding($false)))
            # Windows PowerShell 5.1 converts ordinary $null to an empty string here.
            # File.Replace requires an actual null backup filename, not an empty path.
            if (Test-Path -LiteralPath $script:settingsPath) {
                [IO.File]::Replace($temporary,$script:settingsPath,[System.Management.Automation.Language.NullString]::Value)
            }
            else { [IO.File]::Move($temporary,$script:settingsPath) }
        }
        finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
    }
    $previousLogLimit=$script:statusLogLimit
    $script:statusLogLimit=$nextLogLimit
    $script:logMaxSizeMB=$nextLogSize
    $null=Set-WowAutoLogSizeMB $nextLogSize
    $script:versionRanges=$next
    $script:audioThresholds=$nextThresholds
    $script:audioRecordingSelections=$nextRecordings
    Set-WowAutoFocusRetryInterval $script:scheduler $retry
    Set-WowAutoHoldDuration $script:scheduler $nextHold
    Set-WowAutoJumpInterval $script:scheduler $nextJumpCycles
    $script:keyBindings=$nextBindings
    $script:audioDetectionEnabled=[bool]$nextAudio
    $script:processItemPreferences=$nextItems
    $script:processModePreferences=$nextModes
    Sync-PreferenceControls
    # Update future waits for every running task of the same version; existing events keep their due time.
    foreach ($row in $script:rows.Values) {
        if ($null -ne $row.State -and $row.State.Running) {
            $range=$next[$row.Client.Flavor]
            $row.State.MinimumMs=$range.MinimumMs; $row.State.MaximumMs=$range.MaximumMs
            $row.State.AudioTimeoutMs=$range.AudioTimeoutMs
        }
        if ($script:audioCaptures.ContainsKey($row.Key) -and $script:audioCaptures[$row.Key].TemplateMode) {
            $script:audioCaptures[$row.Key].Capture.SetMinimumSimilarity($nextThresholds[$row.Client.Flavor]/100.0)
        }
        if ($nextLogLimit -ne $previousLogLimit) { Update-RowStatus $row }
    }
    $script:settingsWarning=''
    Update-VersionSummary
}
function Import-VersionWaitSettings {
    if (-not (Test-Path -LiteralPath $script:settingsPath)) {
        $script:settingsWarning='config.ini 不存在，保留当前配置；请打开设置保存。'
        return
    }
    try {
        $saved=Read-WowAutoSettingsIni $script:settingsPath
        $bindings=@{}
        foreach ($action in @('Cast','Reel','Item')) { $bindings[$action]=ConvertFrom-KeyBindingText $saved[($action+'Key')] }
        Set-VersionWaitRanges $saved.TitanMinimumMs $saved.TitanMaximumMs $saved.ForerverMinimumMs $saved.ForerverMaximumMs -Persist $false -FocusRetryIntervalMs $saved.FocusRetryIntervalMs -TitanAudioThresholdPercent $saved.TitanAudioThresholdPercent -ForerverAudioThresholdPercent $saved.ForerverAudioThresholdPercent -ReelHoldMs $saved.ReelHoldMs -KeyBindings $bindings -AudioDetectionEnabled $saved.AudioDetectionEnabled -ProcessItemPreferences $saved.ProcessItemPreferences -ProcessModePreferences $saved.ProcessModePreferences -TitanAudioTimeoutMs $saved.TitanAudioTimeoutMs -ForerverAudioTimeoutMs $saved.ForerverAudioTimeoutMs -TitanAudioRecordingId $saved.TitanAudioRecordingId -ForerverAudioRecordingId $saved.ForerverAudioRecordingId -StatusLogLimit $saved.StatusLogLimit -JumpEveryCycles $saved.JumpEveryCycles -LogMaxSizeMB $saved.LogMaxSizeMB
    }
    catch { $script:settingsWarning="config.ini 读取失败，保留当前配置：$($_.Exception.Message)" }
}
function Sync-PreferenceControls {
    $previousGuard=$script:updatingPreferenceControls
    $script:updatingPreferenceControls=$true
    try {
        if ($null -ne $audioCheck) { $audioCheck.Checked=$script:audioDetectionEnabled }
        foreach ($row in $script:rows.Values) {
            # Legacy INI choices are read for migration; live task choices belong to the current slot.
            Set-WowAutoItemEnabled $script:scheduler $row.Key $row.SlotUseItem $script:schedulerClock.ElapsedMilliseconds
        }
    }
    finally { $script:updatingPreferenceControls=$previousGuard }
}
function Save-PreferenceSwitches($AudioDetectionEnabled=$script:audioDetectionEnabled, $ProcessItemPreferences=$script:processItemPreferences, $ProcessModePreferences=$script:processModePreferences) {
    $t=$script:versionRanges.titan; $f=$script:versionRanges.forerver
    Set-VersionWaitRanges $t.MinimumMs $t.MaximumMs $f.MinimumMs $f.MaximumMs -AudioDetectionEnabled $AudioDetectionEnabled -ProcessItemPreferences $ProcessItemPreferences -ProcessModePreferences $ProcessModePreferences
}
if (-not $UiTest) { Import-VersionWaitSettings }
$script:uiColors=@{
    Background=[System.Drawing.Color]::FromArgb(58,58,58)
    Surface=[System.Drawing.Color]::FromArgb(72,72,72)
    Input=[System.Drawing.Color]::FromArgb(50,50,50)
    Text=[System.Drawing.Color]::White
    Button=[System.Drawing.Color]::FromArgb(86,86,86)
    Accent=[System.Drawing.Color]::FromArgb(88,100,112)
    Tab=[System.Drawing.Color]::FromArgb(54,78,98)
    Border=[System.Drawing.Color]::FromArgb(116,116,116)
}
function Set-UiButtonStyle($Button, [bool]$Accent=$false) {
    $Button.UseVisualStyleBackColor=$false
    $Button.BackColor=if ($Accent) { $script:uiColors.Accent } else { $script:uiColors.Button }
    $Button.ForeColor=$script:uiColors.Text
    $Button.FlatStyle='Flat'
    $Button.FlatAppearance.BorderColor=$script:uiColors.Border
    $Button.FlatAppearance.MouseOverBackColor=[System.Drawing.Color]::FromArgb(104,104,104)
    $Button.FlatAppearance.MouseDownBackColor=[System.Drawing.Color]::FromArgb(64,64,64)
}
$form = New-Object WowAuto.DimForm
$form.Text = 'wowAuto'
$form.ClientSize = New-Object System.Drawing.Size(1330, 460)
$form.MinimumSize = New-Object System.Drawing.Size(1250, 350)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 12)
$form.BackColor = $script:uiColors.Background
$form.ForeColor = $script:uiColors.Text
$form.AutoScaleMode = 'Dpi'

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 75
$header.Width = $form.ClientSize.Width
$title = New-Object System.Windows.Forms.Label
$title.Text = 'wowAuto'
$title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 23, [System.Drawing.FontStyle]::Bold)
$title.SetBounds(20, 14, 230, 45)
$header.Controls.Add($title)
$countLabel = New-Object System.Windows.Forms.Label
$countLabel.SetBounds(270, 27, 670, 30)
$countLabel.Anchor = 'Top, Left, Right'

$refreshButton = New-Object WowAuto.DimButton
$refreshButton.Text = '刷新进程'
Set-UiButtonStyle $refreshButton
$refreshButton.SetBounds(1020, 20, 115, 36)
$refreshButton.Anchor = 'Top, Right'

$tabs = New-Object WowAuto.DimTabControl
$tabs.Dock = 'Fill'
$tabs.HeaderBackground = [System.Drawing.Color]::Black
$tabs.HeaderSurface = $script:uiColors.Tab
$tabs.ForeColor = $script:uiColors.Text
$tabs.SizeMode = 'Fixed'
$tabs.ItemSize = New-Object System.Drawing.Size(112,32)
$tab = New-Object System.Windows.Forms.TabPage
$tab.Text = '进程任务'
$tab.BackColor = $script:uiColors.Background
$tab.ForeColor = $script:uiColors.Text
$tabs.TabPages.Add($tab)
$form.Controls.Add($tabs)
$form.Controls.Add($header)
$toolbar = New-Object System.Windows.Forms.Panel
$toolbar.Dock = 'Top'
$toolbar.AutoScroll = $true
$toolbar.Height = 116
$toolbar.BackColor = $script:uiColors.Surface
$toolbar.Width = $form.ClientSize.Width
$refreshButton.Anchor = 'Top, Left'
$refreshButton.SetBounds(12, 10, 120, 35)
$toolbar.Controls.Add($refreshButton)
$startAllButton = New-Object WowAuto.DimButton
$startAllButton.Text = '全部开始'
$startAllButton.SetBounds(142, 10, 120, 35)
Set-UiButtonStyle $startAllButton $true
$startAllButton.Enabled = $false
$toolbar.Controls.Add($startAllButton)
$stopAllButton = New-Object WowAuto.DimButton
$stopAllButton.Text = '全部停止'
Set-UiButtonStyle $stopAllButton
$stopAllButton.SetBounds(272, 10, 120, 35)
$stopAllButton.Enabled = $false
$toolbar.Controls.Add($stopAllButton)
$countLabel.SetBounds(410, 15, 245, 28)
$countLabel.Anchor = 'Top, Left'
$countLabel.AutoEllipsis = $true
$toolbar.Controls.Add($countLabel)
$settingsButton = New-Object WowAuto.DimButton
$settingsButton.Text = '设置'
Set-UiButtonStyle $settingsButton
$settingsButton.SetBounds(665, 10, 110, 35)
$toolbar.Controls.Add($settingsButton)
$audioCheck = New-Object WowAuto.DimCheckBox
$audioCheck.Text = '音频咬钩检测'
$audioCheck.SetBounds(790, 13, 195, 32)
$audioCheck.FlatStyle = 'Flat'
$audioCheck.Checked = $script:audioDetectionEnabled
$toolbar.Controls.Add($audioCheck)
$audioCheck.Add_CheckedChanged({ param($sender,$eventArgs)
    if ($script:updatingPreferenceControls) { return }
    try { Save-PreferenceSwitches -AudioDetectionEnabled $sender.Checked }
    catch {
        $script:updatingPreferenceControls=$true
        try { $sender.Checked=$script:audioDetectionEnabled }
        finally { $script:updatingPreferenceControls=$false }
        $script:settingsWarning='config.ini 保存失败，音频选项未改变：'+$_.Exception.Message
        Update-VersionSummary
    }
})
$settingsSummary = New-Object System.Windows.Forms.Label
$settingsSummary.SetBounds(12, 56, 1250, 52)
$settingsSummary.Anchor = 'Top, Left, Right'
$settingsSummary.AutoEllipsis = $true
$toolbar.Controls.Add($settingsSummary)
Update-VersionSummary

function Set-KeyBinding($InputBox, [int]$Code, [bool]$Ctrl, [bool]$Shift, [bool]$Alt) {
    $binding=New-KeyBinding $Code $Ctrl $Shift $Alt
    if ($null -eq $binding) { return }
    # Editing a dialog changes only its draft, never the active input mapping.
    $InputBox.Tag.Bindings[$InputBox.Tag.Action]=$binding
    $InputBox.Text=$binding.Text
}

function New-WaitSettingsDialog([switch]$Embedded) {
    $dialog=New-Object WowAuto.DimForm
    $dialog.Text='自动钓鱼设置'
    $dialog.Font=$form.Font
    $dialog.BackColor=$script:uiColors.Background
    $dialog.ForeColor=$script:uiColors.Text
    $dialog.AutoScaleMode='Dpi'
    $dialog.ClientSize=New-Object System.Drawing.Size(960,770)
    $dialog.FormBorderStyle='FixedDialog'
    $dialog.MaximizeBox=$false; $dialog.MinimizeBox=$false
    $dialog.StartPosition='CenterParent'
    foreach ($spec in @(@('版本',18,18,95),@('收杆延迟区间配置（ms）',130,18,375),@('音频门槛（%）',530,18,185),@('无咬钩保护（ms）',730,18,215))) {
        $label=New-Object System.Windows.Forms.Label
        $label.Text=$spec[0]; $label.SetBounds($spec[1],$spec[2],$spec[3],25)
        $dialog.Controls.Add($label)
    }
    $inputs=@{}
    foreach ($spec in @(@('titan','时光服',54),@('forerver','无限服',100))) {
        $label=New-Object System.Windows.Forms.Label
        $label.Text=$spec[1]; $label.SetBounds(18,($spec[2]+4),95,30)
        $dialog.Controls.Add($label)
        $min=New-Object System.Windows.Forms.NumericUpDown
        $max=New-Object System.Windows.Forms.NumericUpDown
        $threshold=New-Object System.Windows.Forms.NumericUpDown
        $min.SetBounds(130,$spec[2],175,30); $max.SetBounds(330,$spec[2],175,30)
        $separator=New-Object System.Windows.Forms.Label
        $separator.Text='-'; $separator.SetBounds(306,($spec[2]+2),24,28); $separator.TextAlign='MiddleCenter'
        $dialog.Controls.Add($separator)
        foreach ($input in @($min,$max)) { $input.Minimum=1; $input.Maximum=3600000; $input.Increment=100; $input.BackColor=$script:uiColors.Input; $input.ForeColor=$script:uiColors.Text; $input.BorderStyle='FixedSingle'; $dialog.Controls.Add($input) }
        $min.Value=$script:versionRanges[$spec[0]].MinimumMs; $max.Value=$script:versionRanges[$spec[0]].MaximumMs
        $threshold.SetBounds(530,$spec[2],175,30); $threshold.Minimum=50; $threshold.Maximum=100; $threshold.Increment=1
        $threshold.Value=$script:audioThresholds[$spec[0]]; $dialog.Controls.Add($threshold)
        $threshold.BackColor=$script:uiColors.Input
        $threshold.ForeColor=$script:uiColors.Text
        $threshold.BorderStyle='FixedSingle'
        $timeout=New-Object System.Windows.Forms.NumericUpDown
        $timeout.SetBounds(730,$spec[2],200,30); $timeout.Minimum=1000; $timeout.Maximum=3600000; $timeout.Increment=1000
        $timeout.Value=$script:versionRanges[$spec[0]].AudioTimeoutMs
        $timeout.BackColor=$script:uiColors.Input; $timeout.ForeColor=$script:uiColors.Text; $timeout.BorderStyle='FixedSingle'
        $dialog.Controls.Add($timeout)
        $inputs[$spec[0]]=[pscustomobject]@{Minimum=$min; Maximum=$max; Separator=$separator; AudioThreshold=$threshold; AudioTimeout=$timeout}
    }
    $retryLabel=New-Object System.Windows.Forms.Label
    $retryLabel.Text='焦点重试间隔（ms，所有进程）'
    $retryLabel.SetBounds(18,150,300,30); $dialog.Controls.Add($retryLabel)
    $retryInput=New-Object System.Windows.Forms.NumericUpDown
    $retryInput.SetBounds(330,146,175,30)
    $retryInput.Minimum=1000; $retryInput.Maximum=3600000; $retryInput.Increment=1000
    $retryInput.Value=$script:scheduler.FocusRetryIntervalMs; $dialog.Controls.Add($retryInput)
    $retryInput.BackColor=$script:uiColors.Input
    $retryInput.ForeColor=$script:uiColors.Text
    $retryInput.BorderStyle='FixedSingle'
    $logLimitLabel=New-Object System.Windows.Forms.Label
    $logLimitLabel.Text='日志保留条数'; $logLimitLabel.SetBounds(530,150,185,30); $dialog.Controls.Add($logLimitLabel)
    $logLimitInput=New-Object System.Windows.Forms.NumericUpDown
    $logLimitInput.SetBounds(730,146,200,30); $logLimitInput.Minimum=1; $logLimitInput.Maximum=1000; $logLimitInput.Increment=1
    $logLimitInput.Value=$script:statusLogLimit; $logLimitInput.BackColor=$script:uiColors.Input; $logLimitInput.ForeColor=$script:uiColors.Text
    $logLimitInput.BorderStyle='FixedSingle'; $dialog.Controls.Add($logLimitInput)
    $holdLabel=New-Object System.Windows.Forms.Label
    $holdLabel.Text='收竿后保持（ms，所有进程）'
    $holdLabel.SetBounds(18,196,300,30); $dialog.Controls.Add($holdLabel)
    $reelHoldInput=New-Object System.Windows.Forms.NumericUpDown
    $reelHoldInput.SetBounds(330,192,175,30)
    $reelHoldInput.Minimum=0; $reelHoldInput.Maximum=60000; $reelHoldInput.Increment=1
    $reelHoldInput.Value=$script:scheduler.ReelHoldMs
    $reelHoldInput.BackColor=$script:uiColors.Input
    $reelHoldInput.ForeColor=$script:uiColors.Text
    $reelHoldInput.BorderStyle='FixedSingle'; $dialog.Controls.Add($reelHoldInput)
    $jumpLabel=New-Object System.Windows.Forms.Label
    $jumpLabel.Text='跳跃间隔（循环，0关闭）'; $jumpLabel.SetBounds(530,196,200,30); $dialog.Controls.Add($jumpLabel)
    $jumpInput=New-Object System.Windows.Forms.NumericUpDown
    $jumpInput.SetBounds(730,192,200,30); $jumpInput.Minimum=0; $jumpInput.Maximum=1000000; $jumpInput.Increment=1
    $jumpInput.Value=$script:scheduler.JumpEveryCycles; $jumpInput.BackColor=$script:uiColors.Input; $jumpInput.ForeColor=$script:uiColors.Text
    $jumpInput.BorderStyle='FixedSingle'; $dialog.Controls.Add($jumpInput)
    $recordGroup=New-Object System.Windows.Forms.GroupBox
    $recordGroup.Text='咬钩匹配片段（按版本选择）'; $recordGroup.SetBounds(18,238,912,151)
    $recordGroup.BackColor=$script:uiColors.Surface; $recordGroup.ForeColor=$script:uiColors.Text
    $dialog.Controls.Add($recordGroup)
    $recordInputs=@{}
    foreach ($spec in @(@('titan','时光服',30),@('forerver','无限服',76))) {
        $recordLabel=New-Object System.Windows.Forms.Label
        $recordLabel.Text=$spec[1]; $recordLabel.SetBounds(16,($spec[2]+5),95,30); $recordGroup.Controls.Add($recordLabel)
        $selection=New-Object System.Windows.Forms.ComboBox
        $selection.DropDownStyle='DropDownList'; $selection.DisplayMember='Label'
        $selection.DrawMode='OwnerDrawFixed'; $selection.ItemHeight=26; $selection.FlatStyle='Flat'
        $selection.SetBounds(112,$spec[2],528,34)
        $selection.BackColor=$script:uiColors.Input; $selection.ForeColor=$script:uiColors.Text
        $selection.Add_DrawItem({param($sender,$eventArgs)
            $brush=New-Object System.Drawing.SolidBrush($script:uiColors.Input)
            try { $eventArgs.Graphics.FillRectangle($brush,$eventArgs.Bounds) }
            finally { $brush.Dispose() }
            $item=if ($eventArgs.Index -ge 0) {$sender.Items[$eventArgs.Index]} else {$sender.SelectedItem}
            if ($null -ne $item) {
                $bounds=$eventArgs.Bounds; $bounds.X+=3; $bounds.Width-=6
                [System.Windows.Forms.TextRenderer]::DrawText($eventArgs.Graphics,$item.Label,$sender.Font,$bounds,$script:uiColors.Text,([System.Windows.Forms.TextFormatFlags]'Left,VerticalCenter,NoPrefix,EndEllipsis'))
            }
            $eventArgs.DrawFocusRectangle()
        })
        foreach ($recording in $script:audioRecordings[$spec[0]]) { [void]$selection.Items.Add($recording) }
        $selection.SelectedItem=Get-AudioRecording $spec[0] $script:audioRecordingSelections[$spec[0]]
        $selection.Tag=$dialog; $recordGroup.Controls.Add($selection)
        $selection.Add_SelectedIndexChanged({param($sender,$eventArgs) Stop-AudioPreview $sender.Tag})
        $preview=New-Object WowAuto.DimButton
        $preview.Text='试听'; $preview.SetBounds(652,$spec[2],110,36); Set-UiButtonStyle $preview
        $preview.Tag=[pscustomobject]@{Dialog=$dialog; Flavor=$spec[0]; Selection=$selection}
        $preview.Add_Click({param($sender,$eventArgs)
            try { $sender.Tag.Dialog.Tag.Error.Text=''; Start-AudioPreview $sender.Tag.Dialog $sender.Tag.Flavor $sender.Tag.Selection.SelectedItem.Id }
            catch { $sender.Tag.Dialog.Tag.Error.Text=$_.Exception.Message }
        })
        $recordGroup.Controls.Add($preview)
        $recordInputs[$spec[0]]=[pscustomobject]@{Selection=$selection; Play=$preview}
    }
    $stopPreview=New-Object WowAuto.DimButton
    $stopPreview.Text='停止试听'; $stopPreview.SetBounds(780,30,110,36); Set-UiButtonStyle $stopPreview
    $stopPreview.Tag=$dialog; $stopPreview.Add_Click({param($sender,$eventArgs) Stop-AudioPreview $sender.Tag})
    $recordGroup.Controls.Add($stopPreview)
    $previewStatus=New-Object System.Windows.Forms.Label
    $previewStatus.SetBounds(16,118,876,28); $recordGroup.Controls.Add($previewStatus)
    $keyGroup=New-Object System.Windows.Forms.GroupBox
    $keyGroup.Text='快捷键（所有进程）'; $keyGroup.SetBounds(18,400,745,131)
    $keyGroup.BackColor=$script:uiColors.Surface; $dialog.Controls.Add($keyGroup)
    $keyGroup.ForeColor=$script:uiColors.Text
    $keyInputs=@{}; $draftBindings=@{}
    $keyTip=New-Object System.Windows.Forms.ToolTip
    foreach ($spec in @(@('Cast','抛竿',16),@('Reel','收竿',248),@('Item','钓鱼道具',480))) {
        $keyLabel=New-Object System.Windows.Forms.Label
        $keyLabel.Text=$spec[1]; $keyLabel.SetBounds($spec[2],28,200,28); $keyGroup.Controls.Add($keyLabel)
        $keyInput=New-Object System.Windows.Forms.TextBox
        $keyInput.Tag=[pscustomobject]@{Action=$spec[0]; Bindings=$draftBindings}
        $keyInput.ReadOnly=$true; $keyInput.SetBounds($spec[2],58,208,34)
        $keyInput.BackColor=$script:uiColors.Input
        $keyInput.ForeColor=$script:uiColors.Text
        $keyInput.BorderStyle='FixedSingle'
        $keyInput.Add_PreviewKeyDown({ param($sender,$e) $e.IsInputKey=$true })
        $keyInput.Add_KeyDown({ param($sender,$e)
            $e.SuppressKeyPress=$true; $e.Handled=$true
            Set-KeyBinding $sender ([int]$e.KeyCode) $e.Control $e.Shift $e.Alt
        })
        $current=$script:keyBindings[$spec[0]]
        Set-KeyBinding $keyInput $current.Code $current.Ctrl $current.Shift $current.Alt
        $keyInputs[$spec[0]]=$keyInput; $keyGroup.Controls.Add($keyInput)
        $keyTip.SetToolTip($keyInput,'点击后直接按下按键或组合键，例如 Ctrl+1、Shift+F2。')
    }
    $keyHint=New-Object System.Windows.Forms.Label
    $keyHint.Text='点击输入框后直接按键，支持 Ctrl / Shift / Alt 组合键。'
    $keyHint.SetBounds(16,98,715,28); $keyGroup.Controls.Add($keyHint)
    $note=New-Object System.Windows.Forms.Label
    $note.Text="音频模式：匹配成功后随机等待；定时模式：变绿后随机等待。`r`n无咬钩保护从确认绿色开始计时，仅用于音频模式。`r`n配置保存到 config.ini；保护新值从下轮生效，已有截止不变。"
    $note.Text+="`r`n片段选择保存后从下轮使用；试听仅播放1秒匹配片段。"
    $note.SetBounds(18,546,912,100); $dialog.Controls.Add($note)
    $errorLabel=New-Object System.Windows.Forms.Label
    $errorLabel.ForeColor=$script:uiColors.Text
    $errorLabel.SetBounds(18,648,912,52); $dialog.Controls.Add($errorLabel)
    $apply=New-Object WowAuto.DimButton
    $apply.Text='保存'; $apply.SetBounds(540,715,95,36); Set-UiButtonStyle $apply $true; $dialog.Controls.Add($apply)
    $cancel=New-Object WowAuto.DimButton
    $cancel.Text='取消'; $cancel.SetBounds(645,715,95,36); Set-UiButtonStyle $cancel
    $cancel.DialogResult='Cancel'; $dialog.Controls.Add($cancel)
    $dialog.AcceptButton=$apply; $dialog.CancelButton=$cancel
    $dialog.Tag=[pscustomobject]@{Inputs=$inputs; FocusRetry=$retryInput; ReelHold=$reelHoldInput; StatusLogLimit=$logLimitInput; JumpEveryCycles=$jumpInput; Apply=$apply; Cancel=$cancel; Error=$errorLabel; KeyInputs=$keyInputs; KeyBindings=$draftBindings; KeyTip=$keyTip; Recordings=$recordInputs; StopPreview=$stopPreview; PreviewStatus=$previewStatus; PreviewPlayer=$null}
    $dialog.Add_FormClosed({param($sender,$eventArgs) Stop-AudioPreview $sender})
    $dialog.Add_Disposed({ param($sender,$eventArgs) Stop-AudioPreview $sender; $sender.Tag.KeyTip.Dispose() })
    $cancel.Tag=$dialog; $cancel.Add_Click({param($sender,$eventArgs) Stop-AudioPreview $sender.Tag})
    $apply.Tag=$dialog
    $apply.Add_Click({ param($sender,$eventArgs)
        $settingsDialog=$sender.Tag; $fields=$settingsDialog.Tag.Inputs
        try {
            $nextHold=0
            $holdText=$settingsDialog.Tag.ReelHold.Text.Trim()
            if ($holdText -notmatch '^\d+$' -or -not [int]::TryParse($holdText,[ref]$nextHold) -or $nextHold -lt 0 -or $nextHold -gt 60000) {
                throw '收竿后保持需为0–60000之间的整数毫秒值。'
            }
            $nextBindings=@{}
            foreach ($action in @('Cast','Reel','Item')) {
                $draft=$settingsDialog.Tag.KeyBindings[$action]
                $nextBindings[$action]=New-KeyBinding $draft.Code $draft.Ctrl $draft.Shift $draft.Alt
                if ($null -eq $nextBindings[$action]) { throw '请选择有效的快捷键。' }
            }
            Set-VersionWaitRanges $fields.titan.Minimum.Text.Trim() $fields.titan.Maximum.Text.Trim() $fields.forerver.Minimum.Text.Trim() $fields.forerver.Maximum.Text.Trim() -FocusRetryIntervalMs $settingsDialog.Tag.FocusRetry.Text.Trim() -TitanAudioThresholdPercent $fields.titan.AudioThreshold.Text.Trim() -ForerverAudioThresholdPercent $fields.forerver.AudioThreshold.Text.Trim() -ReelHoldMs $nextHold -KeyBindings $nextBindings -TitanAudioTimeoutMs $fields.titan.AudioTimeout.Text.Trim() -ForerverAudioTimeoutMs $fields.forerver.AudioTimeout.Text.Trim() -TitanAudioRecordingId $settingsDialog.Tag.Recordings.titan.Selection.SelectedItem.Id -ForerverAudioRecordingId $settingsDialog.Tag.Recordings.forerver.Selection.SelectedItem.Id -StatusLogLimit $settingsDialog.Tag.StatusLogLimit.Text.Trim() -JumpEveryCycles $settingsDialog.Tag.JumpEveryCycles.Text.Trim()
            Stop-AudioPreview $settingsDialog
            if ($settingsDialog.Tag.Embedded) {$settingsDialog.Tag.Error.Text='钓鱼设置已保存。'}
            else {$settingsDialog.DialogResult='OK'}
        }
        catch { $settingsDialog.Tag.Error.Text=$_.Exception.Message }
    })
    $dialog.Tag | Add-Member NoteProperty Embedded ([bool]$Embedded)
    return $dialog
}
$settingsButton.Add_Click({
    if ($script:scanning -or $script:editingSettings) { return }
    # A modal editor must not lose focus to automatic game activation.
    $script:editingSettings=$true
    $dialog=$null
    try { $dialog=New-UnifiedSettingsDialog; [void]$dialog.ShowDialog($form) }
    catch {$settingsSummary.Text='设置未打开：'+$_.Exception.Message}
    finally { if ($null -ne $dialog) { $dialog.Dispose() }; $script:editingSettings=$false; Update-BatchControls }
})

$intro = New-Object System.Windows.Forms.Label
$intro.Dock = 'Top'
$intro.Height = 44
$intro.Padding = New-Object System.Windows.Forms.Padding(12, 12, 0, 0)
$intro.Text = '每行通过角色编排设置名称和任务；“开始”按编排切换角色，“直接开始”留在当前角色执行已验证任务。'
$headings = New-Object System.Windows.Forms.Panel
$headings.Dock = 'Top'
$headings.Height = 32
$headings.BackColor = $script:uiColors.Surface
foreach ($heading in @(@('游戏进程 / 版本 / 窗口位置',12,360), @('操作',386,310), @('实时状态（最新日志在上）',716,350))) {
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
$list.BackColor = $script:uiColors.Background
$list.Padding = New-Object System.Windows.Forms.Padding(6, 0, 6, 0)
$footer = New-Object System.Windows.Forms.Label
$footer.Dock = 'Bottom'
$footer.Height = 48
$footer.Padding = New-Object System.Windows.Forms.Padding(12, 10, 0, 0)
$footer.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 11)
$footer.Text = '运行时自动切换窗口；黄色超过500次循环时请求正常退出，30秒未退出则强制结束；次数不足只停止该行。'
$tab.Controls.Add($list)
$tab.Controls.Add($headings)
$tab.Controls.Add($intro)
$tab.Controls.Add($toolbar)
$tab.Controls.Add($footer)

function Fit-WindowToContent {
    # Measure after layout/DPI scaling. Keep all rows visible when the screen allows it.
    $form.PerformLayout()
    $tab.PerformLayout()
    $list.PerformLayout()
    $workingArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $scale = $form.CurrentAutoScaleDimensions.Width / 96.0
    $frameWidth = $form.Width - $form.ClientSize.Width
    $desiredWidth = [int][Math]::Ceiling([Math]::Max(1330 * $scale, $audioCheck.Right + 28) + $frameWidth)
    $rowHeight = $list.Padding.Vertical + 12
    foreach ($row in $script:rows.Values) { $rowHeight += $row.Panel.Height + $row.Panel.Margin.Vertical }
    $rowHeight = [Math]::Max([int](80 * $scale), $rowHeight)
    $chromeHeight = $form.Height - $list.ClientSize.Height
    $desiredHeight = $chromeHeight + $rowHeight
    $form.MinimumSize = New-Object System.Drawing.Size(
        ([Math]::Min([int](1330 * $scale), $workingArea.Width)),
        ([Math]::Min([int](300 * $scale), $workingArea.Height)))
    $form.Size = New-Object System.Drawing.Size(
        ([Math]::Min($desiredWidth, $workingArea.Width)),
        ([Math]::Min($desiredHeight, $workingArea.Height)))
    $form.Location = New-Object System.Drawing.Point(
        ($workingArea.Left + [int](($workingArea.Width - $form.Width) / 2)),
        ($workingArea.Top + [int](($workingArea.Height - $form.Height) / 2)))
}
$form.Add_Shown({ Fit-WindowToContent })
function Get-ProcessClientInfo($Process) {
    try {
        $path=if ($UiTest) { $Process.ExecutablePath } else { $Process.MainModule.FileName }
        $version=if ($UiTest) { $Process.FileVersion } else { [Diagnostics.FileVersionInfo]::GetVersionInfo($path).FileVersion }
        $flavor=[WowAuto.NativeInput]::GetClientFlavor($path,$version)
        if (-not $flavor -or $Process.ProcessName -ne [IO.Path]::GetFileNameWithoutExtension($path)) { return $null }
        return [pscustomobject]@{
            Flavor=$flavor; Label=$(if ($flavor -eq 'titan') { '时光服' } else { '无限服' })
            ExecutablePath=$path; ProcessName=$Process.ProcessName; Version=$version
        }
    }
    catch { return $null }
}
function Test-RowProcessIdentity($Row) {
    if ($null -eq $Row.StartTime -or $Row.Process.StartTime -ne $Row.StartTime) { return $false }
    $client=Get-ProcessClientInfo $Row.Process
    return $null -ne $client -and $client.Flavor -eq $Row.Client.Flavor -and
        [string]::Equals($client.ExecutablePath,$Row.Client.ExecutablePath,[StringComparison]::OrdinalIgnoreCase)
}
function Get-WowAutoProcesses {
    $candidates=if ($UiTest) { $script:mockProcesses } else { @(Get-Process -Name 'WowClassic','Wow' -ErrorAction SilentlyContinue) }
    foreach ($process in @($candidates | Sort-Object Id)) {
        $client=Get-ProcessClientInfo $process
        if ($null -ne $client) {
            $process | Add-Member NoteProperty WowAutoClient $client -Force
            $process
        }
    }
}
function Read-RowWindowPosition($Row) {
    try {
        if ($UiTest) {
            if ($Row.Process.Minimized) { return '最小化' }
            $r=$Row.Process.WindowBounds; $s=$Row.Process.ScreenBounds
            return [WowAuto.NativeInput]::ClassifyWindowPosition($r[0],$r[1],$r[2],$r[3],$s[0],$s[1],$s[2],$s[3])
        }
        if ($null -eq $Row.StartTime) { return '位置未知' }
        return [WowAuto.NativeInput]::ReadWindowPosition($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath)
    }
    catch { return '位置未知' }
}
function Update-RowName($Row) {
    if ($Row.TaskMode -eq 'fight' -and $Row.FightRow) {
        $class=if ($Row.FightRow.ClassId) {$script:autoFightClasses[[string]$Row.FightRow.ClassId]} else {'等待插件识别'}
        $Row.Name.Text="$($Row.Caption)`r`nPID $($Row.Process.Id) · $($Row.Client.Label) · $($Row.Position)`r`n职业：$class"
        return
    }
    $cycles=Get-WowAutoCycleCount $script:scheduler $Row.Key
    $Row.Name.Text="$($Row.Caption)`r`nPID $($Row.Process.Id) · $($Row.Client.Label) · $($Row.Position) · 循环 $cycles"
}
function Update-WindowPositions {
    foreach ($row in $script:rows.Values) {
        $position=Read-RowWindowPosition $row
        if ($position -ne $row.Position) { $row.Position=$position; Update-RowName $row }
    }
}

function Set-RowControls($Row) {
    $running = Test-UnifiedRowRunning $Row
    $exiting = $script:pendingGameExits.ContainsKey($Row.Key)
    $directEligible = $Row.Validated -and -not $exiting -and -not $script:scanning -and $null -ne $Row.StartTime -and -not $Row.Exited
    if ($Row.TaskMode -eq 'fight') {$directEligible=$directEligible -and $Row.FightRow -and $Row.FightRow.CanStart -and $script:autoFight.ConfigReady}
    $eligible = $directEligible
    if (Test-RowHasRotation $Row) {$eligible=-not $exiting -and -not $Row.Exited -and -not $script:scanning -and $script:rotation.ConfigReady}
    $eligible=$eligible -and -not $script:editingSettings
    $Row.Start.Enabled = $eligible -and -not $running
    $Row.DirectStart.Enabled = $directEligible -and -not $script:editingSettings -and -not $running
    $Row.Stop.Enabled = $running -or $eligible -or $exiting
    if ($Row.PSObject.Properties['AccountBox']) {$Row.AccountBox.Enabled=-not $script:scanning -and -not $script:editingSettings -and -not $running -and -not $exiting}
    Update-RotationRow $Row
}

function Set-RowStatusText($Row, [string]$Message) {
    if ($Row.TaskMode -eq 'fight' -and $Row.FightRow) {Set-AutoFightStatus $Row.FightRow $Message; Set-RowControls $Row; return}
    $Row.StatusMessage=$Message
    if ($null -ne $Row.State) { $Row.State.Status=$Message }
    Update-RowStatus $Row
}

function Update-RowStatus($Row) {
    Update-RowName $Row
    if ($Row.TaskMode -eq 'fight') {Set-RowControls $Row; return}
    $text=$Row.StatusMessage
    $statusKey=$text
    if ($null -ne $Row.State) {
        $text = $Row.State.Status
        if ($Row.State.Running -and $Row.State.UseItem) { $text += "`r`n$($Row.State.ItemStatus)" }
        # Track state transitions and new deadlines, excluding the live countdown text.
        $statusKey="$text|$($Row.State.Mode)|$($Row.State.Deadline)|$($Row.State.FocusRetryAt)|$($Row.State.ReelDelayMs)"
        if ($script:pendingGameExits.ContainsKey($Row.Key)) {
            $exit=$script:pendingGameExits[$Row.Key]
            if ($exit.Requested) {
                $left=[Math]::Max(0,$exit.Due-$script:schedulerClock.ElapsedMilliseconds)
                $text += "`r`n退出超时保护：剩余 $left ms；停止可取消。"
            } else {$text += "`r`n正在排队请求游戏正常退出；停止可取消。"}
        }
        if ($Row.State.Running -and $Row.State.FocusRetryAt -gt 0) {
            $left=[Math]::Max(0,$Row.State.FocusRetryAt-$script:schedulerClock.ElapsedMilliseconds)
            $seconds=[int][Math]::Ceiling($left/1000.0)
            $text += "`r`n焦点重试：剩余 $seconds 秒。"
        }
        elseif ($Row.State.Running -and $Row.State.Mode -in @('Wait', 'Cooldown')) {
            $left = [Math]::Max(0, $Row.State.Deadline - $script:schedulerClock.ElapsedMilliseconds)
            if ($Row.State.UseAudio -and $Row.State.Mode -eq 'Wait' -and $Row.State.AudioReelPending) { $text += "`r`n收竿等待：剩余 $left ms" }
            elseif ($Row.State.UseAudio -and $Row.State.Mode -eq 'Wait') { $text += "`r`n无咬钩超时保护：剩余 $left ms" }
            else { $text += "`r`n剩余 $left ms" }
        }
        if ($Row.State.Running -and $Row.State.FocusRetryAt -eq 0 -and $script:schedulerClock.ElapsedMilliseconds -lt $script:scheduler.ItemHoldUntil) {
            $left=$script:scheduler.ItemHoldUntil-$script:schedulerClock.ElapsedMilliseconds
            $text="道具执行等待：剩余 $left ms；暂停抛竿、收竿及检测。"
            $statusKey="道具执行等待|$($script:scheduler.ItemHoldUntil)"
        }
    }
    if ($null -ne $Row.State -and $Row.State.Running -and $Row.State.Mode -eq 'Wait' -and $Row.State.ReelDelayMs -gt 0) {
        $text += "`r`n当前随机延迟：$($Row.State.ReelDelayMs) ms"
    }
    if ($script:audioCaptures.ContainsKey($Row.Key)) {
        $capture=$script:audioCaptures[$Row.Key].Capture
        if ($capture.Status -eq 'Listening') {
            $text += "`r`n音频峰值：$([Math]::Round($capture.Peak*100,1))%"
            if ($script:audioCaptures[$Row.Key].TemplateMode) {
                $matchLabel=if ($script:audioCaptures[$Row.Key].Trial) { '试用匹配' } else { '匹配' }
                $text += "；$($matchLabel)：$([Math]::Round($capture.Similarity*100,1))%（片段 $($script:audioCaptures[$Row.Key].RecordingId)；门槛 $($script:audioThresholds[$Row.Client.Flavor])%）；排除：$($capture.Rejected)"
            }
        }
    }
    $newEntry=$Row.StatusSnapshot -cne $statusKey
    if ($newEntry) {
        $Row.StatusSnapshot=$statusKey
        $Row.StatusTimestamp=Get-Date -Format 'HH:mm:ss'
        $Row.StatusHistory.Add("[$($Row.StatusTimestamp)] $text")
        Write-WowAutoLog $text $Row status
    }
    $text="[$($Row.StatusTimestamp)] $text"
    $refresh=$newEntry -or $Row.CurrentStatusText -cne $text -or $Row.StatusHistory.Count -gt $script:statusLogLimit
    $Row.CurrentStatusText=$text
    while ($Row.StatusHistory.Count -gt $script:statusLogLimit) { $Row.StatusHistory.RemoveAt(0) }
    if ($refresh) {
        $display=New-Object 'System.Collections.Generic.List[string]'
        $display.Add($text)
        # Refresh only the newest entry's live metrics; prior event snapshots remain immutable.
        for ($index=$Row.StatusHistory.Count-2; $index -ge 0; $index--) { $display.Add($Row.StatusHistory[$index]) }
        $Row.Status.SetStatusText(($display -join "`r`n`r`n"))
    }
    Set-RowControls $Row
}

function Stop-Row($Row, [string]$Reason = '已停止，当前等待已取消。', [switch]$CancelExit, [switch]$KeepRotation) {
    Remove-GameActions -Key $Row.Key -IncludeProcess:$CancelExit
    if (-not $UiTest -and $Row.StartTime) {[WowAutoCapture.Native]::CancelRestore($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath)}
    if (-not $KeepRotation) {Stop-RowRotation $Row}
    if ($Row.FightRow -and $script:autoFight) {Stop-AutoFightRow $Row.FightRow $Reason}
    if ($script:audioCaptures.ContainsKey($Row.Key)) {
        $script:audioCaptures[$Row.Key].Capture.Dispose()
        $script:audioCaptures.Remove($Row.Key)
    }
    if ($CancelExit) { $script:pendingGameExits.Remove($Row.Key) }
    if ($null -ne $script:pendingWork -and $script:pendingWork.Key -eq $Row.Key) { $script:pendingWork=$null }
    Stop-WowAutoTask $script:scheduler $Row.Key $Reason
    if ($null -ne $Row.State) { Stop-WowAutoState $Row.State $Reason }
    else { $Row.StatusMessage = $Reason }
    Update-RowStatus $Row
    Clear-WowAutoCurrentRole $Row
}

function Start-RowDirect($Row) {
    # A delayed/repeated click belongs only to this row and must not restart it.
    if (Test-UnifiedRowRunning $Row) {return}
    Start-Row $Row -TaskOnly
}
function Start-Row($Row,[switch]$TaskOnly) {
    if (-not $TaskOnly) {Remove-GameActions -Domain Restore}
    try {
        if (-not $TaskOnly -and (Test-RowHasRotation $Row)) {Start-RowRotation $Row;return}
        if ($TaskOnly -and -not (Test-RowLoginPoint $Row)) {throw '常驻登录白点不存在，未启动任务。'}
        if ($Row.TaskMode -eq 'fight') {
            if (-not $Row.Validated -or $script:scanning -or $script:editingSettings) {throw '请刷新并通过战斗色块检测。'}
            $wasRunning=$null -ne $Row.FightRow.Session
            Start-AutoFightRow $Row.FightRow
            if (-not $wasRunning -and $Row.FightRow.Session) {Register-WowAutoExecutionRound $Row;Register-RotationTaskStart $Row}
            return
        }
        if ($script:pendingGameExits.ContainsKey($Row.Key)) { throw '正在等待游戏退出，请先停止以取消超时保护。' }
        if (-not $Row.Validated -or $script:scanning -or $script:editingSettings) { throw '请先关闭设置，并刷新通过红色/绿色检测。' }
        if ($null -ne $Row.State -and $Row.State.Running) { return }
        $range=$script:versionRanges[$Row.Client.Flavor]
        $newState = New-WowAutoState $range.MinimumMs $range.MaximumMs
        $Row.Process.Refresh()
        if ($Row.Process.HasExited) { throw '该游戏进程已退出，请刷新。' }
        if (-not (Test-RowProcessIdentity $Row)) {
            throw '进程身份已变化，请刷新。'
        }
        $template=$null
        if ($audioCheck.Checked -and $script:audioUseTemplate) { $template=Get-AudioTemplate $Row.Client.Flavor }
        $Row.State = Add-WowAutoTask $script:scheduler $Row.Key $newState.MinimumMs $newState.MaximumMs $script:schedulerClock.ElapsedMilliseconds -UseItem $Row.SlotUseItem -UseAudio $audioCheck.Checked -AudioTimeoutMs $range.AudioTimeoutMs
        if ($Row.State.UseAudio) {
            if ($UiTest) {
                $capture=[pscustomobject]@{Status='Listening'; Error=''; Peak=0.0; Similarity=0.0; Rejected=0; Session=0L; Bite=0L; Disposed=$false; MinimumSimilarity=$script:audioThresholds[$Row.Client.Flavor]/100.0; Template=$template; TemplateChanges=0}
                $capture | Add-Member ScriptMethod Arm { param([long]$value) if ($this.Session -ne $value) { $this.Session=$value; $this.Bite=0L } }
                $capture | Add-Member ScriptMethod Dispose { $this.Disposed=$true; $this.Session=0L; $this.Bite=0L }
                $capture | Add-Member ScriptMethod SetMinimumSimilarity { param([double]$value) $this.MinimumSimilarity=$value }
                $capture | Add-Member ScriptMethod SetTemplate { param($value,[double]$threshold) if ($this.Session -ne 0) {throw 'Disarm capture before switching recordings.'}; $this.Template=$value; $this.MinimumSimilarity=$threshold; $this.TemplateChanges++; $this.Bite=0L }
            }
            else { $capture=[WowAuto.Audio.ProcessCapture]::new($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath,$template,$script:audioThresholds[$Row.Client.Flavor]/100.0) }
            $script:audioCaptures[$Row.Key]=[pscustomobject]@{Capture=$capture; State=$Row.State; TemplateMode=($null -ne $template); Trial=($null -ne $template -and $template.IsTrial); RecordingId=$script:audioRecordingSelections[$Row.Client.Flavor]; TemplateSession=0L}
            $Row.State.Status='正在启动本进程声音监听，暂不抛竿。'
        }
        Update-RowStatus $Row
        Register-WowAutoExecutionRound $Row
        Register-RotationTaskStart $Row
    }
    catch {
        Stop-Row $Row ('无法开始：' + $_.Exception.Message)
    }
}

function New-ProcessRow($Process, $StartTime, [string]$Key, $Client) {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Height = 106
    $panel.Width = [Math]::Max(1170, $list.ClientSize.Width - 32)
    $panel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
    $panel.BackColor = $script:uiColors.Surface
    $nameLabel = New-Object System.Windows.Forms.Label
    $nameLabel.SetBounds(6, 20, 360, 70)
    $nameLabel.AutoEllipsis=$true
    $panel.Controls.Add($nameLabel)
    $start = New-Object WowAuto.DimButton
    $start.Text = '开始'
    $start.SetBounds(380, 33, 68, 40)
    Set-UiButtonStyle $start $true
    $panel.Controls.Add($start)
    $directStart = New-Object WowAuto.DimButton
    $directStart.Text = '直接开始'
    $directStart.SetBounds(454, 33, 112, 40)
    Set-UiButtonStyle $directStart $true
    $directStart.Enabled = $false
    $panel.Controls.Add($directStart)
    $stop = New-Object WowAuto.DimButton
    $stop.Text = '停止'
    $stop.SetBounds(572, 33, 68, 40)
    Set-UiButtonStyle $stop
    $stop.Enabled = $false
    $panel.Controls.Add($stop)
    $status = New-Object WowAuto.DimStatusLog
    $status.SetBounds(710, 12, $panel.Width - 722, 82)
    $status.Anchor = 'Top, Left, Right'
    $status.Multiline = $true
    $status.MaxLength = 0
    $status.ReadOnly = $true
    $status.ScrollBars = 'Vertical'
    $status.BackColor = $script:uiColors.Input
    $status.ForeColor = $script:uiColors.Text
    $status.BorderStyle = 'FixedSingle'
    $panel.Controls.Add($status)
    $row = [pscustomobject]@{
        Key=$Key; Process=$Process; StartTime=$StartTime; Client=$Client; Position='位置未知'
        Exited=$false; Validated=$false; Caption=[IO.Path]::GetFileName($Client.ExecutablePath)
        Panel=$panel; Name=$nameLabel
        Start=$start; DirectStart=$directStart; Stop=$stop; Status=$status; State=$null
        StatusMessage='尚未验证，请点击刷新进程。'
        StatusSnapshot=$null; StatusTimestamp=''; CurrentStatusText=''; StatusHistory=(New-Object 'System.Collections.Generic.List[string]')

    }
    # Sender.Tag keeps handlers bound to their own row, not a shared loop variable.
    $start.Tag = $row
    $directStart.Tag = $row
    $stop.Tag = $row
    $start.Add_Click({ param($sender, $eventArgs) Start-Row $sender.Tag })
    $directStart.Add_Click({ param($sender, $eventArgs) Start-RowDirect $sender.Tag })
    $stop.Add_Click({ param($sender, $eventArgs) Stop-Row $sender.Tag -CancelExit })
    if ($null -eq $StartTime) { $row.StatusMessage = '无法读取进程信息，请检查权限后刷新。' }
    Add-ProcessTaskControls $row
    Update-RowStatus $row
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
            if ($null -eq $row) { $row = New-ProcessRow $process $started $key $process.WowAutoClient }
            else {Update-RowAccountChoices $row}
            $row.Process=$process
            $row.Client=$process.WowAutoClient
            $row.Position=Read-RowWindowPosition $row
            $caption = [IO.Path]::GetFileName($row.Client.ExecutablePath)
            try { if ($process.MainWindowTitle) { $caption = $process.MainWindowTitle } } catch { }
            $row.Caption = $caption
            Update-RowStatus $row
            $next[$key] = $row
            $ordered += $row
        }
        foreach ($key in @($script:rows.Keys)) {
            if (-not $next.ContainsKey($key)) {
                Stop-Row $script:rows[$key] '进程已退出，已停止。'
                if ($script:autoFight -and $script:autoFight.Unified) {$script:autoFight.Rows.Remove($key)}
                $script:rows[$key].Panel.Dispose()
            }
        }
        $list.SuspendLayout()
        $list.Controls.Clear()
        $script:rows = $next
        foreach ($row in $ordered) { $list.Controls.Add($row.Panel) }
        $list.ResumeLayout()
        $countLabel.Text = "检测到 $($processes.Count) 个游戏进程"
        if ($processes.Count -eq 0) { $countLabel.Text = '未找到游戏，请启动后刷新。' }
        Update-WowAutoRunInfo
    }
    catch { $countLabel.Text = '刷新失败：' + $_.Exception.Message; return $false }
    return $true
}
function Activate-ScanRow($Row) {
    Assert-GameActionContext
    if ($UiTest) {
        $script:scanOrder += $Row.Process.Id
        if ($Row.Process.FocusAllowed) {$script:workerFocus=$Row.Process.Id}
        return $Row.Process.FocusAllowed
    }
    return [WowAuto.NativeInput]::ActivateForScan($Row.Process.Id, $Row.StartTime.Ticks, $Row.Client.ExecutablePath)
}

function Read-ScanColor($Row) {
    $Row.Process.Refresh()
    if ($Row.Process.HasExited -or -not (Test-RowProcessIdentity $Row)) {
        throw '进程已退出或身份改变。'
    }
    if ($UiTest) {$script:detectorSamples+=,$Row.Key; return $Row.Process.ScanColor }
    return [WowAuto.NativeInput]::ReadCenterColor($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath)
}

function Read-LureColor($Row) {
    if ($UiTest) { return $Row.Process.LureColor }
    return [WowAuto.NativeInput]::ReadLureColor($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath)
}

function Finish-RefreshScan {
    $scanTimer.Stop()
    $script:scanning = $false
    $refreshButton.Enabled = $true
    foreach ($row in $script:rows.Values) { Set-RowControls $row }
    $passed = @($script:rows.Values | Where-Object { $_.Validated }).Count
    $countLabel.Text = "进程 $($script:rows.Count) · 验证通过 $passed"
    Add-GameAction -Id restore -Kind Scan.Restore -Domain Restore -Owner $script:scanGeneration -Due $script:schedulerClock.ElapsedMilliseconds -Data $script:scanOriginalWindow -Execute {
        param($event,$now)
        Assert-GameActionContext
        # A task started after the scan owns future foreground input. Complete the
        # scan restore without activating another window or cancelling any row's work.
        if (@($script:rows.Values | Where-Object {Test-UnifiedRowRunning $_}).Count -gt 0) {return}
        if ($UiTest) {$script:restored=$true}
        elseif ($event.Data -ne [IntPtr]::Zero -and -not [WowAuto.NativeInput]::RestoreAfterScan($event.Data)) {$countLabel.Text+=' 请手动切回工具窗口。'}
    }
    $script:scanOriginalWindow = [IntPtr]::Zero
    Update-BatchControls
}

function Begin-RefreshScan {
    if ($script:scanning -or $script:editingSettings) { return }
    Remove-GameActions -IncludeProcess
    $script:scanGeneration++
    $script:pendingGameExits.Clear()
    $script:scanning = $true
    $startAllButton.Enabled = $false
    $script:pendingWork = $null
    $refreshButton.Enabled = $false
    $script:scanOriginalWindow = if ($UiTest) { [IntPtr]::Zero } else { [WowAuto.NativeInput]::CurrentWindow() }
    # Stop all automation first; refresh sends only the requested detector start command.
    foreach ($row in $script:rows.Values) {
        $row.Validated = $false
        Stop-Row $row '刷新前已停止，等待重新检测。'
    }
    if (-not (Refresh-ProcessRows)) {
        Finish-RefreshScan
        $countLabel.Text = '刷新进程失败，请重试。'
        return
    }
    $script:scanQueue = @($script:rows.Values | Sort-Object { $_.Process.Id })
    foreach ($row in $script:scanQueue) {
        $row.Validated = $false
        $row.State = $null
        if ($row.FightRow) {$row.FightRow.CanStart=$false}
        Set-RowStatusText $row '等待切换窗口、开启对应监控，再检测色块。'
        Set-RowControls $row
    }
    $script:scanIndex = 0
    $script:scanPhase = 'Activate'
    $script:scanDue = 0L
    $script:scanClock.Restart()
    if ($script:scanQueue.Count -eq 0) { Finish-RefreshScan; return }
    # The shared 25ms dispatcher drives refresh too; no second action timer.
}

function Invoke-RefreshScan([long]$Now) {
    if (-not $script:gameActions.Current) {
        if ($UiTest) {
            Submit-RefreshAction $Now -ScanNow $Now
            Invoke-GameActionQueue $Now
            if (-not $script:scanning) {Invoke-GameActionQueue ([Math]::Max($Now,$script:schedulerClock.ElapsedMilliseconds))}
        } else {Submit-RefreshAction $script:schedulerClock.ElapsedMilliseconds}
        return
    }
    if (-not $script:scanning -or $Now -lt $script:scanDue) { return }
    # Manual refresh also waits out an in-progress post-reel foreground hold.
    if ($script:schedulerClock.ElapsedMilliseconds -lt $script:scheduler.ReelHoldUntil -or
        $script:schedulerClock.ElapsedMilliseconds -lt $script:scheduler.ItemHoldUntil) { return }
    if ($script:scanIndex -ge $script:scanQueue.Count) { Finish-RefreshScan; return }
    $row = $script:scanQueue[$script:scanIndex]
    try {
        if ($script:scanPhase -eq 'Activate') {
            $countLabel.Text = "检测中：$($script:scanIndex + 1)/$($script:scanQueue.Count)，PID $($row.Process.Id)"
            if ($null -eq $row.StartTime) {throw '游戏进程身份不可读。'}
            Set-RowStatusText $row '等待公共队列开启监控，随后后台获取窗口画面。'
            $script:scanPhase = 'Command'
            $script:scanDue = $Now
            $script:scanTimeout = 0L
            return
        }
        if ($script:scanPhase -eq 'Command') {
            if (-not (Test-WorkerForeground $row)) {
                throw '发送监控指令前失去前台焦点。'
            }
            if (-not (Send-ScanDetectorCommand $row)) {throw '开启监控指令发送失败，未进行色块检测。'}
            Set-RowStatusText $row '已发送对应监控开启命令，等待色块更新。'
            $script:scanPhase='Sample'; $script:scanDue=$Now+200; $script:scanTimeout=$Now+1000
            return
        }
        if ($row.TaskMode -eq 'fight') {
            $packet=Read-ScanFightPacket $row
            if ($packet -and $packet.Action -eq 'dead') {
                Set-RowStatusText $row '角色死亡，未开放开始按钮。'
                Set-RowControls $row;$script:scanIndex++;$script:scanPhase='Activate';$script:scanDue=$Now
                if ($script:scanIndex -ge $script:scanQueue.Count) {Finish-RefreshScan}
                return
            }
            if ($packet -and $packet.Flavor -eq $row.Client.Flavor) {
                $row.Validated=$true; $row.FightRow.CanStart=$true; $row.FightRow.ClassId=$packet.ClassId
                Update-RowName $row; Set-RowStatusText $row '战斗监控已开启并识别职业，可以开始。'
            }
            elseif ($Now -lt $script:scanTimeout) {$script:scanDue=$Now+100; return}
            else {Set-RowStatusText $row ('战斗监控开启后未读到有效主色块：'+[WowAutoFight.Native]::LastReadError)}
            Set-RowControls $row; $script:scanIndex++; $script:scanPhase='Activate'; $script:scanDue=$Now
            if ($script:scanIndex -ge $script:scanQueue.Count) {Finish-RefreshScan}
            return
        }
        $color = Read-ScanColor $row
        if ($color -in @('red', 'green')) {
            $row.Validated = $true
            $label = if ($color -eq 'red') { '红色' } else { '绿色' }
            Set-RowStatusText $row "检测通过（$label），可以开始。"
        }
        elseif ($color -eq 'yellow') {
            Set-RowStatusText $row '黄色：背包已满，未开放按钮。'
        }
        elseif ($color -eq 'dead') {
            Set-RowStatusText $row '角色死亡，未开放开始按钮。'
        }
        elseif ($Now -lt $script:scanTimeout) {
            $script:scanDue = $Now + 100
            return
        }
        else {
            $message = if ($color -eq 'not-foreground') { '未获得前台焦点，请重试刷新。' } else { '未检测到红色或绿色，请启用插件后刷新。' }
            Set-RowStatusText $row $message
        }
    }
    catch {
        if (Test-WindowCapturePending $_) {$script:scanDue=$Now+100;return}
        $row.Validated = $false; Set-RowStatusText $row ('检测失败：' + $_.Exception.Message)
    }
    Set-RowControls $row
    $script:scanIndex++
    $script:scanPhase = 'Activate'
    $script:scanDue = $Now
    if ($script:scanIndex -ge $script:scanQueue.Count) { Finish-RefreshScan }
}

$scanTimer = New-Object System.Windows.Forms.Timer
$scanTimer.Interval = 50
$scanTimer.Add_Tick({
    try { Invoke-RefreshScan $script:scanClock.ElapsedMilliseconds }
    catch {
        foreach ($row in $script:rows.Values) { $row.Validated = $false; Stop-Row $row '扫描异常，请重新刷新。' }
        Finish-RefreshScan
        $countLabel.Text = '扫描失败：' + $_.Exception.Message
    }
})
$refreshButton.Add_Click({ Begin-RefreshScan })
function Update-BatchControls {
    foreach ($controlRow in $script:rows.Values) {Set-RowControls $controlRow}
    $eligible = @($script:rows.Values | Where-Object { $_.Start.Enabled })
    $startAllButton.Enabled = -not $script:scanning -and -not $script:editingSettings -and $eligible.Count -gt 0
    $settingsButton.Enabled = -not $script:scanning -and -not $script:editingSettings
    $audioCheck.Enabled = -not $script:scanning -and -not $script:editingSettings -and $script:scheduler.Tasks.Count -eq 0
    $stopAllButton.Enabled = $script:scanning -or $script:pendingGameExits.Count -gt 0 -or @($script:rows.Values | Where-Object {Test-UnifiedRowRunning $_}).Count -gt 0
}
function Stop-AllRows {
    Remove-GameActions -IncludeProcess
    if ($script:scanning) {Finish-RefreshScan}
    $script:pendingGameExits.Clear()
    foreach ($row in @($script:rows.Values)) { Stop-Row $row }
    $script:pendingWork=$null
    Update-BatchControls
}
$startAllButton.Add_Click({
    if ($script:scanning) { return }
    foreach ($row in @($script:rows.Values | Sort-Object { $_.Process.Id })) {
        if ($row.Start.Enabled) { Start-Row $row }
    }
    Update-BatchControls
})
$stopAllButton.Add_Click({ Stop-AllRows })

$list.Add_SizeChanged({
    foreach ($row in $script:rows.Values) { $row.Panel.Width = [Math]::Max(1170, $list.ClientSize.Width - 32) }
})

function Activate-WorkerRow($Row) {
    Assert-GameActionContext
    if ($UiTest) {
        $script:workerFocus = $Row.Process.Id
        $script:workerActivations += $Row.Process.Id
        return $Row.Process.FocusAllowed
    }
    return [WowAuto.NativeInput]::ActivateForScan($Row.Process.Id, $Row.StartTime.Ticks, $Row.Client.ExecutablePath)
}
function Test-WorkerForeground($Row) {
    if ($UiTest) { return $Row.Process.FocusAllowed -and $script:workerFocus -eq $Row.Process.Id }
    return [WowAuto.NativeInput]::IsTargetForeground($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath)
}
function Send-WorkerKey($Row, [string]$Action) {
    Assert-GameActionContext
    $binding=$script:keyBindings[$Action]
    if ($Action -eq 'Jump') { $binding=[pscustomobject]@{ Code=32; Ctrl=$false; Shift=$false; Alt=$false } }
    if ($null -eq $binding) { throw "未配置按键：$Action" }
    $Number=$binding.Code
    if ($UiTest) {
        $script:workerKeys += "$($Row.Process.Id):$Number"
        return (Test-WorkerForeground $Row)
    }
    return [WowAuto.NativeInput]::PressChord($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath, [System.UInt16]$Number, $binding.Ctrl, $binding.Shift, $binding.Alt)
}
function Close-WorkerGame($Row,[string]$Reason='背包已满') {
    $result=if ($Reason -eq '背包已满') {Exclude-FullRotationRole $Row} else {Exclude-RotationRole $Row $Reason}
    if ($result -eq 'Next') {return}
    $Row.Validated=$false
    if ($result -eq 'NoPlan') {
        Stop-Row $Row ($Reason+'：没有角色编排，保留进程并停止本行。')
        return
    }
    Request-WorkerGameExit $Row '该进程所有编排角色均已移出轮换（背包满或死亡）'
}
function Request-WorkerGameExit($Row,[string]$Reason) {
    if ($script:pendingGameExits.ContainsKey($Row.Key)) {return}
    $exit=[pscustomobject]@{Process=$Row.Process;StartTime=$Row.StartTime;Row=$Row;
        Due=0L;NextCheck=0L;Requested=$false;Reason=$Reason}
    $script:pendingGameExits[$Row.Key]=$exit
    Stop-Row $Row ($Reason+'，停止任务并请求游戏正常退出。')
    Add-GameAction -Id ('close:'+$Row.Key) -Kind Process.Close -Domain Process -Key $Row.Key -Row $Row -Owner $exit -Due $script:schedulerClock.ElapsedMilliseconds -Execute {
        param($event,$now) Invoke-CloseWorkerGame $event.Row
    }
    if ($UiTest -and -not $script:gameActions.Current) {Invoke-GameActionQueue $script:schedulerClock.ElapsedMilliseconds}
}
function Invoke-CloseWorkerGame($Row) {
    Assert-GameActionContext
    $exit=$script:pendingGameExits[$Row.Key]
    if (-not $exit -or $exit.Requested) {return}
    $Row.Validated=$false
    $reason=$exit.Reason
    try {
        $Row.Process.Refresh()
        if ($Row.Process.HasExited) {
            $script:pendingGameExits.Remove($Row.Key)
            $Row.Exited=$true
            Stop-Row $Row ($reason+'，游戏进程已退出。')
            return
        }
        if (-not (Test-RowProcessIdentity $Row)) {
            throw '进程身份已改变，未发送退出请求。'
        }
        $exit.Requested=$true;$exit.Due=$script:schedulerClock.ElapsedMilliseconds+30000;$exit.NextCheck=0L
        if ($UiTest) { $script:workerClosed += $Row.Process.Id; $requested=$true }
        else { $requested=$Row.Process.CloseMainWindow() }
        if (-not $requested) { throw '游戏窗口未接受正常关闭请求，30秒后检查并强制结束。' }
        Stop-Row $Row ($reason+'：已发送正常退出请求，等待游戏完成退出；30秒超时后强制结束。')
    }
    catch {
        if (-not $exit.Requested) {$script:pendingGameExits.Remove($Row.Key)}
        Stop-Row $Row ($reason+'：正常退出请求失败；本行已停止。'+$_.Exception.Message)
    }
    finally {
        if ($exit.Requested -and [object]::ReferenceEquals($script:pendingGameExits[$Row.Key],$exit)) {
            $exit.Due=$script:schedulerClock.ElapsedMilliseconds+30000
        }
    }
}
function Invoke-GameExitChecks([long]$Now,[string]$OnlyKey='') {
    if (-not $script:gameActions.Current) {
        Submit-GameExitActions $Now
        if ($UiTest) {Invoke-GameActionQueue $Now}
        return
    }
    Assert-GameActionContext
    foreach ($key in @($script:pendingGameExits.Keys)) {
        if ($OnlyKey -and $key -ne $OnlyKey) {continue}
        $exit=$script:pendingGameExits[$key]
        if (-not $exit.Requested) {continue}
        if ($Now -lt $exit.NextCheck -and $Now -lt $exit.Due) { continue }
        $exit.NextCheck=$Now+500
        try {
            $exit.Process.Refresh()
            if ($exit.Process.HasExited) {
                $script:pendingGameExits.Remove($key)
                $exit.Row.Exited=$true
                Stop-Row $exit.Row '游戏已正常退出，30秒超时保护已解除。'
                continue
            }
            if (-not (Test-RowProcessIdentity $exit.Row)) {
                throw '进程身份已改变，已取消超时保护。'
            }
            if ($Now -lt $exit.Due) { continue }
            # One attempt only, against the original process instance after identity validation.
            $script:pendingGameExits.Remove($key)
            if ($UiTest) { $script:workerKilled += $exit.Process.Id; $exit.Process.HasExited=$true }
            else { $exit.Process.Kill() }
            Stop-Row $exit.Row '正常退出超过30秒，已请求强制结束对应游戏进程。'
        }
        catch {
            $script:pendingGameExits.Remove($key)
            Stop-Row $exit.Row ('退出保护已停止：'+$_.Exception.Message)
        }
    }
}
function Pause-RowForFocus($Row, [long]$Now, [string]$Reason) {
    Suspend-WowAutoFocus $script:scheduler $Row.Key $Now $Reason
    if ($null -ne $script:pendingWork -and $script:pendingWork.Key -eq $Row.Key) { $script:pendingWork=$null }
    Update-RowStatus $Row
}

function Update-AudioCaptures([long]$Now) {
    foreach ($key in @($script:audioCaptures.Keys)) {
        $entry=$script:audioCaptures[$key]; $row=$script:rows[$key]; $state=$script:scheduler.Tasks[$key]
        if ($null -eq $row -or $null -eq $state -or -not $state.Running -or -not [object]::ReferenceEquals($state,$entry.State)) {
            $entry.Capture.Dispose(); $script:audioCaptures.Remove($key); continue
        }
        $capture=$entry.Capture
        if ($capture.Status -in @('Error','Stopped')) { Stop-Row $row ("音频采集失败，已停止此行：$($capture.Error)"); continue }
        if ($capture.Status -ne 'Listening') { continue }
        if (-not $state.AudioReady) { $state.AudioReady=$true; $state.Status='本进程音频采集就绪，已加入钓鱼队列。' }
        $session=if ($state.Mode -eq 'Wait' -and -not $state.AudioReelPending -and $Now -ge $script:scheduler.ItemHoldUntil) { $state.AudioSession } else { 0L }
        if ($entry.TemplateMode -and $session -ne 0 -and $entry.TemplateSession -ne $state.AudioSession) {
            try {
                $selected=$script:audioRecordingSelections[$row.Client.Flavor]
                if ($entry.RecordingId -ne $selected) {
                    $nextTemplate=Get-AudioTemplate $row.Client.Flavor $selected
                    $capture.Arm(0)
                    $capture.SetTemplate($nextTemplate,$script:audioThresholds[$row.Client.Flavor]/100.0)
                    $entry.RecordingId=$selected; $entry.Trial=$nextTemplate.IsTrial
                }
                $entry.TemplateSession=$state.AudioSession
            }
            catch { Stop-Row $row ("所选片段特征无法加载，已停止此行：$($_.Exception.Message)"); continue }
        }
        $capture.Arm($session)
        $biteSession=0L
        $hasBite=if ($UiTest) { $biteSession=$capture.Bite; $capture.Bite=0L; $biteSession -ne 0 }
            else { $capture.TryTakeBite([ref]$biteSession) }
        if ($hasBite) {
            # The state reference and fishing session prevent an old listener or cast
            # from sending a key after stop/restart/PID reuse.
            if (-not (Test-RowProcessIdentity $row)) { $row.Validated=$false; Stop-Row $row '音频事件的进程身份已变化。'; continue }
            $null=Complete-WowAutoAudioBite $script:scheduler $key $Now $biteSession
        }
    }
}

function Invoke-SchedulerTick([long]$Now,$QueuedWork=$null) {
    if (-not $script:gameActions.Current) {
        Submit-FishingActions $Now
        if ($UiTest) {Invoke-GameActionQueue $Now}
        return
    }
    if ($script:scanning -or $script:editingSettings) { return }
    Update-AudioCaptures $Now
    if ($QueuedWork -and -not (Test-GameActionValid $script:gameActions.Current)) {
        $script:pendingWork=$null;return
    }
    $work=if ($QueuedWork) {$QueuedWork} else {Get-WowAutoWork $script:scheduler $Now}
    if ($null -eq $work) { return }
    $row=$script:rows[$work.Key]
    if ($null -eq $row) { Stop-WowAutoTask $script:scheduler $work.Key; return }
    try {
        $row.Process.Refresh()
        if ($row.Process.HasExited) { $row.Exited=$true; throw '进程已退出。' }
        if (-not (Test-RowProcessIdentity $row)) {
            $row.Validated=$false
            throw '进程身份已改变。'
        }
        if (-not (Test-RowLoginPoint $row)) {throw '插件常驻登录白点不存在，已停止钓鱼任务。'}
        if ($work.Kind -eq 'FocusRetry') {
            Resume-WowAutoFocus $script:scheduler $work.Key
            $script:pendingWork=$null
            Update-RowStatus $row
            return
        }
        # The work selection is repeated every tick, including while switching windows.
        # Overdue Reel events therefore preempt both casting and a pending activation.
        $color=Read-ScanColor $row
        if ($color -eq 'not-foreground') {
            Pause-RowForFocus $row $Now '检测时失去前台焦点。'
            return
        }
        if ($color -eq 'yellow') {
            Close-WorkerGame $row
            $script:pendingWork=$null
            return
        }
        if ($color -eq 'dead') {
            Close-WorkerGame $row '角色死亡'
            $script:pendingWork=$null
            return
        }
        if ($row.State.UseAudio -and $color -notin @('red','green')) {
            Stop-Row $row '检测面板关闭或颜色未知，取消音频检测并停止此行。'
            $script:pendingWork=$null
            return
        }
        if ($work.Kind -eq 'AudioTimeout') {
            $timeoutMs=$row.State.Deadline-$row.State.FishingStartedAt
            Reset-WowAutoAudioWait $script:scheduler $work.Key $Now "$timeoutMs ms内未检测到咬钩声音，重新抛竿；不计有效循环。"
            $script:pendingWork=$null
            Update-RowStatus $row
            return
        }
        if ($work.Kind -eq 'Reel' -and $row.State.UseAudio -and $color -eq 'red') {
            Reset-WowAutoAudioWait $script:scheduler $work.Key $Now '声音事件到达后已不在钓鱼状态，取消收竿并重新抛竿。'
            $script:pendingWork=$null
            Update-RowStatus $row
            return
        }
        $sent=$true
        if ($row.State.UseItem -and -not $row.State.ItemDetectionDisabled -and $work.Kind -ne 'Reel') {
            $lure=Read-LureColor $row
            if ($lure -eq 'not-foreground') { Pause-RowForFocus $row $Now '检测鱼饵时失去前台焦点。'; return }
            if ($lure -eq 'missing' -and $color -eq 'red' -and $Now -ge $row.State.ItemRetryAt -and
                ($row.State.ItemConfirmUntil -le 0 -or $Now -lt $row.State.ItemConfirmUntil) -and
                -not (Request-FishingForeground $Now)) {return}
            $itemAction=Complete-WowAutoItemCheck $script:scheduler $work.Key $Now $lure $color
            if ($itemAction -eq 'Wait') { $script:pendingWork=$null; Update-RowStatus $row; return }
            if ($itemAction -eq 'UseItem') {
                if (-not (Request-FishingForeground $Now)) {return}
                $sent=Send-WorkerKey $row 'Item'
                $completedAt=if ($UiTest) { $Now } else { $script:schedulerClock.ElapsedMilliseconds }
                Complete-WowAutoItem $script:scheduler $work.Key $completedAt $sent
                if (-not $sent -and -not (Test-WorkerForeground $row)) { Pause-RowForFocus $row $completedAt '发送道具时失去前台焦点。' }
                $script:pendingWork=$null
                Update-RowStatus $row
                return
            }
        }
        if ($work.Kind -ne 'Reel' -and (Test-WowAutoPollNeedsInput $row.State $color) -and
            -not (Request-FishingForeground $Now)) {return}
        if ($work.Kind -eq 'Item') {
            # A valid enchant skips item use; continue fishing using the same foreground sample.
            $script:scheduler.ActiveKey=$work.Key
            $action=Complete-WowAutoPoll $script:scheduler $work.Key $Now $color
            if ($action -eq 'Ctrl1') { $sent=Send-WorkerKey $row 'Cast'; Complete-WowAutoCast $script:scheduler $work.Key $sent }
            elseif ($action -eq 'Jump') { $sent=Send-WorkerKey $row 'Jump'; Complete-WowAutoJump $script:scheduler $work.Key $sent }
            $script:pendingWork=$null
        }
        elseif ($work.Kind -eq 'Reel') {
            if (-not (Request-FishingForeground $Now)) {return}
            $sent=Send-WorkerKey $row 'Reel'
            $completedAt=if ($UiTest) { $Now } else { $script:schedulerClock.ElapsedMilliseconds }
            Complete-WowAutoReel $script:scheduler $work.Key $completedAt $sent
            $script:pendingWork=$null
        }
        else {
            $action=Complete-WowAutoPoll $script:scheduler $work.Key $Now $color
            if ($action -eq 'Ctrl1') {
                $sent=Send-WorkerKey $row 'Cast'
                Complete-WowAutoCast $script:scheduler $work.Key $sent
            }
            elseif ($action -eq 'Jump') {
                $sent=Send-WorkerKey $row 'Jump'
                Complete-WowAutoJump $script:scheduler $work.Key $sent
            }
            # Keep focus while repeatedly casting; a due Reel event can still preempt.
            $script:pendingWork=$null
        }
        if (-not $sent -and -not (Test-WorkerForeground $row)) {
            $failedAt=if ($UiTest) { $Now } else { $script:schedulerClock.ElapsedMilliseconds }
            Pause-RowForFocus $row $failedAt '发送按键时失去前台焦点。'
            return
        }
        Update-RowStatus $row
    }
    catch {
        if (Test-WindowCapturePending $_) {throw}
        Stop-Row $row ('已停止：'+$_.Exception.Message)
        $script:pendingWork=$null
    }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 25
$timer.Add_Tick({
    Invoke-UnifiedTick $script:schedulerClock.ElapsedMilliseconds
    foreach ($row in @($script:rows.Values)) { Update-RowStatus $row }
    Update-BatchControls
})
$positionTimer = New-Object System.Windows.Forms.Timer
$positionTimer.Interval = 1000
$positionTimer.Add_Tick({ Update-WindowPositions })
$form.Add_FormClosing({
    Remove-GameActions -IncludeProcess
    $script:gameActions.Closing=$true
    [WowAutoCapture.Native]::Shutdown()
    if ($script:autoFight) { Stop-AutoFightAll }
    $script:pendingGameExits.Clear()
    $timer.Stop()
    $positionTimer.Stop()
    if ($script:scanning) { Finish-RefreshScan }
    $scanTimer.Stop()
    foreach ($row in $script:rows.Values) { Stop-Row $row }
})

. (Join-Path $PSScriptRoot 'wowAuto.Unified.ps1')
. (Join-Path $PSScriptRoot 'wowAuto.Accounts.ps1')
. (Join-Path $PSScriptRoot 'wowAuto.Rotation.ps1')
# One process list and one timer coordinate input across both detector engines.
if (-not $UiTest) {
    try {
        . (Join-Path $PSScriptRoot 'autoFight.ps1')
        Initialize-AutoFightTab $tabs $form -Unified
    }
    catch {
        if ($script:autoFight) { Close-AutoFightTab }
        $countLabel.Text='autoFight initialization failed: '+$_.Exception.Message
    }
}

try {
    if ($UiTest) {
        # Test fixtures are never passed to native input, capture, or termination.
        foreach ($id in @(101, 202, 303)) {
            $isForever=$id -eq 202
            $mock = [pscustomobject]@{
                Id=$id; StartTime=[datetime]'2026-09-27'; ProcessName=$(if ($isForever) { 'Wow' } else { 'WowClassic' })
                ExecutablePath=$(if ($isForever) { 'C:\test-games\_cn_beta_\Wow.exe' } else { 'C:\test-games\_classic_titan_\WowClassic.exe' })
                FileVersion=$(if ($isForever) { '1.60.1.70338' } else { '3.80.2.70177' })
                MainWindowTitle="测试游戏 $id"; HasExited=$false; FocusAllowed=$true; ScanColor='red'; LureColor='missing'
                WindowBounds=@(20,20,820,520); ScreenBounds=@(0,0,1920,1080); Minimized=$false
            }
            $mock | Add-Member ScriptMethod Refresh { }
            $script:mockProcesses += $mock
        }
    }
    $null = Refresh-ProcessRows
    if (-not $PreviewPath -and -not $UiTest) { $timer.Start(); $positionTimer.Start() }
    if ($PreviewPath -or $UiTest) {
        $form.Show()
        [System.Windows.Forms.Application]::DoEvents()
        if ($UiTest) {
            . (Join-Path $PSScriptRoot 'tests\Layout.UiTests.ps1')
            . (Join-Path $PSScriptRoot 'tests\Refresh.UiTests.ps1')
            . (Join-Path $PSScriptRoot 'tests\Scheduler.UiTests.ps1')
            . (Join-Path $PSScriptRoot 'tests\KeyItem.UiTests.ps1')
            . (Join-Path $PSScriptRoot 'tests\ItemDetection.UiTests.ps1')
            . (Join-Path $PSScriptRoot 'tests\ProcessItems.UiTests.ps1')
            . (Join-Path $PSScriptRoot 'tests\FocusRetry.UiTests.ps1')
            . (Join-Path $PSScriptRoot 'tests\StatusTimestamp.UiTests.ps1')
            . (Join-Path $PSScriptRoot 'tests\ClientSettings.UiTests.ps1')
            . (Join-Path $PSScriptRoot 'tests\Audio.UiTests.ps1')
            . (Join-Path $PSScriptRoot 'tests\Audio.Features.UiTests.ps1')
            . (Join-Path $PSScriptRoot 'tests\Preferences.UiTests.ps1')
            . (Join-Path $PSScriptRoot 'tests\Audio.Timeout.UiTests.ps1')
            . (Join-Path $PSScriptRoot 'tests\Audio.Recordings.UiTests.ps1')
            . (Join-Path $PSScriptRoot 'tests\StatusLog.UiTests.ps1')
            . (Join-Path $PSScriptRoot 'tests\JumpInterval.UiTests.ps1')
            . (Join-Path $PSScriptRoot 'tests\AutoFight.UiTests.ps1')
            . (Join-Path $PSScriptRoot 'tests\Unified.UiTests.ps1')
            . (Join-Path $PSScriptRoot 'tests\Rotation.UiTests.ps1')
            . (Join-Path $PSScriptRoot 'tests\Accounts.UiTests.ps1')
            . (Join-Path $PSScriptRoot 'tests\Logging.UiTests.ps1')
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
finally {
    if ($script:autoFight) { Close-AutoFightTab }
    foreach ($entry in @($script:audioCaptures.Values)) { $entry.Capture.Dispose() }
    $script:audioCaptures.Clear()
    $positionTimer.Dispose(); $scanTimer.Dispose(); $timer.Dispose(); $form.Dispose()
    if ($UiTest -and (Test-Path -LiteralPath $script:settingsPath)) { Remove-Item -LiteralPath $script:settingsPath }
    if ($UiTest -and (Test-Path -LiteralPath $script:audioRecordingDirectory)) {
        foreach ($recording in $script:audioRecordings.Values | ForEach-Object {$_}) {
            $wavePath=Join-Path $script:audioRecordingDirectory $recording.Wave
            if ([IO.File]::Exists($wavePath)) { [IO.File]::Delete($wavePath) }
        }
        [IO.Directory]::Delete($script:audioRecordingDirectory)
    }
    if ($UiTest -and (Test-Path -LiteralPath $script:audioFeatureDirectory)) {
        foreach ($name in @(@($script:audioRecordings.Values | ForEach-Object {$_} | ForEach-Object Feature) + @('titan.feature','forerver.feature') | Select-Object -Unique)) { $featurePath=Join-Path $script:audioFeatureDirectory $name; if ([IO.File]::Exists($featurePath)) { [IO.File]::Delete($featurePath) } }
        [IO.Directory]::Delete($script:audioFeatureDirectory)
    }
    if ($UiTest -and $script:logTestDirectory -and [IO.Directory]::Exists($script:logTestDirectory)) {
        foreach ($name in @('wowAuto.log','info.log')) {
            $file=Join-Path $script:logTestDirectory $name
            if ([IO.File]::Exists($file)) {[IO.File]::Delete($file)}
        }
        [IO.Directory]::Delete($script:logTestDirectory)
    }
}
