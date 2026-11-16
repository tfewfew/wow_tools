using System;
using System.ComponentModel;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace WowAuto
{
    public sealed class ScreenshotHotkey : NativeWindow, IDisposable
    {
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
        [DllImport("user32.dll")]
        private static extern bool UnregisterHotKey(IntPtr window, int id);

        public event EventHandler Pressed;

        public ScreenshotHotkey(int key, bool control, bool shift, bool alt)
        {
            CreateHandle(new CreateParams { Parent = new IntPtr(-3) });
            uint modifiers = 0x4000u; // MOD_NOREPEAT prevents a held chord reopening the selector.
            if (control) modifiers |= 2;
            if (shift) modifiers |= 4;
            if (alt) modifiers |= 1;
            if (!RegisterHotKey(Handle, 1, modifiers, (uint)key))
            {
                int error = Marshal.GetLastWin32Error();
                DestroyHandle();
                throw new Win32Exception(error);
            }
        }

        protected override void WndProc(ref Message message)
        {
            if (message.Msg == 0x0312 && message.WParam.ToInt32() == 1)
            {
                var handler = Pressed;
                if (handler != null) handler(this, EventArgs.Empty);
                return;
            }
            base.WndProc(ref message);
        }

        public void Dispose()
        {
            if (Handle == IntPtr.Zero) return;
            UnregisterHotKey(Handle, 1);
            DestroyHandle();
        }
    }

    public sealed class ScreenshotSelection : Form
    {
        [DllImport("user32.dll")]
        private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
        [DllImport("user32.dll")]
        private static extern int GetSystemMetrics(int index);
        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr window);

        private readonly Bitmap desktop;
        private Point anchor;
        private Rectangle selection;
        private bool dragging;
        private bool lostFocus;

        private ScreenshotSelection(Bitmap image, Rectangle bounds)
        {
            desktop = image;
            AutoScaleMode = AutoScaleMode.None;
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            Bounds = bounds;
            TopMost = true;
            ShowInTaskbar = false;
            KeyPreview = true;
            Cursor = Cursors.Cross;
            DoubleBuffered = true;
            SetStyle(ControlStyles.ResizeRedraw, true);
        }

        // Keep every coordinate in physical desktop pixels, including negative monitor origins.
        public static bool CopySelection()
        {
            IntPtr previousDpi = SetThreadDpiAwarenessContext(new IntPtr(-4));
            if (previousDpi == IntPtr.Zero) throw new InvalidOperationException("无法启用截图物理像素坐标。");
            try
            {
                IntPtr originalWindow = GetForegroundWindow();
                var bounds = new Rectangle(GetSystemMetrics(76), GetSystemMetrics(77),
                    GetSystemMetrics(78), GetSystemMetrics(79));
                using (var image = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppRgb))
                {
                    using (var graphics = Graphics.FromImage(image))
                        graphics.CopyFromScreen(bounds.Location, Point.Empty, bounds.Size,
                            CopyPixelOperation.SourceCopy);
                    using (var selector = new ScreenshotSelection(image, bounds))
                    {
                        try
                        {
                            if (selector.ShowDialog() != DialogResult.OK) return false;
                            using (var cropped = image.Clone(selector.selection, PixelFormat.Format32bppRgb))
                            {
                                var data = new DataObject(DataFormats.Bitmap, cropped);
                                Clipboard.SetDataObject(data, true, 10, 50);
                            }
                        }
                        finally
                        {
                            if (!selector.lostFocus && originalWindow != IntPtr.Zero)
                                SetForegroundWindow(originalWindow);
                        }
                    }
                }
                return true;
            }
            finally { SetThreadDpiAwarenessContext(previousDpi); }
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            Activate();
            Focus();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.DrawImageUnscaled(desktop, Point.Empty);
            using (var shade = new SolidBrush(Color.FromArgb(110, Color.Black)))
                e.Graphics.FillRectangle(shade, ClientRectangle);
            if (selection.Width > 0 && selection.Height > 0)
            {
                e.Graphics.DrawImage(desktop, selection, selection, GraphicsUnit.Pixel);
                using (var border = new Pen(Color.FromArgb(40, 190, 235)))
                    e.Graphics.DrawRectangle(border, selection.X, selection.Y,
                        selection.Width - 1, selection.Height - 1);
            }
            string text = dragging
                ? selection.Width + " × " + selection.Height + " 像素 · 松开鼠标复制 · Esc / 右键取消"
                : "拖动鼠标框选截图 · 松开鼠标复制 · Esc / 右键取消";
            var size = TextRenderer.MeasureText(text, Font);
            Point cursor = PointToClient(MousePosition);
            var hint = new Rectangle(Math.Max(0, Math.Min(cursor.X + 18, ClientSize.Width - size.Width - 16)),
                Math.Max(0, Math.Min(cursor.Y + 24, ClientSize.Height - size.Height - 12)),
                size.Width + 16, size.Height + 12);
            e.Graphics.FillRectangle(Brushes.Black, hint);
            TextRenderer.DrawText(e.Graphics, text, Font, hint, Color.White,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
        }

        private Point ClampPoint(Point point)
        {
            return new Point(Math.Max(0, Math.Min(point.X, ClientSize.Width)),
                Math.Max(0, Math.Min(point.Y, ClientSize.Height)));
        }

        private void UpdateSelection(Point point)
        {
            point = ClampPoint(point);
            selection = Rectangle.FromLTRB(Math.Min(anchor.X, point.X), Math.Min(anchor.Y, point.Y),
                Math.Max(anchor.X, point.X), Math.Max(anchor.Y, point.Y));
            Invalidate();
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button == MouseButtons.Right) { DialogResult = DialogResult.Cancel; return; }
            if (e.Button != MouseButtons.Left) return;
            anchor = ClampPoint(e.Location);
            selection = Rectangle.Empty;
            dragging = true;
            Capture = true;
            Invalidate();
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            if (dragging) UpdateSelection(e.Location);
            else Invalidate();
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (e.Button != MouseButtons.Left || !dragging) return;
            UpdateSelection(e.Location);
            dragging = false;
            Capture = false;
            if (selection.Width > 0 && selection.Height > 0) DialogResult = DialogResult.OK;
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Escape) { e.Handled = true; DialogResult = DialogResult.Cancel; }
            base.OnKeyDown(e);
        }

        protected override void OnDeactivate(EventArgs e)
        {
            base.OnDeactivate(e);
            if (Visible && DialogResult == DialogResult.None)
            {
                lostFocus = true;
                DialogResult = DialogResult.Cancel;
            }
        }

        protected override void WndProc(ref Message message)
        {
            // A monitor DPI transition must keep the virtual-desktop overlay at its original bounds.
            if (message.Msg == 0x02E0) { message.Result = IntPtr.Zero; return; }
            if (message.Msg == 0x007E && Visible) DialogResult = DialogResult.Cancel;
            base.WndProc(ref message);
        }
    }
}
