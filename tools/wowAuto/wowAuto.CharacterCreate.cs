using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace WowAuto.CharacterCreate {
    // Native delegates are used by the process reader threads, never PowerShell callbacks.
    public sealed class Worker : IDisposable {
        readonly ConcurrentQueue<string> lines=new ConcurrentQueue<string>();
        readonly ConcurrentQueue<string> errors=new ConcurrentQueue<string>();
        readonly object gate=new object();
        readonly System.IO.StreamWriter input;
        public readonly Process Process=new Process();
        public Worker(string python,string script) {
            Process.StartInfo=new ProcessStartInfo(python,"-u \""+script+"\"") {
                UseShellExecute=false,CreateNoWindow=true,RedirectStandardInput=true,
                RedirectStandardOutput=true,RedirectStandardError=true,
                StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8,
                WorkingDirectory=System.IO.Path.GetDirectoryName(script)};
            Process.StartInfo.EnvironmentVariables["PYTHONIOENCODING"]="utf-8";
            Process.OutputDataReceived+=(sender,e)=>{if(e.Data!=null) lines.Enqueue(e.Data);};
            Process.ErrorDataReceived+=(sender,e)=>{if(e.Data!=null) errors.Enqueue(e.Data);};
            Process.Start();
            // Framework's StandardInput follows the Windows code page. The protocol
            // is UTF-8 even when a reference image path contains Chinese characters.
            input=new System.IO.StreamWriter(Process.StandardInput.BaseStream,new UTF8Encoding(false));input.AutoFlush=true;
            Process.BeginOutputReadLine();Process.BeginErrorReadLine();
        }
        public bool Exited {get {return Process.HasExited;}}
        public string NextLine(){string line;return lines.TryDequeue(out line)?line:null;}
        public string NextError(){string line;return errors.TryDequeue(out line)?line:null;}
        public void Send(string json){lock(gate){if(!Exited) input.WriteLine(json);}}
        public void Dispose(){Close(true);}
        public void Abort(){Close(false);}
        void Close(bool wait){
            try {if(!Exited){Send("{\"stop\":true}");input.Close();
                if(!wait||!Process.WaitForExit(5000)) Process.Kill();}}
            finally {Process.Dispose();}
        }
    }
    public static class Native {
        public static readonly ManualResetEventSlim Cancelled=new ManualResetEventSlim(true);
        [StructLayout(LayoutKind.Sequential)] struct RECT {public int left,top,right,bottom;}
        [StructLayout(LayoutKind.Sequential)] struct POINT {public int x,y;public POINT(int a,int b){x=a;y=b;}}
        [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT {public int dx,dy;public uint mouseData,flags,time;public UIntPtr extra;}
        [StructLayout(LayoutKind.Explicit)] struct UNION {[FieldOffset(0)] public MOUSEINPUT mouse;}
        [StructLayout(LayoutKind.Sequential)] struct INPUT {public uint type;public UNION data;}
        [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
        [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr window,out RECT rect);
        [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr window,ref POINT point);
        [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT point);
        [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window,uint flags);
        [DllImport("user32.dll")] static extern bool SetCursorPos(int x,int y);
        [DllImport("user32.dll")] static extern uint SendInput(uint count,INPUT[] input,int size);
        public static bool KeyDown(int key){return (GetAsyncKeyState(key)&0x8000)!=0;}
        public static int[] Bounds(int pid) {
            using(var process=Process.GetProcessById(pid)) {
                IntPtr old=SetThreadDpiAwarenessContext(new IntPtr(-4));
                try {
                    RECT rect;var point=new POINT(0,0);
                    if(!GetClientRect(process.MainWindowHandle,out rect)||!ClientToScreen(process.MainWindowHandle,ref point))
                        throw new InvalidOperationException("无法读取游戏客户区。");
                    return new[]{point.x,point.y,rect.right-rect.left,rect.bottom-rect.top};
                } finally {if(old!=IntPtr.Zero)SetThreadDpiAwarenessContext(old);}
            }
        }
        public static bool Matches(int[] bounds,int left,int top,int width,int height,int x,int y) {
            return bounds!=null && bounds.Length==4 && bounds[0]==left && bounds[1]==top && bounds[2]==width && bounds[3]==height
                && width>=640 && height>=360 && x>=0 && y>=0 && x<width && y<height;
        }
        public static bool Click(int pid,long ticks,string path,int left,int top,int width,int height,int x,int y) {
            using(var process=Process.GetProcessById(pid)) {
                if(process.HasExited||process.StartTime.Ticks!=ticks||!String.Equals(process.MainModule.FileName,path,StringComparison.OrdinalIgnoreCase))return false;
                IntPtr old=SetThreadDpiAwarenessContext(new IntPtr(-4));
                try {
                IntPtr window=process.MainWindowHandle;
                if(Cancelled.IsSet||KeyDown(0x78)||GetForegroundWindow()!=window||!Matches(Bounds(pid),left,top,width,height,x,y))return false;
                var point=new POINT(left+x,top+y);
                if(GetAncestor(WindowFromPoint(point),2)!=window)return false;
                if(!SetCursorPos(point.x,point.y))return false;
                if(Cancelled.IsSet||KeyDown(0x78)||GetForegroundWindow()!=window||!Matches(Bounds(pid),left,top,width,height,x,y)
                    ||GetAncestor(WindowFromPoint(point),2)!=window)return false;
                var input=new INPUT[2];input[0].data.mouse.flags=2;input[1].data.mouse.flags=4;
                uint sent=SendInput(2,input,Marshal.SizeOf(typeof(INPUT)));
                if(sent!=2){var release=new INPUT[1];release[0].data.mouse.flags=4;SendInput(1,release,Marshal.SizeOf(typeof(INPUT)));return false;}
                return true;
                } finally {if(old!=IntPtr.Zero)SetThreadDpiAwarenessContext(old);}
            }
        }
    }
}
