#nullable disable
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

namespace WowAutoRotation {
    public static class Native {
        public static Func<int,long,string,Bitmap> FrameReader;
        public static Func<int,long,string,Size> SizeReader;
        // Match the in-world palette in each client's LoginPoint.lua.
        static readonly Dictionary<string,Color> LoginModeColors = new Dictionary<string,Color> {
            {"rest",Color.White},
            {"fish",Color.FromArgb(64,170,255)},
            {"fight",Color.FromArgb(255,112,76)},
            {"shop",Color.FromArgb(181,104,255)},
            {"dead",Color.FromArgb(220,48,69)}
        };
        static readonly Dictionary<string,Color> ShoppingColors = new Dictionary<string,Color> {
            {"closed",Color.FromArgb(52,120,230)},
            {"open",Color.FromArgb(154,211,67)},
            {"bought",Color.FromArgb(71,218,181)}
        };
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
                    (product.Equals("_forever_",StringComparison.OrdinalIgnoreCase) || product.Equals("_cn_beta_",StringComparison.OrdinalIgnoreCase)) && file.Equals("Wow.exe",StringComparison.OrdinalIgnoreCase) && version.StartsWith("1.60.");
                if(!valid || IsIconic(p.MainWindowHandle) || GetForegroundWindow()!=p.MainWindowHandle) throw new InvalidOperationException("Expected foreground WoW client unavailable.");
                return p.MainWindowHandle;
            }
        }
        public static Size ReadClientSize(int pid,long ticks,string path) {
            if(SizeReader==null) throw new InvalidOperationException("Window capture source is not initialized.");
            return SizeReader(pid,ticks,path);
        }
        public static bool ClientSizeWithinTolerance(int expectedWidth,int expectedHeight,int width,int height) {
            if(expectedWidth<=0 || expectedHeight<=0 || width<=0 || height<=0) return false;
            // Compare each axis with the original system snapshot; exactly 5% is allowed.
            return Math.Abs((long)width-expectedWidth)*100L<=(long)expectedWidth*5L &&
                Math.Abs((long)height-expectedHeight)*100L<=(long)expectedHeight*5L;
        }
        public static Bitmap Capture(int pid,long ticks,string path,int expectedWidth,int expectedHeight) {
            Size current=ReadClientSize(pid,ticks,path);
            if(!ClientSizeWithinTolerance(expectedWidth,expectedHeight,current.Width,current.Height))
                throw new InvalidOperationException("Client resized before capture.");
            if(FrameReader==null) throw new InvalidOperationException("Window capture source is not initialized.");
            return FrameReader(pid,ticks,path);
        }
        static bool ColorMatches(Color actual,Color expected,int tolerance) {
            return Math.Abs(actual.R-expected.R)<=tolerance && Math.Abs(actual.G-expected.G)<=tolerance &&
                Math.Abs(actual.B-expected.B)<=tolerance;
        }
        static bool IsSolidColor(Bitmap frame,Rectangle bounds,Color expected,int tolerance) {
            for(int y=bounds.Top;y<bounds.Bottom;y++) for(int x=bounds.Left;x<bounds.Right;x++) {
                if(!ColorMatches(frame.GetPixel(x,y),expected,tolerance)) return false;
            }
            return true;
        }
        static string DecodeLoginMode(Bitmap frame,Rectangle bounds) {
            Color center=frame.GetPixel(bounds.X+8,bounds.Y+8);
            // Keep the legacy solid-white threshold and avoid the outer edge pixels.
            bounds.Inflate(-2,-2);
            foreach(var mode in LoginModeColors) {
                int tolerance=mode.Key=="rest" ? 10 : 6;
                if(ColorMatches(center,mode.Value,tolerance) && IsSolidColor(frame,bounds,mode.Value,tolerance))
                    return mode.Key;
            }
            return "unknown";
        }
        public static bool HasLoginPoint(Bitmap sample) {
            return sample!=null && sample.Width==16 && sample.Height==16 &&
                DecodeLoginMode(sample,new Rectangle(0,0,16,16))!="unknown";
        }
        public static Rectangle LoginPointBounds(int width,int height) {
            if(width<48 || height<48) throw new ArgumentException("Client too small for login point.");
            // Match both addons: 16 physical pixels away from the rounded client edges.
            return new Rectangle(width-32,height-32,16,16);
        }
        public static string ReadLoginMode(Bitmap frame) {
            return DecodeLoginMode(frame,LoginPointBounds(frame.Width,frame.Height));
        }
        public static string ReadLoginMode(int pid,long ticks,string path) {
            if(FrameReader==null) throw new InvalidOperationException("Window capture source is not initialized.");
            using(var frame=FrameReader(pid,ticks,path)) return ReadLoginMode(frame);
        }
        public static bool LoginPoint(int pid,long ticks,string path) {
            return ReadLoginMode(pid,ticks,path)!="unknown";
        }
        public static string ReadShoppingState(int pid,long ticks,string path,bool reportDeath=false) {
            if(FrameReader==null) throw new InvalidOperationException("Window capture source is not initialized.");
            using(var frame=FrameReader(pid,ticks,path)) {
                string mode=ReadLoginMode(frame);
                if(reportDeath && mode=="dead") return "dead";
                if(mode!="shop") return "unknown";
                int x=frame.Width/2,y=frame.Height/2;
                Color center=frame.GetPixel(x,y);
                Rectangle interior=new Rectangle(x-2,y-2,5,5);
                foreach(var phase in ShoppingColors) {
                    if(ColorMatches(center,phase.Value,3) && IsSolidColor(frame,interior,phase.Value,3))
                        return phase.Key;
                }
                return "unknown";
            }
        }
        public static System.Drawing.Point CursorParkPoint(int width,int height) {
            if(width<48 || height<48) throw new ArgumentException("Client too small for cursor parking.");
            return new System.Drawing.Point(width/2,height/2);
        }
        public static void ParkCursor(int pid,long ticks,string path) {
            IntPtr old=SetThreadDpiAwarenessContext(new IntPtr(-4));
            try {
                IntPtr h=Window(pid,ticks,path);Rect r;Point origin=new Point();
                if(!GetClientRect(h,out r) || r.R<48 || r.B<48 || !ClientToScreen(h,ref origin)) throw new InvalidOperationException("Client geometry unavailable.");
                var parking=CursorParkPoint(r.R,r.B);
                Point target=new Point {X=origin.X+parking.X,Y=origin.Y+parking.Y};
                if(!SetCursorPos(target.X,target.Y)) throw new InvalidOperationException("Cannot park cursor in game client.");
                Rect after;Point next=new Point();
                if(Window(pid,ticks,path)!=h || !GetClientRect(h,out after) || !ClientToScreen(h,ref next) ||
                    after.R!=r.R || after.B!=r.B || next.X!=origin.X || next.Y!=origin.Y)
                    throw new InvalidOperationException("Window moved during cursor parking.");
            } finally {if(old!=IntPtr.Zero) SetThreadDpiAwarenessContext(old);}
        }
        public static bool ClickCharacter(int pid,long ticks,string path,double x,double y,int expectedWidth,int expectedHeight,int firstDelayMs,int secondDelayMs) {
            return ClickCharacter(pid,ticks,path,x,y,expectedWidth,expectedHeight,firstDelayMs,secondDelayMs,100,250);
        }
        public static bool ClickCharacter(int pid,long ticks,string path,double x,double y,int expectedWidth,int expectedHeight,int firstDelayMs,int secondDelayMs,int minimumMs,int maximumMs) {
            IntPtr old=SetThreadDpiAwarenessContext(new IntPtr(-4));
            try {
                if(minimumMs<1 || maximumMs>2000 || minimumMs>maximumMs || firstDelayMs<minimumMs || firstDelayMs>maximumMs || secondDelayMs<minimumMs || secondDelayMs>maximumMs)
                    throw new ArgumentOutOfRangeException("Character click intervals are outside the configured range.");
                IntPtr h=Window(pid,ticks,path);Rect r;Point p=new Point();
                if(x<=0 || x>=1 || y<=0 || y>=1 || !GetClientRect(h,out r) || !ClientToScreen(h,ref p)) throw new ArgumentException("Invalid client point.");
                // Apply the same 5% tolerance, then map cached ratios using the current dimensions.
                if(!ClientSizeWithinTolerance(expectedWidth,expectedHeight,r.R,r.B)) return false;
                p.X+=(int)Math.Round(x*r.R);p.Y+=(int)Math.Round(y*r.B);
                if(GetAncestor(WindowFromPoint(p),2)!=h || !SetCursorPos(p.X,p.Y)) throw new InvalidOperationException("Target point is obscured.");
                Window(pid,ticks,path);
                var down=new Input();down.Data.Mouse.Flags=2;
                var up=new Input();up.Data.Mouse.Flags=4;
                Input[] inputs=new[]{down,up};
                int[] intervals=new[]{firstDelayMs,secondDelayMs};
                for(int click=0;click<3;click++) {
                    if(click>0) System.Threading.Thread.Sleep(intervals[click-1]);
                    Rect next;Point origin=new Point();
                    if(Window(pid,ticks,path)!=h || !GetClientRect(h,out next) || !ClientToScreen(h,ref origin) ||
                        next.R!=r.R || next.B!=r.B || origin.X+(int)Math.Round(x*r.R)!=p.X || origin.Y+(int)Math.Round(y*r.B)!=p.Y)
                        throw new InvalidOperationException("Window moved during character clicks.");
                    if(GetAncestor(WindowFromPoint(p),2)!=h || SendInput((uint)inputs.Length,inputs,Marshal.SizeOf(typeof(Input)))!=inputs.Length) {
                        SendInput(1,new[]{up},Marshal.SizeOf(typeof(Input)));
                        throw new InvalidOperationException("Character clicks interrupted.");
                    }
                }
                return true;
            } finally {if(old!=IntPtr.Zero) SetThreadDpiAwarenessContext(old);}
        }
        public static byte[] Png(Bitmap b) {
            using(var stream=new MemoryStream()) {b.Save(stream,ImageFormat.Png);return stream.ToArray();}
        }
        // Include the full name column even when the character list keeps a fixed
        // pixel width while the game client is resized.
        public static Rectangle NamesRegion(Bitmap b) {
            // The older 0.373-height crop cut the first glyph in narrow windows.
            int width=Math.Min(b.Width,Math.Max(1,(int)Math.Ceiling(b.Height*0.47)));
            return new Rectangle(b.Width-width,0,width,Math.Max(1,(int)Math.Floor(b.Height*0.84)));
        }
        public static byte[] NamesPng(Bitmap b) {
            return TextPng(b,NamesRegion(b),false);
        }
        public static byte[] AnchorsPng(Bitmap b) {
            return TextPng(b,new Rectangle(0,0,b.Width,b.Height),false);
        }
        public static int OcrTimeoutMs(string flavor) {
            return String.Equals(flavor,"forerver",StringComparison.Ordinal)?10000:3000;
        }
        public static byte[] OcrPng(Bitmap b,int maximumDimension) {
            if(maximumDimension<1) throw new ArgumentOutOfRangeException("maximumDimension");
            // Enlarge small windows for text recognition, cap both axes at the engine's actual limit.
            double scale=Math.Min(Math.Max(1.0,1080.0/b.Height),maximumDimension/(double)Math.Max(b.Width,b.Height));
            int width=Math.Max(1,Math.Min(maximumDimension,(int)Math.Floor(b.Width*scale)));
            int height=Math.Max(1,Math.Min(maximumDimension,(int)Math.Floor(b.Height*scale)));
            using(var resized=new Bitmap(b,new Size(width,height))) return Png(resized);
        }
        static byte[] TextPng(Bitmap b,Rectangle region,bool white) {
            int height=region.Height;
            using(var crop=new Bitmap(region.Width,height,PixelFormat.Format32bppArgb)) {
                using(var g=Graphics.FromImage(crop)) g.DrawImage(b,new Rectangle(0,0,crop.Width,height),region,GraphicsUnit.Pixel);
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
