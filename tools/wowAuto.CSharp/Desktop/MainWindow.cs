using System.Globalization;
using System.Text.Json;
using WowAuto.Protocol;

namespace WowAuto.Desktop;

internal sealed partial class MainWindow : GrayForm
{
    private readonly Automation automation;
    private readonly CommandProcessor commands;
    private readonly DesktopServices desktop;
    private readonly GrayTabs tabs = Ui.Tabs(112);
    private readonly FlowLayoutPanel list = new()
    {
        Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false,
        AutoScroll = true, Padding = new(6, 0, 6, 0)
    };
    private readonly System.Windows.Forms.Timer timer = new();
    private readonly Dictionary<(int Pid, long Start), ProcessCard> cards = [];
    private TabPage processPage = null!;
    private Button refresh = null!, startAll = null!, stopAll = null!, settingsButton = null!, restart = null!, shutdown = null!;
    private Label count = null!, summary = null!;
    private bool scanning;
    private string? commandError;
    private long summaryRevision = -1;

    public MainWindow(Automation automation, CommandProcessor commands, DesktopServices desktop)
    {
        this.automation = automation;
        this.commands = commands;
        this.desktop = desktop;
        Text = "wowAuto";
        ClientSize = new(1330, 460);
        StartPosition = FormStartPosition.CenterScreen;
        SuspendLayout();
        tabs.Size = ClientSize;
        tabs.Dock = DockStyle.Fill;
        Controls.Add(tabs);
        var header = new Panel { Dock = DockStyle.Top, Height = 75 };
        Ui.Title(header, "wowAuto", 20, 14, 230, 45, 23);
        Controls.Add(header);
        BuildProcessPage();
        BuildCreationPage();
        BuildTamePage();
        ResumeLayout();
        list.SizeChanged += (_, _) => ResizeCards();
        Shown += (_, _) =>
        {
            Render();
            FitProcesses();
            timer.Start();
        };
        timer.Interval = automation.Config.Effective.Operations.UiRefreshMs;
        timer.Tick += (_, _) => Render();
    }

    private void BuildProcessPage()
    {
        processPage = Ui.Page(tabs, "进程任务", false);
        var toolbar = new Panel { Width = ClientSize.Width, Dock = DockStyle.Top, Height = 116, AutoScroll = true, BackColor = Ui.Surface };
        refresh = Ui.Button(toolbar, "刷新进程", 12, 10, 120, 35, () => Run(RefreshScan));
        startAll = Ui.Button(toolbar, "全部开始", 142, 10, 120, 35, () => Run(StartAll), true);
        stopAll = Ui.Button(toolbar, "全部停止", 272, 10, 120, 35,
            () => Run(() => Send("task", "stop", "--all", "--wait")));
        count = Ui.Label(toolbar, "", 410, 15, 245, 28);
        settingsButton = Ui.Button(toolbar, "设置", 665, 10, 110, 35, () => Run(() => OpenSettings()));
        restart = Ui.Button(toolbar, "重启客户端", 790, 10, 130, 35, () => Run(() => Send("runtime", "restart")));
        shutdown = Ui.Button(toolbar, "结束倒计时", 935, 10, 260, 35, () => Run(OpenCountdown));
        summary = Ui.Label(toolbar, "", 12, 56, 1250, 52);
        summary.AutoEllipsis = true;
        summary.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;

        var intro = new Label
        {
            Dock = DockStyle.Top, Height = 44, Padding = new(12, 12, 0, 0),
            Text = "每行通过角色编排设置名称和任务；“开始”按编排切换角色，“直接开始”留在当前角色执行已验证任务。"
        };
        var headings = new Panel { Dock = DockStyle.Top, Height = 32, BackColor = Ui.Heading };
        Ui.Label(headings, "游戏进程 / 版本 / 窗口位置", 12, 3, 360, 25);
        Ui.Label(headings, "操作", 386, 3, 310, 25);
        Ui.Label(headings, "实时状态（最新日志在上）", 716, 3, 350, 25);
        var footer = new Label
        {
            Dock = DockStyle.Bottom, Height = 48, Padding = new(12, 10, 0, 0),
            Font = new Font("Microsoft YaHei UI", 11),
            Text = "运行时自动切换窗口；各进程的检测结果和任务状态显示在右侧。"
        };
        footer.Disposed += (_, _) => footer.Font.Dispose();
        processPage.Controls.AddRange([list, headings, intro, toolbar, footer]);
    }

    private async Task RefreshScan()
    {
        scanning = true;
        try
        {
            Render();
            await Send("process", "scan");
            Render();
            FitProcesses();
        }
        finally { scanning = false; }
    }

    private async Task StartAll()
    {
        var rows = cards.Values.Where(card => card.CanStart)
            .Select(card => automation.Select(card.Identity.Pid, false, card.Identity.Start)[0]).ToArray();
        if (rows.Length > 0)
            await automation.Start(rows, null, false, null, false, automation.Token);
    }

    private async void Run(Func<Task> action, Action<string>? showError = null)
    {
        try
        {
            if (showError is null)
                commandError = null;
            await action();
        }
        catch (Exception error)
        {
            if (showError is null)
                commandError = error.Message;
            else
                showError(error.Message);
        }
        finally
        {
            if (!IsDisposed)
                Render();
        }
    }

    private async Task<Response> Execute(params string[] args)
    {
        Response response = await commands.Execute(new(Wire.Version, Guid.NewGuid(), args));
        if (response.State is "failed" or "cancelled")
            throw new InvalidOperationException(response.Error);
        return response;
    }

    private async Task Send(params string[] args)
    {
        Response response = await Execute(args);
        if (response.State == "accepted" && args is ["runtime", "close" or "restart"])
            desktop.RequestExit(args[1] == "restart");
    }

    private Task ForProcess((int Pid, long Start) identity, params string[] args) =>
        Send([.. args, "--pid", identity.Pid.ToString(CultureInfo.InvariantCulture),
            "--start-ticks", identity.Start.ToString(CultureInfo.InvariantCulture)]);

    private Task OpenSettings(ProcessView? row = null)
    {
        WithAutomationPaused(() =>
        {
            using var dialog = new SettingsWindow(automation, desktop, this, row);
            return dialog.ShowDialog(this);
        });
        return Task.CompletedTask;
    }

    private Task OpenCountdown()
    {
        RuntimeView state = automation.Snapshot();
        using var dialog = new GrayForm
        {
            Text = "结束倒计时", StartPosition = FormStartPosition.CenterParent, ClientSize = new(470, 180),
            FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false, MinimizeBox = false, ShowInTaskbar = false
        };
        Ui.Label(dialog, "多久后退出全部游戏（秒）", 18, 18, 430, 30);
        long remaining = state.ShutdownRemainingMs is { } ms ? Math.Max(1, (ms + 999) / 1000) : 3600;
        var seconds = Ui.Number(dialog, remaining, 1, int.MaxValue, 18, 55, 430);
        var start = Ui.Button(dialog, "开始倒计时", 18, 116, 140, 38, accent: true);
        var cancel = Ui.Button(dialog, "取消倒计时", 168, 116, 140, 38);
        var back = Ui.Button(dialog, "返回", 318, 116, 130, 38);
        start.DialogResult = DialogResult.OK;
        cancel.DialogResult = DialogResult.Yes;
        cancel.Enabled = state.ShutdownAt is not null;
        back.DialogResult = DialogResult.Cancel;
        dialog.AcceptButton = start;
        dialog.CancelButton = back;
        return WithAutomationPaused(() => dialog.ShowDialog(this)) switch
        {
            DialogResult.OK => Send("shutdown", "set", seconds.Value.ToString(CultureInfo.InvariantCulture)),
            DialogResult.Yes => Send("shutdown", "cancel"),
            _ => Task.CompletedTask
        };
    }

    private DialogResult WithAutomationPaused(Func<DialogResult> show)
    {
        bool wasPaused = automation.Hub.Paused;
        try
        {
            if (!automation.Hub.PauseAndWait(3000))
                throw new InvalidOperationException("当前操作仍在收尾，请稍后重试。");
            return show();
        }
        finally
        {
            automation.Hub.Paused = wasPaused;
            automation.Hub.Wake.Set();
        }
    }

    private void Render()
    {
        RuntimeView state = automation.Snapshot();
        Configuration configuration = automation.Config;
        Settings effective = configuration.Effective;
        if (timer.Interval != effective.Operations.UiRefreshMs)
            timer.Interval = effective.Operations.UiRefreshMs;
        bool blocked = scanning || state.ShuttingDownGames || automation.Creator.Active;
        processPage.Enabled = !state.ShuttingDownGames && !automation.Creator.Active;
        bool canStart = !blocked && state.ShutdownAt is null;
        foreach (var key in cards.Keys.Except(state.Processes.Select(item => (item.Pid, item.StartTicks))).ToArray())
        {
            cards[key].Panel.Dispose();
            cards.Remove(key);
        }
        for (int i = 0; i < state.Processes.Length; i++)
        {
            ProcessView process = state.Processes[i];
            var key = (process.Pid, process.StartTicks);
            if (!cards.TryGetValue(key, out ProcessCard? card))
            {
                card = new(this, key);
                cards.Add(key, card);
                list.Controls.Add(card.Panel);
                card.Panel.Scale(new SizeF(DeviceDpi / 96f, DeviceDpi / 96f));
                list.Controls.SetChildIndex(card.Panel, i);
                ResizeCards();
            }
            card.Render(process, configuration, state.Now, canStart, !blocked);
        }
        Ui.SetText(count, $"进程 {state.Processes.Length} · 验证通过 {state.Processes.Count(p => p.Phase is "ready" or "running")}");
        refresh.Enabled = canStart;
        settingsButton.Enabled = !blocked;
        restart.Enabled = !state.ShuttingDownGames;
        shutdown.Enabled = !blocked;
        startAll.Enabled = cards.Values.Any(card => card.CanStart);
        stopAll.Enabled = !state.ShuttingDownGames && (scanning || state.Processes.Any(IsBusy));
        Ui.SetText(shutdown, state.ShutdownRemainingMs is { } remaining ? $"倒计时：{(remaining + 999) / 1000}秒" : "结束倒计时");
        if (summaryRevision != configuration.Revision || commandError is not null || state.LogError is not null || summary.Tag is true)
        {
            summaryRevision = configuration.Revision;
            FishFlavor titan = effective.Fish.Titan, forever = effective.Fish.Forerver;
            string? error = commandError ?? state.LogError;
            summary.Tag = error is not null;
            Ui.SetText(summary, error ??
                $"收杆延迟区间（ms）：时光服 {titan.MinimumMs}–{titan.MaximumMs}；无限服 {forever.MinimumMs}–{forever.MaximumMs}；无咬钩保护（ms）：时光服 {titan.AudioTimeoutMs} / 无限服 {forever.AudioTimeoutMs}；焦点重试 {effective.Operations.FocusRetryMs}。\r\n" +
                $"音频门槛：时光服 {titan.AudioThresholdPercent}% / 无限服 {forever.AudioThresholdPercent}%；片段：时光服 {titan.AudioRecordingId} / 无限服 {forever.AudioRecordingId}；定期跳跃 {effective.Fish.JumpEveryCycles} 次（0关闭）；界面日志 {effective.StatusLogLimit} 条；文件日志上限 {effective.LogMaxSizeMB} MB。");
        }
        RenderTaskPages(state, configuration);
    }

    private static bool IsBusy(ProcessView process) => process.Phase is "running" or "starting" or "switching" or "scanning";
    private int Px(int value) => (int)Math.Round(value * DeviceDpi / 96.0);

    private void ResizeCards()
    {
        int width = Math.Max(Px(1170), list.ClientSize.Width - Px(32));
        foreach (ProcessCard card in cards.Values)
            card.Panel.Width = width;
    }

    private void FitProcesses()
    {
        var area = Screen.FromControl(this).WorkingArea;
        int rows = cards.Values.Sum(card => card.Panel.Height + card.Panel.Margin.Vertical);
        int chrome = Height - list.ClientSize.Height;
        MinimumSize = new(Math.Min(Px(1330), area.Width), Math.Min(Px(300), area.Height));
        Size = new(Math.Min(Px(1330) + Width - ClientSize.Width, area.Width),
            Math.Min(chrome + Math.Max(Px(80), rows + Px(12)), area.Height));
        Location = new(area.Left + (area.Width - Width) / 2, area.Top + (area.Height - Height) / 2);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
            timer.Dispose();
        base.Dispose(disposing);
    }

    private sealed class ProcessCard
    {
        private readonly MainWindow owner;
        private readonly Label name, account, roles, progress;
        private readonly Button start, direct, stop, configure;
        private readonly ComboBox mode;
        private readonly StatusLog status;
        private ProcessView process = null!;
        private string? error;
        private string? lastMessage;
        private long configRevision = -1;
        private string? accountKey;
        private bool hasConfiguredRoles;
        private string configuredRoleSummary = "";
        private object? previousMetrics;
        private JsonElement metrics;
        public (int Pid, long Start) Identity { get; }
        public Panel Panel { get; } = new() { Size = new(1170, 224), Margin = new(0, 0, 0, 6), BackColor = Ui.Surface };
        public bool CanStart => start.Enabled;

        public ProcessCard(MainWindow owner, (int Pid, long Start) identity)
        {
            this.owner = owner;
            Identity = identity;
            name = Ui.Label(Panel, "", 6, 20, 360, 70);
            name.AutoEllipsis = true;
            start = Ui.Button(Panel, "开始", 380, 33, 68, 40, () => Run("task", "start"), true);
            mode = Ui.Choice(Panel, 454, 38, 76);
            mode.AccessibleName = "直接开始的任务";
            mode.Items.AddRange(Ui.DirectModes.Select(item => (object)item.Label).ToArray());
            mode.SelectionChangeCommitted += (_, _) => SaveMode();
            direct = Ui.Button(Panel, "直接开始", 536, 33, 94, 40, () => Run("task", "start", "--mode", SelectedMode), true);
            stop = Ui.Button(Panel, "停止", 636, 33, 68, 40, () => Run("task", "stop", "--wait"));
            Ui.Label(Panel, "子战网", 12, 106, 90, 28);
            account = Ui.Label(Panel, "", 110, 106, 400, 28);
            account.AutoEllipsis = true;
            configure = Ui.Button(Panel, "配置角色任务", 520, 102, 178, 34, () => owner.Run(() => owner.OpenSettings(process), SetError));
            roles = Ui.Label(Panel, "", 12, 146, 686, 34);
            roles.AutoEllipsis = true;
            progress = Ui.Label(Panel, "", 12, 192, 686, 26);
            progress.AutoEllipsis = true;
            status = Ui.Place(Panel, new StatusLog(), 710, 12, 448, 212);
            status.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
        }

        private void SetError(string message) => error = message;
        private string SelectedMode => mode.SelectedIndex == Ui.DirectModes.Length ? "tame" : Ui.DirectModes[mode.SelectedIndex].Id;

        private void Run(params string[] args)
        {
            error = null;
            owner.Run(() => owner.ForProcess(Identity, args), SetError);
        }

        private void SaveMode()
        {
            try
            {
                Configuration configuration = owner.automation.Config;
                owner.automation.Configure([new($"DirectModes.{Identity.Pid}:{Identity.Start}", SelectedMode)],
                    false, configuration.Revision);
                error = null;
            }
            catch (Exception failure) { SetError(failure.Message); }
            owner.Render();
        }

        public void Render(ProcessView current, Configuration configuration, long now, bool canStart, bool canConfigure)
        {
            process = current;
            Settings settings = configuration.Effective;
            bool busy = IsBusy(current);
            bool rotating = busy && !current.Direct && current.Phase != "scanning";
            string? key = current.Account is { Length: > 0 } ? $"{current.Flavor}:{current.Account}" : null;
            if (configRevision != configuration.Revision || accountKey != key)
            {
                configRevision = configuration.Revision;
                accountKey = key;
                RoleSettings[] enabledRoles = key is not null && settings.Accounts.TryGetValue(key, out RoleSettings[]? configured)
                    ? configured.Where(item => item.Enabled).ToArray() : [];
                hasConfiguredRoles = settings.Accounts.Any(item => item.Key.StartsWith(current.Flavor + ":", StringComparison.Ordinal) &&
                    item.Value.Any(role => role.Enabled));
                configuredRoleSummary = $"启用 {enabledRoles.Length} 个角色：" +
                    string.Join("、", enabledRoles.Select(item => $"{item.Name}-{item.Realm} / {Ui.ModeLabel(item.Mode)}"));
            }
            string modeId = settings.DirectModes.GetValueOrDefault($"{current.Pid}:{current.StartTicks}", "fish");
            int selected;
            if (modeId.Equals("tame", StringComparison.OrdinalIgnoreCase))
            {
                selected = Ui.DirectModes.Length;
                if (mode.Items.Count == selected)
                    mode.Items.Add("抓宠");
            }
            else
            {
                if (mode.Items.Count > Ui.DirectModes.Length)
                    mode.Items.RemoveAt(Ui.DirectModes.Length);
                selected = Array.FindIndex(Ui.DirectModes, item => item.Id.Equals(modeId, StringComparison.OrdinalIgnoreCase));
            }
            if (mode.SelectedIndex != selected)
                mode.SelectedIndex = selected;
            start.Enabled = canStart && !busy && hasConfiguredRoles;
            mode.Enabled = canStart && !busy;
            direct.Enabled = mode.Enabled && selected >= 0;
            stop.Enabled = busy;
            configure.Enabled = canConfigure;

            if (!ReferenceEquals(previousMetrics, current.Metrics))
            {
                previousMetrics = current.Metrics;
                metrics = JsonSerializer.SerializeToElement(current.Metrics, Wire.Json);
            }
            var character = Ui.Class((int?)Number("classId"));
            name.ForeColor = progress.ForeColor = character.Color;
            string position = string.IsNullOrWhiteSpace(current.Position) ? "位置未知" : current.Position;
            string caption = current.Flavor == "titan" ? "WowClassic.exe" : "Wow.exe";
            Ui.SetText(name, $"{caption}\r\nPID {current.Pid} · {Ui.FlavorLabel(current.Flavor)} · {position}" + (current.Mode switch
            {
                "fish" or null => $"\r\n循环 {current.Cycles} · 无咬钩超时 {current.BiteTimeouts}",
                "shop" => "\r\n购物",
                "rest" when Number("round") is { } round && Number("rounds") is { } rounds => $"\r\n放号轮次 {round} / {rounds}",
                _ => ""
            }));
            Ui.SetText(account, current.Account ?? (rotating ? "识别中（等待选角界面）" : "未识别（开始任务后自动识别）"));
            Ui.SetText(roles, key is null ? "开始任务后通过选角页角色名识别子战网，并加载该子战网角色任务。" :
                configuredRoleSummary);
            string remaining = !busy ? "--" : current.Phase == "switching" ? "角色切换中" :
                current.Mode is "rest" or "shop" && current.Deadline is { } end ? Seconds(end, now) :
                current.Mode == "rest" && Number("remaining") is { } rest ? $"{Math.Ceiling(rest / 1000)}秒" :
                current.Direct ? "直接开始" : current.RotationDueAt is { } due ? Seconds(due, now) : "未启用定时轮转";
            string? roleName = current.Phase == "switching" ? current.TargetRole : current.Role;
            string role = !busy ? "未运行" : roleName is { Length: > 0 } activeRole
                ? (current.Phase == "switching" ? "切换至" : "") + activeRole
                : current.Direct ? "当前已登录角色" : "确认中";
            Ui.SetText(progress, $"当前角色：{role}   剩余时间：{remaining}   切换：{current.RotationSwitches}次");

            string detail = current.Deadline > now && current.Phase == "running"
                ? "\r\n剩余 " + (current.Mode == "rest" ? Seconds(current.Deadline.Value, now) : $"{current.Deadline - now} ms") : "";
            if (Number("stateDue") is { } stateDue && stateDue > now && current.Deadline > stateDue)
                detail += $"\r\n{(String("state") == "open" ? "关店" : "开店")}倒计时 {stateDue - now:0} ms";
            if (Number("similarity") is { } similarity && Number("peak") is { } peak)
                detail += $"\r\n音频匹配 {similarity:P0} · 峰值 {peak:F3}";
            if (lastMessage != current.Message)
            {
                if (lastMessage is not null)
                    error = null;
                lastMessage = current.Message;
            }
            status.ShowStatus(error ?? current.Message, settings.StatusLogLimit, detail);
        }

        private double? Number(string key) => metrics.ValueKind == JsonValueKind.Object &&
            metrics.TryGetProperty(key, out JsonElement value) && value.ValueKind == JsonValueKind.Number ? value.GetDouble() : null;

        private string? String(string key) => metrics.ValueKind == JsonValueKind.Object &&
            metrics.TryGetProperty(key, out JsonElement value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

        private static string Seconds(long due, long now) => $"{Math.Max(0, (due - now + 999) / 1000)}秒";
    }
}
