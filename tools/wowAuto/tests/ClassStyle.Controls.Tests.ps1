param([string]$PreviewPath)
$ErrorActionPreference='Stop'
$tool=Split-Path $PSScriptRoot -Parent
. (Join-Path $tool 'wowAuto.Classes.ps1')
$source=[IO.File]::ReadAllText((Join-Path $tool 'wowAuto.Controls.cs'))
$source+=@'
public class ClassCheckFixture : WowAuto.LargeCheckBoxCell {
    public void ClickCorner() {OnMouseClick(new DataGridViewCellMouseEventArgs(ColumnIndex,RowIndex,1,1,new MouseEventArgs(MouseButtons.Left,1,1,1,0)));}
    public void ContentClick() {OnContentClick(new DataGridViewCellEventArgs(ColumnIndex,RowIndex));}
    public void PressSpace() {OnKeyDown(new KeyEventArgs(Keys.Space),RowIndex);OnKeyUp(new KeyEventArgs(Keys.Space),RowIndex);}
}
public class ClassPreviewForm : Form {
    protected override bool ShowWithoutActivation {get {return true;}}
}
'@
Add-Type -TypeDefinition $source -ReferencedAssemblies System.Drawing,System.Windows.Forms
function Assert-Style($Condition,[string]$Message){if(-not $Condition){throw $Message}}
$form=New-Object ClassPreviewForm;$form.StartPosition='Manual';$form.ShowInTaskbar=$false;$form.SetBounds(-20000,-20000,700,550)
$form.BackColor=[Drawing.Color]::FromArgb(58,58,58);$form.ForeColor=[Drawing.Color]::White;$form.Font=New-Object Drawing.Font('Microsoft YaHei UI',12)
$grid=New-Object Windows.Forms.DataGridView;$grid.SetBounds(20,110,640,390);$grid.AllowUserToAddRows=$false;$grid.RowHeadersVisible=$false
$grid.DefaultCellStyle.BackColor=[Drawing.Color]::FromArgb(50,50,50);$grid.DefaultCellStyle.ForeColor=[Drawing.Color]::White
$grid.DefaultCellStyle.SelectionBackColor=[Drawing.Color]::FromArgb(54,78,98);$grid.RowTemplate.Height=36
$check=New-Object WowAuto.LargeCheckBoxColumn;$check.Name='Enabled';$check.Width=90;$check.CellTemplate=New-Object ClassCheckFixture
[void]$grid.Columns.Add($check);[void]$grid.Columns.Add('Name','角色');[void]$grid.Columns.Add('Class','职业')
$grid.Columns['Name'].Width=220;$grid.Columns['Class'].Width=220
$form.Controls.Add($grid)
try {
    $i=0
    foreach($id in $script:wowClassNames.Keys){
        $index=$grid.Rows.Add([object[]]@($false,('示例角色'+(++$i)),(Get-WowClassName ([int]$id))))
        foreach($field in @('Name','Class')){$grid.Rows[$index].Cells[$field].Style.ForeColor=Get-WowClassColor ([int]$id);$grid.Rows[$index].Cells[$field].Style.SelectionForeColor=Get-WowClassColor ([int]$id)}
    }
    foreach($spec in @(@('音频咬钩检测',$true,$true,16),@('拾取 / 剥皮交互',$false,$true,48),@('禁用时仍显示大勾选框',$true,$false,80))){
        $box=New-Object WowAuto.DimCheckBox;$box.Text=$spec[0];$box.Checked=$spec[1];$box.Enabled=$spec[2];$box.BackColor=$form.BackColor;$box.ForeColor=$form.ForeColor;$box.SetBounds(20,$spec[3],600,30);$form.Controls.Add($box)
    }
    $form.Show();[Windows.Forms.Application]::DoEvents();$grid.CurrentCell=$grid.Rows[0].Cells['Enabled']
    $cell=$grid.Rows[0].Cells['Enabled'];$cell.ClickCorner()
    Assert-Style ([bool]$cell.Value) 'Clicking checkbox cell whitespace did not toggle it.'
    $cell.ContentClick();Assert-Style ([bool]$cell.Value) 'One click toggled twice through content-click handling.'
    $cell.ClickCorner();Assert-Style (-not [bool]$cell.Value) 'A second click did not uncheck.'
    $cell.ReadOnly=$true;$cell.ClickCorner();Assert-Style (-not [bool]$cell.Value) 'Read-only checkbox was toggled.'
    $cell.ReadOnly=$false;$grid.Enabled=$false;$cell.ClickCorner();Assert-Style (-not [bool]$cell.Value) 'Disabled checkbox was toggled.'
    $grid.Enabled=$true
    $null=$grid.BeginEdit($false);$cell.PressSpace();$null=$grid.EndEdit()
    Assert-Style ([bool]$cell.Value) 'Keyboard space no longer toggles the checkbox.'
    Assert-Style ((Get-WowClassName 6) -ceq '死亡骑士' -and (Get-WowClassName 0) -ceq '未知' -and (Get-WowClassColor 8).ToArgb() -eq [Drawing.ColorTranslator]::FromHtml('#69CCF0').ToArgb()) 'Shared class names/colors do not match stable class IDs.'
    Assert-Style ([WowAuto.LargeCheckGlyph]::LogicalSize -eq 22) 'Settings checkbox glyph was not enlarged.'
    if($PreviewPath){$bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height);try{$form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$bitmap.Width,$bitmap.Height)));$bitmap.Save([IO.Path]::GetFullPath($PreviewPath))}finally{$bitmap.Dispose()}}
    Write-Output 'PASS: shared class colors, enlarged standalone/grid checkbox glyphs, whole-cell edge clicks, one toggle per click, keyboard Space and read-only/disabled isolation. No game input.'
}finally{$form.Dispose()}
