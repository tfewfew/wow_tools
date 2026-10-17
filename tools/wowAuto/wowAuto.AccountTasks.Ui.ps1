function New-AccountTaskSettingsPage {
    Update-AccountTaskCatalog
    $page=New-Object Windows.Forms.TabPage;$page.Text='子战网';$page.BackColor=$script:uiColors.Background;$page.AutoScroll=$true
    $draft=ConvertTo-TaskMap ($script:accountTasks.Config | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
    $clients=New-Object WowAuto.DimTabControl;$clients.SetBounds(18,18,920,682)
    $clients.HeaderBackground=[Drawing.Color]::Black;$clients.HeaderSurface=$script:uiColors.Tab
    $clients.ForeColor=$script:uiColors.Text;$clients.SizeMode='Fixed';$clients.ItemSize=New-Object Drawing.Size(150,32)
    $errorLabel=New-Object Windows.Forms.Label;$errorLabel.SetBounds(18,716,920,56)
    $save=New-Object WowAuto.DimButton;$save.Text='保存子战网设置';$save.SetBounds(18,782,210,36);Set-UiButtonStyle $save $true
    $editor=[pscustomobject]@{Draft=$draft;ClientTabs=$clients;Clients=@{};Save=$save;Error=$errorLabel}
    $page.Tag=$editor;$save.Tag=$editor
    foreach($spec in @(@('titan','时光服'),@('forerver','永恒服'))) {
        $clientPage=New-Object Windows.Forms.TabPage;$clientPage.Text=$spec[1];$clientPage.BackColor=$script:uiColors.Background;$clientPage.AutoScroll=$true
        $label=New-Object Windows.Forms.Label;$label.Text='子战网';$label.SetBounds(18,18,150,30)
        $accounts=New-Object Windows.Forms.ComboBox;$accounts.DropDownStyle='DropDownList';$accounts.SetBounds(170,15,710,34)
        $accounts.BackColor=$script:uiColors.Input;$accounts.ForeColor=$script:uiColors.Text;$accounts.FlatStyle='Flat'
        foreach($key in @($script:accountTasks.Catalog.Keys | Sort-Object)) {
            if($key.StartsWith($spec[0]+':',[StringComparison]::Ordinal)){[void]$accounts.Items.Add($script:accountTasks.Catalog[$key].Name)}
        }
        $hint=New-Object Windows.Forms.Label;$hint.Text='勾选启用的角色，选择钓鱼或战斗；进程绑定后按表中顺序轮转。新角色默认停用，选角只识别第一页。';$hint.SetBounds(18,58,880,52)
        if(-not $accounts.Items.Count){$hint.Text='尚未发现该服的子战网角色记录，请检查游戏目录，正常下线保存角色记录后刷新进程。'}
        $grid=New-Object Windows.Forms.DataGridView;$grid.SetBounds(18,116,880,500)
        $grid.AllowUserToAddRows=$false;$grid.AllowUserToDeleteRows=$false;$grid.AllowUserToOrderColumns=$false;$grid.RowHeadersVisible=$false
        $grid.BackgroundColor=$script:uiColors.Input;$grid.GridColor=$script:uiColors.Border;$grid.AutoGenerateColumns=$false
        $grid.DefaultCellStyle.BackColor=$script:uiColors.Input;$grid.DefaultCellStyle.ForeColor=$script:uiColors.Text
        $grid.DefaultCellStyle.SelectionBackColor=$script:uiColors.Tab;$grid.DefaultCellStyle.SelectionForeColor=$script:uiColors.Text
        $grid.EnableHeadersVisualStyles=$false;$grid.ColumnHeadersDefaultCellStyle.BackColor=$script:uiColors.Heading;$grid.ColumnHeadersDefaultCellStyle.ForeColor=$script:uiColors.Text
        $grid.RowTemplate.Height=32;$grid.ColumnHeadersHeight=34
        foreach($columnSpec in @(@('Enabled','启用',65,'check'),@('Name','角色',195,'text'),@('Realm','服务器',170,'text'),@('Mode','任务',110,'mode'),@('UseItem','钓鱼道具',115,'check'),@('Level','等级',65,'text'),@('FreeBagSlots','背包空格',115,'text'))) {
            $column=switch($columnSpec[3]) {'check'{New-Object Windows.Forms.DataGridViewCheckBoxColumn}'mode'{New-Object Windows.Forms.DataGridViewComboBoxColumn}default{New-Object Windows.Forms.DataGridViewTextBoxColumn}}
            $column.Name=$columnSpec[0];$column.HeaderText=$columnSpec[1];$column.Width=$columnSpec[2];$column.SortMode='NotSortable'
            if($columnSpec[3] -eq 'mode'){$column.Items.AddRange([object[]]@('钓鱼','战斗'));$column.FlatStyle='Flat'}
            $column.ReadOnly=$columnSpec[0] -in @('Name','Realm','Level','FreeBagSlots');[void]$grid.Columns.Add($column)
        }
        $clientEditor=[pscustomobject]@{Draft=$draft;Flavor=$spec[0];Page=$clientPage;Accounts=$accounts;Grid=$grid;Selected='';Error=$errorLabel;Loading=$false}
        $editor.Clients[$spec[0]]=$clientEditor;$clientPage.Tag=$clientEditor;$grid.Tag=$clientEditor;$accounts.Tag=$clientEditor
        $accounts.Add_SelectedIndexChanged({param($sender,$e)
            $editor=$sender.Tag
            try {Save-AccountGridDraft $editor;Show-AccountGridDraft $editor ($editor.Flavor+':'+[string]$sender.SelectedItem)}catch{$editor.Error.Text=$_.Exception.Message}
        })
        $grid.Add_CurrentCellDirtyStateChanged({param($sender,$e) if($sender.IsCurrentCellDirty){$null=$sender.CommitEdit([Windows.Forms.DataGridViewDataErrorContexts]::Commit)}})
        $grid.Add_CellValueChanged({param($sender,$e)
            if($sender.Tag.Loading -or $e.RowIndex -lt 0){return}
            $row=$sender.Rows[$e.RowIndex];$combat=$row.Cells['Mode'].Value -eq '战斗'
            $row.Cells['UseItem'].ReadOnly=$combat;if($combat){$row.Cells['UseItem'].Value=$false}
        })
        $grid.Add_DataError({param($sender,$e) $sender.Tag.Error.Text='角色任务输入无效，请选择钓鱼或战斗。';$e.ThrowException=$false})
        $clientPage.Controls.AddRange([Windows.Forms.Control[]]@($label,$accounts,$hint,$grid));$clients.TabPages.Add($clientPage)
        if($accounts.Items.Count){$accounts.SelectedIndex=0}
    }
    $save.Add_Click({param($sender,$e)
        $editor=$sender.Tag
        try {
            foreach($client in $editor.Clients.Values){Save-AccountGridDraft $client}
            $changed=@($editor.Draft.Accounts.Keys | Where-Object {(Get-AccountTaskSignature $editor.Draft.Accounts[$_]) -cne (Get-AccountTaskSignature $script:accountTasks.Config.Accounts[$_])})
            # Save only role drafts; keep the latest saved global periods and process bindings.
            $next=ConvertTo-TaskMap ($script:accountTasks.Config | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
            $next.Accounts=$editor.Draft.Accounts
            Save-AccountTasks $next
            foreach($row in $script:rows.Values){
                if(($row.Client.Flavor+':'+$row.AccountName) -cin $changed){
                    $current=@(Get-AccountTaskRoles $row | Where-Object {$_.Name -ceq $row.CurrentRole})
                    if($current.Count -eq 1){if($current[0].Mode -cne $row.TaskMode){$row.Validated=$false}else{$row.SlotUseItem=$current[0].UseItem}}
                    Stop-Row $row '子战网角色任务已保存，请重新开始。'
                }
                Update-RotationRow $row
            }
            $editor.Error.Text='子战网角色任务已保存。'
            Update-WowAutoRunInfo;Update-BatchControls
        }catch{$editor.Error.Text=$_.Exception.Message}
    })
    if($script:accountTasks.Warnings.Count){$errorLabel.Text=$script:accountTasks.Warnings -join '；'}
    $page.Controls.AddRange([Windows.Forms.Control[]]@($clients,$errorLabel,$save))
    return $page
}
function New-DetectionPeriodSettingsPage {
    $page=New-Object Windows.Forms.TabPage;$page.Text='检测周期';$page.BackColor=$script:uiColors.Background;$page.AutoScroll=$true
    $hint=New-Object Windows.Forms.Label;$hint.Text='全局设置：对两服所有进程生效，单位为毫秒（ms）。保存后关闭设置窗口，新周期用于后续检测。';$hint.SetBounds(18,18,920,60)
    $periodGroup=New-Object Windows.Forms.GroupBox;$periodGroup.Text='检测周期（ms，25–60000）';$periodGroup.SetBounds(18,94,920,482)
    $periodGroup.BackColor=$script:uiColors.Surface;$periodGroup.ForeColor=$script:uiColors.Text;$periods=@{};$i=0
    foreach($spec in @(@('FishMs','钓鱼色块'),@('FightMs','战斗色块'),@('MenuMs','选角画面'),@('LoginMs','登录确认 / 退出检查'),@('BaitMs','钓鱼道具'),@('DeathMs','角色死亡'),@('AudioMs','音频事件'),@('PositionMs','窗口位置'),@('CaptureRetryMs','画面等待重试'),@('OcrMs','OCR采样'))) {
        $x=20+($i%2)*450;$y=44+[Math]::Floor($i/2)*86;$i++
        $name=New-Object Windows.Forms.Label;$name.Text=$spec[1];$name.SetBounds($x,$y,245,30)
        $value=New-Object Windows.Forms.NumericUpDown;$value.Minimum=25;$value.Maximum=60000;$value.Increment=25;$value.Value=$script:accountTasks.Config.Periods[$spec[0]];$value.SetBounds(($x+250),($y-3),175,32)
        $value.BackColor=$script:uiColors.Input;$value.ForeColor=$script:uiColors.Text;$periods[$spec[0]]=$value
        $periodGroup.Controls.AddRange([Windows.Forms.Control[]]@($name,$value))
    }
    $errorLabel=New-Object Windows.Forms.Label;$errorLabel.SetBounds(18,598,920,56)
    $save=New-Object WowAuto.DimButton;$save.Text='保存检测周期';$save.SetBounds(18,674,210,36);Set-UiButtonStyle $save $true
    $editor=[pscustomobject]@{Periods=$periods;Save=$save;Error=$errorLabel};$page.Tag=$editor;$save.Tag=$editor
    $save.Add_Click({param($sender,$e)
        $editor=$sender.Tag
        try {
            # Merge into current saved data; never apply or overwrite another page's role draft.
            $next=ConvertTo-TaskMap ($script:accountTasks.Config | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
            foreach($key in $editor.Periods.Keys){$next.Periods[$key]=[int]$editor.Periods[$key].Value}
            Save-AccountTasks $next
            $editor.Error.Text='全局检测周期已保存。'
        }catch{$editor.Error.Text=$_.Exception.Message}
    })
    $page.Controls.AddRange([Windows.Forms.Control[]]@($hint,$periodGroup,$errorLabel,$save))
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