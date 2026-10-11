using System;
using System.Diagnostics;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

namespace WowAuto.Audio
{
    // A rejected template candidate must not consume the session's one signal.
    public sealed class SpikeDetector
    {
        private double baseline;
        private long armedAt;
        private bool fired;
        public double Baseline { get { return baseline; } }
        public void Reset(long now) { baseline = 0; armedAt = now; fired = false; }
        public bool Observe(double peak, long now)
        {
            if (!Probe(peak, now)) return false;
            Accept(); return true;
        }
        public void Accept() { fired = true; }
        public bool Probe(double peak, long now)
        {
            peak = Math.Max(0, Math.Min(1, peak));
            if (now - armedAt < 1000)
            {
                baseline += 0.12 * (peak - baseline);
                return false;
            }
            if (!fired && peak >= 0.06 && peak >= baseline + 0.025 && peak >= baseline * 3)
            {
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

    // Local, immutable fingerprint: 24 logarithmic FFT bands + 8 envelope bins.
    // No dependencies, network, or learned model. Volume is normalized separately.
    public sealed class AudioTemplate
    {
        public const int SampleRate = 11025;
        public const int WindowSamples = 4096;
        public const int PreSamples = 882; // 80 ms before the loudness gate.
        private readonly double[] spectrum, envelope;
        private readonly short[] clip;
        private AudioTemplate(short[] samples)
        {
            clip = SelectEvent(samples);
            Describe(clip, out spectrum, out envelope);
        }
        public short[] Clip { get { return (short[])clip.Clone(); } }
        public static AudioTemplate FromMono(short[] samples, int rate)
        {
            if (samples == null || rate < 8000 || rate > 192000 || samples.Length < rate / 5 || samples.Length > rate * 10)
                throw new InvalidDataException("Use a 0.2-10 second WAV sample (8-192 kHz).");
            short[] mono = Resample(samples, rate);
            if (SpikeDetector.Pcm16Peak(mono) < 0.005) throw new InvalidDataException("Sample is silent or too quiet.");
            return new AudioTemplate(mono);
        }
        private static short[] Resample(short[] source, int rate)
        {
            int length = (int)((long)source.Length * SampleRate / rate);
            short[] result = new short[length];
            // Average the source interval to suppress high-frequency aliasing.
            for (int i = 0; i < length; i++)
            {
                int begin = (int)((long)i * rate / SampleRate);
                int end = Math.Min(source.Length, Math.Max(begin + 1, (int)((long)(i + 1) * rate / SampleRate)));
                long sum = 0; for (int j = begin; j < end; j++) sum += source[j];
                result[i] = (short)(sum / (end - begin));
            }
            return result;
        }
        private static short[] SelectEvent(short[] samples)
        {
            const int hop = 110; // Locate the loudest 10 ms, then its onset.
            int count = (samples.Length + hop - 1) / hop, loudest = 0;
            double[] energy = new double[count];
            for (int i = 0; i < samples.Length; i++) energy[i / hop] += (double)samples[i] * samples[i];
            for (int i = 1; i < count; i++) if (energy[i] > energy[loudest]) loudest = i;
            int onset = loudest;
            while (onset > 0 && loudest - onset < 10 && energy[onset - 1] > energy[loudest] * 0.04) onset--;
            int start = onset * hop - PreSamples;
            short[] result = new short[WindowSamples];
            for (int i = 0; i < result.Length; i++)
                if (start + i >= 0 && start + i < samples.Length) result[i] = samples[start + i];
            return result;
        }
        private static void Normalize(double[] values)
        {
            double length = 0; foreach (double value in values) length += value * value;
            length = Math.Sqrt(length);
            if (length > 0) for (int i = 0; i < values.Length; i++) values[i] /= length;
        }
        private static void Describe(short[] samples, out double[] bands, out double[] shape)
        {
            bands = new double[24]; shape = new double[8];
            const int size = 512;
            double[] real = new double[size], imaginary = new double[size];
            for (int start = 0; start + size <= samples.Length; start += 256)
            {
                for (int i = 0; i < size; i++)
                { real[i] = samples[start + i] / 32768.0 * (0.5 - 0.5 * Math.Cos(2 * Math.PI * i / (size - 1))); imaginary[i] = 0; }
                Fft(real, imaginary);
                for (int i = 1; i < size / 2; i++)
                {
                    double hz = i * SampleRate / (double)size;
                    int band = (int)(Math.Log(hz / 40, 2) / Math.Log(5500.0 / 40, 2) * 24);
                    if (band >= 0 && band < 24) bands[band] += real[i] * real[i] + imaginary[i] * imaginary[i];
                }
            }
            for (int i = 0; i < samples.Length; i++) shape[Math.Min(7, i * 8 / samples.Length)] += (double)samples[i] * samples[i];
            for (int i = 0; i < bands.Length; i++) bands[i] = Math.Sqrt(bands[i]);
            for (int i = 0; i < shape.Length; i++) shape[i] = Math.Sqrt(shape[i]);
            Normalize(bands); Normalize(shape);
        }
        private static void Fft(double[] real, double[] imaginary)
        {
            int n = real.Length;
            for (int i = 1, j = 0; i < n; i++)
            {
                int bit = n >> 1; for (; (j & bit) != 0; bit >>= 1) j ^= bit; j ^= bit;
                if (i < j) { double value = real[i]; real[i] = real[j]; real[j] = value; }
            }
            for (int length = 2; length <= n; length <<= 1)
            {
                double angle = -2 * Math.PI / length, stepR = Math.Cos(angle), stepI = Math.Sin(angle);
                for (int begin = 0; begin < n; begin += length)
                {
                    double wr = 1, wi = 0;
                    for (int j = 0; j < length / 2; j++)
                    {
                        int a = begin + j, b = a + length / 2;
                        double tr = wr * real[b] - wi * imaginary[b], ti = wr * imaginary[b] + wi * real[b];
                        real[b] = real[a] - tr; imaginary[b] = imaginary[a] - ti; real[a] += tr; imaginary[a] += ti;
                        double next = wr * stepR - wi * stepI; wi = wr * stepI + wi * stepR; wr = next;
                    }
                }
            }
        }
        public double Compare(short[] candidate)
        {
            if (candidate == null || candidate.Length < SampleRate / 5) return 0;
            double[] bands, shape; Describe(SelectEvent(candidate), out bands, out shape);
            double frequency = 0, timing = 0;
            for (int i = 0; i < bands.Length; i++) frequency += spectrum[i] * bands[i];
            for (int i = 0; i < shape.Length; i++) timing += envelope[i] * shape[i];
            return Math.Max(0, Math.Min(1, 0.8 * frequency + 0.2 * timing));
        }
        public static AudioTemplate FromWave(string file) { return FromMono(ReadWave(file), SampleRate); }
        public static short[] ReadWave(string file)
        {
            using (BinaryReader reader = new BinaryReader(File.OpenRead(file)))
            {
                if (reader.BaseStream.Length > 8000000 || reader.BaseStream.Length < 44 || new String(reader.ReadChars(4)) != "RIFF")
                    throw new InvalidDataException("Use a PCM16 or float32 RIFF WAV, at most 10 seconds.");
                reader.ReadUInt32(); if (new String(reader.ReadChars(4)) != "WAVE") throw new InvalidDataException("Not a WAV file.");
                int tag = 0, channels = 0, rate = 0, bits = 0, align = 0; byte[] data = null;
                while (reader.BaseStream.Position + 8 <= reader.BaseStream.Length)
                {
                    string id = new String(reader.ReadChars(4)); uint size = reader.ReadUInt32(); long next = reader.BaseStream.Position + size;
                    if (next > reader.BaseStream.Length) throw new InvalidDataException("Truncated WAV chunk.");
                    if (id == "fmt " && size >= 16)
                    {
                        tag = reader.ReadUInt16(); channels = reader.ReadUInt16(); rate = reader.ReadInt32();
                        reader.ReadInt32(); align = reader.ReadUInt16(); bits = reader.ReadUInt16();
                        if (tag == 65534 && size >= 40)
                        { reader.ReadUInt16(); int validBits = reader.ReadUInt16(); reader.ReadUInt32(); tag = reader.ReadUInt16(); if (validBits != bits) tag = 0; }
                    }
                    if (id == "data") { if (data != null) throw new InvalidDataException("Multiple WAV data chunks."); data = reader.ReadBytes((int)size); }
                    reader.BaseStream.Position = next + (size & 1);
                }
                if ((tag != 1 || bits != 16) && (tag != 3 || bits != 32)) throw new InvalidDataException("Only PCM16 / float32 WAV is supported.");
                if (channels < 1 || channels > 2 || rate < 8000 || rate > 192000 || align != channels * bits / 8 || data == null || data.Length % align != 0)
                    throw new InvalidDataException("Invalid WAV format; use mono or stereo, 8-192 kHz.");
                int frames = data.Length / align;
                if (frames < rate / 5 || frames > rate * 10) throw new InvalidDataException("Use a 0.2-10 second WAV sample.");
                short[] mono = new short[frames];
                for (int i = 0; i < frames; i++)
                {
                    double sum = 0;
                    for (int c = 0; c < channels; c++)
                    {
                        int offset = i * align + c * bits / 8;
                        double value = tag == 1 ? BitConverter.ToInt16(data, offset) / 32768.0 : BitConverter.ToSingle(data, offset);
                        if (Double.IsNaN(value) || Double.IsInfinity(value)) throw new InvalidDataException("Non-finite WAV samples.");
                        sum += value;
                    }
                    mono[i] = (short)(Math.Max(-1, Math.Min(32767.0 / 32768, sum / channels)) * 32768);
                }
                return Resample(mono, rate);
            }
        }
        public static void WriteWave(string file, short[] mono)
        {
            using (BinaryWriter writer = new BinaryWriter(File.Create(file)))
            {
                writer.Write(System.Text.Encoding.ASCII.GetBytes("RIFF")); writer.Write(36 + mono.Length * 2);
                writer.Write(System.Text.Encoding.ASCII.GetBytes("WAVEfmt ")); writer.Write(16);
                writer.Write((short)1); writer.Write((short)1); writer.Write(SampleRate); writer.Write(SampleRate * 2);
                writer.Write((short)2); writer.Write((short)16); writer.Write(System.Text.Encoding.ASCII.GetBytes("data"));
                writer.Write(mono.Length * 2); foreach (short sample in mono) writer.Write(sample);
            }
        }
    }

    // FFT work runs only after a spike, once per ~370 ms candidate. A fixed
    // pre-roll ring and bounded candidate prevent unbounded per-PID memory use.
    public sealed class TemplateDetector
    {
        private readonly AudioTemplate template;
        private readonly double threshold;
        private readonly SpikeDetector spike = new SpikeDetector();
        private readonly Queue<short> history = new Queue<short>();
        private List<short> candidate;
        private long retryAt;
        public double LastSimilarity { get; private set; }
        public int Rejected { get; private set; }
        public TemplateDetector(AudioTemplate sample, double minimumSimilarity)
        {
            if (sample == null || minimumSimilarity < 0.5 || minimumSimilarity > 1 || Double.IsNaN(minimumSimilarity))
                throw new ArgumentException("Template and similarity threshold 0.5-1 are required.");
            template = sample; threshold = minimumSimilarity;
        }
        public void Reset(long now)
        { spike.Reset(now); history.Clear(); candidate = null; retryAt = 0; LastSimilarity = 0; Rejected = 0; }
        public bool Feed(short[] mono, double peak, long now)
        {
            if (candidate == null && now >= retryAt && spike.Probe(peak, now)) candidate = new List<short>(history);
            if (candidate != null) candidate.AddRange(mono);
            foreach (short value in mono) { history.Enqueue(value); if (history.Count > AudioTemplate.PreSamples) history.Dequeue(); }
            if (candidate == null || candidate.Count < AudioTemplate.WindowSamples) return false;
            LastSimilarity = template.Compare(candidate.ToArray()); candidate = null;
            if (LastSimilarity >= threshold) { spike.Accept(); return true; }
            Rejected++; retryAt = now + 150; return false;
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
        private readonly TemplateDetector matcher;
        private List<short> recording;
        private short[] recorded;
        private long recordingUntil;
        private int downsampleCount, downsampleSum;
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
        public double Similarity { get { lock (gate) return matcher == null ? 0 : matcher.LastSimilarity; } }
        public int Rejected { get { lock (gate) return matcher == null ? 0 : matcher.Rejected; } }
        public bool Recording { get { lock (gate) return recording != null; } }
        public ProcessCapture(int processId, long expectedStartTicks, string expectedPath)
            : this(processId, expectedStartTicks, expectedPath, null, 0.88) { }
        public ProcessCapture(int processId, long expectedStartTicks, string expectedPath, AudioTemplate template, double threshold)
        {
            if (Native.WindowsBuild() < 20348)
                throw new NotSupportedException("Process audio capture requires Windows build 20348 or later.");
            pid = processId; startTicks = expectedStartTicks; path = expectedPath;
            if (template != null) matcher = new TemplateDetector(template, threshold);
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
                if (matcher != null) matcher.Reset(clock.ElapsedMilliseconds);
            }
        }
        public void StartRecording(int seconds)
        {
            lock (gate)
            {
                if (disposed || status != "Listening" || session != 0) throw new InvalidOperationException("Recording requires a stopped, ready listener.");
                if (seconds < 1 || seconds > 10) throw new ArgumentOutOfRangeException("seconds");
                recorded = null; recording = new List<short>(); recordingUntil = clock.ElapsedMilliseconds + seconds * 1000;
            }
        }
        public short[] TakeRecording()
        {
            lock (gate) { short[] result = recorded; recorded = null; return result; }
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
                recording = null; recorded = null;
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
                    lock (gate)
                        if (recording != null && clock.ElapsedMilliseconds >= recordingUntil)
                        { recorded = recording.ToArray(); recording = null; }
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
                            int count = checked((int)frames * 2);
                            if (samples.Length != count) samples = new short[count];
                            if ((flags & 2) == 0 && frames > 0)
                            {
                                Marshal.Copy(data, samples, 0, count);
                                packetPeak = SpikeDetector.Pcm16Peak(samples);
                            }
                            else Array.Clear(samples, 0, count);
                            lock (gate)
                            {
                                List<short> mono = new List<short>(count / 8 + 1);
                                for (int i = 0; i < count; i += 2)
                                {
                                    downsampleSum += ((int)samples[i] + samples[i + 1]) / 2;
                                    if (++downsampleCount == 4) { mono.Add((short)(downsampleSum / 4)); downsampleCount = 0; downsampleSum = 0; }
                                }
                                if (recording != null)
                                {
                                    int remaining = 10 * AudioTemplate.SampleRate - recording.Count;
                                    if (remaining > 0) recording.AddRange(mono.GetRange(0, Math.Min(remaining, mono.Count)));
                                }
                                peak = packetPeak;
                                bool bite = !disposed && session != 0 && (matcher == null
                                    ? detector.Observe(packetPeak, clock.ElapsedMilliseconds)
                                    : matcher.Feed(mono.ToArray(), packetPeak, clock.ElapsedMilliseconds));
                                if (bite)
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
