using System.Diagnostics;

namespace WowAuto.Desktop;

internal sealed partial class SettingsWindow : GrayForm
{
    private const int DesignWidth = 1424;
    private readonly Automation automation;
    private readonly DesktopServices desktop;
    private readonly GrayTabs tabs = Ui.Tabs(150);
    private readonly TabPage accountsPage;
    private readonly AccountsEditor accounts;
    private readonly List<SettingsDraft> drafts = [];
    private TabPage fishPage = null!;
    private Label audioPreviewStatus = null!;
    private bool previewing;
    private readonly System.Windows.Forms.Timer previewTimer = new() { Interval = 1000 };

    public SettingsWindow(Automation automation, DesktopServices desktop, Form owner, ProcessView? process)
    {
        this.automation = automation;
        this.desktop = desktop;
        Text = "wowAuto · 设置";
        StartPosition = FormStartPosition.CenterParent;
        ClientSize = Ui.Size(DesignWidth, 934);
        MinimumSize = Ui.Size(700, 500);
        FitOnOwnerScreen(owner);
        tabs.Multiline = true;
        tabs.Size = ClientSize;
        tabs.Dock = DockStyle.Fill;
        Controls.Add(tabs);
        BuildRotationBar();
        BuildFishPage();
        BuildFightPage();
        BuildDirectories();
        BuildScreenshot();
        accountsPage = Ui.Page(tabs, "子战网");
        accounts = new(accountsPage, automation, process);
        BuildRestPage();
        BuildShopPage();
        BuildTimingPages();
        tabs.SelectedIndexChanged += (_, _) =>
        {
            if (tabs.SelectedTab != fishPage)
                StopAudioPreview();
            foreach (SettingsDraft draft in drafts)
                draft.Refresh(automation.Config);
            if (Visible && tabs.SelectedTab == accountsPage)
                _ = accounts.LoadAsync();
        };
        Shown += (_, _) =>
        {
            if (tabs.SelectedTab == accountsPage)
                _ = accounts.LoadAsync();
        };
        previewTimer.Tick += (_, _) => StopAudioPreview();
        if (process is not null)
            tabs.SelectedTab = accountsPage;
        CompleteLayout();
    }

    private SettingsDraft Draft()
    {
        var draft = new SettingsDraft(automation);
        drafts.Add(draft);
        return draft;
    }

    private void BuildRotationBar()
    {
        var draft = Draft();
        var bar = new Panel { Height = Ui.Length(62), Dock = DockStyle.Top, AutoScroll = true, BackColor = Ui.Surface };
        Controls.Add(bar);
        Ui.Label(bar, "全局角色轮换（秒，0关闭）", 12, 12, 285, 30);
        draft.Number(bar, "Rotation.IntervalSeconds", 300, 8, 130, 0, int.MaxValue);
        Label status = Ui.Label(bar, "", 635, 12, 330, 32);
        Ui.Button(bar, "保存全局设置", 450, 8, 170, 34, () => draft.SaveWithFeedback(status, "已保存。"));
    }

    private void BuildDirectories()
    {
        var draft = Draft();
        TabPage page = Ui.Page(tabs, "游戏目录");
        Ui.Label(page, @"选择客户端目录，或包含客户端的魔兽世界总目录。读取 WTF\Account 下的子战网及插件角色记录；开始任务后识别进程所属的子战网。",
            20, 20, 920, 70);
        for (int index = 0; index < Ui.Clients.Length; index++)
        {
            var (flavor, label) = Ui.Clients[index];
            string path = index == 0 ? "Rotation.TitanDirectory" : "Rotation.ForerverDirectory";
            int y = 110 + index * 95;
            Ui.Label(page, label + "目录", 20, y, 140, 32);
            TextBox input = draft.Text(page, path, 165, y, 620, value => ResolveDirectory(value, flavor));
            Ui.Button(page, "浏览", 805, y, 100, 34, () =>
            {
                using var picker = new FolderBrowserDialog { SelectedPath = input.Text };
                if (picker.ShowDialog(this) == DialogResult.OK)
                    input.Text = picker.SelectedPath;
            });
        }
        Label status = Ui.Label(page,
            "角色列表只显示有插件保存记录的角色。上线和下线都会采集资料，无需启动检测；正常下线或 /reload 落盘后再刷新。等级与背包空格为最近保存快照。留空可停用该版本的目录扫描。",
            20, 305, 900, 110);
        Ui.Button(page, "保存游戏目录", 20, 440, 180, 38, () =>
            draft.SaveWithFeedback(status, "游戏目录已保存。", accounts.InvalidateCatalog), true);
    }

    private static string ResolveDirectory(string value, string flavor)
    {
        string input = value.Trim();
        if (input.Length == 0)
            return "";
        if (!Path.IsPathFullyQualified(input))
            throw new ArgumentException("游戏目录须为绝对路径。");
        string full = Path.TrimEndingDirectorySeparator(Path.GetFullPath(input));
        string[] products = flavor == "titan" ? ["_classic_titan_"] : ["_forever_", "_cn_beta_"];
        string exeName = flavor == "titan" ? "WowClassic.exe" : "Wow.exe";
        if (!products.Contains(Path.GetFileName(full), StringComparer.OrdinalIgnoreCase))
            full = products.Select(product => Path.Combine(full, product)).FirstOrDefault(path => File.Exists(Path.Combine(path, exeName)))
                ?? Path.Combine(full, products[0]);
        string exe = Path.Combine(full, exeName);
        if (!File.Exists(exe))
            throw new ArgumentException($"目录内没有对应客户端：{exe}");
        if (WowAuto.NativeInput.GetClientFlavor(exe, FileVersionInfo.GetVersionInfo(exe).FileVersion) != flavor)
            throw new ArgumentException("游戏目录与所选版本不符。");
        return full;
    }

    private void BuildScreenshot()
    {
        var draft = Draft();
        TabPage page = Ui.Page(tabs, "截图");
        Ui.Label(page, "全局截图组合键", 18, 24, 260, 30);
        KeyBox key = draft.Key(page, "ScreenshotKey", 18, 62, 300, "已停用");
        key.Enter += (_, _) => desktop.EditingScreenshotKey = true;
        key.Leave += (_, _) => desktop.EditingScreenshotKey = false;
        Ui.Button(page, "停用", 334, 60, 100, 36, () => key.Binding = "");
        Ui.Label(page, "点击输入框后按下包含 Ctrl 或 Alt 的组合键，默认 Ctrl+Alt+A。\r\n" +
            "按热键后拖动鼠标框选，松开鼠标复制到剪贴板，可直接 Ctrl+V 粘贴。\r\nEsc 或右键取消。框选期间暂停自动操作，结束后恢复。",
            18, 116, 900, 110);
        string Registration() => desktop.ScreenshotStatus;
        Label status = Ui.Label(page, Registration(), 18, 240, 900, 90);
        Ui.Button(page, "保存截图设置", 18, 346, 220, 38, () =>
        {
            try { draft.Save(); status.Text = "已保存，" + Registration(); }
            catch (Exception error) { status.Text = error.Message; }
        }, true);
    }

    private void BuildRestPage()
    {
        var draft = Draft();
        TabPage page = Ui.Page(tabs, "放号");
        Ui.Label(page, "「直接开始」只在当前角色放号，单次倒计时结束后停止本行。确认放号色块后按间隔跳跃。\r\n" +
            "无限服可在子战网配置放号角色，通过「开始」按编排轮次执行。", 18, 18, 1000, 100);
        (string Id, string Label)[] fields = [("DurationSeconds", "单次时间（秒）"), ("Rounds", "编排轮次"), ("JumpIntervalSeconds", "跳跃间隔（秒）")];
        for (int index = 0; index < fields.Length; index++)
        {
            int y = 138 + index * 56;
            Ui.Label(page, fields[index].Label, 18, y, 300, 32);
            draft.Number(page, "Rest." + fields[index].Id, 330, y - 2, 240, 1, int.MaxValue);
        }
        Label status = Ui.Label(page, "", 18, 330, 1000, 70);
        Ui.Button(page, "保存放号设置", 18, 418, 220, 38,
            () => draft.SaveWithFeedback(status, "放号设置已保存。"), true);
    }

    private void BuildShopPage()
    {
        var draft = Draft();
        TabPage page = Ui.Page(tabs, "购物");
        Ui.Label(page, "在游戏插件「游戏辅助 → 自动购物」保存物品 ID 和背包上限。选中附近的商人后，在进程行选择「购物」并点击「直接开始」，也可把「购物」设为角色任务。",
            18, 18, 1000, 66);
        const long maxDelay = 1000L * int.MaxValue;
        (string Id, string Label, long Min, long Max)[] fields =
        [
            ("ReopenDelayMs", "关闭后再打开（毫秒）", 1, maxDelay), ("CloseDelayMs", "打开后关闭（毫秒）", 1, maxDelay),
            ("JitterMs", "随机浮动（毫秒）", 0, maxDelay), ("JumpIntervalSeconds", "跳跃间隔（秒，0 关闭额外跳跃）", 0, int.MaxValue),
            ("DurationSeconds", "最大购物时长（秒）", 1, int.MaxValue)
        ];
        int y = 92;
        foreach (var (id, label, min, max) in fields)
        {
            Ui.Label(page, label, 18, y, 300, 34);
            draft.Number(page, "Shop." + id, 330, y, 240, min, max);
            y += 56;
        }
        Ui.Label(page, "与目标互动键", 18, y, 300, 34);
        draft.Key(page, "Shop.InteractKey", 330, y, 240);
        draft.Check(page, "Shop.JumpOnVisit", "每次开店时自动跳跃", 18, y + 44, 470);
        Label status = Ui.Label(page, "", 18, y + 88, 1000, 52);
        Ui.Button(page, "保存购物设置", 18, y + 146, 220, 38,
            () => draft.SaveWithFeedback(status, "购物设置已保存，下次开始购物时生效。"), true);
    }

    private void BuildTimingPages()
    {
        TabPage page = Ui.Page(tabs, "检测与操作", false);
        var timing = Ui.Tabs(180);
        timing.Dock = DockStyle.Fill;
        page.Controls.Add(timing);
        BuildDetection(Ui.Page(timing, "检测周期"));
        BuildOperations(Ui.Page(timing, "操作队列"));
    }

    private void BuildDetection(TabPage page)
    {
        var draft = Draft();
        Ui.Label(page, "全局设置：对两服所有进程生效，单位为毫秒（ms）。保存后关闭设置窗口，新周期用于后续检测。",
            18, 18, 920, 60);
        GroupBox group = Ui.Group(page, "检测周期（ms，25–60000）", 18, 94, 920, 482);
        (string Path, string Label)[] fields =
        [
            ("FishMs", "钓鱼色块"), ("FightMs", "战斗色块"), ("MenuMs", "选角画面"), ("LoginMs", "登录确认 / 退出检查"),
            ("BaitMs", "钓鱼道具"), ("DeathMs", "角色死亡"), ("AudioMs", "音频状态检查"), ("PositionMs", "窗口位置"),
            ("CaptureRetryMs", "画面等待重试"), ("OcrMs", "OCR采样")
        ];
        for (int i = 0; i < fields.Length; i++)
        {
            int x = 20 + i % 2 * 450;
            int y = 44 + i / 2 * 86;
            Ui.Label(group, fields[i].Label, x, y, 245, 30);
            draft.Number(group, "Periods." + fields[i].Path, x + 250, y - 3, 175, 25, 60000, 25);
        }
        Label status = Ui.Label(page, "", 18, 598, 920, 56);
        Ui.Button(page, "保存检测周期", 18, 674, 210, 36, () => draft.SaveWithFeedback(status, "全局检测周期已保存。"), true);
    }

    private void BuildOperations(TabPage page)
    {
        var draft = Draft();
        Ui.Label(page, "两服所有进程共用，单位为毫秒（ms）。保存并关闭设置后用于后续操作；已提交的操作保留原参数。",
            18, 12, 1280, 36);
        (string Group, (string Path, string Label, int Min, int Max)[] Fields)[] sections =
        [
            ("线程与界面", [("OperatorIdleMs", "操作线程空闲检查", 1, 1000), ("CommandReceiveMs", "检测线程接收命令", 1, 1000),
                ("ReplyCheckMs", "等待回执的取消检查", 1, 1000), ("WaitCheckMs", "操作等待的取消检查", 1, 1000),
                ("DetectorWaitMs", "检测等待检查间隔", 1, 1000), ("UiRefreshMs", "界面消息刷新", 10, 1000)]),
            ("前台与重试", [("ForegroundSettleMs", "前台稳定等待", 0, 5000), ("ForegroundRetryMs", "普通动作前台重试", 1, 60000),
                ("ForegroundTimeoutMs", "普通动作前台超时", 1, 60000), ("RotationFocusRetryMs", "换角前台重试", 1, 60000),
                ("RotationFocusTimeoutMs", "换角前台超时", 1, 60000), ("FocusRetryMs", "前台失败后的操作重试", 1000, 3600000)]),
            ("按键与动作等待", [("KeyPressMs", "普通按键按下时长", 1, 5000), ("ChatKeyPressMs", "聊天及方向键按下时长", 1, 5000),
                ("CommandIntervalMs", "战斗公共最小按键间隔", 100, 60000), ("ReelHoldMs", "收竿后等待", 0, 60000),
                ("ItemHoldMs", "钓鱼道具后等待", 0, 4000), ("InteractionHoldMs", "拾取 / 剥皮交互后等待", 1000, 60000)]),
            ("点击与画面重试", [("ClickMinMs", "三连击随机间隔下限", 1, 2000), ("ClickMaxMs", "三连击随机间隔上限", 1, 2000),
                ("ClickGuardMs", "三连击后跨进程保护", 0, 60000), ("CaptureRetryMs", "操作线程新帧重试", 1, 60000),
                ("FishColorRetryMs", "钓鱼检测关闭或颜色未知后重试", 1000, 60000)])
        ];
        int y = 54;
        foreach (var (name, fields) in sections)
        {
            int height = 42 + (fields.Length + 1) / 2 * 40;
            GroupBox group = Ui.Group(page, name + "（ms）", 18, y, 1280, height);
            for (int i = 0; i < fields.Length; i++)
            {
                var (path, label, min, max) = fields[i];
                int x = 18 + i % 2 * 630;
                int row = 30 + i / 2 * 40;
                Ui.Label(group, label, x, row, 390, 30);
                draft.Number(group, "Operations." + path, x + 395, row - 2, 200, min, max);
            }
            y += height + 12;
        }
        Label status = Ui.Label(page, "", 18, y, 1280, 42);
        Ui.Button(page, "保存操作队列设置", 18, y + 48, 230, 36,
            () => draft.SaveWithFeedback(status, "操作队列设置已保存。"), true);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            StopAudioPreview();
            desktop.EditingScreenshotKey = false;
            previewTimer.Dispose();
        }
        base.Dispose(disposing);
    }
}
