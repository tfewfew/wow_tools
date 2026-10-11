using System;
using System.Diagnostics;
using System.Collections.Generic;
using System.IO;
using System.Globalization;
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

    // Local, immutable fingerprint: spectrum, time-resolved spectrum and envelope.
    // No dependencies, network, or learned model. Volume is normalized separately.
    public sealed class AudioTemplate
    {
        public const int SampleRate = 11025;
        public const int WindowSamples = 11025; // One second, including an 80 ms lead-in.
        public const int PreSamples = 2205; // 200 ms before the loudness gate.
        public const int CandidateSamples = WindowSamples + PreSamples;
        public const int MaximumCandidateSamples = WindowSamples + SampleRate * 3 / 5;
        private const int SpectrumBands = 24, TimeSlices = 8, EnvelopeBins = 16;
        private const int TemporalValues = SpectrumBands * TimeSlices;
        private const int FeatureValues = SpectrumBands + TemporalValues + EnvelopeBins;
        private readonly double[][] spectra, temporalSpectra, envelopes;
        public double MinimumSimilarity { get; private set; }
        public bool IsTrial { get; private set; }
        public int Count { get { return spectra.Length; } }
        private AudioTemplate(short[] samples)
        {
            short[] selected = SelectEvent(samples);
            if (selected == null) throw new InvalidDataException("Provide the first sound within 600 ms and enough leading/trailing audio for a complete one-second fingerprint.");
            double[] spectrum, temporal, envelope;
            Describe(selected, 0, out spectrum, out temporal, out envelope);
            spectra = new double[][] { spectrum }; temporalSpectra = new double[][] { temporal }; envelopes = new double[][] { envelope };
            MinimumSimilarity = 0.86;
            IsTrial = true;
        }
        private AudioTemplate(double[][] frequencies, double[][] temporal, double[][] shapes, double threshold, bool trial)
        { spectra = frequencies; temporalSpectra = temporal; envelopes = shapes; MinimumSimilarity = threshold; IsTrial = trial; }
        public static AudioTemplate LoadFeatures(string path)
        {
            if (new FileInfo(path).Length > 65536) throw new InvalidDataException("Feature file is too large.");
            Dictionary<string, string> headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            List<double[]> frequencies = new List<double[]>(), temporal = new List<double[]>(), shapes = new List<double[]>();
            HashSet<string> knownHeaders = new HashSet<string>(new string[] { "Format", "SampleRate", "WindowSamples", "SpectrumBands", "TimeSlices", "EnvelopeBins", "Threshold", "Status" }, StringComparer.OrdinalIgnoreCase);
            foreach (string source in File.ReadAllLines(path))
            {
                string line = source.Trim(); if (line.Length == 0 || line.StartsWith("#")) continue;
                int separator = line.IndexOf('='); if (separator < 1) throw new InvalidDataException("Invalid feature row.");
                string key = line.Substring(0, separator).Trim(), value = line.Substring(separator + 1).Trim();
                if (String.Equals(key, "Template", StringComparison.OrdinalIgnoreCase))
                {
                    if (frequencies.Count >= 8) throw new InvalidDataException("At most 8 bite feature variants.");
                    string[] values = value.Split(','); if (values.Length != FeatureValues) throw new InvalidDataException("232 feature values required for format 2.");
                    double[] bands = new double[SpectrumBands], timed = new double[TemporalValues], envelope = new double[EnvelopeBins];
                    for (int i = 0; i < values.Length; i++)
                    {
                        double number;
                        if (!Double.TryParse(values[i], NumberStyles.Float, CultureInfo.InvariantCulture, out number) ||
                            Double.IsNaN(number) || Double.IsInfinity(number) || number < 0 || number > 1)
                            throw new InvalidDataException("Feature values must be finite, normalized numbers.");
                        if (i < SpectrumBands) bands[i] = number;
                        else if (i < SpectrumBands + TemporalValues) timed[i - SpectrumBands] = number;
                        else envelope[i - SpectrumBands - TemporalValues] = number;
                    }
                    CheckNormalized(bands); CheckNormalized(timed); CheckNormalized(envelope);
                    frequencies.Add(bands); temporal.Add(timed); shapes.Add(envelope);
                }
                else
                {
                    if (!knownHeaders.Contains(key))
                        throw new InvalidDataException("Unknown feature header.");
                    if (headers.ContainsKey(key)) throw new InvalidDataException("Duplicate feature header.");
                    headers.Add(key, value);
                }
            }
            double threshold;
            if (!headers.ContainsKey("Format") || !headers.ContainsKey("SampleRate") || !headers.ContainsKey("WindowSamples") || !headers.ContainsKey("Threshold") ||
                headers["Format"] != "2" || headers["SampleRate"] != "11025" || headers["WindowSamples"] != "11025" ||
                !headers.ContainsKey("SpectrumBands") || headers["SpectrumBands"] != "24" ||
                !headers.ContainsKey("TimeSlices") || headers["TimeSlices"] != "8" ||
                !headers.ContainsKey("EnvelopeBins") || headers["EnvelopeBins"] != "16" ||
                !Double.TryParse(headers["Threshold"], NumberStyles.Float, CultureInfo.InvariantCulture, out threshold) ||
                Double.IsNaN(threshold) || threshold < 0.5 || threshold > 1 || frequencies.Count == 0)
                throw new InvalidDataException("Missing/unsupported feature format or threshold.");
            string reviewStatus;
            if (!headers.TryGetValue("Status", out reviewStatus)) reviewStatus = "trial";
            if (reviewStatus != "trial" && reviewStatus != "verified") throw new InvalidDataException("Feature status must be trial or verified.");
            return new AudioTemplate(frequencies.ToArray(), temporal.ToArray(), shapes.ToArray(), threshold, reviewStatus == "trial");
        }
        private static void CheckNormalized(double[] values)
        {
            double norm = 0; foreach (double value in values) norm += value * value;
            if (Math.Abs(norm - 1) > 0.001) throw new InvalidDataException("Feature vector is not normalized.");
        }
        // Offline preparation/tests use numerical features; no WAV recording or
        // media-file import/export is exposed by the runtime tool.
        public static void SaveFeatures(string path, AudioTemplate[] templates, double threshold)
        {
            if (templates == null || templates.Length < 1 || templates.Length > 8 || Double.IsNaN(threshold) || threshold < 0.5 || threshold > 1)
                throw new ArgumentException("1-8 templates and a threshold 0.5-1 are required.");
            List<string> lines = new List<string> { "# wowAuto bite fingerprints; no recorded audio", "Format=2", "SampleRate=11025", "WindowSamples=11025", "SpectrumBands=24", "TimeSlices=8", "EnvelopeBins=16", "Status=trial",
                "Threshold=" + threshold.ToString("R", CultureInfo.InvariantCulture) };
            foreach (AudioTemplate template in templates)
            {
                if (template == null || template.Count != 1) throw new ArgumentException("Export individual calibrated samples.");
                string[] values = new string[FeatureValues];
                for (int i = 0; i < SpectrumBands; i++) values[i] = template.spectra[0][i].ToString("R", CultureInfo.InvariantCulture);
                for (int i = 0; i < TemporalValues; i++) values[i + SpectrumBands] = template.temporalSpectra[0][i].ToString("R", CultureInfo.InvariantCulture);
                for (int i = 0; i < EnvelopeBins; i++) values[i + SpectrumBands + TemporalValues] = template.envelopes[0][i].ToString("R", CultureInfo.InvariantCulture);
                lines.Add("Template=" + String.Join(",", values));
            }
            File.WriteAllLines(path, lines);
        }
        public static AudioTemplate FromMono(short[] samples, int rate)
        {
            if (samples == null || rate < 8000 || rate > 192000 || samples.Length < rate * 6 / 5 || samples.Length > rate * 10)
                throw new InvalidDataException("Use a 1.2-10 second mono sample (8-192 kHz).");
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
        private static int FindEventStart(short[] samples)
        {
            const int hop = 110;
            // Anchor the first burst, not a louder unrelated sound later in the clip.
            // Both offline samples and live candidates must retain the complete tail.
            int count = (Math.Min(samples.Length, SampleRate * 3 / 5) + hop - 1) / hop, loudest = 0;
            if (count == 0) return -1;
            double[] energy = new double[count];
            for (int i = 0; i < Math.Min(samples.Length, count * hop); i++) energy[i / hop] += (double)samples[i] * samples[i];
            for (int i = 1; i < count; i++) if (energy[i] > energy[loudest]) loudest = i;
            int onset = loudest;
            if (energy[loudest] == 0) return -1;
            while (onset > 0 && loudest - onset < 30 && energy[onset - 1] > energy[loudest] * 0.04) onset--;
            return onset * hop - 882; // 80 ms before the energy onset.
        }
        internal static int RequiredCandidateSamples(short[] samples)
        {
            int start = FindEventStart(samples);
            return start < 0 ? 0 : start + WindowSamples;
        }
        private static short[] SelectEvent(short[] samples)
        {
            int start = FindEventStart(samples);
            if (start < 0 || start + WindowSamples > samples.Length) return null;
            short[] result = new short[WindowSamples];
            Array.Copy(samples, start, result, 0, result.Length);
            return result;
        }
        private static void Normalize(double[] values)
        {
            double length = 0; foreach (double value in values) length += value * value;
            length = Math.Sqrt(length);
            if (length > 0) for (int i = 0; i < values.Length; i++) values[i] /= length;
        }
        private static void Describe(short[] samples, int shift, out double[] bands, out double[] temporal, out double[] shape)
        {
            bands = new double[SpectrumBands]; temporal = new double[TemporalValues]; shape = new double[EnvelopeBins];
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
                    int band = (int)(Math.Log(hz / 40, 2) / Math.Log(5500.0 / 40, 2) * SpectrumBands);
                    if (band >= 0 && band < SpectrumBands)
                    {
                        double power = real[i] * real[i] + imaginary[i] * imaginary[i];
                        bands[band] += power;
                        int slice = Math.Max(0, Math.Min(TimeSlices - 1, (start + size / 2 + shift) * TimeSlices / samples.Length));
                        temporal[slice * SpectrumBands + band] += power;
                    }
                }
            }
            for (int i = 0; i < samples.Length; i++) shape[Math.Max(0, Math.Min(EnvelopeBins - 1, (i + shift) * EnvelopeBins / samples.Length))] += (double)samples[i] * samples[i];
            for (int i = 0; i < bands.Length; i++) bands[i] = Math.Sqrt(bands[i]);
            for (int i = 0; i < temporal.Length; i++) temporal[i] = Math.Sqrt(temporal[i]);
            for (int i = 0; i < shape.Length; i++) shape[i] = Math.Sqrt(shape[i]);
            Normalize(bands); Normalize(temporal); Normalize(shape);
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
            if (candidate == null || candidate.Length < WindowSamples) return 0;
            short[] selected = SelectEvent(candidate); if (selected == null) return 0;
            double best = 0;
            // One FFT-hop tolerance handles packet phase without erasing time order.
            for (int shift = -256; shift <= 256; shift += 256)
            {
                double[] bands, temporal, shape; Describe(selected, shift, out bands, out temporal, out shape);
                for (int variant = 0; variant < Count; variant++)
                {
                    double frequency = 0, sequence = 0, timing = 0;
                    for (int i = 0; i < bands.Length; i++) frequency += spectra[variant][i] * bands[i];
                    for (int i = 0; i < temporal.Length; i++) sequence += temporalSpectra[variant][i] * temporal[i];
                    for (int i = 0; i < shape.Length; i++) timing += envelopes[variant][i] * shape[i];
                    best = Math.Max(best, 0.35 * frequency + 0.5 * sequence + 0.15 * timing);
                }
            }
            return Math.Max(0, Math.Min(1, best));
        }
    }

    // FFT work runs only after a spike, after ~1-1.4 s of following audio. A fixed
    // pre-roll ring and bounded candidate prevent unbounded per-PID memory use.
    public sealed class TemplateDetector
    {
        private readonly AudioTemplate template;
        private double threshold;
        private readonly SpikeDetector spike = new SpikeDetector();
        private readonly Queue<short> history = new Queue<short>();
        private List<short> candidate;
        private int candidateTarget;
        private long retryAt;
        public double LastSimilarity { get; private set; }
        public int Rejected { get; private set; }
        public double MinimumSimilarity { get { return threshold; } }
        public TemplateDetector(AudioTemplate sample, double minimumSimilarity)
        {
            if (sample == null || minimumSimilarity < 0.5 || minimumSimilarity > 1 || Double.IsNaN(minimumSimilarity))
                throw new ArgumentException("Template and similarity threshold 0.5-1 are required.");
            template = sample; threshold = minimumSimilarity;
        }
        public void SetMinimumSimilarity(double value)
        {
            if (Double.IsNaN(value) || value < 0.5 || value > 1) throw new ArgumentOutOfRangeException("value");
            // Preserve the candidate, warmup, and once-per-session signal state.
            threshold = value;
        }
        public void Reset(long now)
        { spike.Reset(now); history.Clear(); candidate = null; candidateTarget = 0; retryAt = 0; LastSimilarity = 0; Rejected = 0; }
        public bool Feed(short[] mono, double peak, long now)
        {
            if (candidate == null && now >= retryAt && spike.Probe(peak, now))
            { candidate = new List<short>(history); candidateTarget = AudioTemplate.CandidateSamples; }
            if (candidate != null) candidate.AddRange(mono);
            foreach (short value in mono) { history.Enqueue(value); if (history.Count > AudioTemplate.PreSamples) history.Dequeue(); }
            if (candidate == null || candidate.Count < candidateTarget) return false;
            // The first 600 ms anchor is now fixed. A late rise can need more tail
            // than the minimum capture; keep those frames instead of rejecting it.
            short[] frames = candidate.ToArray();
            int needed = AudioTemplate.RequiredCandidateSamples(frames);
            if (needed > candidate.Count && needed <= AudioTemplate.MaximumCandidateSamples)
            { candidateTarget = needed; return false; }
            LastSimilarity = template.Compare(frames); candidate = null;
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
        private TemplateDetector matcher;
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
        public void SetMinimumSimilarity(double value)
        {
            if (Double.IsNaN(value) || value < 0.5 || value > 1) throw new ArgumentOutOfRangeException("value");
            lock (gate) { if (!disposed && matcher != null) matcher.SetMinimumSimilarity(value); }
        }
        // The controller switches recordings only between fishing sessions.
        // Do not discard a candidate or a pending bite from the current round.
        public void SetTemplate(AudioTemplate template, double threshold)
        {
            if (template == null) throw new ArgumentNullException("template");
            if (Double.IsNaN(threshold) || threshold < 0.5 || threshold > 1) throw new ArgumentOutOfRangeException("threshold");
            lock (gate)
            {
                if (disposed) return;
                if (session != 0) throw new InvalidOperationException("Disarm capture before switching recordings.");
                matcher = new TemplateDetector(template, threshold);
                matcher.Reset(clock.ElapsedMilliseconds);
                pendingBite = 0;
            }
        }
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
