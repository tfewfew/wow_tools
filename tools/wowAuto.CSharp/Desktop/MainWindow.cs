using System.Text.Json;
using System.Text.Json.Nodes;
using WowAuto.Protocol;

namespace WowAuto.Desktop;

internal sealed class MainWindow : Form
{
    private readonly Automation automation;
    private readonly CommandProcessor commands;
    private readonly DesktopServices desktop;
    private readonly DataGridView processes = new();
    private readonly TextBox details = new();
    private readonly Label feedback = new();
    private readonly ComboBox modes = new();
    private readonly System.Windows.Forms.Timer timer = new();
    private readonly Dictionary<int, DataGridViewRow> displayed = [];
    private bool f8;
    private static readonly JsonSerializerOptions DisplayJson = new(Wire.Json)
    {
        WriteIndented = true,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };
    private static readonly (string Mode, string Label)[] TaskModes =
        [("fish", "钓鱼"), ("fight", "战斗"), ("tame", "抓宠"), ("rest", "放号"), ("shop", "购物")];

    public MainWindow(Automation automation, CommandProcessor commands, DesktopServices desktop)
    {
        this.automation = automation;
        this.commands = commands;
        this.desktop = desktop;
        Text = "wowAuto · C#";
        Size = new(1100, 710);
        MinimumSize = new(860, 540);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Microsoft YaHei UI", 9);
        BackColor = Color.White;
        Build();
        timer.Interval = automation.Config.Effective.Operations.UiRefreshMs;
        timer.Tick += (_, _) => Render();
        timer.Start();
    }

    private void Build()
    {
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 5, Padding = new Padding(12) };
        layout.RowStyles.Add(new(SizeType.AutoSize));
        layout.RowStyles.Add(new(SizeType.AutoSize));
        layout.RowStyles.Add(new(SizeType.Percent, 60));
        layout.RowStyles.Add(new(SizeType.Percent, 40));
        layout.RowStyles.Add(new(SizeType.AutoSize));
        Controls.Add(layout);

        var top = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, WrapContents = true };
        layout.Controls.Add(top, 0, 0);
        AddButton(top, "刷新进程", () => Send("process", "refresh"));
        AddButton(top, "重新扫描", () => Send("process", "scan"));
        AddButton(top, "全部开始", () => Send("task", "start", "--all"));
        AddButton(top, "全部停止", () => Send("task", "stop", "--all", "--wait"));
        AddButton(top, "设置", OpenSettings);
        AddButton(top, "结束倒计时", OpenCountdown);
        AddButton(top, "截图", () => Send("screenshot", "select", "--wait"));
        AddButton(top, "重启", () => Send("runtime", "restart"));

        var rowActions = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, WrapContents = true };
        layout.Controls.Add(rowActions, 0, 1);
        modes.DropDownStyle = ComboBoxStyle.DropDownList;
        modes.Width = 96;
        modes.Items.AddRange(TaskModes.Select(item => (object)item.Label).ToArray());
        modes.SelectedIndex = 0;
        rowActions.Controls.Add(modes);
        AddButton(rowActions, "直接开始", () => OnRow("task", "start", "--mode", TaskModes[modes.SelectedIndex].Mode));
        AddButton(rowActions, "开始轮转", () => OnRow("task", "start"));
        AddButton(rowActions, "换角色", ChooseRole);
        AddButton(rowActions, "停止", () => OnRow("task", "stop", "--wait"));
        AddButton(rowActions, "角色创建", () => OnRow("character", "create"));
        AddButton(rowActions, "创建预览", Preview);
        AddButton(rowActions, "停止创建", () => Send("character", "stop", "--wait"));

        processes.Dock = DockStyle.Fill;
        processes.ReadOnly = true;
        processes.MultiSelect = false;
        processes.RowHeadersVisible = false;
        processes.AllowUserToAddRows = false;
        processes.AllowUserToDeleteRows = false;
        processes.AllowUserToResizeRows = false;
        processes.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
        processes.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
        processes.BorderStyle = BorderStyle.None;
        processes.BackgroundColor = Color.FromArgb(246, 248, 252);
        processes.AlternatingRowsDefaultCellStyle.BackColor = Color.FromArgb(246, 248, 252);
        foreach ((string name, int width) in new[] { ("PID", 65), ("客户端", 75), ("窗口", 170), ("子战网", 90),
                     ("角色", 100), ("任务", 80), ("轮次", 55), ("状态", 220) })
        {
            int index = processes.Columns.Add(name, name);
            processes.Columns[index].FillWeight = width;
        }
        layout.Controls.Add(processes, 0, 2);

        details.Multiline = true;
        details.ReadOnly = true;
        details.Dock = DockStyle.Fill;
        details.ScrollBars = ScrollBars.Vertical;
        details.Font = new Font("Microsoft YaHei UI", 9);
        details.BorderStyle = BorderStyle.FixedSingle;
        layout.Controls.Add(details, 0, 3);
        feedback.AutoSize = true;
        feedback.Padding = new Padding(0, 6, 0, 0);
        feedback.MaximumSize = new Size(900, 0);
        layout.Controls.Add(feedback, 0, 4);
    }

    private void AddButton(FlowLayoutPanel panel, string label, Func<Task> action)
    {
        var button = new Button { Text = label, AutoSize = true, Height = 33, Padding = new Padding(3, 0, 3, 0), FlatStyle = FlatStyle.System };
        button.Click += async (_, _) =>
        {
            try { await action(); }
            catch (Exception error) { feedback.Text = error.Message; }
        };
        panel.Controls.Add(button);
    }

    private ProcessView? Selected => processes.CurrentRow?.Tag as ProcessView;

    private Task OnRow(params string[] args)
    {
        ProcessView selected = Selected ?? throw new InvalidOperationException("请选择一个游戏窗口。");
        var target = new List<string> { "--pid", selected.Pid.ToString() };
        if (args[0] == "task" || args[0] == "action")
            target.AddRange(["--start-ticks", selected.StartTicks.ToString()]);
        return Send([.. args, .. target]);
    }

    private async Task Send(params string[] args)
    {
        var response = await Execute(args);
        feedback.Text = response.State == "accepted" ? $"请求已受理 {response.Id}" : "已完成。";
        if (response.State == "accepted" && args is ["runtime", "close" or "restart"])
            desktop.RequestExit(args[1] == "restart");
    }

    private async Task<Response> Execute(params string[] args)
    {
        Response response = await commands.Execute(new(Wire.Version, Guid.NewGuid(), args));
        if (response.State == "failed" || response.State == "cancelled")
            throw new InvalidOperationException(response.Error);
        return response;
    }

    private void Render()
    {
        RuntimeView state = automation.Snapshot();
        timer.Interval = automation.Config.Effective.Operations.UiRefreshMs;
        foreach (int pid in displayed.Keys.Except(state.Processes.Select(item => item.Pid)).ToArray())
        {
            processes.Rows.Remove(displayed[pid]);
            displayed.Remove(pid);
        }
        foreach (ProcessView process in state.Processes)
        {
            if (!displayed.TryGetValue(process.Pid, out DataGridViewRow? row))
            {
                row = processes.Rows[processes.Rows.Add()];
                displayed[process.Pid] = row;
            }
            if (ReferenceEquals(row.Tag, process))
                continue;
            row.Tag = process;
            row.SetValues(process.Pid, process.Flavor == "titan" ? "时光服" : "无限服",
                $"{process.Title} {process.Position}", process.Account ?? "", process.Role ?? "", TaskModes.FirstOrDefault(item => item.Mode == process.Mode).Label ?? "",
                process.Round, process.Message);
        }
        CreationView creation = automation.Creator.View;
        string text = creation.Active ? $"角色创建 · {creation.Message}\r\n完成 {creation.Finishes} 次，确认 {creation.Confirmations} 次" :
            Selected is { } selected ? $"PID {selected.Pid} · {selected.Phase} · {selected.Message}\r\n" +
                $"循环 {selected.Cycles} · 无咬钩超时 {selected.BiteTimeouts} · 配置版本 {selected.ConfigRevision}" +
                (selected.Deadline is { } due ? $" · 当前阶段剩余 {Math.Max(0, (due - state.Now) / 1000)} 秒" : "") +
                (selected.Metrics is not null ? "\r\n" + JsonSerializer.Serialize(selected.Metrics, DisplayJson) : "") :
                creation.Message;
        if (state.ShutdownAt is not null)
            text = $"结束倒计时 · {Math.Ceiling(state.ShutdownRemainingMs.GetValueOrDefault() / 1000.0)} 秒\r\n" + text;
        if (state.LogError is { Length: > 0 })
            text += $"\r\n日志写入失败 · {state.LogError}";
        if (details.Text != text)
            details.Text = text;
        bool pressed = WowAuto.CharacterCreate.Native.KeyDown(0x77);
        if (pressed && !f8 && ContainsFocus && !creation.Active && Selected is not null)
            _ = StartOnHotkey();
        f8 = pressed;
    }

    private async Task StartOnHotkey()
    {
        try { await OnRow("character", "create"); }
        catch (Exception error) { feedback.Text = error.Message; }
    }

    private Task ChooseRole()
    {
        ProcessView selected = Selected ?? throw new InvalidOperationException("请选择一个游戏窗口。");
        string[] roleNames = selected.Account is { } account &&
            automation.Config.Effective.Accounts.TryGetValue($"{selected.Flavor}:{account}", out RoleSettings[]? configured)
            ? configured.Where(item => item.Enabled).Select(item => item.Name).ToArray() : [];
        using var dialog = new Form { Text = "换角色", StartPosition = FormStartPosition.CenterParent, ClientSize = new Size(350, 105),
            FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false, MinimizeBox = false };
        var choice = new ComboBox { Left = 14, Top = 14, Width = 310 };
        choice.Items.AddRange(roleNames);
        if (choice.Items.Count > 0) choice.SelectedIndex = 0;
        var apply = new Button { Text = "切换", DialogResult = DialogResult.OK, Left = 235, Top = 55, Width = 90 };
        dialog.Controls.AddRange([choice, apply]);
        dialog.AcceptButton = apply;
        return dialog.ShowDialog(this) == DialogResult.OK && choice.Text.Trim().Length > 0
            ? OnRow("task", "switch", "--role", choice.Text.Trim()) : Task.CompletedTask;
    }

    private Task OpenCountdown()
    {
        using var dialog = new Form { Text = "结束倒计时（秒）", StartPosition = FormStartPosition.CenterParent, ClientSize = new Size(340, 115),
            FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false, MinimizeBox = false };
        var seconds = new NumericUpDown { Left = 12, Top = 15, Minimum = 1, Maximum = int.MaxValue, Value = 600, Width = 160 };
        var start = new Button { Text = "开始", DialogResult = DialogResult.OK, Left = 12, Top = 65, Width = 100 };
        var cancel = new Button { Text = "取消倒计时", DialogResult = DialogResult.Abort, Left = 145, Top = 65, Width = 125 };
        dialog.Controls.AddRange([seconds, start, cancel]);
        dialog.AcceptButton = start;
        return dialog.ShowDialog(this) switch
        {
            DialogResult.OK => Send("shutdown", "set", ((int)seconds.Value).ToString()),
            DialogResult.Abort => Send("shutdown", "cancel"),
            _ => Task.CompletedTask
        };
    }

    private async Task Preview()
    {
        using var dialog = new OpenFileDialog { Filter = "图片|*.png;*.jpg;*.jpeg;*.bmp", Title = "选择预览图片，取消则使用当前游戏窗口" };
        string[] input;
        if (dialog.ShowDialog(this) == DialogResult.OK)
            input = ["--image", dialog.FileName];
        else if (Selected is { } selected)
            input = ["--pid", selected.Pid.ToString()];
        else
            return;
        string file = Path.Combine(Path.GetTempPath(), $"wowauto-preview-{Guid.NewGuid():N}.png");
        await Execute(["character", "preview", .. input, "--output", file]);
        if (!File.Exists(file))
            return;
        using var preview = new Form { Text = "角色创建预览", Size = new(980, 660), StartPosition = FormStartPosition.CenterParent };
        try
        {
            using var source = new Bitmap(file);
            using var image = new Bitmap(source);
            preview.Controls.Add(new PictureBox { Dock = DockStyle.Fill, SizeMode = PictureBoxSizeMode.Zoom, Image = image });
            preview.ShowDialog(this);
        }
        finally { File.Delete(file); }
    }

    private Task OpenSettings()
    {
        using var editor = new Form { Text = "wowAuto 设置", StartPosition = FormStartPosition.CenterParent, Size = new Size(850, 610) };
        var split = new SplitContainer { Dock = DockStyle.Fill, SplitterDistance = 180 };
        var groups = new ListBox { Dock = DockStyle.Fill };
        var value = new TextBox { Dock = DockStyle.Fill, Multiline = true, ScrollBars = ScrollBars.Both, WordWrap = false, Font = new Font("Consolas", 11) };
        var footer = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 44 };
        var status = new Label { AutoSize = true, Padding = new Padding(5, 9, 0, 0) };
        editor.Controls.Add(split);
        editor.Controls.Add(footer);
        split.Panel1.Controls.Add(groups);
        split.Panel2.Controls.Add(value);
        Configuration current = automation.Config;
        JsonObject data = SettingsJson.Tree(current.Saved);
        void LoadGroup()
        {
            if (groups.SelectedItem is string name)
                value.Text = data[name]?.ToJsonString(DisplayJson) ?? "";
        }
        groups.Items.AddRange(data.Select(item => (object)item.Key).ToArray());
        groups.SelectedIndexChanged += (_, _) => LoadGroup();
        groups.SelectedIndex = 0;
        var save = new Button { Text = "保存当前组", AutoSize = true };
        save.Click += async (_, _) =>
        {
            try
            {
                string group = (string)groups.SelectedItem!;
                await Execute("config", "set", group, value.Text, "--revision", current.Revision.ToString());
                current = automation.Config;
                data = SettingsJson.Tree(current.Saved);
                LoadGroup();
                status.Text = "已保存。";
            }
            catch (Exception error) { status.Text = error.Message; }
        };
        var reread = new Button { Text = "重新读取", AutoSize = true };
        reread.Click += (_, _) =>
        {
            current = automation.Config;
            data = SettingsJson.Tree(current.Saved);
            LoadGroup();
            status.Text = "";
        };
        var import = new Button { Text = "导入旧脚本配置", AutoSize = true };
        import.Click += async (_, _) =>
        {
            using var folder = new FolderBrowserDialog { Description = "选择原 wowAuto 脚本目录" };
            if (folder.ShowDialog(editor) != DialogResult.OK) return;
            try
            {
                await Execute("config", "import", folder.SelectedPath, "--revision", current.Revision.ToString());
                current = automation.Config;
                data = SettingsJson.Tree(current.Saved);
                LoadGroup();
                status.Text = "导入完成。";
            }
            catch (Exception error) { status.Text = error.Message; }
        };
        footer.Controls.AddRange([save, reread, import, status]);
        editor.ShowDialog(this);
        return Task.CompletedTask;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
            timer.Dispose();
        base.Dispose(disposing);
    }
}
