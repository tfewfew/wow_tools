using System.Collections.Concurrent;
using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using System.Text.Json.Nodes;
using WowAuto.Protocol;

namespace WowAuto.Desktop;

internal sealed class CommandProcessor(Automation automation, DesktopServices desktop)
{
    private readonly ConcurrentDictionary<Guid, Response> jobs = new();
    private readonly ConcurrentQueue<Guid> jobOrder = new();
    private static readonly string[] Commands =
    [
        "status get|watch [--pid PID]", "status log [--lines N]", "process list|refresh|scan",
        "config list", "config get [PATH]", "config set PATH VALUE [--runtime] [--revision N]",
        "config patch --set PATH=VALUE [...] [--runtime] [--revision N]", "config import OLD_DIRECTORY [--revision N]",
        "account list [--flavor titan|forerver]", "task start --pid PID|--all [--mode MODE] [--role NAME] [--wait]",
        "task stop --pid PID|--all [--wait]", "task switch --pid PID (--mode MODE|--role NAME) [--wait]", "task get --pid PID [PATH]",
        "task update --pid PID [--set PATH=VALUE ...] [--use-item true|false] [--mode MODE|--role NAME] [--wait]",
        "action list", "action send NAME --pid PID [--wait]", "shutdown set SECONDS [--wait]", "shutdown cancel",
        "character create --pid PID [--start-ticks TICKS] [--wait]",
        "character preview (--pid PID [--start-ticks TICKS]|--image PATH) [--output PNG]",
        "character stop [--wait]", "audio preview FLAVOR ID", "audio stop", "screenshot select [--wait]",
        "request get ID", "runtime close", "runtime restart"
    ];

    public async Task<Response> Execute(Request request)
    {
        try
        {
            if (request.Version != Wire.Version || request.Id == Guid.Empty || request.Args is null || request.Args.Length is < 1 or > 128 ||
                request.Args.Any(value => value is null || value.Length > 262144))
                throw new ArgumentException("请求格式或协议版本无效。");
            return await Dispatch(request);
        }
        catch (Exception error) { return Failure(request.Id, error); }
    }

    public static (bool Watch, int? Pid) Subscription(string[] args)
    {
        if (args.Length < 2 || args[0] != "status" || args[1] != "watch")
            return (false, null);
        var options = new Arguments(args[2..]);
        int? pid = options.Int("--pid");
        options.Done(0);
        return (true, pid);
    }

    private async Task<Response> Dispatch(Request request)
    {
        Guid id = request.Id;
        string[] args = request.Args;
        if (args is ["help"])
            return Wire.Reply(id, "completed", Commands);
        if (args.Length < 2)
            throw new ArgumentException("需要命令和子命令。使用 help 查看命令。");
        var options = new Arguments(args[2..]);
        string command = $"{args[0]} {args[1]}";
        object? result;
        switch (command)
        {
            case "status get":
                int? pid = options.Int("--pid");
                options.Done(0);
                result = automation.Snapshot(pid);
                break;
            case "status log":
                int lines = options.Int("--lines", 1, 1000) ?? 50;
                options.Done(0);
                string log = Path.Combine(desktop.DataDirectory, "log", "wowAuto.log");
                using (var stream = new FileStream(log, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (var reader = new StreamReader(stream))
                {
                    var recent = new Queue<JsonElement>(lines);
                    while (await reader.ReadLineAsync(automation.Token) is { } line)
                    {
                        try
                        {
                            using var document = JsonDocument.Parse(line);
                            if (recent.Count == lines)
                                recent.Dequeue();
                            recent.Enqueue(document.RootElement.Clone());
                        }
                        catch (JsonException) { }
                    }
                    result = recent.ToArray();
                }
                break;
            case "process list":
                options.Done(0);
                result = automation.Snapshot().Processes;
                break;
            case "process refresh":
            case "process scan":
                options.Done(0);
                await automation.Refresh(command == "process scan", automation.Token);
                result = automation.Snapshot().Processes;
                break;
            case "config list":
                options.Done(0);
                result = new { fields = Describe(typeof(Settings), ""), defaults = SettingsJson.Tree(new()), effective = SettingsJson.Tree(automation.Config.Effective) };
                break;
            case "config get":
                options.Done(0, 1);
                result = ReadConfig(options.At(0) ?? "");
                break;
            case "config set":
            case "config patch":
            {
                bool runtime = options.Flag("--runtime");
                long? revision = options.Long("--revision", 0);
                var changes = command == "config set" ? [new SettingChange(options.Required(0), options.Required(1))] : Changes(options);
                options.Done(command == "config set" ? 2 : 0);
                if (changes.Length == 0)
                    throw new ArgumentException("请提供至少一个 --set PATH=VALUE。");
                Configuration configuration = await desktop.OnUi(() => automation.Configure(changes, runtime, revision));
                result = new { configuration.Revision, runtime, paths = changes.Select(change => change.Path) };
                break;
            }
            case "config import":
            {
                long? revision = options.Long("--revision", 0);
                options.Done(1);
                var imported = LegacyImport.Read(options.Required(0), automation.Config.Saved);
                string? skipped = null;
                Configuration configuration = await desktop.OnUi(() =>
                {
                    try { return automation.Configure(imported, false, revision); }
                    catch (System.ComponentModel.Win32Exception error) when (error.NativeErrorCode == 1409 &&
                        imported.Any(change => change.Path == "ScreenshotKey"))
                    {
                        // The legacy host may still own the global hotkey. Import
                        // the remaining settings without changing either binding.
                        skipped = "ScreenshotKey";
                        imported = imported.Where(change => change.Path != skipped).ToArray();
                        return automation.Configure(imported, false, revision);
                    }
                });
                result = new { configuration.Revision, imported = imported.Select(change => change.Path), skipped };
                break;
            }
            case "account list":
            {
                string? flavor = options.Value("--flavor");
                options.Done(0);
                RotationSettings rotation = automation.Config.Effective.Rotation;
                if (flavor is not (null or "titan" or "forerver"))
                    throw new ArgumentException("--flavor 仅支持 titan 或 forerver。");
                result = (flavor is null ? new[] { "titan", "forerver" } : [flavor]).ToDictionary(
                    value => value, value => AccountCatalog.ReadDirectory(value == "titan" ? rotation.TitanDirectory : rotation.ForerverDirectory));
                break;
            }
            case "task start":
            case "task switch":
            {
                var rows = Select(options);
                string? role = options.Value("--role");
                string? mode = Mode(options);
                bool direct = options.Flag("--direct") || mode is not null;
                bool wait = options.Flag("--wait");
                options.Done(0);
                if ((role is not null && direct) || (command == "task switch" && (rows.Length != 1 || (mode is null && role is null))))
                    throw new ArgumentException("角色切换指定一个 PID 和角色名。切换到直接任务可指定 --mode。");
                GameSession[] sessions = await automation.Start(rows, mode, direct, role, command == "task switch", automation.Token);
                return await Work(id, wait, async () =>
                {
                    bool[] confirmed = await Task.WhenAll(sessions.Select(session => session.Started));
                    var perProcess = rows.Select((row, index) => new { pid = row.Client.ProcessId, started = confirmed[index],
                        status = Volatile.Read(ref row.View) }).ToArray();
                    return (confirmed.All(value => value), perProcess);
                }, rows.Select(row => row.Client.ProcessId).ToArray());
            }
            case "task stop":
            {
                var rows = Select(options);
                bool wait = options.Flag("--wait");
                options.Done(0);
                return await Work(id, wait, async () =>
                {
                    await automation.Stop(rows, automation.Token);
                    return (true, rows.Select(row => Volatile.Read(ref row.View)).ToArray());
                });
            }
            case "task get":
            {
                var rows = Select(options);
                options.Done(0, 1);
                if (rows.Length != 1 || rows[0].Session is not { Active: true, Applied: { } applied })
                    throw new InvalidOperationException("该进程没有已完成初始化的运行任务。");
                result = new { applied.ConfigRevision, taskRevision = applied.Overrides.Revision, applied.Overrides.UseItem,
                    applied.Overrides.Changes, effective = SettingsJson.Get(SettingsJson.Tree(applied.Effective), options.At(0) ?? "") };
                break;
            }
            case "task update":
            {
                var rows = Select(options);
                bool wait = options.Flag("--wait");
                string? role = options.Value("--role");
                string? mode = Mode(options);
                bool? useItem = options.Bool("--use-item");
                SettingChange[] changes = Changes(options);
                options.Done(0);
                if (rows.Length != 1 || (role is not null && mode is not null) || (role is null && mode is null && changes.Length == 0 && useItem is null))
                    throw new ArgumentException("指定单个 PID 和至少一个要修改的值。");
                var row = rows[0];
                GameSession session = row.Session is { Active: true } running ? running : throw new InvalidOperationException("该进程没有运行任务。");
                if (role is not null || mode is not null)
                    session = (await automation.Start(rows, mode, mode is not null, role, true, automation.Token))[0];
                long revision = changes.Length > 0 || useItem is not null ? session.Update(changes, useItem) : 0;
                return await Work(id, wait, async () =>
                {
                    while (session.Active)
                    {
                        ProcessView current = Volatile.Read(ref row.View);
                        if (current.SessionVersion == session.Version && current.TaskRevision >= revision && (role is null && mode is null || current.Phase == "running"))
                            return (true, current);
                        await Task.Delay(25, automation.Token);
                    }
                    return (false, Volatile.Read(ref row.View));
                }, new { revision, pid = row.Client.ProcessId });
            }
            case "action list":
                options.Done(0);
                result = PublicActions;
                break;
            case "action send":
            {
                var rows = Select(options);
                bool wait = options.Flag("--wait");
                options.Done(1);
                string action = PublicActions.FirstOrDefault(value => value.Equals(options.Required(0), StringComparison.OrdinalIgnoreCase))
                    ?? throw new ArgumentException("未知操作。使用 action list 查看。");
                if (rows.Length != 1 || rows[0].Session is not { Active: true } session)
                    throw new InvalidOperationException("请选择正在运行任务的单个进程。");
                return await Work(id, wait, async () =>
                {
                    ActionResult performed = await session.RequestAction(action, automation.Token);
                    return (performed.Executed, performed);
                });
            }
            case "shutdown set":
            {
                bool wait = options.Flag("--wait");
                options.Done(1);
                if (!int.TryParse(options.Required(0), out int seconds) || seconds < 1)
                    throw new ArgumentException("倒计时需要正整数秒。");
                var task = automation.Countdown(seconds);
                return await Work(id, wait, async () =>
                {
                    ActionResult[] actions = await task;
                    return (actions.All(action => action.Executed), actions);
                }, new { seconds });
            }
            case "shutdown cancel":
                options.Done(0);
                await automation.Countdown(null);
                result = automation.Snapshot();
                break;
            case "character create":
            case "character preview":
            {
                int? target = options.Int("--pid");
                long? startTicks = options.Long("--start-ticks", 1);
                string? image = options.Value("--image");
                string? output = options.Value("--output");
                bool preview = command == "character preview";
                bool wait = options.Flag("--wait") || preview;
                options.Done(0);
                if (startTicks is not null && target is null)
                    throw new ArgumentException("--start-ticks 需要同时指定 --pid。");
                GameRow? row = target is null ? null : automation.Select(target, false, startTicks)[0];
                Task<CreationResult>? pending = null;
                await automation.Exclusive(() =>
                {
                    pending = automation.Creator.Start(row, image, preview, output);
                    return Task.FromResult(true);
                }, automation.Token);
                return await Work(id, wait, async () =>
                {
                    CreationResult outcome = await pending!;
                    if (outcome.State.Mode == "failed")
                        throw new InvalidOperationException(outcome.State.Message);
                    return (true, outcome);
                });
            }
            case "character stop":
                bool waitStop = options.Flag("--wait");
                options.Done(0);
                return await Work(id, waitStop, async () => { await automation.Creator.Stop(); return (true, automation.Creator.View); });
            case "audio preview":
                options.Done(2);
                if (!int.TryParse(options.Required(1), out int sample))
                    throw new ArgumentException("需要片段编号。");
                result = await desktop.AudioPreview(options.Required(0), sample);
                break;
            case "audio stop":
                options.Done(0);
                await desktop.AudioStop();
                result = null;
                break;
            case "screenshot select":
                bool waitShot = options.Flag("--wait");
                options.Done(0);
                return await Work(id, waitShot, async () => { bool copied = await desktop.Screenshot(); return (copied, new { copied }); });
            case "request get":
                options.Done(1);
                if (!Guid.TryParse(options.Required(0), out Guid lookup) || !jobs.TryGetValue(lookup, out var receipt))
                    throw new ArgumentException("未找到本次运行中的请求。");
                result = receipt;
                break;
            case "runtime close":
            case "runtime restart":
                options.Done(0);
                return Wire.Reply(id, "accepted", new { exit = true, restart = command == "runtime restart" });
            default:
                throw new ArgumentException("未知命令。使用 help 查看命令。");
        }
        return Wire.Reply(id, "completed", result);
    }

    private async Task<Response> Work(Guid id, bool wait, Func<Task<(bool Success, object? Result)>> perform, object? acceptance = null)
    {
        Response accepted = Wire.Reply(id, "accepted", acceptance);
        if (!jobs.TryAdd(id, accepted))
            return jobs[id];
        jobOrder.Enqueue(id);
        while (jobOrder.Count > 256 && jobOrder.TryDequeue(out Guid old))
            jobs.TryRemove(old, out _);
        Task<Response> completion = Complete();
        return wait ? await completion : accepted;

        async Task<Response> Complete()
        {
            Response reply;
            try
            {
                (bool success, object? data) = await perform();
                reply = success ? Wire.Reply(id, "completed", data) :
                    Wire.Reply(id, "failed", data) with { Code = "operation_failed", Error = "操作未完成，请查看结果和当前状态。" };
            }
            catch (Exception error) { reply = Failure(id, error); }
            jobs.TryUpdate(id, reply, accepted);
            return reply;
        }
    }

    private object ReadConfig(string path)
    {
        Configuration current = automation.Config;
        JsonNode? Read(Settings settings)
        {
            try { return SettingsJson.Get(SettingsJson.Tree(settings), path); }
            catch (ArgumentException) { return null; }
        }
        JsonNode? saved = Read(current.Saved), effective = Read(current.Effective);
        if (saved is null && effective is null)
            throw new ArgumentException($"配置路径不存在 {path}。");
        return new { current.Revision, path, saved, effective };
    }

    private static object[] Describe(Type type, string parent) => type.GetProperties().SelectMany(property =>
    {
        string name = parent.Length == 0 ? property.Name : $"{parent}.{property.Name}";
        var range = (RangeAttribute?)Attribute.GetCustomAttribute(property, typeof(RangeAttribute));
        Type child = property.PropertyType;
        if (child.IsArray || child.IsGenericType || child.IsValueType || child == typeof(string))
            return new object[] { new { path = name, type = child.Name, minimum = range?.Minimum, maximum = range?.Maximum, apply = ApplyMode(name) } };
        return Describe(child, name);
    }).ToArray();

    private static string ApplyMode(string path) => path.Split('.')[0] switch
    {
        "DirectModes" => "nextStart",
        "Rotation" or "Accounts" => "nextSelection",
        "Priorities" or "Operations" or "Tame" => "nextAction",
        _ => "live"
    };

    private GameRow[] Select(Arguments args) => automation.Select(args.Int("--pid"), args.Flag("--all"), args.Long("--start-ticks", 1));
    private static string? Mode(Arguments args)
    {
        string? mode = args.Value("--mode")?.ToLowerInvariant();
        if (mode is not null && !SettingsRules.Modes.Contains(mode))
            throw new ArgumentException("未知任务类型。");
        return mode;
    }

    private static SettingChange[] Changes(Arguments args) => args.Values("--set").Select(text =>
    {
        int split = text.IndexOf('=');
        if (split <= 0)
            throw new ArgumentException("--set 需要 PATH=VALUE。");
        return new SettingChange(text[..split], text[(split + 1)..]);
    }).ToArray();

    internal static Response Failure(Guid id, Exception error) => new(id,
        error is OperationCanceledException ? "cancelled" : "failed", Error: error.Message,
        Code: error is ArgumentException or JsonException ? "invalid_argument" : error is OperationCanceledException ? "cancelled" : "operation_failed");

    private static readonly string[] PublicActions =
    [
        "Fish.Cast", "Fish.Reel", "Fish.Item", "Fish.Jump", "Fight.Opening", "Fight.Combat", "Fight.Recover",
        "Fight.Buff", "Fight.Jump", "Fight.Interact", "Fight.Target", "Fight.MoveForward", "Fight.MoveBackward",
        "Fight.MoveLeft", "Fight.MoveRight", "Tame.Key", "Tame.Jump", "Rest.Jump", "Shop.Visit", "Shop.Close", "Shop.Jump"
    ];

    private sealed class Arguments
    {
        private static readonly HashSet<string> Flags = ["--wait", "--runtime", "--all", "--direct"];
        private readonly Dictionary<string, List<string>> options = new(StringComparer.Ordinal);
        private readonly List<string> positionals = [];

        public Arguments(IEnumerable<string> args)
        {
            using var iter = args.GetEnumerator();
            while (iter.MoveNext())
            {
                string token = iter.Current;
                if (token == "--")
                {
                    while (iter.MoveNext())
                        positionals.Add(iter.Current);
                    break;
                }
                if (!token.StartsWith("--", StringComparison.Ordinal))
                {
                    positionals.Add(token);
                    continue;
                }
                string value = "";
                if (!Flags.Contains(token))
                {
                    if (!iter.MoveNext())
                        throw new ArgumentException($"{token} 需要值。");
                    value = iter.Current;
                }
                if (!options.TryGetValue(token, out var items))
                    options[token] = items = [];
                items.Add(value);
            }
        }

        public string? At(int index) => index < positionals.Count ? positionals[index] : null;
        public string Required(int index) => At(index) ?? throw new ArgumentException("缺少命令参数。");
        public bool Flag(string name) => Value(name) is not null;
        public string[] Values(string name) => options.Remove(name, out List<string>? result) ? result.ToArray() : [];

        public string? Value(string name)
        {
            string[] values = Values(name);
            if (values.Length > 1)
                throw new ArgumentException($"{name} 只允许出现一次。");
            return values.FirstOrDefault();
        }

        public long? Long(string name, long minimum, long maximum = long.MaxValue)
        {
            string? value = Value(name);
            if (value is null)
                return null;
            return long.TryParse(value, out long parsed) && parsed >= minimum && parsed <= maximum ? parsed :
                throw new ArgumentException($"{name} 需要 {minimum} 至 {maximum} 范围内的整数。");
        }

        public int? Int(string name, int minimum = 1, int maximum = int.MaxValue) => (int?)Long(name, minimum, maximum);
        public bool? Bool(string name) => Value(name) switch
        {
            null => null, "true" => true, "false" => false, _ => throw new ArgumentException($"{name} 需要 true 或 false。")
        };

        public void Done(int min, int? max = null)
        {
            if (positionals.Count < min || positionals.Count > (max ?? min) || options.Count != 0)
                throw new ArgumentException($"命令参数不正确。{string.Join(' ', options.Keys)}");
        }
    }
}
