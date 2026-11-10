. (Join-Path $PSScriptRoot 'autoFight.Engine.ps1')
. (Join-Path $PSScriptRoot 'autoTame.Engine.ps1')
$tamePath=Join-Path $PSScriptRoot 'autoTame.config.json'
if($UiTest){$tamePath=Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-tame-ui-'+[guid]::NewGuid().ToString('N')+'.json')}
$script:autoTame=@{ConfigPath=$tamePath;Config=(New-AutoTameConfig);Error='';Ui=$null}
try {$script:autoTame.Config=Read-AutoTameConfig $tamePath}catch{$script:autoTame.Error=$_.Exception.Message}
function Save-AutoTamePage {
    $ui=$script:autoTame.Ui
    $draft=New-AutoTameConfig
    foreach($stage in @('Trap','Opening','Backward','Tame')) {
        $draft.($stage+'Key')=$ui.Keys[$stage].Text
        $draft.($stage+'WaitMs')=[int]($ui.Waits[$stage].Value*1000)
    }
    $script:autoTame.Config=Save-AutoTameConfig $script:autoTame.ConfigPath $draft
    $script:autoTame.Error=''
    $ui.Feedback.Text='抓宠设置已保存，下次开始时生效。'
}
function Start-AutoTameRow($Row) {
    if(-not $script:useWorkers){throw '抓宠需要并行检测与操作线程。'}
    if(-not $Row -or $Row.Exited){throw '请选择有效的游戏进程。'}
    if($script:parallelHub.Closing -or $script:characterCreate.Busy -or $script:editingSettings -or $script:scanning -or $script:shutdownState.Started -or $script:restartRequested){throw '请先结束角色创建、设置编辑、刷新或退出任务。'}
    if($Row.RuntimeRunning -or $Row.RuntimeScanning -or $Row.RuntimeExiting){throw '请先停止此进程的当前任务。'}
    $null=ConvertTo-AutoTameConfig $script:autoTame.Config -RequireKey
    $Row.TaskMode='tame';$Row.Validated=$false;$Row.RuntimeRunning=$true;$Row.RuntimeDirect=$true;$Row.RuntimePhase='running'
    try {
        Send-ParallelCommand $Row Start '' $true
        $script:parallelHub.ActiveTasks=@($script:rows.Values | Where-Object RuntimeRunning).Count
        Set-RowStatusText $Row '正在开启抓宠检测，等待匹配当前目标名称。'
        Update-WowAutoRunInfo
    }catch{$Row.RuntimeRunning=$false;$Row.RuntimeDirect=$false;$Row.RuntimePhase='stopped';throw}
}
function Update-AutoTamePage {
    $ui=$script:autoTame.Ui
    if(-not $ui){return}
    $rows=@($script:rows.Values | Where-Object {-not $_.Exited} | Sort-Object {$_.Process.Id})
    $signature=($rows | ForEach-Object Key) -join ','
    if($signature -cne $ui.Signature) {
        $selected=if($ui.Windows.SelectedIndex -ge 0){$ui.Rows[$ui.Windows.SelectedIndex].Key}else{''}
        $ui.Signature=$signature;$ui.Rows=$rows;$ui.Windows.Items.Clear()
        foreach($row in $rows){$null=$ui.Windows.Items.Add($row.Caption+' [PID '+$row.Process.Id+' / '+$row.Client.Label+']')}
        if($rows.Count){$ui.Windows.SelectedIndex=0}
        for($i=0;$i -lt $rows.Count;$i++){if($rows[$i].Key -eq $selected){$ui.Windows.SelectedIndex=$i;break}}
    }
    $row=if($ui.Windows.SelectedIndex -ge 0){$ui.Rows[$ui.Windows.SelectedIndex]}else{$null}
    $available=$row -and -not $script:parallelHub.Closing -and -not $script:characterCreate.Busy -and -not $script:scanning -and -not $script:editingSettings -and -not $script:shutdownState.Started -and -not $script:restartRequested
    $ui.Start.Enabled=$available -and -not $row.RuntimeRunning -and -not $row.RuntimeScanning -and -not $row.RuntimeExiting
    $ui.Stop.Enabled=$row -and $row.RuntimeRunning -and $row.TaskMode -eq 'tame'
    $ui.Status.Text=if($row){$row.StatusMessage}else{'使用“进程任务”页的刷新按钮发现游戏进程。'}
}
function Initialize-AutoTamePage {
    $page=New-Object Windows.Forms.TabPage
    $page.Text='自动抓宠';$page.BackColor=$script:uiColors.Background;$page.ForeColor=$script:uiColors.Text;$page.AutoScroll=$true
    $page.AutoScrollMinSize=New-Object Drawing.Size(900,620)
    $tabs.TabPages.Add($page)
    $ui=@{Page=$page;Keys=@{};Waits=@{};Rows=@();Signature=$null};$script:autoTame.Ui=$ui
    $title=New-Object Windows.Forms.Label;$title.Text='自动抓宠';$title.SetBounds(20,16,850,36);$title.Font=New-Object Drawing.Font($form.Font.FontFamily,18,[Drawing.FontStyle]::Bold)
    $hint=New-Object Windows.Forms.Label;$hint.Text='插件 /pettamer 设置名单并保存。匹配当前目标后，按陷阱 → 开怪 → 后退 → 捕捉执行。';$hint.SetBounds(20,62,850,32)
    $page.Controls.AddRange([Windows.Forms.Control[]]@($title,$hint))
    $labels=@{Trap='陷阱（可选）';Opening='开怪（可选）';Backward='后退（可选）';Tame='捕捉（必选）'}
    $y=110
    foreach($stage in @('Trap','Opening','Backward','Tame')) {
        $label=New-Object Windows.Forms.Label;$label.Text=$labels[$stage];$label.SetBounds(20,$y,130,32)
        $box=New-AutoFightKeyBox;$box.Text=$script:autoTame.Config.($stage+'Key');$box.SetBounds(155,$y,170,32)
        $clear=New-Object WowAuto.DimButton;$clear.Text='清空';$clear.SetBounds(335,$y,64,32);Set-UiButtonStyle $clear
        $clear.Tag=$box;$clear.Add_Click({param($sender,$eventArgs) $sender.Tag.Text=''})
        $waitLabel=New-Object Windows.Forms.Label;$waitLabel.Text=if($stage -eq 'Tame'){'执行时长 / 重试间隔（秒）'}else{'执行后等待（秒）'};$waitLabel.SetBounds(420,$y,230,32)
        $wait=New-Object Windows.Forms.NumericUpDown;$wait.DecimalPlaces=2;$wait.Increment=[decimal]0.1;$wait.Minimum=0;$wait.Maximum=600
        if($stage -eq 'Tame'){$wait.Minimum=[decimal]0.1}
        $wait.Value=[decimal]$script:autoTame.Config.($stage+'WaitMs')/1000;$wait.SetBounds(660,$y,110,32)
        $page.Controls.AddRange([Windows.Forms.Control[]]@($label,$box,$clear,$waitLabel,$wait));$ui.Keys[$stage]=$box;$ui.Waits[$stage]=$wait
        $y+=52
    }
    $note=New-Object Windows.Forms.Label;$note.Text='可选按键留空则跳过该阶段及等待。每次短按并释放，之后开始计时。捕捉重复到目标丢失或脱战。';$note.SetBounds(20,326,860,48)
    $save=New-Object WowAuto.DimButton;$save.Text='保存抓宠设置';$save.SetBounds(20,380,160,36);Set-UiButtonStyle $save
    $save.Add_Click({try{Save-AutoTamePage}catch{$script:autoTame.Ui.Feedback.Text=$_.Exception.Message}})
    $feedback=New-Object Windows.Forms.Label;$feedback.SetBounds(200,384,650,44);$feedback.Text=$script:autoTame.Error;$ui.Feedback=$feedback
    $windows=New-Object Windows.Forms.ComboBox;$windows.DropDownStyle='DropDownList';$windows.SetBounds(20,450,540,34);$ui.Windows=$windows
    $start=New-Object WowAuto.DimButton;$start.Text='开始抓宠';$start.SetBounds(580,448,120,36);Set-UiButtonStyle $start;$ui.Start=$start
    $stop=New-Object WowAuto.DimButton;$stop.Text='停止抓宠';$stop.SetBounds(720,448,120,36);Set-UiButtonStyle $stop;$ui.Stop=$stop
    $status=New-Object Windows.Forms.Label;$status.SetBounds(20,506,830,80);$ui.Status=$status
    $start.Add_Click({
        try {
            Save-AutoTamePage
            $ui=$script:autoTame.Ui
            $row=if($ui.Windows.SelectedIndex -ge 0){$ui.Rows[$ui.Windows.SelectedIndex]}else{$null}
            Start-AutoTameRow $row
        }catch{$script:autoTame.Ui.Feedback.Text=$_.Exception.Message}
        Update-AutoTamePage
    })
    $stop.Add_Click({$ui=$script:autoTame.Ui;if($ui.Windows.SelectedIndex -ge 0){$row=$ui.Rows[$ui.Windows.SelectedIndex];if($row.TaskMode -eq 'tame'){Stop-Row $row}};Update-AutoTamePage})
    $windows.Add_SelectedIndexChanged({Update-AutoTamePage})
    $page.Controls.AddRange([Windows.Forms.Control[]]@($note,$save,$feedback,$windows,$start,$stop,$status))
    Update-AutoTamePage
}
