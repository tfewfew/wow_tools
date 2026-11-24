namespace WowAuto.Desktop;

// Port of the script's enlarged checkboxes for the settings controls and role grids.
internal static class CheckGlyph
{
    public static int Size(Graphics graphics) => (int)Math.Round(22 * graphics.DpiX / 96);

    public static void Draw(Graphics graphics, Rectangle bounds, bool value, bool enabled, Color foreground, Color background)
    {
        using var fill = new SolidBrush(background);
        graphics.FillRectangle(fill, bounds);
        Color color = enabled ? foreground : Ui.Gray(158);
        using var border = new Pen(color, Math.Max(1, graphics.DpiX / 96));
        graphics.DrawRectangle(border, bounds.X, bounds.Y, bounds.Width - 1, bounds.Height - 1);
        if (!value)
            return;

        using var check = new Pen(color, Math.Max(2, 2 * graphics.DpiX / 96));
        graphics.DrawLines(check,
        [
            new Point(bounds.Left + bounds.Width / 5, bounds.Top + bounds.Height / 2),
            new Point(bounds.Left + 2 * bounds.Width / 5, bounds.Top + 3 * bounds.Height / 4),
            new Point(bounds.Left + 4 * bounds.Width / 5, bounds.Top + bounds.Height / 4)
        ]);
    }
}

internal sealed class GrayCheckBox : CheckBox
{
    public GrayCheckBox() => SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
        ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.Clear(BackColor);
        int size = Math.Max(1, Math.Min(CheckGlyph.Size(e.Graphics), Height - 2));
        CheckGlyph.Draw(e.Graphics, new(1, (Height - size) / 2, size, size), Checked, Enabled, ForeColor, BackColor);
        int left = size + (int)Math.Round(7 * e.Graphics.DpiX / 96);
        var text = new Rectangle(left, 0, Math.Max(0, Width - left), Height);
        TextRenderer.DrawText(e.Graphics, Text, Font, text, Enabled ? ForeColor : Ui.Gray(186),
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
        if (Focused && ShowFocusCues)
            ControlPaint.DrawFocusRectangle(e.Graphics, text, ForeColor, BackColor);
    }
}

internal sealed class GrayCheckBoxCell : DataGridViewCheckBoxCell
{
    protected override void OnContentClick(DataGridViewCellEventArgs e) { }
    protected override void OnContentDoubleClick(DataGridViewCellEventArgs e) { }

    protected override void OnMouseClick(DataGridViewCellMouseEventArgs e)
    {
        base.OnMouseClick(e);
        if (e.Button == MouseButtons.Left)
            Toggle(e.RowIndex);
    }

    protected override void OnKeyUp(KeyEventArgs e, int rowIndex)
    {
        if (e.KeyCode == Keys.Space && e.Modifiers == Keys.None)
        {
            Toggle(rowIndex);
            e.Handled = true;
        }
        else
            base.OnKeyUp(e, rowIndex);
    }

    private void Toggle(int row)
    {
        if (row < 0 || DataGridView is not { Enabled: true } grid || ReadOnly || !grid.EndEdit())
            return;
        Value = Value is not true;
        grid.InvalidateCell(this);
    }

    protected override void Paint(Graphics graphics, Rectangle clipBounds, Rectangle cellBounds, int rowIndex,
        DataGridViewElementStates cellState, object? value, object? formattedValue, string? errorText,
        DataGridViewCellStyle style, DataGridViewAdvancedBorderStyle borderStyle, DataGridViewPaintParts parts)
    {
        base.Paint(graphics, clipBounds, cellBounds, rowIndex, cellState, value, formattedValue, errorText,
            style, borderStyle, parts & ~DataGridViewPaintParts.ContentForeground);
        if ((parts & DataGridViewPaintParts.ContentForeground) == 0)
            return;
        int size = Math.Max(1, Math.Min(CheckGlyph.Size(graphics), Math.Min(cellBounds.Width, cellBounds.Height) - 8));
        var glyph = new Rectangle(cellBounds.X + (cellBounds.Width - size) / 2, cellBounds.Y + (cellBounds.Height - size) / 2, size, size);
        bool selected = (cellState & DataGridViewElementStates.Selected) != 0;
        CheckGlyph.Draw(graphics, glyph, formattedValue is true or CheckState.Checked, !ReadOnly && DataGridView?.Enabled == true,
            selected ? style.SelectionForeColor : style.ForeColor, selected ? style.SelectionBackColor : style.BackColor);
    }
}
