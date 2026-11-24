using System.ComponentModel;
using System.Runtime.InteropServices;

namespace WowAuto.Desktop;

internal static class Ui
{
    public static readonly Color Background = Gray(42);
    public static readonly Color Surface = Gray(58);
    public static readonly Color Heading = Gray(78);
    public static readonly Color Input = Gray(50);
    public static readonly Color Text = Gray(245);
    public static readonly Color Border = Gray(117);
    public static readonly Color Selected = Gray(90);
    public static readonly (string Id, string Label)[] Clients = [("titan", "时光服"), ("forerver", "无限服")];
    public static readonly (string Id, string Label)[] DirectModes = [("rest", "放号"), ("fight", "战斗"), ("shop", "购物"), ("fish", "钓鱼")];
    public static readonly Dictionary<int, (string Label, Color Color)> Classes = new()
    {
        [1] = ("战士", Color.FromArgb(199, 156, 110)), [2] = ("圣骑士", Color.FromArgb(245, 140, 186)),
        [3] = ("猎人", Color.FromArgb(171, 212, 115)), [4] = ("潜行者", Color.FromArgb(255, 245, 105)),
        [5] = ("牧师", Color.White), [6] = ("死亡骑士", Color.FromArgb(196, 31, 59)),
        [7] = ("萨满祭司", Color.FromArgb(73, 152, 235)), [8] = ("法师", Color.FromArgb(105, 204, 240)),
        [9] = ("术士", Color.FromArgb(148, 130, 201)), [11] = ("德鲁伊", Color.FromArgb(255, 125, 10))
    };

    public static Color Gray(int value) => Color.FromArgb(value, value, value);
    public static string ModeLabel(string? mode) => mode == "tame" ? "抓宠" : DirectModes.FirstOrDefault(item => item.Id == mode).Label ?? "";
    public static string FlavorLabel(string flavor) => flavor == "titan" ? "时光服" : "无限服";
    public static (string Label, Color Color) Class(int? id) => Classes.GetValueOrDefault(id ?? 0, ("未知", Text));

    public static T Place<T>(Control parent, T control, int x, int y, int width, int height) where T : Control
    {
        control.SetBounds(x, y, width, height);
        parent.Controls.Add(control);
        return control;
    }

    public static Label Label(Control parent, string text, int x, int y, int width, int height) =>
        Place(parent, new Label { Text = text, UseMnemonic = false }, x, y, width, height);

    public static Label Title(Control parent, string text, int x, int y, int width, int height, int points)
    {
        Label label = Label(parent, text, x, y, width, height);
        label.Font = new("Microsoft YaHei UI", points, FontStyle.Bold);
        label.Disposed += (_, _) => label.Font.Dispose();
        return label;
    }

    public static Button Button(Control parent, string text, int x, int y, int width, int height, Action? click = null, bool accent = false)
    {
        var button = new GrayButton
        {
            Text = text, BackColor = accent ? Gray(101) : Gray(82), ForeColor = Text,
            FlatStyle = FlatStyle.Flat, UseVisualStyleBackColor = false
        };
        button.FlatAppearance.BorderColor = Border;
        button.FlatAppearance.MouseOverBackColor = Gray(110);
        button.FlatAppearance.MouseDownBackColor = Gray(64);
        if (click is not null)
            button.Click += (_, _) => click();
        return Place(parent, button, x, y, width, height);
    }

    public static GrayTabs Tabs(int width, int height = 32) =>
        new() { SizeMode = TabSizeMode.Fixed, ItemSize = new(width, height), ForeColor = Text };

    public static TabPage Page(string text, bool scroll = true) =>
        new(text) { BackColor = Background, ForeColor = Text, AutoScroll = scroll, UseVisualStyleBackColor = false };

    public static TabPage Page(TabControl tabs, string text, bool scroll = true)
    {
        TabPage page = Page(text, scroll);
        tabs.TabPages.Add(page);
        return page;
    }

    public static ComboBox Choice(Control parent, int x, int y, int width, Func<object, Color>? itemColor = null)
    {
        var combo = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList, FlatStyle = FlatStyle.Flat,
            BackColor = Input, ForeColor = Text, DrawMode = DrawMode.OwnerDrawFixed, ItemHeight = 26
        };
        combo.DrawItem += (_, args) =>
        {
            if (args.Index < 0 || combo.Items[args.Index] is not { } item)
                return;
            Color background = args.State.HasFlag(DrawItemState.Selected) ? Selected : Input;
            using var brush = new SolidBrush(background);
            args.Graphics.FillRectangle(brush, args.Bounds);
            TextRenderer.DrawText(args.Graphics, combo.GetItemText(item), combo.Font, args.Bounds, itemColor?.Invoke(item) ?? Text,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis);
            args.DrawFocusRectangle();
        };
        return Place(parent, combo, x, y, width, 34);
    }

    public static TextBox InputBox(Control parent, string text, int x, int y, int width, int height = 32) =>
        Place(parent, new TextBox { Text = text, BackColor = Input, ForeColor = Text, BorderStyle = BorderStyle.FixedSingle }, x, y, width, height);

    public static NumericUpDown Number(Control parent, decimal value, decimal min, decimal max,
        int x, int y, int width, decimal step = 1, int places = 0) =>
        Place(parent, new NumericUpDown
        {
            Minimum = min, Maximum = max, Value = value, Increment = step, DecimalPlaces = places,
            BackColor = Input, ForeColor = Text, BorderStyle = BorderStyle.FixedSingle
        }, x, y, width, 32);

    public static CheckBox Check(Control parent, string text, bool value, int x, int y, int width, int height = 34) =>
        Place(parent, new GrayCheckBox { Text = text, Checked = value, ForeColor = Text }, x, y, width, height);

    public static KeyBox Key(Control parent, string value, int x, int y, int width, string empty = "") =>
        Place(parent, new KeyBox(value, empty), x, y, width, 32);

    public static GroupBox Group(Control parent, string text, int x, int y, int width, int height) =>
        Place(parent, new GroupBox { Text = text, BackColor = Surface, ForeColor = Text }, x, y, width, height);

    public static void SetText(Control control, string text)
    {
        if (control.Text != text)
            control.Text = text;
    }
}

internal class GrayForm : Form
{
    public GrayForm()
    {
        AutoScaleDimensions = new SizeF(96, 96);
        AutoScaleMode = AutoScaleMode.Dpi;
        Font = new("Microsoft YaHei UI", 12);
        BackColor = Ui.Background;
        ForeColor = Ui.Text;
        Disposed += (_, _) => Font.Dispose();
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        int dark = 1;
        int caption = ColorTranslator.ToWin32(Ui.Gray(31));
        int text = ColorTranslator.ToWin32(Ui.Text);
        _ = DwmSetWindowAttribute(Handle, 20, ref dark, sizeof(int));
        _ = DwmSetWindowAttribute(Handle, 35, ref caption, sizeof(int));
        _ = DwmSetWindowAttribute(Handle, 36, ref text, sizeof(int));
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);
}

internal sealed class GrayTabs : TabControl
{
    public GrayTabs() => SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
        ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);

    protected override void OnPaintBackground(PaintEventArgs e) => e.Graphics.Clear(Ui.Gray(30));

    protected override void OnPaint(PaintEventArgs e)
    {
        for (int i = 0; i < TabCount; i++)
        {
            Rectangle bounds = GetTabRect(i);
            using var brush = new SolidBrush(i == SelectedIndex ? Ui.Selected : Ui.Gray(61));
            e.Graphics.FillRectangle(brush, bounds);
            using var pen = new Pen(Ui.Border);
            e.Graphics.DrawRectangle(pen, bounds.X, bounds.Y, bounds.Width - 1, bounds.Height - 1);
            TextRenderer.DrawText(e.Graphics, TabPages[i].Text, Font, bounds, Ui.Text,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
            if (Focused && ShowFocusCues && i == SelectedIndex)
                ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(bounds, -3, -3));
        }
        base.OnPaint(e);
    }

    protected override void OnSelectedIndexChanged(EventArgs e)
    {
        base.OnSelectedIndexChanged(e);
        Invalidate();
    }
}

internal sealed class GrayButton : Button
{
    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        if (Enabled)
            return;
        Rectangle bounds = Rectangle.Inflate(ClientRectangle, -1, -1);
        using var brush = new SolidBrush(BackColor);
        e.Graphics.FillRectangle(brush, bounds);
        TextRenderer.DrawText(e.Graphics, Text, Font, bounds, Ui.Gray(186),
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
    }
}

internal sealed class StatusLog : TextBox
{
    private readonly List<string> history = [];
    private string? last;

    public StatusLog()
    {
        Multiline = true;
        ReadOnly = true;
        ScrollBars = ScrollBars.Vertical;
        BackColor = Ui.Input;
        ForeColor = Ui.Text;
        BorderStyle = BorderStyle.FixedSingle;
    }

    public void ShowStatus(string message, int limit, string details = "")
    {
        if (last != message)
        {
            last = message;
            history.Insert(0, $"[{DateTime.Now:HH:mm:ss}] {message}");
        }
        if (history.Count > limit)
            history.RemoveRange(limit, history.Count - limit);
        string display = history[0] + details;
        if (history.Count > 1)
            display += Environment.NewLine + string.Join(Environment.NewLine, history.Skip(1));
        if (Text == display)
            return;
        int first = FirstLine;
        int start = SelectionStart;
        int length = SelectionLength;
        Text = display;
        Select(Math.Min(start, TextLength), Math.Min(length, Math.Max(0, TextLength - start)));
        if (IsHandleCreated)
            _ = SendMessage(Handle, 0x00B6, IntPtr.Zero, first - FirstLine); // EM_LINESCROLL
    }

    private int FirstLine => IsHandleCreated ? (int)SendMessage(Handle, 0x00CE, IntPtr.Zero, IntPtr.Zero) : 0;

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SendMessage(IntPtr window, int message, IntPtr wParam, IntPtr lParam);
}

internal sealed class KeyBox : TextBox
{
    private readonly string empty;
    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public string Binding
    {
        get => Text == empty ? "" : Text;
        set => Text = value.Length == 0 ? empty : value;
    }

    public KeyBox(string binding, string empty)
    {
        this.empty = empty;
        Binding = binding;
        ReadOnly = true;
        BackColor = Ui.Input;
        ForeColor = Ui.Text;
        BorderStyle = BorderStyle.FixedSingle;
    }

    protected override void OnPreviewKeyDown(PreviewKeyDownEventArgs e)
    {
        base.OnPreviewKeyDown(e);
        e.IsInputKey = true;
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        e.SuppressKeyPress = true;
        string key = e.KeyCode is >= Keys.D0 and <= Keys.D9 ? ((char)e.KeyCode).ToString() : e.KeyCode switch
        {
            Keys.Oemplus => "=", Keys.OemMinus => "-", Keys.Oemcomma => ",", Keys.OemPeriod => ".",
            Keys.OemQuestion => "/", Keys.OemSemicolon => ";", Keys.OemQuotes => "'", Keys.OemOpenBrackets => "[",
            Keys.OemCloseBrackets => "]", Keys.OemPipe => @"\", Keys.Oemtilde => "`", _ => e.KeyCode.ToString()
        };
        string binding = (e.Control ? "Ctrl+" : "") + (e.Shift ? "Shift+" : "") + (e.Alt ? "Alt+" : "") + key;
        try { _ = KeyChord.Parse(binding); Binding = binding; }
        catch (ArgumentException) { }
    }
}
