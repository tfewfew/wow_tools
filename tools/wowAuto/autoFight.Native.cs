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
        public string Action, Flavor, Recovery;
        public bool Combat, Skin, Busy;
        public int ClassId, Heartbeat, EncounterId;
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
        public static int[] SampleOffsets(int width,int height)
        {
            if (width<210 || height<160) return null;
            return new int[] {width/2-16,height/2-64,width/2+16,height/2-64};
        }
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
                    if (!GetClientRect(h,out rect) || rect.Right-rect.Left<210 || rect.Bottom-rect.Top<160) return null;
                    // Client rectangle and screen samples share physical coordinates under PMv2 DPI.
                    int[] samples=SampleOffsets(rect.Right-rect.Left,rect.Bottom-rect.Top);
                    Point point=new Point { X=samples[0], Y=samples[1] };
                    if (!ClientToScreen(h,ref point)) return null;
                    dc=GetDC(IntPtr.Zero);
                    if (dc==IntPtr.Zero) return null;
                    uint main=GetPixel(dc,point.X,point.Y), aux=GetPixel(dc,point.X+32,point.Y);
                    uint againMain=GetPixel(dc,point.X,point.Y), againAux=GetPixel(dc,point.X+32,point.Y);
                    Rect after;
                    if (main!=againMain || aux!=againAux || !GetClientRect(h,out after)
                        || after.Right!=rect.Right || after.Bottom!=rect.Bottom || !Foreground(c)) return null;
                    int[] afterSamples=SampleOffsets(after.Right-after.Left,after.Bottom-after.Top);
                    Point afterPoint=new Point { X=afterSamples[0], Y=afterSamples[1] };
                    if (!ClientToScreen(h,ref afterPoint) || afterPoint.X!=point.X || afterPoint.Y!=point.Y) return null;
                    return Decode(new uint[] {main,aux},c.Flavor);
                }
                finally
                {
                    if (dc!=IntPtr.Zero) ReleaseDC(IntPtr.Zero,dc);
                    if (previous!=IntPtr.Zero) SetThreadDpiAwarenessContext(previous);
                }
            }
        }
        private static int Slot(int value,int start,int step,int count)
        {
            int slot=(int)Math.Round((value-start)/(double)step);
            return slot>=0 && slot<count && Math.Abs(value-(start+slot*step))<=2 ? slot : -1;
        }
        // Pure v4 parser: exactly two RGB colors with quantized channels and coherence checksum.
        public static Packet Decode(uint[] cells,string expectedFlavor)
        {
            if (cells==null || cells.Length!=2 || cells[0]==0xffffffff || cells[1]==0xffffffff) return null;
            int action=Slot(R(cells[0]),16,32,7), identity=Slot(G(cells[0]),16,8,26);
            int encounter=Slot(B(cells[0]),4,8,32), aux=Slot(R(cells[1]),8,16,16);
            int beat=Slot(G(cells[1]),8,16,16), check=Slot(B(cells[1]),8,16,16);
            if (action<0 || identity<0 || encounter<0 || aux<0 || beat<0 || check<0
                || check!=(action+identity+encounter+aux+beat+7)%16) return null;
            string flavor=identity<13 ? "titan" : "forerver";
            if (flavor!=expectedFlavor) return null;
            string[] actions={"unknown","idle","opening","waiting","combat","loot","skin"};
            string[] recoveries={"none","recover","emergency","unknown"};
            string state=actions[action], recovery=recoveries[aux/4];
            bool combat=(aux&2)!=0, busy=(aux&1)!=0;
            if ((state=="unknown" && recovery=="none") || recovery=="unknown"
                || (combat && state!="combat" && state!="waiting" && state!="unknown")
                || (recovery=="recover" && combat) || (recovery=="emergency" && !combat)) return null;
            return new Packet {Action=state,Recovery=recovery,Flavor=flavor,Combat=combat,Busy=busy,
                Skin=state=="skin",ClassId=identity%13+1,Heartbeat=beat,EncounterId=encounter};
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
        private static Input[] heldRelease;
        public static bool IsHolding { get { return heldRelease!=null; } }
        public static void ReleaseHold()
        {
            if (heldRelease==null) return;
            Send(heldRelease);
            heldRelease=null;
        }
        public static bool BeginHold(Client c,ushort code,bool ctrl,bool shift,bool alt)
        {
            if (heldRelease!=null) throw new InvalidOperationException("autoFight movement key still held");
            if (!Foreground(c)) return false;
            var down=new System.Collections.Generic.List<Input>();
            var up=new System.Collections.Generic.List<Input>();
            if (ctrl) down.Add(Key(17,false)); if (shift) down.Add(Key(16,false)); if (alt) down.Add(Key(18,false));
            down.Add(Key(code,false)); up.Add(Key(code,true));
            if (alt) up.Add(Key(18,true)); if (shift) up.Add(Key(16,true)); if (ctrl) up.Add(Key(17,true));
            heldRelease=up.ToArray();
            try { Send(down.ToArray()); }
            catch { ReleaseHold(); throw; }
            return true;
        }
        public static bool Press(Client c,ushort code,bool ctrl,bool shift,bool alt)
        {
            if (!BeginHold(c,code,ctrl,shift,alt)) return false;
            try { Thread.Sleep(30); }
            finally { ReleaseHold(); }
            return true;
        }
    }
}
