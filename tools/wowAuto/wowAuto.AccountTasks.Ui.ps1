function New-AccountTaskSettingsPage {
    Update-AccountTaskCatalog
    $page=New-Object Windows.Forms.TabPage;$page.Text='子战网';$page.BackColor=$script:uiColors.Background;$page.AutoScroll=$true
    $draft=ConvertTo-TaskMap ($script:accountTasks.Config | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
    $label=New-Object Windows.Forms.Label;$label.Text='子战网 / 客户端';$label.SetBounds(18,18,190,30)
    $accounts=New-Object Windows.Forms.ComboBox;$accounts.DropDownStyle='DropDownList';$accounts.SetBounds(210,15,710,34)
    $accounts.BackColor=$script:uiColors.Input;$accounts.ForeColor=$script:uiColors.Text;$accounts.FlatStyle='Flat'
    foreach($key in @($script:accountTasks.Catalog.Keys | Sort-Object)){[void]$accounts.Items.Add($key)}
    $hint=New-Object Windows.Forms.Label;$hint.Text='勾选启用的角色，选择钓鱼或战斗；进程绑定后按表中顺序轮转。新角色默认停用，选角只识别第一页。';$hint.SetBounds(18,58,920,52)
    $grid=New-Object Windows.Forms.DataGridView;$grid.SetBounds(18,116,920,310);$grid.Anchor='Top, Left, Right'
    $grid.AllowUserToAddRows=$false;$grid.AllowUserToDeleteRows=$false;$grid.AllowUserToOrderColumns=$false;$grid.RowHeadersVisible=$false
    $grid.BackgroundColor=$script:uiColors.Input;$grid.GridColor=$script:uiColors.Border;$grid.AutoGenerateColumns=$false
    $grid.DefaultCellStyle.BackColor=$script:uiColors.Input;$grid.DefaultCellStyle.ForeColor=$script:uiColors.Text
    $grid.DefaultCellStyle.SelectionBackColor=$script:uiColors.Tab;$grid.DefaultCellStyle.SelectionForeColor=$script:uiColors.Text
    $grid.EnableHeadersVisualStyles=$false;$grid.ColumnHeadersDefaultCellStyle.BackColor=$script:uiColors.Heading;$grid.ColumnHeadersDefaultCellStyle.ForeColor=$script:uiColors.Text
    $grid.RowTemplate.Height=32;$grid.ColumnHeadersHeight=34
    foreach($spec in @(@('Enabled','启用',65,'check'),@('Name','角色',210,'text'),@('Realm','服务器',185,'text'),@('Mode','任务',110,'mode'),@('UseItem','钓鱼道具',115,'check'),@('Level','等级',80,'text'),@('FreeBagSlots','背包空格',115,'text'))) {
        $column=switch($spec[3]) {'check'{New-Object Windows.Forms.DataGridViewCheckBoxColumn}'mode'{New-Object Windows.Forms.DataGridViewComboBoxColumn}default{New-Object Windows.Forms.DataGridViewTextBoxColumn}}
        $column.Name=$spec[0];$column.HeaderText=$spec[1];$column.Width=$spec[2];$column.SortMode='NotSortable'
        if($spec[3] -eq 'mode'){$column.Items.AddRange([object[]]@('钓鱼','战斗'));$column.FlatStyle='Flat'}
        $column.ReadOnly=$spec[0] -in @('Name','Realm','Level','FreeBagSlots');[void]$grid.Columns.Add($column)
    }
    $errorLabel=New-Object Windows.Forms.Label;$errorLabel.SetBounds(18,716,920,56)
    $periodGroup=New-Object Windows.Forms.GroupBox;$periodGroup.Text='检测周期（ms，25–60000；全局共用）';$periodGroup.SetBounds(18,442,920,262)
    $periodGroup.BackColor=$script:uiColors.Surface;$periodGroup.ForeColor=$script:uiColors.Text;$periods=@{};$i=0
    foreach($spec in @(@('FishMs','钓鱼色块'),@('FightMs','战斗色块'),@('MenuMs','选角画面'),@('LoginMs','登录确认 / 退出检查'),@('BaitMs','钓鱼道具'),@('DeathMs','角色死亡'),@('AudioMs','音频事件'),@('PositionMs','窗口位置'),@('CaptureRetryMs','画面等待重试'),@('OcrMs','OCR采样'))) {
        $x=16+($i%2)*450;$y=32+[Math]::Floor($i/2)*43;$i++
        $name=New-Object Windows.Forms.Label;$name.Text=$spec[1];$name.SetBounds($x,$y,245,30)
        $value=New-Object Windows.Forms.NumericUpDown;$value.Minimum=25;$value.Maximum=60000;$value.Increment=25;$value.Value=$draft.Periods[$spec[0]];$value.SetBounds(($x+250),($y-3),175,32)
        $value.BackColor=$script:uiColors.Input;$value.ForeColor=$script:uiColors.Text;$periods[$spec[0]]=$value
        $periodGroup.Controls.AddRange([Windows.Forms.Control[]]@($name,$value))
    }
    $save=New-Object WowAuto.DimButton;$save.Text='保存子战网设置';$save.SetBounds(18,782,210,36);Set-UiButtonStyle $save $true
    $page.Tag=[pscustomobject]@{Draft=$draft;Accounts=$accounts;Grid=$grid;Selected='';Periods=$periods;Save=$save;Error=$errorLabel;Loading=$false}
    $grid.Tag=$page;$accounts.Tag=$page;$save.Tag=$page
    $accounts.Add_SelectedIndexChanged({param($sender,$e)
        $editor=$sender.Tag.Tag
        try {Save-AccountGridDraft $editor;Show-AccountGridDraft $editor ([string]$sender.SelectedItem)}catch{$editor.Error.Text=$_.Exception.Message}
    })
    $grid.Add_CurrentCellDirtyStateChanged({param($sender,$e) if($sender.IsCurrentCellDirty){$null=$sender.CommitEdit([Windows.Forms.DataGridViewDataErrorContexts]::Commit)}})
    $grid.Add_CellValueChanged({param($sender,$e)
        if($sender.Tag.Tag.Loading -or $e.RowIndex -lt 0){return}
        $row=$sender.Rows[$e.RowIndex];$combat=$row.Cells['Mode'].Value -eq '战斗'
        $row.Cells['UseItem'].ReadOnly=$combat;if($combat){$row.Cells['UseItem'].Value=$false}
    })
    $grid.Add_DataError({param($sender,$e) $sender.Tag.Tag.Error.Text='角色任务输入无效，请选择钓鱼或战斗。';$e.ThrowException=$false})
    $save.Add_Click({param($sender,$e)
        $editor=$sender.Tag.Tag
        try {
            Save-AccountGridDraft $editor
            foreach($key in $editor.Periods.Keys){$editor.Draft.Periods[$key]=[int]$editor.Periods[$key].Value}
            $changed=@($editor.Draft.Accounts.Keys | Where-Object {(Get-AccountTaskSignature $editor.Draft.Accounts[$_]) -cne (Get-AccountTaskSignature $script:accountTasks.Config.Accounts[$_])})
            Save-AccountTasks $editor.Draft
            foreach($row in $script:rows.Values){
                if(($row.Client.Flavor+':'+$row.AccountName) -cin $changed){
                    $current=@(Get-AccountTaskRoles $row | Where-Object {$_.Name -ceq $row.CurrentRole})
                    if($current.Count -eq 1){if($current[0].Mode -cne $row.TaskMode){$row.Validated=$false}else{$row.SlotUseItem=$current[0].UseItem}}
                    Stop-Row $row '子战网角色任务已保存，请重新开始。'
                }
                Update-RotationRow $row
            }
            $editor.Error.Text='子战网任务与检测周期已保存。'
            Update-WowAutoRunInfo;Update-BatchControls
        }catch{$editor.Error.Text=$_.Exception.Message}
    })
    if($script:accountTasks.Warnings.Count){$errorLabel.Text=$script:accountTasks.Warnings -join '；'}
    $page.Controls.AddRange([Windows.Forms.Control[]]@($label,$accounts,$hint,$grid,$periodGroup,$errorLabel,$save))
    if($accounts.Items.Count){$accounts.SelectedIndex=0}
    return $page
}
function Save-AccountGridDraft($Editor) {
    if(-not $Editor.Selected){return}
    $null=$Editor.Grid.EndEdit()
    $roles=@(foreach($row in $Editor.Grid.Rows){@{Name=[string]$row.Cells['Name'].Value;Realm=[string]$row.Cells['Realm'].Value;
        Enabled=[bool]$row.Cells['Enabled'].Value;Mode=$(if($row.Cells['Mode'].Value -eq '战斗'){'fight'}else{'fish'});UseItem=([bool]$row.Cells['UseItem'].Value -and $row.Cells['Mode'].Value -eq '钓鱼')}})
    $Editor.Draft.Accounts[$Editor.Selected]=$roles
}
function Show-AccountGridDraft($Editor,[string]$Key) {
    $Editor.Loading=$true
    try {
        $Editor.Grid.Rows.Clear();$Editor.Selected=$Key
        if(-not $Key){return}
        $records=$script:accountTasks.Catalog[$Key].Characters
        foreach($role in $Editor.Draft.Accounts[$Key]) {
            $record=@($records | Where-Object {$_.Name -ceq $role.Name -and $_.Realm -ceq $role.Realm})
            if($record.Count -ne 1){continue}
            $index=$Editor.Grid.Rows.Add([object[]]@($role.Enabled,$role.Name,$role.Realm,$(if($role.Mode -eq 'fight'){'战斗'}else{'钓鱼'}),$role.UseItem,$record[0].Level,$record[0].FreeBagSlots))
            $Editor.Grid.Rows[$index].Cells['UseItem'].ReadOnly=$role.Mode -eq 'fight'
        }
    }finally{$Editor.Loading=$false}
}
