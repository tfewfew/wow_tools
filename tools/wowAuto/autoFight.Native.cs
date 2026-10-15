using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

// Combat decoding/input is independent; frames come from the host window-capture service.
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
        public bool Combat, Busy;
        public int ClassId, EncounterId;
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
        [StructLayout(LayoutKind.Sequential)] private struct MonitorInfo
        { public int size; public Rect monitor, work; public uint flags; }
        [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr h,out Rect rect);
        [DllImport("user32.dll")] private static extern IntPtr MonitorFromWindow(IntPtr h,uint flags);
        [DllImport("user32.dll", CharSet=CharSet.Auto)] private static extern bool GetMonitorInfo(IntPtr h,ref MonitorInfo info);
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr h);
        [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr h);
        [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr h);
        [DllImport("user32.dll")] private static extern bool ShowWindowAsync(IntPtr h, int command);
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

        public static string ReadWindowPosition(Client client)
        {
            using (System.Diagnostics.Process target = System.Diagnostics.Process.GetProcessById(client.ProcessId))
            {
                if (!Matches(target, client)) return "位置未知";
                IntPtr window = target.MainWindowHandle;
                if (window == IntPtr.Zero) return "位置未知";
                if (IsIconic(window)) return "最小化";
                IntPtr oldContext = SetThreadDpiAwarenessContext(new IntPtr(-4));
                try
                {
                    Rect rect;
                    MonitorInfo info = new MonitorInfo();
                    info.size = Marshal.SizeOf(typeof(MonitorInfo));
                    if (!GetWindowRect(window, out rect) || !GetMonitorInfo(MonitorFromWindow(window, 2), ref info)) return "位置未知";
                    return ClassifyWindowPosition(rect.Left, rect.Top, rect.Right, rect.Bottom,
                        info.monitor.Left, info.monitor.Top, info.monitor.Right, info.monitor.Bottom);
                }
                finally { if (oldContext != IntPtr.Zero) SetThreadDpiAwarenessContext(oldContext); }
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
            return new int[] {width/2,height/2};
        }
        public static Func<int,long,string,Bitmap> FrameReader;
        public static Func<Exception,bool> CapturePending;
        public static bool LastReadPending { get; private set; }
        public static string LastReadError { get; private set; }
        private static Packet ReadFailed(string reason) { LastReadError=reason; return null; }
        private static string RGB(uint c) { return R(c)+","+G(c)+","+B(c); }
        public static Packet Read(Client c) {
            LastReadError="";LastReadPending=false;
            try {
                if(FrameReader==null) return ReadFailed("窗口捕获源未初始化");
                // The shared source validates process identity and returns this client's pixels only.
                using(var frame=FrameReader(c.ProcessId,c.StartTicks,c.Path)) {
                    int[] samples=SampleOffsets(frame.Width,frame.Height);
                    if(samples==null) return ReadFailed("客户区尺寸不可读或过小");
                    Color color=frame.GetPixel(samples[0],samples[1]);
                    Color hint=frame.GetPixel(samples[0]+32,samples[1]);
                    uint main=(uint)(color.R|(color.G<<8)|(color.B<<16));
                    uint auxiliary=(uint)(hint.R|(hint.G<<8)|(hint.B<<16));
                    return Decode(new uint[]{main,auxiliary},c.Flavor)
                        ?? ReadFailed("色块数据未知或编码不符，主RGB("+RGB(main)+")，副RGB("+RGB(auxiliary)+")");
                }
            } catch(Exception error) {
                LastReadPending=CapturePending!=null && CapturePending(error);
                return ReadFailed(error.Message);
            }
        }
        private static int Slot(int value,int start,int step,int count)
        {
            int slot=(int)Math.Round((value-start)/(double)step);
            return slot>=0 && slot<count && Math.Abs(value-(start+slot*step))<=1 ? slot : -1;
        }
        private static bool ColorNear(uint actual,int red,int green,int blue)
        {
            return Math.Abs(R(actual)-red)<=1 && Math.Abs(G(actual)-green)<=1 && Math.Abs(B(actual)-blue)<=1;
        }
        // V9 adds terminal death (7); removed waiting (3) and skin (6) remain invalid.
        public static Packet Decode(uint[] cells,string expectedFlavor)
        {
            if (cells==null || cells.Length!=2 || cells[0]==0xffffffff) return null;
            int action=Slot(R(cells[0]),7,20,8);
            int identityBusy=Slot(G(cells[0]),0,4,52), encounterCombat=Slot(B(cells[0]),0,4,64);
            if (action<=0 || identityBusy<0 || encounterCombat<0) return null;
            int identity=identityBusy%26, classId=identity%13+1;
            string flavor=identity<13 ? "titan" : "forerver";
            if (flavor!=expectedFlavor || classId==10 || classId>11 || (flavor=="forerver" && classId==6)) return null;
            string[] actions={"unknown","idle","opening",null,"combat","interact",null,"dead"};
            string state=actions[action];
            bool combat=encounterCombat>=32, busy=identityBusy>=26;
            if (state==null || (combat != (state=="combat"))) return null;
            string recovery=ColorNear(cells[1],38,38,38) ? "none"
                : ColorNear(cells[1],0,102,255) ? "recover"
                : ColorNear(cells[1],128,128,128) ? "unknown" : null;
            if (recovery==null) return null;
            if (state=="dead" && (busy || recovery!="none")) return null;
            return new Packet {Action=state,Flavor=flavor,Recovery=recovery,Combat=combat,Busy=busy,
                ClassId=classId,EncounterId=encounterCombat%32};
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
