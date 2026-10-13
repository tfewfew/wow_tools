using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
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
        public static void ValidateSnapshot(int pid,long ticks,string path,int width,int height) {
            Rect r;if(!GetClientRect(Window(pid,ticks,path),out r) || r.R!=width || r.B!=height) throw new InvalidOperationException("Window resized during OCR.");
        }
        public static void MouseAction(int pid,long ticks,string path,double x,double y,int wheel,bool doubleClick) {
            IntPtr old=SetThreadDpiAwarenessContext(new IntPtr(-4));
            try {
                IntPtr h=Window(pid,ticks,path);Rect r;Point p=new Point();
                if(x<=0 || x>=1 || y<=0 || y>=1 || !GetClientRect(h,out r) || !ClientToScreen(h,ref p)) throw new ArgumentException("Invalid client point.");
                p.X+=(int)Math.Round(x*r.R);p.Y+=(int)Math.Round(y*r.B);
                if(GetAncestor(WindowFromPoint(p),2)!=h || !SetCursorPos(p.X,p.Y)) throw new InvalidOperationException("Target point is obscured.");
                Window(pid,ticks,path);
                Input[] inputs;
                if(wheel!=0) {var input=new Input();input.Data.Mouse.Flags=0x800;input.Data.Mouse.Value=unchecked((uint)wheel);inputs=new[]{input};}
                else {var down=new Input();down.Data.Mouse.Flags=2;var up=new Input();up.Data.Mouse.Flags=4;inputs=new[]{down,up};}
                if(SendInput((uint)inputs.Length,inputs,Marshal.SizeOf(typeof(Input)))!=inputs.Length) {
                    if(wheel==0) {var up=new Input();up.Data.Mouse.Flags=4;SendInput(1,new[]{up},Marshal.SizeOf(typeof(Input)));}
                    throw new InvalidOperationException("Mouse input failed.");
                }
                if(wheel==0 && doubleClick) {
                    System.Threading.Thread.Sleep(40);
                    Window(pid,ticks,path);
                    if(GetAncestor(WindowFromPoint(p),2)!=h || SendInput((uint)inputs.Length,inputs,Marshal.SizeOf(typeof(Input)))!=inputs.Length) {
                        var up=new Input();up.Data.Mouse.Flags=4;SendInput(1,new[]{up},Marshal.SizeOf(typeof(Input)));
                        throw new InvalidOperationException("Double-click interrupted.");
                    }
                }
            } finally {if(old!=IntPtr.Zero) SetThreadDpiAwarenessContext(old);}
        }
        public static byte[] Png(Bitmap b) {
            using(var stream=new MemoryStream()) {b.Save(stream,ImageFormat.Png);return stream.ToArray();}
        }
        // The demonstration's yellow names remain readable over the selected-row highlight.
        // This is OCR preprocessing of text, never a detector/state color protocol.
        public static byte[] NamesPng(Bitmap b) {
            return TextPng(b,0.79,0.21,0.84,false);
        }
        public static byte[] WorldPng(Bitmap b) {
            return TextPng(b,0,0.25,0.50,true);
        }
        static byte[] TextPng(Bitmap b,double fractionX,double width,double fraction,bool white) {
            int left=(int)(b.Width*fractionX),height=Math.Max(1,(int)(b.Height*fraction));
            using(var crop=new Bitmap(Math.Max(1,(int)(b.Width*width)),height,PixelFormat.Format32bppArgb)) {
                using(var g=Graphics.FromImage(crop)) g.DrawImage(b,new Rectangle(0,0,crop.Width,height),new Rectangle(left,0,crop.Width,height),GraphicsUnit.Pixel);
                var data=crop.LockBits(new Rectangle(0,0,crop.Width,height),ImageLockMode.ReadWrite,PixelFormat.Format32bppArgb);
                try {
                    var pixels=new byte[data.Stride*height];Marshal.Copy(data.Scan0,pixels,0,pixels.Length);
                    for(int y=0;y<height;y++) for(int x=0;x<crop.Width;x++) {
                        int i=y*data.Stride+x*4;
                        bool text=white?pixels[i+2]>100 && pixels[i+1]>100 && pixels[i]>100:pixels[i+2]>180 && pixels[i+1]>130 && pixels[i]<120;
                        byte value=(byte)(text?0:255);
                        pixels[i]=pixels[i+1]=pixels[i+2]=value;pixels[i+3]=255;
                    }
                    Marshal.Copy(pixels,0,data.Scan0,pixels.Length);
                } finally {crop.UnlockBits(data);}
                double scale=Math.Min(white?3.0:2.0,9000.0/Math.Max(crop.Width,height));
                using(var larger=new Bitmap(crop,new Size(Math.Max(1,(int)(crop.Width*scale)),Math.Max(1,(int)(height*scale))))) return Png(larger);
            }
        }
    }
}
