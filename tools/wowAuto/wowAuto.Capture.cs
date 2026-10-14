using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Threading;

// All image consumers use this window-owned WGC source. No desktop/GDI fallback.
// WinRT is resolved at runtime so Windows PowerShell 5.1 needs no SDK or NuGet package.
namespace WowAutoCapture {
    public sealed class PendingException : Exception {
        public PendingException(string message) : base("[CAPTURE_PENDING] " + message) {}
    }
    public sealed class RestoreRequest {
        public int ProcessId;
        public long StartTicks;
        public string Path, Key;
        public IntPtr Window;
        internal string SourceKey;
    }
    public static class Native {
        const int WaitMs=5000, FreshMs=1500;
        static readonly object Gate=new object();
        static readonly Dictionary<string,Source> Sources=new Dictionary<string,Source>();
        static bool closing;
        public static readonly Func<int,long,string,Bitmap> FrameReader=ReadClientFrame;
        public static readonly Func<int,long,string,Size> SizeReader=ReadClientSize;
        public static readonly Func<int,long,string,int,uint> PixelReader=ReadCenterPixel;
        public static readonly Func<Exception,bool> PendingReader=IsPending;
        sealed class Source {
            public readonly object Sync=new object();
            public RestoreRequest Identity, Restore;
            public Thread Worker;
            public volatile bool Stop;
            public Bitmap Frame;
            public Rectangle Client;
            public long FrameAt, RequestedAt, WaitingAt, RestoreUntil, NextRestoreAt, MinimumFrameAt;
            public string Error;
        }
        [StructLayout(LayoutKind.Sequential)] struct Rect { public int L,T,R,B; }
        [StructLayout(LayoutKind.Sequential)] struct Point { public int X,Y; }
        [StructLayout(LayoutKind.Sequential)] struct TextureDesc {
            public uint Width,Height,MipLevels,ArraySize,Format,SampleCount,SampleQuality,Usage,BindFlags,CpuAccess,MiscFlags;
        }
        [StructLayout(LayoutKind.Sequential)] struct Mapped { public IntPtr Data; public uint RowPitch,DepthPitch; }
        [StructLayout(LayoutKind.Sequential)] struct Box { public uint Left,Top,Front,Right,Bottom,Back; }
        [ComImport,Guid("3628e81b-3cac-4c60-b7f4-23ce0e0c3356"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface CaptureItemInterop {
            void CreateForWindow(IntPtr window,ref Guid iid,out IntPtr result);
            void CreateForMonitor(IntPtr monitor,ref Guid iid,out IntPtr result);
        }
        [ComImport,Guid("a9b3d012-3df2-4ee3-b8d1-8695f457d3c1"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface SurfaceAccess { void GetInterface(ref Guid iid,out IntPtr result); }
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void GetDesc(IntPtr self,out TextureDesc desc);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int CreateTexture(IntPtr self,ref TextureDesc desc,IntPtr initial,out IntPtr texture);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void CopyRegion(IntPtr self,IntPtr target,uint sub,uint x,uint y,uint z,IntPtr source,uint sourceSub,ref Box box);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int MapTexture(IntPtr self,IntPtr texture,uint sub,uint mode,uint flags,out Mapped mapped);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void UnmapTexture(IntPtr self,IntPtr texture,uint sub);
        [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
        [DllImport("user32.dll")] static extern bool IsIconic(IntPtr window);
        [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr window,int command);
        [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr window,out Rect rect);
        [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr window,ref Point point);
        [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
        [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr window,int attribute,out Rect rect,int size);
        [DllImport("combase.dll")] static extern int RoInitialize(uint mode);
        [DllImport("combase.dll")] static extern void RoUninitialize();
        [DllImport("combase.dll",CharSet=CharSet.Unicode)] static extern int WindowsCreateString(string text,int length,out IntPtr value);
        [DllImport("combase.dll")] static extern int WindowsDeleteString(IntPtr value);
        [DllImport("combase.dll")] static extern int RoGetActivationFactory(IntPtr name,ref Guid iid,out IntPtr factory);
        [DllImport("d3d11.dll")] static extern int D3D11CreateDevice(IntPtr adapter,uint driver,IntPtr software,uint flags,IntPtr levels,uint levelCount,uint sdk,out IntPtr device,out uint level,out IntPtr context);
        [DllImport("d3d11.dll")] static extern int CreateDirect3D11DeviceFromDXGIDevice(IntPtr device,out IntPtr inspectable);
        static long Now { get { return (long)(Stopwatch.GetTimestamp()*1000.0/Stopwatch.Frequency); } }
        static string Key(int pid,long ticks,string path) { return pid+"_"+ticks+"|"+path.ToUpperInvariant(); }
        static IntPtr Resolve(int pid,long ticks,string path) {
            using(var process=Process.GetProcessById(pid)) {
                if(process.HasExited || process.StartTime.Ticks!=ticks || !String.Equals(process.MainModule.FileName,path,StringComparison.OrdinalIgnoreCase) ||
                    !String.Equals(process.ProcessName,System.IO.Path.GetFileNameWithoutExtension(path),StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("窗口捕获进程身份已变化。");
                string product=System.IO.Path.GetFileName(System.IO.Path.GetDirectoryName(path));
                string file=System.IO.Path.GetFileName(path),version=FileVersionInfo.GetVersionInfo(path).FileVersion;
                if(!(product.Equals("_classic_titan_",StringComparison.OrdinalIgnoreCase) && file.Equals("WowClassic.exe",StringComparison.OrdinalIgnoreCase) && version.StartsWith("3.80.") ||
                     product.Equals("_cn_beta_",StringComparison.OrdinalIgnoreCase) && file.Equals("Wow.exe",StringComparison.OrdinalIgnoreCase) && version.StartsWith("1.60.")))
                    throw new InvalidOperationException("窗口捕获客户端版本不符。");
                IntPtr window=process.MainWindowHandle;
                if(window==IntPtr.Zero || !IsWindow(window)) throw new InvalidOperationException("窗口捕获目标不存在。");
                return window;
            }
        }
        static Source Prepare(int pid,long ticks,string path) {
            IntPtr window=Resolve(pid,ticks,path);
            Source source; string key=Key(pid,ticks,path); long now=Now;
            lock(Gate) {
                if(closing) throw new InvalidOperationException("窗口捕获已关闭。");
                if(Sources.TryGetValue(key,out source) && source.Identity.Window!=window) {
                    source.Stop=true;lock(source.Sync) {source.Restore=null;ClearFrame(source);}Sources.Remove(key);source=null;
                }
                if(source==null) {
                    source=new Source {Identity=new RestoreRequest {ProcessId=pid,StartTicks=ticks,Path=path,Key=pid+":"+ticks,SourceKey=key,Window=window},WaitingAt=now,MinimumFrameAt=now};
                    Sources.Add(key,source);
                }
            }
            lock(source.Sync) {
                source.RequestedAt=now;
                if(IsIconic(window)) {
                    ClearFrame(source);
                    if(source.Restore==null) {
                        source.Restore=new RestoreRequest {ProcessId=pid,StartTicks=ticks,Path=path,Key=source.Identity.Key,SourceKey=key,Window=window};
                        source.RestoreUntil=0;source.NextRestoreAt=now;source.MinimumFrameAt=now;
                    }
                    if(source.RestoreUntil!=0 && now>=source.RestoreUntil) throw new InvalidOperationException("窗口最小化后5秒内未能恢复。");
                    throw new PendingException("等待公共队列恢复最小化窗口。");
                }
                if(source.Restore!=null) {source.Restore=null;source.RestoreUntil=0;source.WaitingAt=now;source.MinimumFrameAt=now;source.Error=null;}
                if(source.Error!=null) throw new InvalidOperationException(source.Error);
                if(source.Worker==null) {
                    source.Stop=false;source.WaitingAt=now;
                    source.Worker=new Thread(()=>Run(source));source.Worker.IsBackground=true;
                    source.Worker.Name="WoW window capture "+pid;source.Worker.SetApartmentState(ApartmentState.MTA);source.Worker.Start();
                }
            }
            return source;
        }
        public static RestoreRequest[] PendingRestores() {
            var requests=new List<RestoreRequest>();long now=Now;
            lock(Gate) foreach(var source in Sources.Values) lock(source.Sync)
                if(source.Restore!=null && now>=source.NextRestoreAt && (source.RestoreUntil==0 || now<source.RestoreUntil)) requests.Add(source.Restore);
            return requests.ToArray();
        }
        public static bool RestoreCurrent(RestoreRequest request) {
            Source source;
            lock(Gate) return !closing && Sources.TryGetValue(request.SourceKey,out source) && Object.ReferenceEquals(source.Restore,request) && !source.Stop;
        }
        // Called only by Capture.Restore inside the common game-action executor.
        public static void RestoreMinimized(RestoreRequest request) {
            if(!RestoreCurrent(request)) return;
            Source source;lock(Gate) {if(!Sources.TryGetValue(request.SourceKey,out source)) return;}
            lock(source.Sync) {if(source.RestoreUntil==0) source.RestoreUntil=Now+WaitMs;source.NextRestoreAt=Now+500;}
            try {
                IntPtr window=Resolve(request.ProcessId,request.StartTicks,request.Path);
                if(window!=request.Window) {lock(source.Sync) source.Restore=null;return;}
                if(IsIconic(window)) ShowWindowAsync(window,4); // SW_SHOWNOACTIVATE: restore without requesting foreground.
            } catch(Exception error) {
                lock(source.Sync) {source.Restore=null;source.Error="窗口恢复失败："+error.Message;}
                throw;
            }
        }
        public static void CancelRestore(int pid,long ticks,string path) {
            Source source;
            lock(Gate) {if(!Sources.TryGetValue(Key(pid,ticks,path),out source)) return;}
            lock(source.Sync) {source.Restore=null;source.RestoreUntil=0;}
        }
        public static bool IsPending(Exception error) {
            for(var current=error;current!=null;current=current.InnerException)
                if(current is PendingException || current.Message.Contains("[CAPTURE_PENDING]")) return true;
            return false;
        }
        public static Size ReadClientSize(int pid,long ticks,string path) {
            Source source=Prepare(pid,ticks,path);IntPtr old=SetThreadDpiAwarenessContext(new IntPtr(-4));
            try {
                Rect rect;
                if(!GetClientRect(source.Identity.Window,out rect) || rect.R<=rect.L || rect.B<=rect.T) throw new PendingException("等待客户区尺寸。");
                return new Size(rect.R-rect.L,rect.B-rect.T);
            } finally {if(old!=IntPtr.Zero) SetThreadDpiAwarenessContext(old);}
        }
        public static Bitmap ReadClientFrame(int pid,long ticks,string path) {
            Source source=Prepare(pid,ticks,path);IntPtr old=SetThreadDpiAwarenessContext(new IntPtr(-4));
            try {
                Rectangle client;Rect bounds;
                bool geometry=Geometry(source.Identity.Window,out client,out bounds);
                lock(source.Sync) {
                    long now=Now;
                    if(source.Error!=null) throw new InvalidOperationException(source.Error);
                    if(geometry && source.Frame!=null && source.Client==client && now-source.FrameAt<=FreshMs) return (Bitmap)source.Frame.Clone();
                    if(source.WaitingAt==0) source.WaitingAt=now;
                    if(now-source.WaitingAt>=WaitMs) throw new InvalidOperationException("5秒内没有取得有效的窗口新帧。");
                    throw new PendingException("等待窗口捕获首帧或尺寸更新后的新帧。");
                }
            } finally {if(old!=IntPtr.Zero) SetThreadDpiAwarenessContext(old);}
        }
        public static uint ReadCenterPixel(int pid,long ticks,string path,int offset) {
            using(var frame=ReadClientFrame(pid,ticks,path)) {
                int x=frame.Width/2+offset,y=frame.Height/2;
                if(x<0 || x>=frame.Width) throw new InvalidOperationException("窗口客户区过小。");
                Color c=frame.GetPixel(x,y);return (uint)(c.R|(c.G<<8)|(c.B<<16));
            }
        }
        static bool Geometry(IntPtr window,out Rectangle client,out Rect bounds) {
            Rect rect;Point origin=new Point();client=Rectangle.Empty;bounds=new Rect();
            if(IsIconic(window) || !GetClientRect(window,out rect) || !ClientToScreen(window,ref origin) ||
                DwmGetWindowAttribute(window,9,out bounds,Marshal.SizeOf(typeof(Rect)))<0 || rect.R<=rect.L || rect.B<=rect.T) return false;
            client=new Rectangle(origin.X-bounds.L,origin.Y-bounds.T,rect.R-rect.L,rect.B-rect.T);
            return client.X>=0 && client.Y>=0 && client.Right<=bounds.R-bounds.L && client.Bottom<=bounds.B-bounds.T;
        }
        static void ClearFrame(Source source) {if(source.Frame!=null) {source.Frame.Dispose();source.Frame=null;}source.FrameAt=0;}
        public static void Shutdown() {
            lock(Gate) {
                closing=true;
                foreach(var source in Sources.Values) {source.Stop=true;lock(source.Sync) {source.Restore=null;ClearFrame(source);}}
                Sources.Clear();
            }
        }
        static Type WinRT(string name) {return Type.GetType(name+", "+name.Substring(0,name.LastIndexOf('.'))+", ContentType=WindowsRuntime",true);}
        static object Property(object value,Type type,string name) {return type.GetProperty(name).GetValue(value,null);}
        static int Dimension(object size,string name) {
            var field=size.GetType().GetField(name);
            return Convert.ToInt32(field!=null?field.GetValue(size):size.GetType().GetProperty(name).GetValue(size,null));
        }
        static T Slot<T>(IntPtr value,int slot) where T:class {
            return Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(Marshal.ReadIntPtr(value),slot*IntPtr.Size),typeof(T)) as T;
        }
        static void Release(ref IntPtr value) {if(value!=IntPtr.Zero) {Marshal.Release(value);value=IntPtr.Zero;}}
        static void Close(object value) {var disposable=value as IDisposable;if(disposable!=null) disposable.Dispose();else if(value!=null && Marshal.IsComObject(value)) Marshal.ReleaseComObject(value);}
        static object Item(IntPtr window) {
            string name="Windows.Graphics.Capture.GraphicsCaptureItem";IntPtr text=IntPtr.Zero,factory=IntPtr.Zero,result=IntPtr.Zero;
            Guid interop=new Guid("3628e81b-3cac-4c60-b7f4-23ce0e0c3356"),item=new Guid("79c3f95b-31f2-4ec2-a464-632ef5d30760");
            object wrapper=null;
            try {
                Marshal.ThrowExceptionForHR(WindowsCreateString(name,name.Length,out text));
                Marshal.ThrowExceptionForHR(RoGetActivationFactory(text,ref interop,out factory));
                wrapper=Marshal.GetObjectForIUnknown(factory);
                ((CaptureItemInterop)wrapper).CreateForWindow(window,ref item,out result);
                return Marshal.GetObjectForIUnknown(result);
            } finally {Release(ref result);Release(ref factory);if(wrapper!=null && Marshal.IsComObject(wrapper)) Marshal.ReleaseComObject(wrapper);if(text!=IntPtr.Zero) WindowsDeleteString(text);}
        }
        static void Run(Source source) {
            IntPtr device=IntPtr.Zero,context=IntPtr.Zero,dxgi=IntPtr.Zero,inspectable=IntPtr.Zero,staging=IntPtr.Zero;
            object rtDevice=null,item=null,pool=null,session=null;bool initialized=false;
            IntPtr old=SetThreadDpiAwarenessContext(new IntPtr(-4));
            try {
                Marshal.ThrowExceptionForHR(RoInitialize(1));initialized=true;
                Type sessionType=WinRT("Windows.Graphics.Capture.GraphicsCaptureSession");
                if(!(bool)sessionType.GetMethod("IsSupported").Invoke(null,null)) throw new NotSupportedException("系统不支持Windows.Graphics.Capture。");
                uint level;
                Marshal.ThrowExceptionForHR(D3D11CreateDevice(IntPtr.Zero,1,IntPtr.Zero,0x20,IntPtr.Zero,0,7,out device,out level,out context));
                Guid dxgiId=new Guid("54ec77fa-1377-44e6-8c32-88fd5f44c84c");
                Marshal.ThrowExceptionForHR(Marshal.QueryInterface(device,ref dxgiId,out dxgi));
                Marshal.ThrowExceptionForHR(CreateDirect3D11DeviceFromDXGIDevice(dxgi,out inspectable));
                rtDevice=Marshal.GetObjectForIUnknown(inspectable);
                item=Item(source.Identity.Window);
                Type itemType=WinRT("Windows.Graphics.Capture.GraphicsCaptureItem"),poolType=WinRT("Windows.Graphics.Capture.Direct3D11CaptureFramePool");
                Type frameType=WinRT("Windows.Graphics.Capture.Direct3D11CaptureFrame"),formatType=WinRT("Windows.Graphics.DirectX.DirectXPixelFormat");
                object format=Enum.ToObject(formatType,87),size=Property(item,itemType,"Size");
                int poolWidth=Dimension(size,"Width"),poolHeight=Dimension(size,"Height");
                var create=poolType.GetMethod("CreateFreeThreaded");
                if(create==null) throw new NotSupportedException("窗口捕获需要Windows 10 1903或更新版本。");
                pool=create.Invoke(null,new object[]{rtDevice,format,2,size});
                session=poolType.GetMethod("CreateCaptureSession").Invoke(pool,new object[]{item});
                var cursor=sessionType.GetProperty("IsCursorCaptureEnabled");if(cursor!=null) cursor.SetValue(session,false,null);
                sessionType.GetMethod("StartCapture").Invoke(session,null);
                var next=poolType.GetMethod("TryGetNextFrame");long identityAt=0;int stagingWidth=0,stagingHeight=0;
                while(!source.Stop) {
                    long now=Now;
                    lock(source.Sync) {if(now-source.RequestedAt>10000) break;}
                    if(now>=identityAt) {
                        if(Resolve(source.Identity.ProcessId,source.Identity.StartTicks,source.Identity.Path)!=source.Identity.Window) throw new InvalidOperationException("窗口捕获句柄已变化。");
                        identityAt=now+1000;
                    }
                    if(IsIconic(source.Identity.Window)) {lock(source.Sync) ClearFrame(source);Thread.Sleep(25);continue;}
                    object frame=next.Invoke(pool,null);
                    if(frame==null) {Thread.Sleep(15);continue;}
                    try {
                        object content=Property(frame,frameType,"ContentSize");
                        int width=Dimension(content,"Width"),height=Dimension(content,"Height");
                        if(width!=poolWidth || height!=poolHeight) {
                            size=Property(item,itemType,"Size");poolWidth=Dimension(size,"Width");poolHeight=Dimension(size,"Height");
                            lock(source.Sync) ClearFrame(source);
                            // Dispose the checked-out frame before recreating its pool.
                            Close(frame);frame=null;
                            poolType.GetMethod("Recreate").Invoke(pool,new object[]{rtDevice,format,2,size});continue;
                        }
                        Rectangle client;Rect bounds;
                        if(!Geometry(source.Identity.Window,out client,out bounds) || width!=bounds.R-bounds.L || height!=bounds.B-bounds.T) continue;
                        TimeSpan stamp=(TimeSpan)Property(frame,frameType,"SystemRelativeTime");
                        long frameAt=(long)stamp.TotalMilliseconds;
                        if(Now-frameAt>FreshMs || frameAt>Now+100) continue;
                        lock(source.Sync) {if(frameAt<source.MinimumFrameAt || frameAt-source.FrameAt<50) continue;}
                        object surface=Property(frame,frameType,"Surface");IntPtr texture=IntPtr.Zero;
                        try {
                            Guid textureId=new Guid("6f15aaf2-d208-4e89-9ab4-489535d34f9c");
                            ((SurfaceAccess)surface).GetInterface(ref textureId,out texture);
                            TextureDesc desc;Slot<GetDesc>(texture,10)(texture,out desc);
                            if(desc.Format!=87 || client.Right>desc.Width || client.Bottom>desc.Height) throw new InvalidOperationException("窗口捕获纹理格式或范围无效。");
                            if(staging==IntPtr.Zero || stagingWidth!=client.Width || stagingHeight!=client.Height) {
                                Release(ref staging);
                                var target=new TextureDesc {Width=(uint)client.Width,Height=(uint)client.Height,MipLevels=1,ArraySize=1,Format=87,SampleCount=1,Usage=3,CpuAccess=0x20000};
                                Marshal.ThrowExceptionForHR(Slot<CreateTexture>(device,5)(device,ref target,IntPtr.Zero,out staging));
                                stagingWidth=client.Width;stagingHeight=client.Height;
                            }
                            var box=new Box {Left=(uint)client.Left,Top=(uint)client.Top,Right=(uint)client.Right,Bottom=(uint)client.Bottom,Back=1};
                            Slot<CopyRegion>(context,46)(context,staging,0,0,0,0,texture,0,ref box);
                            Mapped mapped;Marshal.ThrowExceptionForHR(Slot<MapTexture>(context,14)(context,staging,0,1,0,out mapped));
                            Bitmap copy=null;
                            try {
                                copy=new Bitmap(client.Width,client.Height,PixelFormat.Format32bppArgb);
                                var data=copy.LockBits(new Rectangle(0,0,copy.Width,copy.Height),ImageLockMode.WriteOnly,PixelFormat.Format32bppArgb);
                                bool hasPixels=false;
                                try {
                                    var row=new byte[checked(client.Width*4)];
                                    for(int y=0;y<client.Height;y++) {
                                        Marshal.Copy(IntPtr.Add(mapped.Data,checked((int)(y*mapped.RowPitch))),row,0,row.Length);
                                        Marshal.Copy(row,0,IntPtr.Add(data.Scan0,y*data.Stride),row.Length);
                                        if(!hasPixels) for(int x=0;x<row.Length;x+=4)
                                            if(row[x]>8 || row[x+1]>8 || row[x+2]>8) {hasPixels=true;break;}
                                    }
                                } finally {copy.UnlockBits(data);}
                                if(!hasPixels) continue;
                                Rectangle after;Rect afterBounds;
                                if(!Geometry(source.Identity.Window,out after,out afterBounds) || after!=client || afterBounds.L!=bounds.L || afterBounds.T!=bounds.T || afterBounds.R!=bounds.R || afterBounds.B!=bounds.B) continue;
                                lock(source.Sync) {
                                    if(source.Stop) continue;
                                    ClearFrame(source);source.Frame=copy;copy=null;source.Client=client;source.FrameAt=frameAt;source.WaitingAt=0;
                                }
                            } finally {if(copy!=null) copy.Dispose();Slot<UnmapTexture>(context,15)(context,staging,0);}
                        } finally {Release(ref texture);if(Marshal.IsComObject(surface)) Marshal.ReleaseComObject(surface);}
                    } finally {if(frame!=null) Close(frame);}
                }
            } catch(Exception error) {
                Exception cause=error;while(cause.InnerException!=null) cause=cause.InnerException;
                lock(source.Sync) {source.Error="窗口捕获失败："+cause.Message;ClearFrame(source);}
            } finally {
                // WinRT close can block in the capture service; never close on the GUI/input thread.
                try {Close(session);} catch {}
                try {Close(pool);} catch {}
                try {Close(item);} catch {}
                try {Close(rtDevice);} catch {}
                Release(ref staging);Release(ref inspectable);Release(ref dxgi);Release(ref context);Release(ref device);
                if(initialized) RoUninitialize();if(old!=IntPtr.Zero) SetThreadDpiAwarenessContext(old);
                lock(source.Sync) {source.Worker=null;ClearFrame(source);}
            }
        }
    }
}
