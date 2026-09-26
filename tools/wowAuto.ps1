# Sends only while the selected WowClassic.exe window is foreground; never activates windows.
# Switch back to this PowerShell window and press Ctrl+C to stop.
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

$targets = @(Get-Process -Name 'WowClassic' -ErrorAction SilentlyContinue)
if ($targets.Count -eq 0) { throw 'WowClassic.exe is not running. Start the game first.' }
if ($targets.Count -ne 1) { throw 'Multiple WowClassic.exe processes found. Keep only one game instance open.' }
$targetProcessId = $targets[0].Id
$targetStartTime = $targets[0].StartTime
Write-Host "Selected WowClassic.exe, PID $targetProcessId."

Write-Host 'Pixel loop: sample the CENTER every random 300-600 ms; consecutive intervals differ.'
Write-Host 'RED: Ctrl+1. GREEN: wait random 8000-13000 ms, Ctrl+2, then pause detection for 1000 ms. YELLOW: terminate selected game and stop.'
Write-Host 'No window activation. Background/minimized: pause and cancel pending interaction; check every 500 ms.'
Write-Host 'Return to the game: restart color detection. Gray/unknown colors: no action.'
Write-Host 'In game, use /wowdetector center and /wowdetector on before starting.'
Write-Host 'To stop: switch back to this PowerShell window and press Ctrl+C.'
Write-Host 'Release modifier keys and switch to the game during the countdown.'
for ($seconds = 5; $seconds -gt 0; $seconds--) {
    Write-Host "Starting in $seconds..."
    Start-Sleep -Seconds 1
}

function Get-NextDetectionInterval {
    param([int]$Previous = -1)
    if ($Previous -lt 300 -or $Previous -gt 600) {
        return (Get-Random -Minimum 300 -Maximum 601)
    }
    # Choose uniformly from the 300 remaining values, excluding the previous value.
    $next = Get-Random -Minimum 300 -Maximum 600
    if ($next -ge $Previous) { $next++ }
    return $next
}

$lastDetectionIntervalMs = -1
$lastColor = ''
$wasForeground = $false
$interactionDueMs = $null
$resumeDetectionAtMs = $null
$sessionClock = [System.Diagnostics.Stopwatch]::StartNew()
try {
    while ($true) {
        $pollTimer = [System.Diagnostics.Stopwatch]::StartNew()
        if (-not [WowAuto.NativeInput]::IsTargetForeground($targetProcessId)) {
            if ($wasForeground) { Write-Host 'Paused: game is not foreground. Pending interaction cancelled.' }
            $wasForeground = $false
            $resumeDetectionAtMs = $null
            $interactionDueMs = $null
            $lastColor = ''
        }
        else {
            if (-not $wasForeground) { Write-Host 'Game is foreground. Starting fresh color detection.' }
            $wasForeground = $true
            if ($null -ne $resumeDetectionAtMs -and $sessionClock.ElapsedMilliseconds -ge $resumeDetectionAtMs) {
                $resumeDetectionAtMs = $null
            }
            $color = 'unknown'
            if ($null -eq $resumeDetectionAtMs) {
                $color = [WowAuto.NativeInput]::ReadCenterColor($targetProcessId)
            }
            if ($color -eq 'yellow') {
                Write-Host 'Bags full (yellow). Terminating the selected WowClassic process and stopping.'
                $targetToStop = Get-Process -Id $targetProcessId -ErrorAction SilentlyContinue
                if ($null -ne $targetToStop) {
                    if ($targetToStop.ProcessName -ne 'WowClassic' -or $targetToStop.StartTime -ne $targetStartTime) {
                        throw 'Target process identity changed. No process was terminated.'
                    }
                    Stop-Process -InputObject $targetToStop -Force -ErrorAction Stop
                    if (-not $targetToStop.WaitForExit(5000)) { throw 'The selected game process did not exit within 5 seconds.' }
                }
                break
            }
            if ($null -ne $interactionDueMs) {
                # While waiting, check focus and the full-bag signal every 500 ms.
                if ($sessionClock.ElapsedMilliseconds -ge $interactionDueMs) {
                    $sentInteraction = [WowAuto.NativeInput]::PressCtrlNumber($targetProcessId, 0x32)
                    if ($sentInteraction) {
                        $resumeDetectionAtMs = $sessionClock.ElapsedMilliseconds + 1000
                        Write-Host 'Ctrl+2 sent. Waiting 1000 ms before resuming color detection.'
                    }
                    $interactionDueMs = $null
                    $lastColor = ''
                }
            }
            elseif ($null -eq $resumeDetectionAtMs) {
                if ($color -ne $lastColor) {
                    Write-Host "Center pixel: $color"
                    $lastColor = $color
                }
                if ($color -eq 'red') {
                    $null = [WowAuto.NativeInput]::PressCtrlNumber($targetProcessId, 0x31)
                }
                elseif ($color -eq 'green') {
                    $delayMs = Get-Random -Minimum 8000 -Maximum 13001
                    $interactionDueMs = $sessionClock.ElapsedMilliseconds + $delayMs
                    Write-Host "Waiting $delayMs ms before Ctrl+2; focus and yellow checks continue."
                }
            }
        }
        $pollIntervalMs = 500
        if ($wasForeground -and $null -eq $interactionDueMs -and $null -eq $resumeDetectionAtMs) {
            $pollIntervalMs = Get-NextDetectionInterval -Previous $lastDetectionIntervalMs
            $lastDetectionIntervalMs = $pollIntervalMs
        }
        $remainingMs = [Math]::Max(0, $pollIntervalMs - [int]$pollTimer.ElapsedMilliseconds)
        # Wake at the actual deadline instead of rounding random waits to 500 ms.
        foreach ($deadline in @($interactionDueMs, $resumeDetectionAtMs)) {
            if ($null -ne $deadline) {
                $untilDeadline = [Math]::Max(0, $deadline - $sessionClock.ElapsedMilliseconds)
                $remainingMs = [Math]::Min($remainingMs, $untilDeadline)
            }
        }
        if ($remainingMs -gt 0) { Start-Sleep -Milliseconds ([int]$remainingMs) }
    }
}
finally {
    Write-Host 'Pixel loop stopped.'
}
