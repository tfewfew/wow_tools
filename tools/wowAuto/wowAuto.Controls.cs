using System;
using System.Drawing;
using System.Windows.Forms;

namespace WowAuto {
    public static class LargeCheckGlyph {
        public const int LogicalSize=22;
        public static int Size(Graphics graphics) {return (int)Math.Round(LogicalSize*graphics.DpiX/96.0);}
        public static void Paint(Graphics graphics,Rectangle bounds,bool check,bool enabled,Color foreground,Color background) {
            using(var fill=new SolidBrush(background)) graphics.FillRectangle(fill,bounds);
            Color border=enabled?foreground:Color.FromArgb(150,foreground);
            using(var pen=new Pen(border,Math.Max(1,graphics.DpiX/96f))) graphics.DrawRectangle(pen,bounds.X,bounds.Y,bounds.Width-1,bounds.Height-1);
            if(check) using(var pen=new Pen(foreground,Math.Max(2,2*graphics.DpiX/96f))) {
                graphics.DrawLines(pen,new[] {new Point(bounds.Left+bounds.Width/5,bounds.Top+bounds.Height/2),
                    new Point(bounds.Left+2*bounds.Width/5,bounds.Top+3*bounds.Height/4),
                    new Point(bounds.Left+4*bounds.Width/5,bounds.Top+bounds.Height/4)});
            }
        }
    }
    public sealed class DimCheckBox : CheckBox {
        public DimCheckBox() {SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.ResizeRedraw,true);}
        public override Size GetPreferredSize(Size proposedSize) {
            Size text=TextRenderer.MeasureText(Text,Font);
            int size=(int)Math.Round(LargeCheckGlyph.LogicalSize*DeviceDpi/96.0);
            return new Size(size+8+text.Width,Math.Max(size+4,text.Height));
        }
        protected override void OnPaint(PaintEventArgs e) {
            e.Graphics.Clear(BackColor);
            int size=Math.Min(LargeCheckGlyph.Size(e.Graphics),Math.Max(1,Height-2));
            var glyph=new Rectangle(1,(Height-size)/2,size,size);
            LargeCheckGlyph.Paint(e.Graphics,glyph,Checked,Enabled,ForeColor,BackColor);
            int left=size+(int)Math.Round(7*e.Graphics.DpiX/96);
            var text=new Rectangle(left,0,Math.Max(0,Width-left),Height);
            TextRenderer.DrawText(e.Graphics,Text,Font,text,ForeColor,TextFormatFlags.Left|TextFormatFlags.VerticalCenter);
            if(Focused && ShowFocusCues) ControlPaint.DrawFocusRectangle(e.Graphics,text,ForeColor,BackColor);
        }
    }
    public class LargeCheckBoxCell : DataGridViewCheckBoxCell {
        // Content clicks are suppressed so a mouse click toggles exactly once,
        // including the whitespace around the enlarged glyph. Keyboard Space
        // uses the same guarded toggle path as the mouse.
        protected override void OnContentClick(DataGridViewCellEventArgs e) {}
        protected override void OnContentDoubleClick(DataGridViewCellEventArgs e) {}
        protected override void OnMouseClick(DataGridViewCellMouseEventArgs e) {
            base.OnMouseClick(e);
            if(e.Button==MouseButtons.Left) ToggleValue(e.RowIndex);
        }
        protected override void OnKeyUp(KeyEventArgs e,int rowIndex) {
            if(e.KeyCode==Keys.Space && e.Modifiers==Keys.None) {ToggleValue(rowIndex);e.Handled=true;return;}
            base.OnKeyUp(e,rowIndex);
        }
        void ToggleValue(int rowIndex) {
            if(rowIndex<0 || DataGridView==null || !DataGridView.Enabled) return;
            if(!DataGridView.EndEdit() || ReadOnly) return;
            Value=!(Value is bool && (bool)Value);
            DataGridView.InvalidateCell(this);
        }
        protected override void Paint(Graphics graphics,Rectangle clipBounds,Rectangle cellBounds,int rowIndex,
            DataGridViewElementStates cellState,object value,object formattedValue,string errorText,
            DataGridViewCellStyle style,DataGridViewAdvancedBorderStyle borderStyle,DataGridViewPaintParts parts) {
            base.Paint(graphics,clipBounds,cellBounds,rowIndex,cellState,value,formattedValue,errorText,style,borderStyle,parts&~DataGridViewPaintParts.ContentForeground);
            if((parts&DataGridViewPaintParts.ContentForeground)==0) return;
            int size=Math.Min(LargeCheckGlyph.Size(graphics),Math.Max(1,Math.Min(cellBounds.Width,cellBounds.Height)-8));
            var glyph=new Rectangle(cellBounds.X+(cellBounds.Width-size)/2,cellBounds.Y+(cellBounds.Height-size)/2,size,size);
            bool selected=(cellState&DataGridViewElementStates.Selected)!=0;
            Color background=selected?style.SelectionBackColor:style.BackColor;
            Color foreground=selected?style.SelectionForeColor:style.ForeColor;
            bool check=formattedValue is bool?(bool)formattedValue:formattedValue is CheckState && (CheckState)formattedValue==CheckState.Checked;
            LargeCheckGlyph.Paint(graphics,glyph,check,!ReadOnly && DataGridView.Enabled,foreground,background);
        }
    }
    public sealed class LargeCheckBoxColumn : DataGridViewCheckBoxColumn {
        public LargeCheckBoxColumn() {CellTemplate=new LargeCheckBoxCell();}
    }
}
