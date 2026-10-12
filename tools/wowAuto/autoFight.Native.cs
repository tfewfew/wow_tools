using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

// Intentionally independent of WowAuto.NativeInput and the fishing adapters.
namespace WowAutoFight
{
    public sealed class Client
    {
        public int ProcessId;
        public long StartTicks;
        public string Path, Flavor, Title;
        public string Key { get { return ProcessId + "_" + StartTicks; } }
    }
    public sealed class Packet
    {
        public string Action, Flavor;
        public bool Combat, Skin;
        public int ClassId, Heartbeat;
    }
    public static class Native
    {
        [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential)] private struct Point { public int X, Y; }
        [StructLayout(LayoutKind.Sequential)] private struct Input { public uint Type; public InputData Data; }
        [StructLayout(LayoutKind.Explicit)] private struct InputData
        {
            [FieldOffset(0)] public Keyboard Keyboard;
            [FieldOffset(0)] public Mouse Mouse;
        }
        [StructLayout(LayoutKind.Sequential)] private struct Keyboard
        { public ushort Key, Scan; public uint Flags, Time; public UIntPtr Extra; }
        [StructLayout(LayoutKind.Sequential)] private struct Mouse
        { public int X, Y; public uint Data, Flags, Time; public UIntPtr Extra; }
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr h);
        [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr h);
        [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr h);
        [DllImport("user32.dll")] private static extern bool ShowWindowAsync(IntPtr h, int command);
        [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr h, out Rect rect);
        [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr h, ref Point point);
        [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr h);
        [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr h, IntPtr dc);
        [DllImport("gdi32.dll")] private static extern uint GetPixel(IntPtr dc, int x, int y);
        [DllImport("user32.dll")] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
        [DllImport("user32.dll", SetLastError=true)] private static extern uint SendInput(uint count, Input[] inputs, int size);

        private static string Flavor(string path, string version)
        {
            if (String.IsNullOrEmpty(path) || String.IsNullOrEmpty(version)) return null;
            string product=System.IO.Path.GetFileName(System.IO.Path.GetDirectoryName(path));
            string file=System.IO.Path.GetFileName(path);
            if (String.Equals(product,"_classic_titan_",StringComparison.OrdinalIgnoreCase)
                && String.Equals(file,"WowClassic.exe",StringComparison.OrdinalIgnoreCase) && version.StartsWith("3.80.")) return "titan";
            if (String.Equals(product,"_cn_beta_",StringComparison.OrdinalIgnoreCase)
                && String.Equals(file,"Wow.exe",StringComparison.OrdinalIgnoreCase) && version.StartsWith("1.60.")) return "forerver";
            return null;
        }
        public static Client[] FindClients()
        {
            var clients=new System.Collections.Generic.List<Client>();
            foreach (string name in new [] { "WowClassic", "Wow" })
                foreach (Process process in Process.GetProcessesByName(name))
                    using (process)
                        try
                        {
                            string path=process.MainModule.FileName;
                            string flavor=Flavor(path,FileVersionInfo.GetVersionInfo(path).FileVersion);
                            if (flavor==null || process.MainWindowHandle==IntPtr.Zero) continue;
                            clients.Add(new Client { ProcessId=process.Id, StartTicks=process.StartTime.Ticks,
                                Path=path, Flavor=flavor, Title=process.MainWindowTitle });
                        }
                        catch { /* Exited or inaccessible processes do not enter the queue. */ }
            return clients.ToArray();
        }
        private static bool Matches(Process p, Client c)
        {
            string path=p.MainModule.FileName;
            return !p.HasExited && p.StartTime.Ticks==c.StartTicks
                && String.Equals(path,c.Path,StringComparison.OrdinalIgnoreCase)
                && String.Equals(p.ProcessName,System.IO.Path.GetFileNameWithoutExtension(path),StringComparison.OrdinalIgnoreCase)
                && Flavor(path,FileVersionInfo.GetVersionInfo(path).FileVersion)==c.Flavor;
        }
        public static bool IsAlive(Client c)
        {
            try { using (Process p=Process.GetProcessById(c.ProcessId)) return Matches(p,c); }
            catch { return false; }
        }
        public static bool Foreground(Client c)
        {
            using (Process p=Process.GetProcessById(c.ProcessId))
            {
                if (!Matches(p,c)) return false;
                IntPtr h=p.MainWindowHandle;
                uint pid;
                GetWindowThreadProcessId(GetForegroundWindow(),out pid);
                return h!=IntPtr.Zero && !IsIconic(h) && GetForegroundWindow()==h && pid==(uint)c.ProcessId;
            }
        }
        public static bool Activate(Client c)
        {
            using (Process p=Process.GetProcessById(c.ProcessId))
            {
                if (!Matches(p,c) || p.MainWindowHandle==IntPtr.Zero) return false;
                if (IsIconic(p.MainWindowHandle)) ShowWindowAsync(p.MainWindowHandle,9);
                SetForegroundWindow(p.MainWindowHandle);
                return true; // The timer waits and then verifies actual ownership.
            }
        }
        public static IntPtr CurrentWindow() { return GetForegroundWindow(); }
        public static void Restore(IntPtr h) { if (h!=IntPtr.Zero && IsWindow(h)) SetForegroundWindow(h); }
        private static int R(uint c) { return (int)(c&255); }
        private static int G(uint c) { return (int)((c>>8)&255); }
        private static int B(uint c) { return (int)((c>>16)&255); }
        private static bool Near(uint c,int r,int g,int b)
        { return c!=0xffffffff && Math.Abs(R(c)-r)<=12 && Math.Abs(G(c)-g)<=12 && Math.Abs(B(c)-b)<=12; }
        public static Packet Read(Client c)
        {
            if (!Foreground(c)) return null;
            using (Process p=Process.GetProcessById(c.ProcessId))
            {
                if (!Matches(p,c)) return null;
                IntPtr h=p.MainWindowHandle, dc=IntPtr.Zero;
                IntPtr previous=SetThreadDpiAwarenessContext(new IntPtr(-4));
                try
                {
                    Rect rect;
                    if (!GetClientRect(h,out rect) || rect.Right-rect.Left<160 || rect.Bottom-rect.Top<160) return null;
                    Point point=new Point { X=(rect.Right-rect.Left)/2-56, Y=(rect.Bottom-rect.Top)/2-64 };
                    if (!ClientToScreen(h,ref point)) return null;
                    dc=GetDC(IntPtr.Zero);
                    if (dc==IntPtr.Zero) return null;
                    uint before=GetPixel(dc,point.X+96,point.Y);
                    uint[] cells=new uint[8];
                    for (int i=0;i<8;i++) cells[i]=GetPixel(dc,point.X+i*16,point.Y);
                    if (before!=cells[6] || GetPixel(dc,point.X+96,point.Y)!=before || !Foreground(c)) return null;
                    if (!Near(cells[0],0,255,255) || !Near(cells[7],255,255,255)) return null;
                    string flavor=Near(cells[5],255,128,0)?"titan":Near(cells[5],128,0,255)?"forerver":null;
                    if (flavor!=c.Flavor) return null;
                    int classId=(int)Math.Round(R(cells[4])/16.0);
                    if (classId<1 || classId>13 || Math.Abs(R(cells[4])-classId*16)>3
                        || Math.Abs(G(cells[4])-(255-classId*16))>3 || Math.Abs(B(cells[4])-85)>12) return null;
                    if (B(cells[6])<158 || B(cells[6])>182 || Math.Abs(R(cells[6])+G(cells[6])-255)>12) return null;
                    string action=Near(cells[1],255,0,0)?"fight":Near(cells[1],255,0,255)?"skin":
                        Near(cells[1],0,255,0)?"loot":Near(cells[1],255,255,0)?"busy":Near(cells[1],0,0,255)?"idle":null;
                    bool combat=Near(cells[2],255,0,0), peaceful=Near(cells[2],0,255,0);
                    bool skin=Near(cells[3],255,0,255), noSkin=Near(cells[3],0,0,255);
                    if (action==null || (!combat && !peaceful) || (!skin && !noSkin)
                        || (action=="skin" && !skin) || (skin && action!="skin")
                        || (combat && (action=="skin" || action=="loot"))) return null;
                    return new Packet { Action=action, Flavor=flavor, Combat=combat, Skin=skin,
                        ClassId=classId, Heartbeat=R(cells[6]) };
                }
                finally
                {
                    if (dc!=IntPtr.Zero) ReleaseDC(IntPtr.Zero,dc);
                    if (previous!=IntPtr.Zero) SetThreadDpiAwarenessContext(previous);
                }
            }
        }
        private static Input Key(ushort code,bool up)
        {
            Input result=new Input(); result.Type=1; result.Data.Keyboard.Key=code;
            result.Data.Keyboard.Flags=up?2u:0u; return result;
        }
        private static void Send(Input[] input)
        {
            if (SendInput((uint)input.Length,input,Marshal.SizeOf(typeof(Input)))!=input.Length)
                throw new Win32Exception(Marshal.GetLastWin32Error(),"autoFight SendInput incomplete");
        }
        public static bool Press(Client c,ushort code,bool ctrl,bool shift,bool alt)
        {
            if (!Foreground(c)) return false;
            var down=new System.Collections.Generic.List<Input>();
            var up=new System.Collections.Generic.List<Input>();
            if (ctrl) down.Add(Key(17,false)); if (shift) down.Add(Key(16,false)); if (alt) down.Add(Key(18,false));
            down.Add(Key(code,false)); up.Add(Key(code,true));
            if (alt) up.Add(Key(18,true)); if (shift) up.Add(Key(16,true)); if (ctrl) up.Add(Key(17,true));
            try { Send(down.ToArray()); Thread.Sleep(30); }
            finally { Send(up.ToArray()); }
            return true;
        }
    }
}
