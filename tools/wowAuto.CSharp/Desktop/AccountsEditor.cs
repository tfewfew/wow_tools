using System.Text.Json;

namespace WowAuto.Desktop;

internal sealed class AccountsEditor
{
    private readonly Automation automation;
    private readonly TabPage page;
    private readonly Label feedback;
    private readonly Button save;
    private readonly Dictionary<string, ClientPage> clients = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Dictionary<(string Realm, string Name), RoleEdit>> edits = new(StringComparer.Ordinal);
    private (string Titan, string Forerver)? requestedDirectories;
    private int loadVersion;

    public AccountsEditor(TabPage page, Automation automation, ProcessView? process)
    {
        this.automation = automation;
        this.page = page;
        GrayTabs tabs = Ui.Place(page, Ui.Tabs(150), 18, 18, 1380, 682);
        foreach (var (id, label) in Ui.Clients)
        {
            TabPage child = Ui.Page(tabs, id == "forerver" ? "永恒服" : label);
            var client = new ClientPage(this, child, id, process?.Flavor == id ? process.Account : null);
            clients.Add(id, client);
            if (process?.Flavor == id)
                tabs.SelectedTab = child;
        }
        feedback = Ui.Label(page, "", 18, 716, 1380, 56);
        save = Ui.Button(page, "保存子战网设置", 18, 782, 210, 36, Save, true);
        save.Enabled = false;
    }

    public void InvalidateCatalog()
    {
        requestedDirectories = null;
        loadVersion++;
        save.Enabled = false;
    }

    private (string Titan, string Forerver) Directories()
    {
        RotationSettings settings = automation.Config.Saved.Rotation;
        return (settings.TitanDirectory, settings.ForerverDirectory);
    }

    public async Task LoadAsync()
    {
        var directories = Directories();
        if (requestedDirectories == directories)
            return;
        requestedDirectories = directories;
        int version = ++loadVersion;
        save.Enabled = false;
        feedback.Text = "";
        foreach (ClientPage client in clients.Values)
            client.SetHint("正在读取子战网角色资料…");
        try
        {
            var (titan, forerver) = await Task.Run(() => (ReadCatalog(directories.Titan), ReadCatalog(directories.Forerver)));
            if (page.IsDisposed || page.Disposing || version != loadVersion)
                return;
            if (directories != Directories())
            {
                await LoadAsync();
                return;
            }

            page.SuspendLayout();
            try
            {
                clients["titan"].SetCatalog(titan);
                clients["forerver"].SetCatalog(forerver);
                feedback.Text = "";
                save.Enabled = true;
            }
            finally { page.ResumeLayout(); }
        }
        catch (Exception error)
        {
            if (page.IsDisposed || page.Disposing || version != loadVersion)
                return;
            requestedDirectories = null;
            foreach (ClientPage client in clients.Values)
                client.SetHint($"读取子战网角色资料失败：{error.Message}");
        }
    }

    private void Save()
    {
        if (requestedDirectories != Directories())
        {
            _ = LoadAsync();
            return;
        }
        try
        {
            foreach (ClientPage client in clients.Values)
                client.Capture();
            Configuration config = automation.Config;
            var updates = new List<SettingChange>();
            foreach (ClientPage client in clients.Values)
            foreach (var (account, records) in client.Catalog)
            {
                string accountKey = client.Flavor + ":" + account;
                RoleSettings[] saved = config.Saved.Accounts.GetValueOrDefault(accountKey, []);
                var merged = MergeRoles(saved, records);
                if (edits.TryGetValue(accountKey, out var changes))
                {
                    foreach (var (id, edit) in changes)
                    {
                        int index = merged.FindIndex(role => (role.Realm, role.Name) == id);
                        bool wasSaved = saved.Any(role => (role.Realm, role.Name) == id);
                        if (index < 0 || (edit.WasSaved != wasSaved || merged[index] != edit.Original) && merged[index] != edit.Value)
                            throw new InvalidOperationException($"{account} / {id.Name} 已通过其他入口修改，请重新打开设置后保存。");
                        merged[index] = edit.Value;
                    }
                }
                if (!saved.SequenceEqual(merged))
                    updates.Add(new("/Accounts/" + accountKey.Replace("~", "~0", StringComparison.Ordinal),
                        JsonSerializer.Serialize(merged, SettingsJson.Options)));
            }
            if (edits.Keys.Any(key => !clients.Values.Any(client => key.StartsWith(client.Flavor + ":", StringComparison.Ordinal) &&
                client.Catalog.ContainsKey(key[(client.Flavor.Length + 1)..]))))
                throw new InvalidOperationException("有编辑中的子战网未出现在当前游戏目录，请恢复目录后再保存。");
            if (updates.Count > 0)
                automation.Configure(updates, false, config.Revision);
            edits.Clear();
            foreach (ClientPage client in clients.Values)
                client.ShowAccount();
            feedback.Text = "子战网角色任务已保存。";
        }
        catch (Exception error) { feedback.Text = error.Message; }
    }

    private static List<RoleSettings> MergeRoles(RoleSettings[] saved, CharacterRecord[] records)
    {
        var identities = saved.Select(role => (role.Realm, role.Name)).ToHashSet();
        var roles = new List<RoleSettings>(saved);
        foreach (CharacterRecord record in records)
            if (identities.Add((record.Realm, record.Name)))
                roles.Add(new() { Name = record.Name, Realm = record.Realm });
        return roles;
    }

    private sealed record RoleEdit(RoleSettings Original, RoleSettings Value, bool WasSaved);

    private sealed record ClientCatalog(Dictionary<string, CharacterRecord[]> Accounts, IReadOnlyDictionary<string, int> RealmLevels);

    private static ClientCatalog ReadCatalog(string directory) => new(
        AccountCatalog.ReadDirectory(directory).GroupBy(item => item.Account, StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => group.ToArray(), StringComparer.Ordinal),
        AccountCatalog.ReadRealmLevels(directory));

    private sealed class ClientPage
    {
        private readonly AccountsEditor owner;
        private readonly ComboBox accounts;
        private readonly Label hint, fullLabel, levelingLabel;
        private readonly DataGridView full, leveling;
        private readonly string? suggested;
        private IReadOnlyDictionary<string, int> realmLevels = new Dictionary<string, int>();
        private string? selected;
        private bool loading;

        public string Flavor { get; }
        public Dictionary<string, CharacterRecord[]> Catalog { get; private set; } = new(StringComparer.Ordinal);

        public void SetHint(string message) => hint.Text = message;

        public ClientPage(AccountsEditor owner, TabPage page, string flavor, string? suggested)
        {
            this.owner = owner;
            this.suggested = suggested;
            Flavor = flavor;
            Ui.Label(page, "子战网", 18, 18, 150, 30);
            accounts = Ui.Choice(page, 170, 15, 710);
            hint = Ui.Label(page, "", 18, 58, 1340, 52);
            fullLabel = Ui.Label(page, "满级角色", 18, 106, 1340, 26);
            full = BuildGrid(page, 134);
            levelingLabel = Ui.Label(page, "未满级角色", 18, 364, 1340, 26);
            leveling = BuildGrid(page, 394);
            accounts.SelectedIndexChanged += (_, _) =>
            {
                if (!loading)
                {
                    Capture();
                    ShowAccount();
                }
            };
        }

        public void SetCatalog(ClientCatalog catalog)
        {
            Capture();
            string? previous = selected ?? suggested;
            Catalog = catalog.Accounts;
            realmLevels = catalog.RealmLevels;
            loading = true;
            accounts.BeginUpdate();
            try
            {
                accounts.Items.Clear();
                accounts.Items.AddRange(Catalog.Keys.Order(StringComparer.Ordinal).ToArray());
                if (accounts.Items.Count > 0)
                {
                    int index = previous is null ? -1 : accounts.Items.IndexOf(previous);
                    accounts.SelectedIndex = Math.Max(0, index);
                }
            }
            finally
            {
                accounts.EndUpdate();
                loading = false;
            }
            hint.Text = accounts.Items.Count == 0
                ? "尚未发现该服的子战网角色记录，请检查游戏目录，正常下线保存角色记录后刷新进程。"
                : "满级角色在上，未满级按等级降序。分表保留轮转顺序，新角色默认停用。资料为最近保存快照；上线和下线都会采集，需下线或 /reload 落盘后刷新。";
            ShowAccount();
        }

        public void Capture()
        {
            if (selected is null)
                return;
            string key = Flavor + ":" + selected;
            if (!owner.edits.TryGetValue(key, out var changes))
                changes = [];
            foreach (DataGridView grid in new[] { full, leveling })
            {
                if (!grid.EndEdit())
                    throw new InvalidOperationException("角色任务输入无效，请检查当前单元格。");
                foreach (DataGridViewRow row in grid.Rows)
                {
                    var entry = (RoleEdit)row.Tag!;
                    string label = (string)row.Cells["Mode"].Value!;
                    string mode = Ui.DirectModes.Single(item => item.Label == label).Id;
                    RoleSettings next = entry.Original with
                    {
                        Enabled = row.Cells["Enabled"].Value is true,
                        Mode = mode,
                        UseItem = mode == "fish" && row.Cells["UseItem"].Value is true
                    };
                    var id = (next.Realm, next.Name);
                    if (next == entry.Original)
                        changes.Remove(id);
                    else
                        changes[id] = entry with { Value = next };
                }
            }
            if (changes.Count > 0)
                owner.edits[key] = changes;
            else
                owner.edits.Remove(key);
        }

        public void ShowAccount()
        {
            loading = true;
            try
            {
                selected = accounts.SelectedItem as string;
                if (selected is null || !Catalog.TryGetValue(selected, out CharacterRecord[]? records))
                {
                    ReplaceRows(full, []);
                    ReplaceRows(leveling, []);
                    fullLabel.Text = "满级角色";
                    levelingLabel.Text = "未满级角色";
                    return;
                }
                string key = Flavor + ":" + selected;
                RoleSettings[] saved = owner.automation.Config.Saved.Accounts.GetValueOrDefault(key, []);
                var byIdentity = records.GroupBy(record => (record.Realm, record.Name))
                    .Where(group => group.Count() == 1).ToDictionary(group => group.Key, group => group.Single());
                var savedIds = saved.Select(role => (role.Realm, role.Name)).ToHashSet();
                var maxLevel = new List<DataGridViewRow>();
                var below = new List<(RoleEdit Role, CharacterRecord Record, int Maximum)>();
                owner.edits.TryGetValue(key, out var changes);
                foreach (RoleSettings role in MergeRoles(saved, records))
                {
                    var id = (role.Realm, role.Name);
                    if (!byIdentity.TryGetValue(id, out CharacterRecord? record))
                        continue;
                    RoleEdit entry = changes?.GetValueOrDefault(id) ?? new(role, role, savedIds.Contains(id));
                    int max = realmLevels.GetValueOrDefault(record.Realm);
                    if (max > 0 && record.Level >= max)
                        maxLevel.Add(CreateRoleRow(full, entry, record, max));
                    else
                        below.Add((entry, record, max));
                }
                var other = below.OrderByDescending(item => item.Record.Level ?? -1)
                    .Select(item => CreateRoleRow(leveling, item.Role, item.Record, item.Maximum)).ToArray();
                ReplaceRows(full, maxLevel.ToArray());
                ReplaceRows(leveling, other);
                fullLabel.Text = $"满级角色（{full.Rows.Count}）";
                levelingLabel.Text = $"未满级角色（{leveling.Rows.Count}，按等级降序；上限未知列于此，等级未知置后）";
            }
            finally { loading = false; }
        }

        private static void ReplaceRows(DataGridView grid, DataGridViewRow[] rows)
        {
            grid.SuspendLayout();
            try
            {
                // Insert complete rows with automatic height calculation suspended.
                grid.AutoSizeRowsMode = DataGridViewAutoSizeRowsMode.None;
                grid.Rows.Clear();
                grid.Rows.AddRange(rows);
                grid.AutoResizeColumn(grid.Columns["Name"]!.Index, DataGridViewAutoSizeColumnMode.AllCells);
            }
            finally
            {
                grid.AutoSizeRowsMode = DataGridViewAutoSizeRowsMode.DisplayedCellsExceptHeaders;
                grid.ResumeLayout();
            }
        }

        private static DataGridViewRow CreateRoleRow(DataGridView grid, RoleEdit edit, CharacterRecord record, int max)
        {
            RoleSettings role = edit.Value;
            var (classLabel, classColor) = Ui.Class(record.ClassId);
            var row = (DataGridViewRow)grid.RowTemplate.Clone();
            row.CreateCells(grid, role.Enabled, $"{record.Name}-{record.DisplayRealm}", classLabel, record.DisplayRealm,
                Ui.ModeLabel(role.Mode), role.UseItem, record.Level?.ToString() ?? "未知", record.FreeBagSlots?.ToString() ?? "未知",
                FormatSkills(record.Professions), FormatSkills(record.SecondarySkills),
                record.BindLocation is null or "" or "?" ? "未知" : record.BindLocation);
            row.Tag = edit;
            DataGridViewCell Cell(string name) => row.Cells[grid.Columns[name]!.Index];
            Cell("Name").Style.ForeColor = Cell("Name").Style.SelectionForeColor = classColor;
            Cell("Class").Style.ForeColor = Cell("Class").Style.SelectionForeColor = classColor;
            Cell("UseItem").ReadOnly = role.Mode != "fish";
            Cell("Level").ToolTipText = max == 0 ? "服务器等级上限未知，保存资料后刷新进程。" : $"服务器满级等级：{max}";
            return row;
        }

        private static string FormatSkills(string? skills)
        {
            if (skills is null or "?")
                return "未知";
            if (skills.Length == 0)
                return "未学习";
            string[][] rows = skills.Split(';').Select(item => item.Split('|')).ToArray();
            return rows.All(row => row.Length == 4)
                ? string.Join(Environment.NewLine, rows.Select(row => $"{row[1]} {row[2]}/{row[3]}")) : "未知";
        }

        private DataGridView BuildGrid(TabPage page, int y)
        {
            var grid = new RoleGrid
            {
                AllowUserToAddRows = false, AllowUserToDeleteRows = false, AllowUserToOrderColumns = false,
                AutoGenerateColumns = false, RowHeadersVisible = false, BackgroundColor = Ui.Input, GridColor = Ui.Border,
                EnableHeadersVisualStyles = false, AutoSizeRowsMode = DataGridViewAutoSizeRowsMode.DisplayedCellsExceptHeaders,
                ColumnHeadersHeightSizeMode = DataGridViewColumnHeadersHeightSizeMode.DisableResizing,
                DefaultCellStyle = new()
                {
                    BackColor = Ui.Input, ForeColor = Ui.Text, SelectionBackColor = Ui.Selected, SelectionForeColor = Ui.Text
                },
                ColumnHeadersDefaultCellStyle = new() { BackColor = Ui.Heading, ForeColor = Ui.Text }
            };
            DataGridViewColumn? modeColumn = null;
            (string Id, string Label, int Width)[] columns =
            [
                ("Enabled", "启用", 65), ("Name", "角色全名", 240), ("Class", "职业", 100), ("Realm", "服务器", 125),
                ("Mode", "任务", 85), ("UseItem", "钓鱼道具", 90), ("Level", "等级", 55), ("FreeBagSlots", "背包空格", 90),
                ("Professions", "生产 / 采集技能", 210), ("SecondarySkills", "生活技能", 170), ("BindLocation", "炉石位置", 170)
            ];
            foreach (var (id, label, width) in columns)
            {
                DataGridViewColumn column = id switch
                {
                    "Enabled" or "UseItem" => new DataGridViewCheckBoxColumn { CellTemplate = new GrayCheckBoxCell() },
                    "Mode" => new DataGridViewComboBoxColumn { FlatStyle = FlatStyle.Flat },
                    _ => new DataGridViewTextBoxColumn { ReadOnly = true }
                };
                if (column is DataGridViewComboBoxColumn mode)
                {
                    modeColumn = mode;
                    mode.Items.AddRange("钓鱼", "战斗", "购物");
                    if (Flavor == "forerver")
                        mode.Items.Add("放号");
                }
                column.Name = id;
                column.HeaderText = label;
                column.Width = width;
                column.SortMode = DataGridViewColumnSortMode.NotSortable;
                if (id == "Name")
                    column.MinimumWidth = width;
                if (id is "Professions" or "SecondarySkills" or "BindLocation")
                    column.DefaultCellStyle.WrapMode = DataGridViewTriState.True;
                grid.Columns.Add(column);
            }
            void SizeCells()
            {
                int rowHeight = Ui.Pixels(36, grid.DeviceDpi);
                grid.ColumnHeadersHeight = Ui.Pixels(34, grid.DeviceDpi);
                grid.RowTemplate.Height = grid.RowTemplate.MinimumHeight = rowHeight;
                foreach (DataGridViewRow row in grid.Rows)
                    row.MinimumHeight = rowHeight;
                for (int index = 0; index < columns.Length; index++)
                {
                    var column = grid.Columns[index];
                    int width = Ui.Pixels(columns[index].Width, grid.DeviceDpi);
                    if (column.Name == "Name")
                    {
                        column.MinimumWidth = width;
                        grid.AutoResizeColumn(index, DataGridViewAutoSizeColumnMode.AllCells);
                    }
                    else
                        column.Width = width;
                }
            }
            SizeCells();
            grid.HandleCreated += (_, _) => SizeCells();
            grid.DpiChangedAfterParent += (_, _) => SizeCells();
            grid.CurrentCellDirtyStateChanged += (_, _) =>
            {
                if (grid.IsCurrentCellDirty)
                    grid.CommitEdit(DataGridViewDataErrorContexts.Commit);
            };
            grid.CellValueChanged += (_, args) =>
            {
                if (loading || args.RowIndex < 0 || args.ColumnIndex != modeColumn?.Index)
                    return;
                DataGridViewRow row = grid.Rows[args.RowIndex];
                bool fish = row.Cells["Mode"].Value is "钓鱼";
                row.Cells["UseItem"].ReadOnly = !fish;
                if (!fish)
                    row.Cells["UseItem"].Value = false;
            };
            grid.DataError += (_, args) =>
            {
                args.ThrowException = false;
                owner.feedback.Text = "角色任务输入无效，请从当前客户端的任务列表选择。";
            };
            return Ui.Place(page, grid, 18, y, 1340, 220);
        }
    }

    private sealed class RoleGrid : DataGridView
    {
        public RoleGrid() => DoubleBuffered = true;
    }
}
