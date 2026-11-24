using System.Globalization;
using System.Text.Json;
using WowAuto.Protocol;

namespace WowAuto.Desktop;

internal sealed partial class MainWindow
{
    private TabPage creationPage = null!, tamePage = null!;
    private ComboBox creationWindows = null!, tameWindows = null!;
    private TextBox titleFilter = null!, creationLog = null!;
    private NumericUpDown createInterval = null!;
    private CheckBox createAutoStop = null!, createDryRun = null!;
    private Button createStart = null!, createStop = null!, previewGame = null!, previewFile = null!, tameStart = null!, tameStop = null!;
    private Control[] creationInputs = [];
    private Label creationStatus = null!, creationCounts = null!, tameStatus = null!, tameFeedback = null!;
    private SettingsDraft creationDraft = null!, tameDraft = null!;
    private bool f8;
    private string? creationMessage;
    private ProcessChoice[] creationChoices = [], tameChoices = [];

    private void BuildCreationPage()
    {
        creationPage = Ui.Page(tabs, "角色创建");
        creationPage.AutoScrollMinSize = new(1185, 600);
        creationDraft = new(automation);
        Ui.Title(creationPage, "角色创建 · 自动重试", 20, 15, 1100, 38, 18);
        Ui.Label(creationPage, "先选好外观并填写姓名。等待间隔 → 红色“完成” → 阵营人口不平衡时点击“确定” → 重新等待。",
            20, 58, 1150, 30);
        Ui.Label(creationPage, "标题包含", 20, 102, 85, 28);
        titleFilter = creationDraft.Text(creationPage, "CharacterCreate.TitleFilter", 105, 100, 160);
        var refreshWindows = Ui.Button(creationPage, "刷新窗口", 280, 96, 100, 36, () => Run(RefreshCreationWindows, WriteCreation));
        creationWindows = Ui.Choice(creationPage, 395, 100, 770);
        Ui.Label(creationPage, "重试间隔（秒，1–86400）", 20, 151, 230, 28);
        createInterval = creationDraft.Number(creationPage, "CharacterCreate.IntervalSeconds", 260, 148, 140, 1, 86400, places: 1);
        createAutoStop = creationDraft.Check(creationPage, "CharacterCreate.AutoStop", "连续12秒找不到红色“完成”时自动停止", 20, 198, 570);
        createDryRun = creationDraft.Check(creationPage, "CharacterCreate.DryRun", "试运行：识别和记录，不点击", 615, 198, 550);
        createStart = Ui.Button(creationPage, "开始 F8", 20, 245, 155, 38, () => Run(StartCreation, WriteCreation), true);
        createStop = Ui.Button(creationPage, "停止 F9", 190, 245, 155, 38, () => Run(StopCreation, WriteCreation));
        previewGame = Ui.Button(creationPage, "仅识别游戏", 360, 245, 155, 38, () => Run(() => Preview(null), WriteCreation));
        previewFile = Ui.Button(creationPage, "从图片测试", 530, 245, 155, 38, () => Run(PickPreviewFile, WriteCreation));
        creationStatus = Ui.Label(creationPage, "就绪。首次点击前等待完整间隔；提前最多3秒切换前台，失败3次跳过本轮。",
            20, 300, 1145, 48);
        creationCounts = Ui.Label(creationPage, "", 20, 352, 1145, 30);
        creationLog = Ui.Place(creationPage, new TextBox
        {
            Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical,
            BackColor = Ui.Input, ForeColor = Ui.Text, BorderStyle = BorderStyle.FixedSingle
        }, 20, 395, 1145, 190);
        creationPage.Resize += (_, _) =>
        {
            creationWindows.Width = Math.Max(Px(770), creationPage.ClientSize.Width - Px(415));
            creationStatus.Width = creationLog.Width = Math.Max(Px(1145), creationPage.ClientSize.Width - Px(40));
            creationLog.Height = Math.Max(Px(190), creationPage.ClientSize.Height - Px(415));
        };
        creationInputs = [titleFilter, refreshWindows, creationWindows, createInterval, createAutoStop, createDryRun];
    }

    private void BuildTamePage()
    {
        tamePage = Ui.Page(tabs, "自动抓宠");
        tamePage.AutoScrollMinSize = new(900, 716);
        tameDraft = new(automation);
        Ui.Title(tamePage, "自动抓宠", 20, 16, 850, 36, 18);
        Ui.Label(tamePage, "插件 /pettamer 设置名单并保存。匹配当前目标后，按陷阱 → 开怪 → 后退 → 捕捉执行。",
            20, 62, 850, 32);
        (string Stage, string Label)[] stages =
            [("Trap", "陷阱（可选）"), ("Opening", "开怪（可选）"), ("Backward", "后退（可选）"), ("Tame", "捕捉（必选）")];
        for (int i = 0; i < stages.Length; i++)
        {
            var (stage, label) = stages[i];
            int y = 110 + i * 52;
            Ui.Label(tamePage, label, 20, y, 130, 32);
            KeyBox key = tameDraft.Key(tamePage, $"Tame.{stage}Key", 155, y, 170);
            Ui.Button(tamePage, "清空", 335, y, 64, 32, () => key.Binding = "");
            Ui.Label(tamePage, stage == "Tame" ? "执行时长 / 重试间隔（秒）" : "执行后等待（秒）", 420, y, 230, 32);
            tameDraft.Number(tamePage, $"Tame.{stage}WaitMs", 660, y, 110,
                stage == "Tame" ? 0.1m : 0, 600, 0.1m, 3, 1000);
        }
        Ui.Label(tamePage, "后退按住时长（秒，0 为短按）", 20, 326, 310, 32);
        tameDraft.Number(tamePage, "Tame.BackwardHoldMs", 335, 326, 110, 0, 60, 0.1m, 3, 1000);
        Ui.Label(tamePage, "自动跳跃", 20, 374, 130, 32);
        KeyBox jump = tameDraft.Key(tamePage, "Tame.JumpKey", 155, 374, 170);
        Ui.Button(tamePage, "清空", 335, 374, 64, 32, () => jump.Binding = "");
        Ui.Label(tamePage, "跳跃间隔（秒，0 关闭）", 420, 374, 230, 32);
        tameDraft.Number(tamePage, "Tame.JumpIntervalSeconds", 660, 374, 110, 0, 3600);
        Ui.Label(tamePage, "后退松键后计算阶段等待。跳跃到期会等当前阶段结束，跳完等待1秒再继续抓宠。",
            20, 422, 860, 48);
        tameFeedback = Ui.Label(tamePage, "", 200, 480, 650, 44);
        Ui.Button(tamePage, "保存抓宠设置", 20, 476, 160, 36, () =>
            tameDraft.SaveWithFeedback(tameFeedback, "抓宠设置已保存。"));
        tameWindows = Ui.Choice(tamePage, 20, 546, 540);
        tameStart = Ui.Button(tamePage, "开始抓宠", 580, 544, 120, 36, () => Run(StartTame, ReportTame));
        tameStop = Ui.Button(tamePage, "停止抓宠", 720, 544, 120, 36, () => Run(StopTame, ReportTame));
        tameStatus = Ui.Label(tamePage, "", 20, 602, 830, 80);
    }

    private async Task RefreshCreationWindows()
    {
        await Send("process", "refresh");
        Render();
    }

    private async Task StartCreation()
    {
        ProcessChoice target = SelectedWindow(creationWindows);
        creationDraft.Save();
        await Send("character", "create", "--pid", target.PidText, "--start-ticks", target.StartText);
    }

    private Task StopCreation() => Send("character", "stop", "--wait");

    private async Task PickPreviewFile()
    {
        using var picker = new OpenFileDialog { Filter = "图片|*.png;*.jpg;*.jpeg;*.bmp" };
        if (picker.ShowDialog(this) == DialogResult.OK)
            await Preview(picker.FileName);
    }

    private async Task Preview(string? image)
    {
        string[] input;
        if (image is not null)
            input = ["--image", image];
        else
        {
            ProcessChoice target = SelectedWindow(creationWindows);
            input = ["--pid", target.PidText, "--start-ticks", target.StartText];
        }
        creationDraft.Save();
        string path = Path.Combine(Path.GetTempPath(), $"wowauto-preview-{Guid.NewGuid():N}.png");
        try
        {
            Response response = await Execute(["character", "preview", .. input, "--output", path]);
            if (response.Data?.Deserialize<CreationResult>(Wire.Json)?.State is { } result)
            {
                if (result.OcrSeconds is { } duration)
                    WriteCreation($"{result.Message}；OCR {duration:F2}秒");
                foreach (CreationHit hit in result.Hits ?? [])
                    WriteCreation($"OCR：{hit.Text}（{hit.Score:P0}）");
            }
            if (File.Exists(path) && !IsDisposed)
                ShowPreviewImage(path);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    private void ShowPreviewImage(string path)
    {
        using var source = new Bitmap(path);
        var image = new Bitmap(source);
        var preview = new GrayForm
        {
            Text = "角色创建识别预览（不执行点击）", Size = new(1000, 660), StartPosition = FormStartPosition.CenterParent
        };
        preview.Controls.Add(new PictureBox { Dock = DockStyle.Fill, SizeMode = PictureBoxSizeMode.Zoom, Image = image });
        preview.Disposed += (_, _) => image.Dispose();
        try { preview.Show(this); }
        catch { preview.Dispose(); throw; }
    }

    private void WriteCreation(string message)
    {
        if (IsDisposed)
            return;
        creationStatus.Text = message;
        creationLog.AppendText($"{DateTime.Now:HH:mm:ss}  {message}\r\n");
        if (creationLog.Lines.Length > 500)
        {
            creationLog.Lines = creationLog.Lines[^300..];
            creationLog.Select(creationLog.TextLength, 0);
            creationLog.ScrollToCaret();
        }
    }

    private void ReportTame(string message)
    {
        if (!IsDisposed)
            tameFeedback.Text = message;
    }

    private Task StartTame()
    {
        ProcessChoice process = SelectedWindow(tameWindows);
        tameDraft.Save();
        tameFeedback.Text = "抓宠设置已保存。";
        return ForProcess((process.Pid, process.Start), "task", "start", "--mode", "tame");
    }

    private Task StopTame()
    {
        ProcessChoice process = SelectedWindow(tameWindows);
        return ForProcess((process.Pid, process.Start), "task", "stop", "--wait");
    }

    private void RenderTaskPages(RuntimeView state, Configuration config)
    {
        creationDraft.Refresh(config);
        tameDraft.Refresh(config);
        CreationView creation = automation.Creator.View;
        if (!creation.Active)
            RefreshChoices(creationWindows, ref creationChoices, state.Processes, titleFilter.Text);
        foreach (Control input in creationInputs)
            input.Enabled = !creation.Active;
        bool createAvailable = !creation.Active && !scanning && state.ShutdownAt is null &&
            !state.ShuttingDownGames && !state.Processes.Any(IsBusy);
        createStart.Enabled = previewGame.Enabled = createAvailable && creationWindows.SelectedIndex >= 0;
        previewFile.Enabled = createAvailable;
        createStop.Enabled = creation.Active;
        Ui.SetText(creationCounts, $"完成点击 {creation.Finishes} 次 · 确定点击 {creation.Confirmations} 次");
        if (creationMessage != creation.Message)
        {
            if (creationMessage is not null || creation.Active)
                WriteCreation(creation.Message);
            creationMessage = creation.Message;
        }

        RefreshChoices(tameWindows, ref tameChoices, state.Processes);
        ProcessChoice? target = tameWindows.SelectedItem as ProcessChoice;
        ProcessView? process = target is null ? null : state.Processes.FirstOrDefault(item => item.Pid == target.Pid && item.StartTicks == target.Start);
        tameStart.Enabled = process is not null && !IsBusy(process) && !scanning && !creation.Active &&
            state.ShutdownAt is null && !state.ShuttingDownGames;
        tameStop.Enabled = process is { Mode: "tame" } && IsBusy(process);
        tamePage.Enabled = !state.ShuttingDownGames && !creation.Active;
        Ui.SetText(tameStatus, process?.Message ?? "使用“进程任务”页的刷新按钮发现游戏进程。");

        bool pressed = WowAuto.CharacterCreate.Native.KeyDown(0x77);
        if (pressed && !f8 && ContainsFocus && tabs.SelectedTab == creationPage)
        {
            f8 = true;
            if (createStop.Enabled)
                Run(StopCreation, WriteCreation);
            else if (createStart.Enabled)
                Run(StartCreation, WriteCreation);
        }
        f8 = pressed;
    }

    private static ProcessChoice SelectedWindow(ComboBox windows) =>
        windows.SelectedItem as ProcessChoice ?? throw new InvalidOperationException("请选择有效的游戏窗口。");

    private static void RefreshChoices(ComboBox combo, ref ProcessChoice[] existing, ProcessView[] processes, string filter = "")
    {
        var items = processes.Select(item => new ProcessChoice(item.Pid, item.StartTicks,
            $"{item.Title} [PID {item.Pid} / {Ui.FlavorLabel(item.Flavor)}]"))
            .Where(item => filter.Length == 0 || item.Label.Contains(filter, StringComparison.CurrentCultureIgnoreCase)).ToArray();
        if (items.SequenceEqual(existing))
            return;
        ProcessChoice? previous = combo.SelectedItem as ProcessChoice;
        existing = items;
        combo.BeginUpdate();
        try
        {
            combo.Items.Clear();
            combo.Items.AddRange(items);
            int selected = Array.FindIndex(items, item => item.Pid == previous?.Pid && item.Start == previous.Start);
            combo.SelectedIndex = selected >= 0 ? selected : items.Length > 0 ? 0 : -1;
        }
        finally { combo.EndUpdate(); }
    }

    private sealed record ProcessChoice(int Pid, long Start, string Label)
    {
        public string PidText => Pid.ToString(CultureInfo.InvariantCulture);
        public string StartText => Start.ToString(CultureInfo.InvariantCulture);
        public override string ToString() => Label;
    }
}
