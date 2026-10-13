using System;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;

namespace WowAutoRotation {
    public static class Native {
        [StructLayout(LayoutKind.Sequential)] struct Rect { public int L,T,R,B; }
        [StructLayout(LayoutKind.Sequential)] struct Point { public int X,Y; }
        [StructLayout(LayoutKind.Sequential)] struct Input { public uint Type; public Data Data; }
        [StructLayout(LayoutKind.Explicit)] struct Data {
            [FieldOffset(0)] public Mouse Mouse;
            [FieldOffset(0)] public Keyboard Keyboard;
        }
        [StructLayout(LayoutKind.Sequential)] struct Mouse { public int X,Y; public uint Value,Flags,Time; public UIntPtr Extra; }
        [StructLayout(LayoutKind.Sequential)] struct Keyboard { public ushort Key,Scan; public uint Flags,Time; public UIntPtr Extra; }
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
        [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h,out Rect r);
        [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h,ref Point p);
        [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
        [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point p);
        [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h,uint flags);
        [DllImport("user32.dll")] static extern bool SetCursorPos(int x,int y);
        [DllImport("user32.dll",SetLastError=true)] static extern uint SendInput(uint n,Input[] a,int size);
        static IntPtr Window(int pid,long ticks,string path) {
            using (var p=Process.GetProcessById(pid)) {
                if(p.HasExited || p.StartTime.Ticks!=ticks || !String.Equals(p.MainModule.FileName,path,StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Process identity changed.");
                string product=System.IO.Path.GetFileName(System.IO.Path.GetDirectoryName(path));
                string file=System.IO.Path.GetFileName(path),version=FileVersionInfo.GetVersionInfo(path).FileVersion;
                bool valid=product.Equals("_classic_titan_",StringComparison.OrdinalIgnoreCase) && file.Equals("WowClassic.exe",StringComparison.OrdinalIgnoreCase) && version.StartsWith("3.80.") ||
                    product.Equals("_cn_beta_",StringComparison.OrdinalIgnoreCase) && file.Equals("Wow.exe",StringComparison.OrdinalIgnoreCase) && version.StartsWith("1.60.");
                if(!valid || IsIconic(p.MainWindowHandle) || GetForegroundWindow()!=p.MainWindowHandle) throw new InvalidOperationException("Expected foreground WoW client unavailable.");
                return p.MainWindowHandle;
            }
        }
        public static Bitmap Capture(int pid,long ticks,string path) {
            IntPtr old=SetThreadDpiAwarenessContext(new IntPtr(-4)); Bitmap bitmap=null;
            try {
                IntPtr h=Window(pid,ticks,path); Rect r; Point p=new Point();
                if(!GetClientRect(h,out r) || r.R<=0 || r.B<=0 || !ClientToScreen(h,ref p)) throw new InvalidOperationException("Client geometry unavailable.");
                // Reject an overlay covering either the center or corners of the game client.
                foreach(var probe in new [] {new Point{X=p.X+r.R/2,Y=p.Y+r.B/2},new Point{X=p.X+2,Y=p.Y+2},new Point{X=p.X+r.R-3,Y=p.Y+r.B-3}})
                    if(GetAncestor(WindowFromPoint(probe),2)!=h) throw new InvalidOperationException("Game client is covered.");
                bitmap=new Bitmap(r.R,r.B);
                using(Graphics g=Graphics.FromImage(bitmap)) g.CopyFromScreen(p.X,p.Y,0,0,bitmap.Size);
                Rect after;Point q=new Point();
                if(Window(pid,ticks,path)!=h || !GetClientRect(h,out after) || !ClientToScreen(h,ref q) || after.R!=r.R || after.B!=r.B || p.X!=q.X || p.Y!=q.Y) throw new InvalidOperationException("Window moved during capture.");
                return bitmap;
            } catch {if(bitmap!=null) bitmap.Dispose();throw;} finally {if(old!=IntPtr.Zero) SetThreadDpiAwarenessContext(old);}
        }
        public static void MouseAction(int pid,long ticks,string path,double x,double y,bool scroll) {
            IntPtr old=SetThreadDpiAwarenessContext(new IntPtr(-4));
            try {
                IntPtr h=Window(pid,ticks,path);Rect r;Point p=new Point();
                if(x<=0 || x>=1 || y<=0 || y>=1 || !GetClientRect(h,out r) || !ClientToScreen(h,ref p)) throw new ArgumentException("Invalid client point.");
                p.X+=(int)Math.Round(x*r.R);p.Y+=(int)Math.Round(y*r.B);
                if(GetAncestor(WindowFromPoint(p),2)!=h || !SetCursorPos(p.X,p.Y)) throw new InvalidOperationException("Target point is obscured.");
                Window(pid,ticks,path);
                Input[] inputs;
                if(scroll) {var wheel=new Input();wheel.Data.Mouse.Flags=0x800;wheel.Data.Mouse.Value=120*100;inputs=new[]{wheel};}
                else {var down=new Input();down.Data.Mouse.Flags=2;var up=new Input();up.Data.Mouse.Flags=4;inputs=new[]{down,up};}
                if(SendInput((uint)inputs.Length,inputs,Marshal.SizeOf(typeof(Input)))!=inputs.Length) {
                    if(!scroll) {var up=new Input();up.Data.Mouse.Flags=4;SendInput(1,new[]{up},Marshal.SizeOf(typeof(Input)));}
                    throw new InvalidOperationException("Mouse input failed.");
                }
            } finally {if(old!=IntPtr.Zero) SetThreadDpiAwarenessContext(old);}
        }
        // Fixed-location visual fingerprint, normalized to client dimensions. Never accepts flat/black patches.
        public static int[] Fingerprint(Bitmap b,double x,double y,double width,double height) {
            if(x<0 || y<0 || width<=0 || height<=0 || x+width>1 || y+height>1) throw new ArgumentException("Invalid patch.");
            var values=new int[16*8*3];int i=0;
            for(int row=0;row<8;row++) for(int col=0;col<16;col++) {
                int px=Math.Min(b.Width-1,(int)((x+width*(col+0.5)/16)*b.Width));
                int py=Math.Min(b.Height-1,(int)((y+height*(row+0.5)/8)*b.Height));
                Color c=b.GetPixel(px,py);values[i++]=c.R;values[i++]=c.G;values[i++]=c.B;
            }
            return values;
        }
        public static bool Matches(int[] expected,int[] actual) {
            if(expected==null || actual==null || expected.Length!=384 || actual.Length!=384) return false;
            double sum=0,squares=0,diff=0;for(int i=0;i<expected.Length;i++){sum+=expected[i];squares+=expected[i]*expected[i];diff+=Math.Abs(expected[i]-actual[i]);}
            double mean=sum/expected.Length;
            return squares/expected.Length-mean*mean>=180 && diff/expected.Length<=12;
        }
        public static int ReadyToken(Bitmap b) {
            Color c=b.GetPixel(b.Width/2,b.Height/2);
            if(Math.Abs(c.G-231)>1 || Math.Abs(c.B-157)>1 || c.R<21 || c.R>220) return -1;
            return c.R-20;
        }
    }
}
