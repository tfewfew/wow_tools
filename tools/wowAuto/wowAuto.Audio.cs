using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

namespace WowAuto.Audio
{
    // Detect a transient over a quiet, adaptive baseline. This is a loudness
    // detector, not identification of a particular sound or of its in-game owner.
    public sealed class SpikeDetector
    {
        private double baseline;
        private long armedAt;
        private bool fired;
        public double Baseline { get { return baseline; } }
        public void Reset(long now) { baseline = 0; armedAt = now; fired = false; }
        public bool Observe(double peak, long now)
        {
            peak = Math.Max(0, Math.Min(1, peak));
            if (now - armedAt < 1000)
            {
                baseline += 0.12 * (peak - baseline);
                return false;
            }
            if (!fired && peak >= 0.06 && peak >= baseline + 0.025 && peak >= baseline * 3)
            {
                fired = true;
                return true;
            }
            if (!fired) baseline += 0.04 * (peak - baseline);
            return false;
        }
        public static double Pcm16Peak(short[] samples)
        {
            double peak = 0;
            foreach (short sample in samples) peak = Math.Max(peak, Math.Abs((double)sample) / 32768.0);
            return peak;
        }
    }

    // Only VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK is used. Never fall back to
    // capturing a playback endpoint or the system-wide audio mix.
    public sealed class ProcessCapture : IDisposable
    {
        private readonly int pid;
        private readonly long startTicks;
        private readonly string path;
        private readonly object gate = new object();
        private readonly ManualResetEvent stop = new ManualResetEvent(false);
        private readonly Stopwatch clock = Stopwatch.StartNew();
        private readonly SpikeDetector detector = new SpikeDetector();
        private readonly Thread thread;
        private string status = "Starting";
        private string error = "";
        private long session;
        private long pendingBite;
        private bool disposed;
        private double peak;
        public string Status { get { lock (gate) return status; } }
        public string Error { get { lock (gate) return error; } }
        public double Peak { get { lock (gate) return peak; } }
        public ProcessCapture(int processId, long expectedStartTicks, string expectedPath)
        {
            if (Native.WindowsBuild() < 20348)
                throw new NotSupportedException("Process audio capture requires Windows build 20348 or later.");
            pid = processId; startTicks = expectedStartTicks; path = expectedPath;
            CheckIdentity();
            thread = new Thread(Run);
            thread.IsBackground = true;
            thread.Name = "wowAuto audio PID " + pid;
            thread.SetApartmentState(ApartmentState.MTA);
            thread.Start();
        }
        public void Arm(long fishingSession)
        {
            lock (gate)
            {
                if (disposed) return;
                if (session == fishingSession) return;
                session = fishingSession; pendingBite = 0;
                detector.Reset(clock.ElapsedMilliseconds);
            }
        }
        public bool TryTakeBite(out long fishingSession)
        {
            lock (gate)
            {
                fishingSession = pendingBite; pendingBite = 0;
                return fishingSession != 0;
            }
        }
        public void Dispose()
        {
            lock (gate)
            {
                if (disposed) return;
                disposed = true; session = 0; pendingBite = 0;
                stop.Set();
            }
            // Cleanup runs on the capture thread. Do not block the GUI or its holds.
        }
        private void CheckIdentity()
        {
            using (Process process = Process.GetProcessById(pid))
            {
                if (process.HasExited || process.StartTime.Ticks != startTicks ||
                    !String.Equals(process.MainModule.FileName, path, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Target process exited or its identity changed.");
            }
        }
        private void Run()
        {
            IAudioClient client = null;
            IAudioCaptureClient capture = null;
            AutoResetEvent ready = null;
            bool comInitialized = false;
            try
            {
                Native.Check(Native.CoInitializeEx(IntPtr.Zero, 0)); comInitialized = true;
                CheckIdentity();
                client = Native.Activate(pid, stop);
                if (stop.WaitOne(0)) return;
                WaveFormat format = new WaveFormat { Tag = 1, Channels = 2, SamplesPerSecond = 44100,
                    BitsPerSample = 16, BlockAlign = 4, AverageBytesPerSecond = 176400 };
                Native.Check(client.Initialize(0, 0x80060000u, 0, 0, ref format, IntPtr.Zero));
                object service;
                Guid captureGuid = typeof(IAudioCaptureClient).GUID;
                Native.Check(client.GetService(ref captureGuid, out service));
                capture = (IAudioCaptureClient)service;
                ready = new AutoResetEvent(false);
                Native.Check(client.SetEventHandle(ready.SafeWaitHandle.DangerousGetHandle()));
                Native.Check(client.Start());
                lock (gate) status = "Listening";
                long checkedAt = 0;
                short[] samples = new short[0];
                WaitHandle[] waits = { stop, ready };
                while (WaitHandle.WaitAny(waits, 100) != 0)
                {
                    if (clock.ElapsedMilliseconds - checkedAt >= 1000)
                    { CheckIdentity(); checkedAt = clock.ElapsedMilliseconds; }
                    uint available;
                    Native.Check(capture.GetNextPacketSize(out available));
                    while (available > 0)
                    {
                        IntPtr data;
                        uint frames, flags;
                        ulong devicePosition, qpcPosition;
                        Native.Check(capture.GetBuffer(out data, out frames, out flags, out devicePosition, out qpcPosition));
                        try
                        {
                            double packetPeak = 0;
                            if ((flags & 2) == 0 && frames > 0)
                            {
                                int count = checked((int)frames * 2);
                                if (samples.Length != count) samples = new short[count];
                                Marshal.Copy(data, samples, 0, count);
                                packetPeak = SpikeDetector.Pcm16Peak(samples);
                            }
                            lock (gate)
                            {
                                peak = packetPeak;
                                if (!disposed && session != 0 && detector.Observe(packetPeak, clock.ElapsedMilliseconds))
                                    pendingBite = session;
                            }
                        }
                        finally { Native.Check(capture.ReleaseBuffer(frames)); }
                        Native.Check(capture.GetNextPacketSize(out available));
                        if (stop.WaitOne(0)) break;
                    }
                }
            }
            catch (Exception ex) { lock (gate) { status = "Error"; error = ex.Message; } }
            finally
            {
                if (client != null) { try { client.Stop(); } catch { } }
                Native.Release(capture); Native.Release(client);
                if (ready != null) ready.Dispose();
                if (comInitialized) Native.CoUninitialize();
                lock (gate) { disposed = true; if (status != "Error") status = "Stopped"; stop.Dispose(); }
            }
        }
    }

    [StructLayout(LayoutKind.Sequential, Pack = 2)]
    internal struct WaveFormat
    {
        public ushort Tag, Channels;
        public uint SamplesPerSecond, AverageBytesPerSecond;
        public ushort BlockAlign, BitsPerSample, ExtraSize;
    }
    [ComImport, Guid("1CB9AD4C-DBFA-4C32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioClient
    {
        [PreserveSig] int Initialize(int mode, uint flags, long duration, long period, ref WaveFormat format, IntPtr session);
        [PreserveSig] int GetBufferSize(out uint frames);
        [PreserveSig] int GetStreamLatency(out long latency);
        [PreserveSig] int GetCurrentPadding(out uint frames);
        [PreserveSig] int IsFormatSupported(int mode, ref WaveFormat format, out IntPtr closest);
        [PreserveSig] int GetMixFormat(out IntPtr format);
        [PreserveSig] int GetDevicePeriod(out long normal, out long minimum);
        [PreserveSig] int Start();
        [PreserveSig] int Stop();
        [PreserveSig] int Reset();
        [PreserveSig] int SetEventHandle(IntPtr handle);
        [PreserveSig] int GetService(ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object service);
    }
    [ComImport, Guid("C8ADBD64-E71E-48A0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioCaptureClient
    {
        [PreserveSig] int GetBuffer(out IntPtr data, out uint frames, out uint flags, out ulong devicePosition, out ulong qpcPosition);
        [PreserveSig] int ReleaseBuffer(uint frames);
        [PreserveSig] int GetNextPacketSize(out uint frames);
    }
    [ComImport, Guid("72A22D78-CDE4-431D-B8CC-843A71199B6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IActivationOperation
    {
        [PreserveSig] int GetActivateResult(out int result, [MarshalAs(UnmanagedType.IUnknown)] out object activated);
    }
    [ComVisible(true), Guid("41D949AB-9862-444A-80F6-C261334DA5EB"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IActivationCompletion
    {
        [PreserveSig] int ActivateCompleted(IActivationOperation operation);
    }
    [ComVisible(true), Guid("94EA2B94-E9CC-49E0-C0FF-EE64CA8F5B90"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAgileObject { }

    [ComVisible(true), ClassInterface(ClassInterfaceType.None)]
    public sealed class Activation : IActivationCompletion, IAgileObject
    {
        internal readonly ManualResetEvent Done = new ManualResetEvent(false);
        private readonly object gate = new object();
        private bool completed, abandoned;
        private object client;
        private int result;
        internal IntPtr Parameters;
        public int ActivateCompleted(IActivationOperation operation)
        {
            lock (gate)
            {
                try
                {
                    Native.Check(operation.GetActivateResult(out result, out client));
                    if (abandoned) { Native.Release(client); client = null; }
                }
                catch (Exception ex) { result = Marshal.GetHRForException(ex); }
                finally
                {
                    if (Parameters != IntPtr.Zero) { Marshal.FreeHGlobal(Parameters); Parameters = IntPtr.Zero; }
                    completed = true;
                    if (abandoned) Done.Dispose(); else Done.Set();
                }
            }
            return 0;
        }
        internal IAudioClient TakeClient()
        {
            lock (gate)
            {
                Native.Check(result);
                IAudioClient value = (IAudioClient)client; client = null;
                return value;
            }
        }
        internal void Abandon()
        {
            lock (gate)
            {
                abandoned = true;
                Native.Release(client); client = null;
                if (completed) Done.Dispose();
                // A late callback still owns its parameters and event.
            }
        }
        internal void FailedBeforeCallback()
        {
            lock (gate)
            {
                if (Parameters != IntPtr.Zero) { Marshal.FreeHGlobal(Parameters); Parameters = IntPtr.Zero; }
                completed = true;
            }
        }
    }
    internal static class Native
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct PropVariant { public ushort Vt, R1, R2, R3; public uint Size; public IntPtr Data; }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct OsVersion
        {
            public int Size, Major, Minor, Build, Platform;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string ServicePack;
        }
        [DllImport("ntdll.dll", CharSet = CharSet.Unicode)] private static extern int RtlGetVersion(ref OsVersion version);
        [DllImport("ole32.dll")] internal static extern int CoInitializeEx(IntPtr reserved, uint mode);
        [DllImport("ole32.dll")] internal static extern void CoUninitialize();
        [DllImport("Mmdevapi.dll", CharSet = CharSet.Unicode)]
        private static extern int ActivateAudioInterfaceAsync(string device, ref Guid iid, ref PropVariant parameters,
            IActivationCompletion callback, out IActivationOperation operation);
        internal static int WindowsBuild()
        {
            OsVersion version = new OsVersion(); version.Size = Marshal.SizeOf(typeof(OsVersion));
            Check(RtlGetVersion(ref version)); return version.Build;
        }
        internal static void Check(int hr) { if (hr < 0) Marshal.ThrowExceptionForHR(hr); }
        internal static void Release(object value) { if (value != null && Marshal.IsComObject(value)) Marshal.ReleaseComObject(value); }
        internal static IAudioClient Activate(int pid, WaitHandle stop)
        {
            Activation callback = new Activation();
            callback.Parameters = Marshal.AllocHGlobal(12);
            Marshal.WriteInt32(callback.Parameters, 0, 1); // PROCESS_LOOPBACK
            Marshal.WriteInt32(callback.Parameters, 4, pid);
            Marshal.WriteInt32(callback.Parameters, 8, 0); // INCLUDE_TARGET_PROCESS_TREE
            PropVariant parameters = new PropVariant { Vt = 65, Size = 12, Data = callback.Parameters };
            IActivationOperation operation = null;
            bool called = false;
            try
            {
                Guid iid = typeof(IAudioClient).GUID;
                Check(ActivateAudioInterfaceAsync("VAD\\Process_Loopback", ref iid, ref parameters, callback, out operation));
                called = true;
                int signal = WaitHandle.WaitAny(new WaitHandle[] { stop, callback.Done }, 10000);
                if (signal == 0) throw new OperationCanceledException("Audio capture stopped.");
                if (signal == WaitHandle.WaitTimeout) throw new TimeoutException("Process audio activation timed out.");
                return callback.TakeClient();
            }
            finally
            {
                if (!called) callback.FailedBeforeCallback();
                callback.Abandon();
                Release(operation);
            }
        }
    }
}
