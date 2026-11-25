using System.Threading.Channels;
using WowAuto.Threading;
using WowAutoFight;
using Capture = WowAutoCapture.Native;
using Rotation = WowAutoRotation.Native;

namespace WowAuto.Desktop;

internal sealed record ProcessView(int Pid, long StartTicks, string Flavor, string Title, string Position,
    string Phase, string? Mode, string? Account, string? Role, bool Direct, int Round, long Cycles, long BiteTimeouts,
    long SessionVersion, long ConfigRevision, long TaskRevision, long SampledAt, long? Deadline, string Message, object? Metrics,
    long? RotationDueAt = null, int RotationSwitches = 0, string? TargetRole = null);

internal sealed class GameRow(Client client, Endpoint endpoint)
{
    public Client Client { get; } = client;
    public Endpoint Endpoint { get; } = endpoint;
    public GameSession? Session;
    public long Cycles, CyclesSinceJump, BiteTimeouts;
    public int Round;
    public ProcessView View = new(client.ProcessId, client.StartTicks, client.Flavor, client.Title, "", "idle", null,
        null, null, false, 0, 0, 0, endpoint.Version, 0, 0, 0, null, "等待任务。", null);
}

internal sealed record ManualAction(string Kind, TaskCompletionSource<ActionResult> Completion);
internal sealed record TaskOverrides(long Revision, IReadOnlyList<SettingChange> Changes, bool? UseItem);
internal sealed record AppliedTaskConfiguration(long ConfigRevision, TaskOverrides Overrides, Settings Effective);

internal sealed partial class GameSession
{
    private readonly Automation automation;
    private readonly GameRow row;
    private readonly CancellationTokenSource stop = new();
    private readonly Channel<ManualAction> manual = Channel.CreateBounded<ManualAction>(16);
    private readonly SemaphoreSlim wake = new(0, 1);
    private readonly Dictionary<string, int> restVisits = new(StringComparer.Ordinal);
    private readonly HashSet<string> excluded = new(StringComparer.Ordinal);
    private readonly HashSet<string> shoppingFinished = new(StringComparer.Ordinal);
    private readonly TaskCompletionSource<bool> started = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private TaskOverrides overrides = new(0, [], null);
    private AppliedTaskConfiguration? applied;
    private long seenConfig = -1, seenOverride = -1;
    private Settings settings = new();
    private string mode;
    private readonly bool direct;
    private readonly bool directRest;
    private readonly long version;
    private string? role, account, target;
    private string phase = "starting", message = "正在开始任务。", position = "";
    private object? metrics;
    private long? deadline;
    private long nextPosition, nextRotate, retryAt;
    private bool roleUseItem, shopPrepared;
    private int initialRestVisits;
    private int rotationSwitches;
    private RotationBatch? batch;
    private Task run = Task.CompletedTask;
    private ManualAction? activeManual;
    private int stopRequested;

    private Client Client => row.Client;
    private Endpoint Endpoint => row.Endpoint;
    private long Now => automation.Hub.Now;
    private CancellationToken Token => stop.Token;
    private bool Current => !Token.IsCancellationRequested && Endpoint.Current(version);
    public bool Active => !run.IsCompleted;
    public Task Completion => run;
    public Task<bool> Started => started.Task;
    public bool Direct => direct;
    public string Mode => mode;
    public string? Account => account;
    public string? Role => role;
    public long Version => version;
    public AppliedTaskConfiguration? Applied => Volatile.Read(ref applied);

    public GameSession(Automation automation, GameRow row, string mode, bool direct, string? target, string? account, RotationBatch? batch,
        TaskOverrides? initialOverrides = null)
    {
        this.automation = automation;
        this.row = row;
        version = row.Endpoint.Advance();
        this.mode = mode;
        this.direct = direct;
        directRest = direct && mode == "rest";
        this.target = target;
        this.account = directRest ? null : account;
        this.batch = batch;
        if (initialOverrides is not null)
            overrides = initialOverrides;
    }

    public void Start()
    {
        Publish();
        run = Task.Run(Run);
    }

    public void Stop()
    {
        if (!Active || Interlocked.Exchange(ref stopRequested, 1) != 0)
            return;
        Endpoint.Advance();
        stop.Cancel();
        automation.Hub.Wake.Set();
        batch?.Drop(Endpoint.Key);
        Capture.CancelRestore(Client.ProcessId, Client.StartTicks, Client.Path);
        Wake();
    }

    public void Wake()
    {
        try { wake.Release(); }
        catch (SemaphoreFullException) { }
    }

    public long Update(IReadOnlyList<SettingChange> changes, bool? useItem)
    {
        lock (manual)
        {
            TaskOverrides before = overrides;
            var combined = before.Changes.Concat(changes).ToArray();
            _ = SettingsStore.Patch(automation.Config.Effective, combined);
            var next = new TaskOverrides(before.Revision + 1, combined, useItem ?? before.UseItem);
            Volatile.Write(ref overrides, next);
            Wake();
            return next.Revision;
        }
    }

    public async Task<ActionResult> RequestAction(string kind, CancellationToken cancellation)
    {
        var request = new ManualAction(kind, new(TaskCreationOptions.RunContinuationsAsynchronously));
        if (!Active || !manual.Writer.TryWrite(request))
            throw new InvalidOperationException("任务未运行或操作队列已满。");
        Wake();
        return await request.Completion.Task.WaitAsync(cancellation);
    }

    private async Task Run()
    {
        try
        {
            ApplyConfig();
            if (!direct)
            {
                if (batch is null)
                    throw new InvalidOperationException("缺少换角批次。");
                if (!await Rotate(batch))
                    return;
            }
            else
                await Enable("Scan.Enable");
            while (Current)
            {
                ApplyConfig();
                phase = "running";
                row.Round++;
                nextRotate = RotationDue();
                if (directRest)
                {
                    retryAt = 0;
                    deadline = null;
                    metrics = null;
                }
                message = "任务已开始。";
                Publish();
                started.TrySetResult(true);
                string result = mode switch
                {
                    "fish" => await Fish(),
                    "fight" => await Fight(),
                    "tame" => await Tame(),
                    "rest" => await Rest(),
                    "shop" => await Shop(),
                    _ => throw new InvalidOperationException($"未知任务模式 {mode}。")
                };
                if (!Current)
                    break;
                message = result;
                if (direct && !directRest)
                    break;
                if (directRest && role is null)
                {
                    if (result != "放号完成")
                        break;
                    initialRestVisits++;
                    ApplyConfig();
                    if (!settings.Accounts.Any(item => item.Key.StartsWith(Client.Flavor + ":", StringComparison.Ordinal) &&
                        item.Value.Any(configured => configured.Enabled && configured.Mode == "rest")))
                    {
                        if (initialRestVisits < settings.Rest.Rounds)
                            continue;
                        break;
                    }
                }
                else
                {
                    if (result is "角色死亡" or "背包已满")
                        excluded.Add(role!);
                    if (result == "放号完成")
                        restVisits[role!] = restVisits.GetValueOrDefault(role!) + 1;
                    if (result == "购物结束")
                        shoppingFinished.Add(role!);
                    if (result == "买到商品，已请求退出")
                        break;
                    ApplyConfig();
                    var roles = Eligible();
                    if (roles.Length == 0)
                    {
                        if (!directRest && excluded.Count > 0 && !ConfiguredRoles().Any(r => !excluded.Contains(r.Name)))
                            await automation.CloseClient(row, version, settings, Token);
                        message = "本次轮转已完成。";
                        break;
                    }
                    if (directRest && roles.Length == 1 && roles[0].Name == role)
                        continue;
                }
                batch = await automation.JoinRotation(Endpoint, Token);
                if (!await Rotate(batch))
                    break;
                rotationSwitches++;
            }
        }
        catch (OperationCanceledException) when (!Current) { message = "任务已停止。"; }
        catch (Exception error) { message = error.Message; phase = "failed"; automation.Log(Client.ProcessId, "error", message); }
        finally
        {
            batch?.Drop(Endpoint.Key);
            if (shopPrepared)
                await CancelShop();
            manual.Writer.TryComplete();
            activeManual?.Completion.TrySetResult(new(activeManual.Kind, Client.ProcessId, false, Now, "任务已结束。"));
            while (manual.Reader.TryRead(out ManualAction? request))
                request.Completion.TrySetResult(new(request.Kind, Client.ProcessId, false, Now, "任务已结束。"));
            started.TrySetResult(false);
            phase = phase == "failed" ? "failed" : "stopped";
            deadline = null;
            metrics = null;
            Publish();
        }
    }

    private void ApplyConfig()
    {
        Configuration global = automation.Config;
        TaskOverrides local = Volatile.Read(ref overrides);
        if (global.Revision == seenConfig && local.Revision == seenOverride)
            return;
        Settings merged = local.Changes.Count == 0 ? global.Effective : SettingsStore.Patch(global.Effective, local.Changes);
        if (settings.Rotation.IntervalSeconds != merged.Rotation.IntervalSeconds && nextRotate != 0)
            nextRotate = !direct && merged.Rotation.IntervalSeconds > 0 ? Now + 1000L * merged.Rotation.IntervalSeconds : long.MaxValue;
        settings = merged;
        seenConfig = global.Revision;
        seenOverride = local.Revision;
        Volatile.Write(ref applied, new(seenConfig, local, merged));
    }

    private long RotationDue() => !direct && settings.Rotation.IntervalSeconds > 0 ? Now + 1000L * settings.Rotation.IntervalSeconds : long.MaxValue;

    private bool ShouldRotate() => !direct && (Now >= nextRotate || !ConfiguredRoles().Any(item => item.Name == role && item.Mode == mode));

    private RoleSettings[] ConfiguredRoles() => account is not null && settings.Accounts.TryGetValue($"{Client.Flavor}:{account}", out var roles)
        ? roles.Where(item => item.Enabled && (!directRest || item.Mode == "rest")).ToArray() : [];

    private int RestVisits() => role is null ? initialRestVisits : restVisits.GetValueOrDefault(role);

    private RoleSettings[] Eligible() => ConfiguredRoles().Where(item => !excluded.Contains(item.Name) &&
        (item.Mode != "rest" || restVisits.GetValueOrDefault(item.Name) < settings.Rest.Rounds) &&
        (item.Mode != "shop" || !shoppingFinished.Contains(item.Name))).ToArray();

    private void Publish()
    {
        var view = new ProcessView(Client.ProcessId, Client.StartTicks, Client.Flavor, Client.Title, position, phase, mode,
            account, role ?? target, direct, row.Round, row.Cycles, row.BiteTimeouts,
            version, seenConfig, seenOverride, Now, deadline, message, metrics,
            phase == "running" && nextRotate is > 0 and < long.MaxValue ? nextRotate : null, rotationSwitches,
            phase == "switching" ? target ?? role : null);
        if (ReferenceEquals(row.Session, this))
        {
            string before = Volatile.Read(ref row.View).Message;
            Volatile.Write(ref row.View, view);
            automation.Changed();
            if (before != message)
                automation.Log(Client.ProcessId, "status", message);
        }
    }

    private async Task Tick(int delay)
    {
        if (!Current)
            throw new OperationCanceledException(Token);
        ApplyConfig();
        if (Now >= nextPosition)
        {
            nextPosition = Now + settings.Periods.PositionMs;
            if (!Native.IsAlive(Client))
                throw new InvalidOperationException("游戏进程已退出或身份变化。");
            position = Native.ReadWindowPosition(Client);
        }
        Publish();
        await wake.WaitAsync(Math.Max(1, delay), Token);
    }

    private async Task WaitUntil(long until)
    {
        while (Now < until)
            await Tick((int)Math.Clamp(until - Now, 1, Math.Max(100, settings.Operations.DetectorWaitMs)));
    }

    private Task<ActionResult> Operate(string kind, Func<Operation, bool?> perform, bool foreground = true,
        CancellationToken? cancellation = null)
    {
        return automation.Operator.Submit(Endpoint, version, settings, kind, perform, cancellation ?? Token, foreground);
    }

    private string LoginMode() => Rotation.ReadLoginMode(Client.ProcessId, Client.StartTicks, Client.Path);
    private string FishColor() => NativeInput.ReadCenterColor(Client.ProcessId, Client.StartTicks, Client.Path);
    private string LureColor() => NativeInput.ReadLureColor(Client.ProcessId, Client.StartTicks, Client.Path);
    private string ShopState() => Rotation.ReadShoppingState(Client.ProcessId, Client.StartTicks, Client.Path, true);
    private bool LoggedIn() => LoginMode() is not ("unknown" or "dead");
    private bool Key(Operation operation, params string[] keys) => automation.Operator.Keys(operation, Client, keys);
    private bool Chat(Operation operation, string action) => NativeInput.SendShoppingCommand(Client.ProcessId, Client.StartTicks,
        Client.Path, action, operation.Timing.ChatKeyPressMs);

    private async Task RepairCapture()
    {
        foreach (var repair in Capture.PendingRestores().Where(item => item.ProcessId == Client.ProcessId && item.StartTicks == Client.StartTicks))
            await Operate("Capture.Restore", _ => { Capture.RestoreMinimized(repair); return true; }, false);
        await Tick(settings.Periods.CaptureRetryMs);
    }

    private async Task<string> ObserveMode()
    {
        while (true)
        {
            Token.ThrowIfCancellationRequested();
            try { return LoginMode(); }
            catch (WowAutoCapture.PendingException) { await RepairCapture(); }
        }
    }

    private async Task Enable(string kind)
    {
        string login = await ObserveMode();
        if (login is "unknown" or "dead")
            throw new InvalidOperationException("请先登录一个存活角色并确认插件登录色块。");
        if (mode == "tame" && settings.Tame.TameKey.Length == 0)
            throw new InvalidOperationException("请先配置抓宠按键。");
        if (mode == "fish")
        {
            string rod = settings.Fish.EquipRodKey;
            if (rod.Length == 0)
                throw new InvalidOperationException("请先配置装备鱼竿按键。");
            var equip = await Operate(kind.StartsWith("Rotation", StringComparison.Ordinal) ? "Rotation.EquipRod" : "Fish.EquipRod",
                op => LoggedIn() && Key(op, rod));
            Require(equip);
        }
        var enable = await Operate(kind, op => LoggedIn() && (mode == "shop" ? Chat(op, "prepare") :
            NativeInput.SendDetectorCommand(Client.ProcessId, Client.StartTicks, Client.Path, mode, op.Timing.ChatKeyPressMs)));
        Require(enable);
        shopPrepared = mode == "shop";
        int confirmed = 0;
        long end = Now + 15000;
        while (confirmed < 3 && Now < end)
        {
            login = await ObserveMode();
            if (login == "dead")
                throw new InvalidOperationException("角色死亡。");
            bool valid = mode == "tame" ? Native.ReadTame(Client) is not null : login == mode;
            confirmed = valid ? confirmed + 1 : 0;
            if (confirmed < 3)
                await Tick(settings.Periods.LoginMs);
        }
        if (confirmed < 3)
            throw new InvalidOperationException("未确认对应任务色块。");
    }

    private static void Require(ActionResult result)
    {
        if (!result.Executed)
            throw new InvalidOperationException(result.Error ?? $"{result.Kind} 未执行。");
    }

    private async Task<bool> Execute(string kind, Func<Operation, bool?> perform, ManualAction? command = null)
    {
        ActionResult result;
        try { result = await Operate(kind, perform); }
        catch (OperationCanceledException)
        {
            command?.Completion.TrySetCanceled();
            throw;
        }
        command?.Completion.TrySetResult(result);
        if (result.Error?.Contains("前台保护时间", StringComparison.Ordinal) == true)
        {
            retryAt = Now + settings.Operations.FocusRetryMs;
            message = result.Error;
        }
        else if (result.Error is not null && Current)
            message = result.Error;
        return result.Executed;
    }

    private ManualAction? Manual(string? eligible)
    {
        while (manual.Reader.TryRead(out ManualAction? request))
        {
            if (request.Kind.Equals(eligible, StringComparison.OrdinalIgnoreCase))
                return activeManual = request;
            request.Completion.TrySetResult(new(request.Kind, Client.ProcessId, false, Now, "当前状态不允许执行该动作。"));
        }
        return null;
    }
}
