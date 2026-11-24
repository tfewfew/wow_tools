using WowAuto.Threading;
using WowAutoFight;
using Capture = WowAutoCapture.Native;
using Rotation = WowAutoRotation.Native;

namespace WowAuto.Desktop;

internal sealed record ActionResult(string Kind, int Pid, bool Executed, long SentAt, string? Error = null);

internal sealed class GameOperator : IDisposable
{
    private readonly Hub hub;
    private readonly Thread thread;
    private readonly Action<ActionResult> report;
    private long clickUntil;
    private string? clickOwner;
    private long fightReadyAt;

    public GameOperator(Hub hub, Action<ActionResult> report)
    {
        this.hub = hub;
        this.report = report;
        NativeInput.WindowPixelReader = Capture.PixelReader;
        Native.FrameReader = Capture.FrameReader;
        Native.CapturePending = Capture.PendingReader;
        Rotation.SizeReader = Capture.SizeReader;
        Rotation.FrameReader = Capture.FrameReader;
        thread = new Thread(Run) { Name = "wowAuto.Operator", IsBackground = true };
        thread.SetApartmentState(ApartmentState.MTA);
        thread.Start();
    }

    public async Task<ActionResult> Submit(Endpoint endpoint, long version, Settings settings, string kind,
        Func<Operation, bool?> action, CancellationToken cancellation, bool foreground = true)
    {
        cancellation.ThrowIfCancellationRequested();
        string domain = kind[..kind.IndexOf('.')];
        QueueTimings timing = Timings(settings.Operations);
        long sentAt = 0;
        var request = hub.Request(endpoint, version, kind, domain, ActionDefaults.Priority(settings, kind), "", timing, operation =>
        {
            if (cancellation.IsCancellationRequested)
                return false;
            if (foreground && !PrepareForeground(operation))
                return null;
            if (!operation.Current)
                return false;
            bool? sent = action(operation);
            sentAt = hub.Now;
            if (sent == true && kind == "Rotation.Click")
            {
                clickOwner = endpoint.Key;
                clickUntil = sentAt + timing.ClickGuardMs;
            }
            if (sent == true && domain == "Fight")
                fightReadyAt = sentAt + timing.CommandIntervalMs;
            return sent;
        });
        var result = await request.Completion.Task.WaitAsync(cancellation);
        return new(kind, endpoint.Pid, result.Executed, sentAt, result.Error);
    }

    public bool Keys(Operation request, Client client, params string[] keys)
    {
        foreach (string key in keys)
        {
            if (key.Length == 0 || !request.Current)
                return false;
            KeyChord binding = KeyChord.Parse(key);
            if (!Native.Press(client, binding.Code, binding.Ctrl, binding.Shift, binding.Alt, request.Timing.KeyPressMs))
                return false;
        }
        return keys.Length != 0;
    }

    public bool Hold(Operation request, Client client, string key, int milliseconds, Func<bool> valid)
    {
        KeyChord binding = KeyChord.Parse(key);
        if (!request.Current || !Native.BeginHold(client, binding.Code, binding.Ctrl, binding.Shift, binding.Alt))
            return false;
        try
        {
            long end = hub.Now + milliseconds;
            while (hub.Now < end)
            {
                if (!request.Current || hub.Paused || !Native.Foreground(client) || !valid())
                    return false;
                Thread.Sleep((int)Math.Clamp(end - hub.Now, 1, Math.Min(request.Timing.WaitCheckMs, 100)));
            }
            return request.Current;
        }
        finally { Native.ReleaseHold(); }
    }

    public bool Wait(Operation request, int milliseconds)
    {
        long end = hub.Now + milliseconds;
        while (hub.Now < end && request.Current && !hub.Paused)
            Thread.Sleep((int)Math.Clamp(end - hub.Now, 1, request.Timing.WaitCheckMs));
        return request.Current && !hub.Paused;
    }

    private bool PrepareForeground(Operation request)
    {
        var owner = request.Owner;
        long now = hub.Now;
        long earliest = clickOwner != owner.Key ? clickUntil : 0;
        if (request.Domain == "Fight")
            earliest = Math.Max(earliest, fightReadyAt);
        if (now < earliest)
        {
            hub.Requeue(request, (int)(earliest - now));
            return false;
        }
        var timing = request.Timing;
        bool rotate = request.Domain == "Rotation";
        if (!NativeInput.IsTargetForeground(owner.Pid, owner.StartTicks, owner.Path))
        {
            if (request.FocusUntil == 0)
                request.FocusUntil = now + (rotate ? timing.RotationFocusTimeoutMs : timing.ForegroundTimeoutMs);
            if (now >= request.FocusUntil)
                throw new InvalidOperationException("操作线程未能在前台保护时间内取得窗口。");
            if (now >= request.NextActivateAt)
            {
                NativeInput.ActivateForScan(owner.Pid, owner.StartTicks, owner.Path);
                request.NextActivateAt = now + (rotate ? timing.RotationFocusRetryMs : timing.ForegroundRetryMs);
            }
            request.ReadyAt = 0;
            hub.Focus = request;
            hub.Requeue(request, timing.WaitCheckMs);
            return false;
        }
        if (request.ReadyAt == 0)
            request.ReadyAt = now + timing.ForegroundSettleMs;
        if (request.ReadyAt > now)
        {
            hub.Focus = request;
            hub.Requeue(request, (int)(request.ReadyAt - now));
            return false;
        }
        return true;
    }

    public static QueueTimings Timings(OperationSettings settings)
    {
        var timings = new QueueTimings();
        foreach (var field in typeof(QueueTimings).GetFields())
            field.SetValue(timings, typeof(OperationSettings).GetProperty(field.Name)!.GetValue(settings));
        return timings;
    }

    private void Run()
    {
        hub.BindOperator();
        try
        {
            while (!hub.Closing)
            {
                Operation? request = hub.NextOperation();
                if (request is null)
                {
                    hub.Wake.WaitOne(hub.Timing.OperatorIdleMs);
                    continue;
                }
                try
                {
                    bool? sent = request.Current ? request.Handler(request) : false;
                    if (sent is null)
                        continue;
                    var result = new ActionResult(request.Kind, request.Owner.Pid, sent.Value, hub.Now);
                    request.Complete(true, sent.Value, null, null);
                    report(result);
                }
                catch (Exception error) when (Capture.IsPending(error) && request.Current)
                {
                    hub.Requeue(request, request.Timing.CaptureRetryMs);
                }
                catch (Exception error)
                {
                    request.Complete(false, false, null, error.Message);
                    report(new(request.Kind, request.Owner.Pid, false, hub.Now, error.Message));
                }
                finally
                {
                    if (request.Completion.Task.IsCompleted && ReferenceEquals(hub.Focus, request))
                        hub.Focus = null;
                    hub.FinishOperation();
                }
            }
        }
        finally { Native.ReleaseHold(); }
    }

    public void Dispose()
    {
        hub.Close();
        if (!thread.Join(TimeSpan.FromSeconds(15)))
            throw new InvalidOperationException("操作线程尚未退出。");
        Capture.Shutdown();
    }
}
