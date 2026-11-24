using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text.Json;
using System.Threading.Channels;
using WowAuto.Protocol;
using WowAuto.Threading;
using WowAutoFight;

namespace WowAuto.Desktop;

internal sealed record RuntimeView(Guid InstanceId, DateTimeOffset StartedAt, long Now, long ConfigRevision,
    bool Paused, bool ShuttingDownGames, long? ShutdownAt, long? ShutdownRemainingMs, string? RotationBatch,
    object? CharacterCreate, object? Desktop, ProcessView[] Processes, object[] PendingActions, ActionResult[] RecentActions, string? LogError);

internal readonly record struct DesktopView(long Now, bool ShuttingDownGames, long? ShutdownAt, long? ShutdownRemainingMs,
    CreationView Creation, ProcessView[] Processes, string? LogError);

internal sealed class Automation : IAsyncDisposable
{
    private readonly object gate = new();
    private readonly SemaphoreSlim mutations = new(1, 1);
    private readonly ConcurrentDictionary<int, GameRow> rows = new();
    private readonly ConcurrentDictionary<Guid, Channel<byte>> watchers = new();
    private readonly ConcurrentQueue<ActionResult> completed = new();
    private readonly List<(Endpoint Endpoint, TaskCompletionSource<RotationBatch> Promise)> rotationWaiters = [];
    private readonly CancellationTokenSource lifetime = new();
    private readonly SettingsStore config;
    private readonly Task idleMonitor;
    private CancellationTokenSource? countdown;
    private long shutdownAt;
    private volatile bool shuttingDown;
    private bool formingBatch;
    private volatile bool closing;
    private long lastInfo;
    private readonly DateTimeOffset startedAt = DateTimeOffset.Now;

    public Guid InstanceId { get; } = Guid.NewGuid();
    public Hub Hub { get; }
    public GameOperator Operator { get; }
    public CharacterCreator Creator { get; }
    public Configuration Config => config.Current;
    public GameRow[] Rows => rows.Values.OrderBy(item => item.Client.ProcessId).ToArray();
    public CancellationToken Token => lifetime.Token;
    public Func<Settings, Action<bool>?>? PrepareSettings { get; set; }
    public Func<object>? DesktopState { get; set; }

    public Automation(string directory)
    {
        config = new SettingsStore(directory);
        Hub = new Hub(Path.Combine(directory, "log"), Config.Effective.LogMaxSizeMB);
        Hub.ConfigureTiming(GameOperator.Timings(Config.Effective.Operations));
        Operator = new GameOperator(Hub, RecordAction);
        Creator = new CharacterCreator(this);
        RefreshRows();
        idleMonitor = Task.Run(IdleMonitor);
    }

    public static string AudioPath(string flavor, int id) => Path.Combine(AppContext.BaseDirectory, "AudioFeatures",
        flavor == "titan" ? $"titan-{id:D2}.feature" : "forerver.feature");

    public RuntimeView Snapshot(int? pid = null)
    {
        long now = Hub.Now, due = Interlocked.Read(ref shutdownAt);
        return new(InstanceId, startedAt, now, Config.Revision, Hub.Paused, shuttingDown, due > 0 ? due : null,
            due > 0 ? Math.Max(0, due - now) : null, Hub.Batch is { } batch && !batch.All(8) ? batch.Id : null,
            Creator.View, DesktopState?.Invoke(), ProcessViews(pid), Hub.OperationSnapshots(),
            completed.Where(action => pid is null || action.Pid == pid).ToArray(), Hub.Logger.LastError);
    }

    public DesktopView DesktopSnapshot()
    {
        long now = Hub.Now, due = Interlocked.Read(ref shutdownAt);
        return new(now, shuttingDown, due > 0 ? due : null, due > 0 ? Math.Max(0, due - now) : null,
            Creator.View, ProcessViews(null), Hub.Logger.LastError);
    }

    private ProcessView[] ProcessViews(int? pid) => Rows.Where(row => pid is null || row.Client.ProcessId == pid)
        .Select(row => Volatile.Read(ref row.View)).ToArray();

    public void Changed()
    {
        foreach (Channel<byte> channel in watchers.Values)
            channel.Writer.TryWrite(0);
    }

    public async IAsyncEnumerable<RuntimeView> Watch(int? pid, [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellation)
    {
        var id = Guid.NewGuid();
        var channel = Channel.CreateBounded<byte>(new BoundedChannelOptions(1) { FullMode = BoundedChannelFullMode.DropOldest });
        watchers[id] = channel;
        try
        {
            yield return Snapshot(pid);
            await foreach (byte _ in channel.Reader.ReadAllAsync(cancellation))
                yield return Snapshot(pid);
        }
        finally { watchers.TryRemove(id, out _); }
    }

    public void Log(int? pid, string type, string message) => Hub.Logger.Log(pid, type, message);

    private void RecordAction(ActionResult action)
    {
        completed.Enqueue(action);
        while (completed.Count > Math.Min(100, Config.Effective.StatusLogLimit))
            completed.TryDequeue(out _);
        Log(action.Pid, action.Error is null ? "action" : "error", $"{action.Kind} / {action.Executed} {action.Error}");
        Changed();
    }

    public Configuration Configure(IReadOnlyList<SettingChange> changes, bool runtime, long? expected)
    {
        if (closing)
            throw new InvalidOperationException("程序正在关闭。");
        Configuration updated = config.Update(changes, runtime, expected, PrepareSettings);
        Hub.ConfigureTiming(GameOperator.Timings(updated.Effective.Operations));
        Hub.LogMaxSizeMB = updated.Effective.LogMaxSizeMB;
        foreach (var row in Rows)
            row.Session?.Wake();
        Log(null, "config", $"配置版本 {updated.Revision}。");
        Changed();
        return updated;
    }

    public GameRow[] Select(int? pid, bool all, long? startTicks = null)
    {
        if (all == (pid is not null))
            throw new ArgumentException("指定一个 --pid 或 --all。");
        if (all)
            return Rows;
        if (!rows.TryGetValue(pid!.Value, out GameRow? row) || (startTicks is not null && row.Client.StartTicks != startTicks))
            throw new ArgumentException("未找到符合身份的游戏进程，请刷新。");
        return [row];
    }

    public async Task Refresh(bool scan, CancellationToken cancellation)
    {
        await mutations.WaitAsync(cancellation);
        try
        {
            AssertAvailable();
            if (scan)
                await StopCore(Rows, cancellation);
            RefreshRows();
            if (scan)
            {
                IntPtr previous = NativeInput.CurrentWindow();
                var scanned = Rows;
                await Task.WhenAll(scanned.Select(row => Scan(row, cancellation)));
                if (scanned.Length > 0 && previous != IntPtr.Zero)
                {
                    GameRow first = scanned[0];
                    await Operator.Submit(first.Endpoint, first.Endpoint.Version, Config.Effective, "Scan.Restore",
                        _ => NativeInput.RestoreAfterScan(previous), cancellation, false);
                }
            }
        }
        finally { mutations.Release(); }
    }

    private void RefreshRows()
    {
        lock (gate)
        {
            Client[] clients = Native.FindClients();
            foreach (GameRow row in Rows)
            {
                if (clients.Any(client => client.Key == row.Client.Key))
                    continue;
                row.Session?.Stop();
                Hub.Remove(row.Endpoint.Key);
                rows.TryRemove(row.Client.ProcessId, out _);
            }
            foreach (Client client in clients)
            {
                if (rows.ContainsKey(client.ProcessId))
                    continue;
                var endpoint = Hub.Register(client.Key, client.ProcessId, client.StartTicks, client.Path, client.Flavor);
                rows[client.ProcessId] = new GameRow(client, endpoint);
            }
        }
        Changed();
    }

    private async Task Scan(GameRow row, CancellationToken cancellation)
    {
        Configuration configuration = Config;
        Settings settings = configuration.Effective;
        Client client = row.Client;
        string mode = settings.DirectModes.GetValueOrDefault($"{client.ProcessId}:{client.StartTicks}", "fish").ToLowerInvariant();
        long version = row.Endpoint.Advance();
        ProcessView view = Volatile.Read(ref row.View) with { Phase = "scanning", SessionVersion = version, ConfigRevision = configuration.Revision,
            Mode = mode, SampledAt = Hub.Now, Message = "正在检查检测色块。", Metrics = null };
        Volatile.Write(ref row.View, view);
        Changed();
        bool valid = false;
        string? failure = null;
        string login = "unknown";
        const int timeout = 5000;
        long until = Hub.Now + timeout;
        try
        {
            if (mode is not ("rest" or "shop"))
            {
                var enabled = await Operator.Submit(row.Endpoint, version, settings, "Scan.Enable", op =>
                    WowAutoRotation.Native.ReadLoginMode(client.ProcessId, client.StartTicks, client.Path) is not ("unknown" or "dead") &&
                    NativeInput.SendDetectorCommand(client.ProcessId, client.StartTicks, client.Path, mode, op.Timing.ChatKeyPressMs),
                    cancellation);
                if (!enabled.Executed)
                    throw new InvalidOperationException(enabled.Error ?? "监控开启命令未完成。");
            }
            do
            {
                cancellation.ThrowIfCancellationRequested();
                try
                {
                    login = WowAutoRotation.Native.ReadLoginMode(client.ProcessId, client.StartTicks, client.Path);
                    valid = mode switch
                    {
                        "fish" => login == "fish" && NativeInput.ReadCenterColor(client.ProcessId, client.StartTicks, client.Path) is "red" or "green",
                        "fight" => login == "fight" && Native.Read(client) is { Action: not "dead" },
                        "tame" => Native.ReadTame(client) is { State: "idle" or "matched" },
                        _ => login is not ("unknown" or "dead")
                    };
                }
                catch (WowAutoCapture.PendingException)
                {
                    foreach (var repair in WowAutoCapture.Native.PendingRestores().Where(item => item.ProcessId == client.ProcessId &&
                        item.StartTicks == client.StartTicks))
                        await Operator.Submit(row.Endpoint, version, settings, "Capture.Restore",
                            _ => { WowAutoCapture.Native.RestoreMinimized(repair); return true; }, cancellation, false);
                }
                if (!valid && Hub.Now < until)
                    await Task.Delay(settings.Periods.CaptureRetryMs, cancellation);
            } while (!valid && Hub.Now < until);
        }
        catch (Exception error) when (error is not OperationCanceledException) { failure = error.Message; }
        finally
        {
            Volatile.Write(ref row.View, view with { Phase = valid ? "ready" : "unverified", SampledAt = Hub.Now,
                Message = valid ? "检测通过，可以开始。" : failure ?? "未识别到有效检测色块。", Metrics = new { valid, login } });
            Changed();
        }
    }

    public async Task<GameSession[]> Start(GameRow[] selected, string? mode, bool direct, string? role,
        bool replace, CancellationToken cancellation)
    {
        if (!direct)
            await WaitForBatch(cancellation);
        await mutations.WaitAsync(cancellation);
        try
        {
            AssertAvailable();
            if (selected.Length == 0)
                throw new ArgumentException("当前没有可用游戏进程。");
            if (!replace && selected.Any(row => row.Session?.Active == true))
                throw new InvalidOperationException("所选进程已有运行任务，请使用 task switch 或先停止。");
            string? rememberedAccount = replace && selected.Length == 1 && selected[0].Session?.Direct == false
                ? selected[0].Session?.Account : null;
            if (replace)
                await StopCore(selected, cancellation);
            lock (gate)
            {
                if (!direct && Hub.Batch is { } previous && !previous.All(8))
                    throw new InvalidOperationException("另一批角色切换已开始，请在批次完成后重试。");
                if (selected.Any(row => !row.Endpoint.Current(row.Endpoint.Version) || !Native.IsAlive(row.Client)))
                    throw new ArgumentException("至少一个进程已退出或身份变化，请先刷新。");
                RotationBatch? batch = direct ? null : new(selected.Select(row => row.Endpoint.Key).ToArray());
                if (!direct)
                    Hub.Batch = batch!;
                var sessions = new List<GameSession>();
                foreach (GameRow row in selected)
                {
                    string defaultMode = Config.Effective.DirectModes.GetValueOrDefault($"{row.Client.ProcessId}:{row.Client.StartTicks}", "fish");
                    var session = new GameSession(this, row, mode ?? defaultMode.ToLowerInvariant(), direct, role, rememberedAccount, batch);
                    row.Session = session;
                    sessions.Add(session);
                }
                foreach (GameSession session in sessions)
                    session.Start();
                return sessions.ToArray();
            }
        }
        finally { mutations.Release(); }
    }

    public async Task Stop(GameRow[] selected, CancellationToken cancellation)
    {
        await mutations.WaitAsync(cancellation);
        try { await StopCore(selected, cancellation); }
        finally { mutations.Release(); }
    }

    private static async Task StopCore(IEnumerable<GameRow> selected, CancellationToken cancellation)
    {
        var sessions = selected.Select(row => row.Session).OfType<GameSession>().Where(session => session.Active).ToArray();
        foreach (GameSession session in sessions)
            session.Stop();
        await Task.WhenAll(sessions.Select(session => session.Completion)).WaitAsync(cancellation);
    }

    public async Task<T> Exclusive<T>(Func<Task<T>> setup, CancellationToken cancellation)
    {
        await mutations.WaitAsync(cancellation);
        try { AssertAvailable(); return await setup(); }
        finally { mutations.Release(); }
    }

    private void AssertAvailable()
    {
        if (closing || shuttingDown || Creator.Active)
            throw new InvalidOperationException("程序正在关闭、退出游戏或执行角色创建。");
    }

    private async Task WaitForBatch(CancellationToken cancellation)
    {
        while (Hub.Batch is { } batch && !batch.All(8))
            await Task.Delay(50, cancellation);
    }

    public async Task<RotationBatch> JoinRotation(Endpoint endpoint, CancellationToken cancellation)
    {
        var promise = new TaskCompletionSource<RotationBatch>(TaskCreationOptions.RunContinuationsAsynchronously);
        lock (gate)
        {
            rotationWaiters.Add((endpoint, promise));
            if (!formingBatch)
            {
                formingBatch = true;
                _ = Task.Run(FormRotation);
            }
        }
        using var registration = cancellation.Register(() => promise.TrySetCanceled(cancellation));
        return await promise.Task;
    }

    private async Task FormRotation()
    {
        try
        {
            await Task.Delay(120, Token);
            while (!Token.IsCancellationRequested)
            {
                await WaitForBatch(Token);
                lock (gate)
                {
                    if (Hub.Batch is { } previous && !previous.All(8))
                        continue;
                    var participants = rotationWaiters.Where(item => !item.Promise.Task.IsCompleted && !item.Endpoint.Closed).ToArray();
                    rotationWaiters.Clear();
                    formingBatch = false;
                    if (participants.Length == 0)
                        return;
                    var batch = new RotationBatch(participants.Select(item => item.Endpoint.Key).ToArray());
                    Hub.Batch = batch;
                    foreach (var item in participants)
                        if (!item.Promise.TrySetResult(batch))
                            batch.Drop(item.Endpoint.Key);
                    return;
                }
            }
        }
        catch (OperationCanceledException) when (Token.IsCancellationRequested) { }
    }

    public async Task<ActionResult> CloseClient(GameRow row, long version, Settings settings, CancellationToken cancellation)
    {
        var client = row.Client;
        var outcome = await Operator.Submit(row.Endpoint, version, settings, "Process.Close", _ =>
        {
            using Process process = Process.GetProcessById(client.ProcessId);
            if (!Matches(process, client))
                return false;
            process.CloseMainWindow();
            return true;
        }, cancellation, foreground: false);
        if (!outcome.Executed)
            return outcome;
        long limit = Hub.Now + 30000;
        while (Native.IsAlive(client) && Hub.Now < limit)
            await Task.Delay(500, cancellation);
        if (!Native.IsAlive(client))
            return outcome;
        outcome = await Operator.Submit(row.Endpoint, version, settings, "Process.Kill", _ =>
        {
            using Process process = Process.GetProcessById(client.ProcessId);
            if (!Matches(process, client))
                return false;
            process.Kill();
            return true;
        }, cancellation, foreground: false);
        limit = Hub.Now + 5000;
        while (Native.IsAlive(client) && Hub.Now < limit)
            await Task.Delay(500, cancellation);
        return Native.IsAlive(client) ? outcome with { Executed = false, Error = "退出后未确认进程已结束。" } : outcome;
    }

    private static bool Matches(Process process, Client client) => !process.HasExited &&
        process.StartTime.Ticks == client.StartTicks &&
        string.Equals(process.MainModule?.FileName, client.Path, StringComparison.OrdinalIgnoreCase) &&
        NativeInput.GetClientFlavor(client.Path, FileVersionInfo.GetVersionInfo(client.Path).FileVersion) == client.Flavor;

    public Task<ActionResult[]> Countdown(int? seconds)
    {
        lock (gate)
        {
            if (shuttingDown || closing)
                throw new InvalidOperationException("游戏退出流程已经开始。");
            if (seconds is not null && Creator.Active)
                throw new InvalidOperationException("请先停止角色创建。");
            countdown?.Cancel();
            Interlocked.Exchange(ref shutdownAt, seconds is null ? 0 : Hub.Now + seconds.Value * 1000L);
            Changed();
            if (seconds is null)
                return Task.FromResult(Array.Empty<ActionResult>());
            var session = CancellationTokenSource.CreateLinkedTokenSource(Token);
            countdown = session;
            return Task.Run(() => RunCountdown(session, Interlocked.Read(ref shutdownAt)));
        }
    }

    private async Task<ActionResult[]> RunCountdown(CancellationTokenSource owner, long deadline)
    {
        try
        {
            while (Hub.Now < deadline)
            {
                await Task.Delay((int)Math.Clamp(deadline - Hub.Now, 1, 200), owner.Token);
                Changed();
            }
            await mutations.WaitAsync(owner.Token);
            try
            {
                lock (gate)
                {
                    owner.Token.ThrowIfCancellationRequested();
                    if (!ReferenceEquals(countdown, owner))
                        return [];
                    shuttingDown = true;
                }
                Changed();
                await StopCore(Rows, owner.Token);
                RefreshRows();
                return await Task.WhenAll(Rows.Select(row => CloseClient(row, row.Endpoint.Version, Config.Effective, owner.Token)));
            }
            finally { mutations.Release(); }
        }
        finally
        {
            lock (gate)
            {
                if (ReferenceEquals(countdown, owner))
                {
                    countdown = null;
                    shuttingDown = false;
                    Interlocked.Exchange(ref shutdownAt, 0);
                }
            }
            owner.Dispose();
            Changed();
        }
    }

    private async Task IdleMonitor()
    {
        try
        {
            while (!Token.IsCancellationRequested)
            {
                long now = Hub.Now;
                foreach (GameRow row in Rows)
                {
                    if (row.Session?.Active == true)
                        continue;
                    ProcessView view = Volatile.Read(ref row.View);
                    bool alive = Native.IsAlive(row.Client);
                    string position = alive ? Native.ReadWindowPosition(row.Client) : view.Position;
                    if (view.Position != position || (!alive && view.Phase != "exited"))
                    {
                        Volatile.Write(ref row.View, view with { Position = position, Phase = alive ? view.Phase : "exited",
                            SampledAt = now, Message = alive ? view.Message : "游戏进程已退出。" });
                        Changed();
                    }
                }
                if (now >= lastInfo + 1000)
                {
                    lastInfo = now;
                    Hub.WriteInfo(JsonSerializer.Serialize(Snapshot(), Wire.Json));
                    Changed();
                }
                await Task.Delay(Math.Min(1000, Config.Effective.Periods.PositionMs), Token);
            }
        }
        catch (OperationCanceledException) when (Token.IsCancellationRequested) { }
        catch (Exception error) { Log(null, "error", $"空闲状态采集失败。{error.Message}"); }
    }

    public async ValueTask DisposeAsync()
    {
        closing = true;
        await Creator.Stop();
        await StopCore(Rows, CancellationToken.None);
        lifetime.Cancel();
        await idleMonitor;
        foreach (var watcher in watchers.Values)
            watcher.Writer.TryComplete();
        Operator.Dispose();
        if (!Hub.Logger.Close(5000))
            throw new InvalidOperationException("日志线程尚未退出。");
        lifetime.Dispose();
    }
}
