#nullable disable
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
                && (String.Equals(product, "_forever_", StringComparison.OrdinalIgnoreCase) || String.Equals(product, "_cn_beta_", StringComparison.OrdinalIgnoreCase))
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
        {return PressChord(targetProcessId,startTimeTicks,executablePath,number,ctrl,shift,alt,50);}
        public static bool PressChord(int targetProcessId, long startTimeTicks, string executablePath, ushort number, bool ctrl, bool shift, bool alt,int durationMs)
        {
            if(durationMs<1 || durationMs>5000) throw new ArgumentOutOfRangeException("durationMs");
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
                Thread.Sleep(durationMs);
            }
            finally
            {
                Send(up.ToArray());
            }
            return true;
        }

        // Send only the addon start commands, never arbitrary chat text or macros.
        public static bool SendDetectorCommand(int processId, long startTicks, string path, string mode)
        {return SendDetectorCommand(processId,startTicks,path,mode,50);}
        public static bool SendDetectorCommand(int processId, long startTicks, string path, string mode,int durationMs)
        {
            string command = DetectorCommand(mode);
            if (!PressChord(processId,startTicks,path,13,false,false,false,durationMs)) return false;
            if (!PressChord(processId,startTicks,path,65,true,false,false,durationMs)) return false;
            if (!IsTargetForeground(processId,startTicks,path)) return false;
            var inputs = new System.Collections.Generic.List<INPUT>();
            foreach (char character in command) {
                INPUT down = new INPUT(); down.type=1;
                down.data.keyboard.wScan=character; down.data.keyboard.dwFlags=4;
                INPUT up=down; up.data.keyboard.dwFlags=6;
                inputs.Add(down); inputs.Add(up);
            }
            Send(inputs.ToArray());
            return PressChord(processId,startTicks,path,13,false,false,false,durationMs);
        }
        public static string DetectorCommand(string mode)
        {
            if (mode=="fish") return "/wowdetector on";
            if (mode=="fight") return "/fightdetector on";
            if (mode=="tame") return "/pettamer on";
            if (mode=="rest") return "/wowrest";
            throw new ArgumentException("Unknown detector mode.");
        }
        public static string ShoppingCommand(string action)
        {
            if (action=="prepare" || action=="buy" || action=="close" || action=="finish" || action=="cancel")
                return "/autoshop " + action;
            throw new ArgumentException("Invalid shopping command.");
        }

        public static bool SendShoppingCommand(int pid,long ticks,string path,string action,int durationMs)
        {
            return SendChatCommand(pid,ticks,path,ShoppingCommand(action),durationMs);
        }

        public static string RotationCommand(string action,int token)
        {
            if(action=="logout") return "/logout";
            throw new ArgumentException("Unknown rotation command.");
        }
        public static bool SendRotationCommand(int pid,long ticks,string path,string action,int token)
        {return SendRotationCommand(pid,ticks,path,action,token,50);}
        public static bool SendRotationCommand(int pid,long ticks,string path,string action,int token,int durationMs)
        {
            string command=RotationCommand(action,token);
            if(action=="logout" && !SendChatCommand(pid,ticks,path,"/stopcasting",durationMs)) return false;
            return SendChatCommand(pid,ticks,path,command,durationMs);
        }
        private static bool SendChatCommand(int pid,long ticks,string path,string command,int durationMs)
        {
            if(!PressChord(pid,ticks,path,13,false,false,false,durationMs) || !PressChord(pid,ticks,path,65,true,false,false,durationMs)) return false;
            if(!IsTargetForeground(pid,ticks,path)) return false;
            var inputs=new System.Collections.Generic.List<INPUT>();
            foreach(char c in command) {
                INPUT down=new INPUT();down.type=1;down.data.keyboard.wScan=c;down.data.keyboard.dwFlags=4;
                INPUT up=down;up.data.keyboard.dwFlags=6;inputs.Add(down);inputs.Add(up);
            }
            Send(inputs.ToArray());
            return PressChord(pid,ticks,path,13,false,false,false,durationMs);
        }
    }
}
