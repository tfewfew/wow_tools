# Embedded desktop page; the Python worker only recognizes frames and proposes actions.
if(-not ('WowAuto.CharacterCreate.Worker' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'wowAuto.CharacterCreate.cs')}
$script:characterCreate=@{Busy=$false;Worker=$null;Pending=$null;Endpoint=$null;Version=0L;StopAt=0L;F8=$false;F9=$false;Ui=$null}
function Get-CharacterPython {
    if($env:WOWAUTO_CHARACTER_PYTHON -and [IO.File]::Exists($env:WOWAUTO_CHARACTER_PYTHON)){return $env:WOWAUTO_CHARACTER_PYTHON}
    return Join-Path $PSScriptRoot 'character-create/.runtime/Scripts/python.exe'
}
function New-CharacterCreateWorker([string]$Python,[string]$Script) {
    if($UiTest){throw '界面测试必须提供角色创建后台替身。'}
    return New-Object WowAuto.CharacterCreate.Worker($Python,$Script)
}
function Write-CharacterStatus([string]$Text) {
    if(-not $script:characterCreate.Ui){return}
    $ui=$script:characterCreate.Ui;$ui.Status.Text=$Text
    $ui.Log.AppendText(([datetime]::Now.ToString('HH:mm:ss')+'  '+$Text+[Environment]::NewLine))
    if($ui.Log.Lines.Count -gt 500){$ui.Log.Lines=@($ui.Log.Lines | Select-Object -Last 300)}
    Write-WowAutoLog $Text -Row $script:characterCreate.Row -Kind 'character-create'
}
function Update-CharacterWindows {
    if($script:characterCreate.Busy -or -not $script:characterCreate.Ui){return}
    $ui=$script:characterCreate.Ui;$old=$ui.Windows.SelectedItem
    $ui.Windows.Items.Clear();$ui.Targets=@{}
    foreach($row in @($script:rows.Values | Sort-Object {$_.Process.Id})){
        $text=$row.Process.MainWindowTitle+' [PID '+$row.Process.Id+' / '+$row.Client.Flavor+']'
        if($text -like ('*'+$ui.Filter.Text+'*')){$null=$ui.Windows.Items.Add($text);$ui.Targets[$text]=$row}
    }
    if($old -and $ui.Windows.Items.Contains($old)){$ui.Windows.SelectedItem=$old}elseif($ui.Windows.Items.Count){$ui.Windows.SelectedIndex=0}
}
function Update-CharacterControls {
    if(-not $script:characterCreate.Ui){return}
    $ui=$script:characterCreate.Ui;$busy=$script:characterCreate.Busy
    foreach($control in @($ui.Start,$ui.Preview,$ui.File,$ui.Refresh,$ui.Filter,$ui.Windows,$ui.Interval,$ui.AutoStop,$ui.DryRun)){$control.Enabled=-not $busy}
    $ui.Stop.Enabled=$busy
    $tab.Enabled=-not $busy
}
function Stop-CharacterCreate {
    if(-not $script:characterCreate.Busy){return}
    [WowAuto.CharacterCreate.Native]::Cancelled.Set()
    if($script:characterCreate.Endpoint){$null=$script:characterCreate.Endpoint.Send('Stop','{}')}
    try{if($script:characterCreate.Worker){$script:characterCreate.Worker.Send('{"stop":true}')}}catch{}
    if(-not $script:characterCreate.StopAt){$script:characterCreate.StopAt=$script:schedulerClock.ElapsedMilliseconds+5000}
    $script:characterCreate.Ui.Status.Text='正在停止角色创建…'
}
function Close-CharacterCreate {
    Stop-CharacterCreate
    if($script:characterCreate.Worker){$script:characterCreate.Worker.Dispose();$script:characterCreate.Worker=$null}
    $script:characterCreate.Busy=$false
    if($script:characterCreate.Timer){$script:characterCreate.Timer.Stop();$script:characterCreate.Timer.Dispose()}
}
function Start-CharacterCreate([string]$Mode='run',[string]$Image='') {
    if($script:characterCreate.Busy){return}
    $ui=$script:characterCreate.Ui
    $script:characterCreate.Row=$null
    try {
        if(-not $script:useWorkers){throw '角色创建需要并行操作线程。'}
        if($script:editingSettings -or $script:scanning -or $script:restartRequested -or $script:shutdownState.Started -or $script:shutdownState.Deadline -gt 0){throw '请先结束刷新、设置编辑或退出倒计时。'}
        if(@($script:rows.Values | Where-Object {$_.RuntimeRunning -or $_.RuntimeScanning -or $_.RuntimeExiting}).Count){throw '请先停止进程任务，再开始角色创建。'}
        $python=Get-CharacterPython
        if(-not [IO.File]::Exists($python)){throw '角色创建运行环境缺失，请运行 character-create/install-runtime.ps1 准备环境。'}
        $row=$null
        if(-not $Image){$row=$ui.Targets[[string]$ui.Windows.SelectedItem];if(-not $row){throw '请选择有效的游戏窗口。'}}
        $script:characterCreate.Row=$row
        $config=@{mode=$Mode;image=$Image;interval=[double]$ui.Interval.Value;auto_stop=[bool]$ui.AutoStop.Checked;dry_run=[bool]$ui.DryRun.Checked}
        $path=Join-Path $PSScriptRoot 'character-create/data/settings.json'
        if(-not $UiTest){
            $null=[IO.Directory]::CreateDirectory((Split-Path $path -Parent))
            $temp=$path+'.tmp';[IO.File]::WriteAllText($temp,(@{interval=$config.interval;auto_stop=$config.auto_stop;title_filter=$ui.Filter.Text} | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
            if([IO.File]::Exists($path)){[IO.File]::Replace($temp,$path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$path)}
        }
        if($row){
            $endpoint=Ensure-ParallelWorker $row
            $null=$endpoint.Send('Stop','{}')
            $script:characterCreate.Endpoint=$endpoint;$script:characterCreate.Version=$endpoint.Version
        }else{$script:characterCreate.Endpoint=$null}
        [WowAuto.CharacterCreate.Native]::Cancelled.Reset()
        $script:characterCreate.Pending=$null;$script:characterCreate.StopAt=0L
        $script:characterCreate.Worker=New-CharacterCreateWorker $python (Join-Path $PSScriptRoot 'character-create/bridge.py')
        $script:characterCreate.Busy=$true;Update-CharacterControls
        $ui.Counts.Text='完成点击 0 次 · 确定点击 0 次'
        $script:characterCreate.Worker.Send(($config | ConvertTo-Json -Compress))
        Write-CharacterStatus '角色创建后台已启动，正在加载OCR；首次点击会等待完整重试间隔。'
    }catch{
        [WowAuto.CharacterCreate.Native]::Cancelled.Set()
        if($script:characterCreate.Worker){$script:characterCreate.Worker.Dispose();$script:characterCreate.Worker=$null}
        $script:characterCreate.Busy=$false;Update-CharacterControls;Write-CharacterStatus $_.Exception.Message
    }
}
function Show-CharacterPreview($Message) {
    $bytes=[Convert]::FromBase64String($Message.png);$stream=New-Object IO.MemoryStream(,$bytes)
    try{$source=[Drawing.Image]::FromStream($stream);try{$bitmap=New-Object Drawing.Bitmap($source)}finally{$source.Dispose()}}finally{$stream.Dispose()}
    $dialog=New-Object Windows.Forms.Form;$dialog.Text='角色创建识别预览（不执行点击）';$dialog.Size=New-Object Drawing.Size(1000,660);$dialog.StartPosition='CenterParent'
    $picture=New-Object Windows.Forms.PictureBox;$picture.Dock='Fill';$picture.SizeMode='Zoom';$picture.Image=$bitmap;$dialog.Controls.Add($picture)
    $dialog.Tag=$bitmap;$dialog.Add_FormClosed({param($sender,$args) $sender.Tag.Dispose();$sender.Dispose()});$dialog.Show($form)
    Write-CharacterStatus ($Message.description+'；OCR '+[Math]::Round($Message.seconds,2)+'秒')
    foreach($hit in $Message.hits){Write-CharacterStatus ('OCR：'+$hit.text+'（'+[Math]::Round($hit.score*100)+'%）')}
}
function Invoke-CharacterMessage($Message) {
    $state=$script:characterCreate
    switch($Message.kind){
        'status' {$state.Ui.Status.Text=$Message.text}
        'log' {Write-CharacterStatus $Message.text}
        'error' {Write-CharacterStatus ('角色创建错误：'+$Message.text)}
        'counts' {$state.Ui.Counts.Text='完成点击 '+$Message.finish+' 次 · 确定点击 '+$Message.confirm+' 次'}
        'preview' {Show-CharacterPreview $Message}
        'finished' {Write-CharacterStatus $Message.text}
        'operation' {
            if($state.Pending){throw '角色创建后端重复提交操作。'}
            if(-not $state.Endpoint -or -not $state.Endpoint.Current($state.Version) -or [WowAuto.CharacterCreate.Native]::Cancelled.IsSet){
                $state.Worker.Send((@{id=$Message.id;error='目标进程会话已失效或任务已取消。'} | ConvertTo-Json -Compress));return
            }
            if($Message.action -cnotin @('State','Capture','Activate','Click')){throw '未知角色创建请求。'}
            $body=$Message.data | ConvertTo-Json -Depth 6 -Compress
            $request=$script:parallelHub.Request($state.Endpoint,$state.Version,('Character.'+$Message.action),'Process',35,$body)
            $state.Pending=@{Id=$Message.id;Request=$request}
        }
    }
}
function Update-CharacterCreate {
    $state=$script:characterCreate
    if(-not $UiTest){
        $f8=[WowAuto.CharacterCreate.Native]::KeyDown(0x77);$f9=[WowAuto.CharacterCreate.Native]::KeyDown(0x78)
        if($f9 -and -not $state.F9 -and $state.Busy){Stop-CharacterCreate}
        if($f8 -and -not $state.F8 -and $tabs.SelectedTab -eq $state.Ui.Page){if($state.Busy){Stop-CharacterCreate}else{Start-CharacterCreate}}
        $state.F8=$f8;$state.F9=$f9
    }
    if(-not $state.Worker){return}
    try {
        for($i=0;$i -lt 30;$i++){$line=$state.Worker.NextLine();if($null -eq $line){break};Invoke-CharacterMessage ($line | ConvertFrom-Json)}
        for($i=0;$i -lt 5;$i++){$line=$state.Worker.NextError();if($null -eq $line){break};Write-CharacterStatus $line}
        if($state.Pending -and $state.Pending.Request.Done.IsSet){
            $pending=$state.Pending;$state.Pending=$null;$request=$pending.Request
            $reply=@{id=$pending.Id}
            if($request.Success){$reply.data=$request.Result | ConvertFrom-Json}else{$reply.error=$request.Error}
            $state.Worker.Send(($reply | ConvertTo-Json -Depth 6 -Compress))
        }
        if($state.StopAt -gt 0 -and $script:schedulerClock.ElapsedMilliseconds -ge $state.StopAt){
            $state.Worker.Abort();$state.Worker=$null;$state.Pending=$null;$state.Busy=$false;$state.StopAt=0L;Update-CharacterControls;return
        }
        if($state.Worker.Exited){
            if($state.Endpoint){$null=$state.Endpoint.Send('Stop','{}')}
            $state.Worker.Dispose();$state.Worker=$null;$state.Pending=$null;$state.Busy=$false;$state.StopAt=0L
            [WowAuto.CharacterCreate.Native]::Cancelled.Set();Update-CharacterControls
        }
    }catch{Write-CharacterStatus $_.Exception.Message;Stop-CharacterCreate}
}
function Initialize-CharacterCreatePage {
    $page=New-Object Windows.Forms.TabPage;$page.Text='角色创建';$page.BackColor=$script:uiColors.Background;$page.ForeColor=$script:uiColors.Text;$page.AutoScroll=$true
    $null=$tabs.TabPages.Add($page)
    $ui=@{Page=$page;Targets=@{}};$script:characterCreate.Ui=$ui
    $title=New-Object Windows.Forms.Label;$title.Text='角色创建 · 自动重试';$title.SetBounds(20,15,1100,38);$title.Font=New-Object Drawing.Font($form.Font.FontFamily,18,[Drawing.FontStyle]::Bold);$page.Controls.Add($title)
    $hint=New-Object Windows.Forms.Label;$hint.Text='先选好外观并填写姓名。等待间隔 → 红色“完成” → 阵营人口不平衡时点击“确定” → 重新等待。';$hint.SetBounds(20,58,1150,30);$page.Controls.Add($hint)
    $filterLabel=New-Object Windows.Forms.Label;$filterLabel.Text='标题包含';$filterLabel.SetBounds(20,102,85,28);$page.Controls.Add($filterLabel)
    $filter=New-Object Windows.Forms.TextBox;$filter.Text='魔兽世界';$filter.SetBounds(105,100,160,30);$page.Controls.Add($filter);$ui.Filter=$filter
    $refresh=New-Object WowAuto.DimButton;$refresh.Text='刷新窗口';$refresh.SetBounds(280,96,100,36);Set-UiButtonStyle $refresh;$page.Controls.Add($refresh);$ui.Refresh=$refresh
    $windows=New-Object Windows.Forms.ComboBox;$windows.DropDownStyle='DropDownList';$windows.SetBounds(395,100,770,32);$windows.Anchor='Top,Left,Right';$page.Controls.Add($windows);$ui.Windows=$windows
    $label=New-Object Windows.Forms.Label;$label.Text='重试间隔（秒，1–86400）';$label.SetBounds(20,151,230,28);$page.Controls.Add($label)
    $interval=New-Object Windows.Forms.NumericUpDown;$interval.Minimum=1;$interval.Maximum=86400;$interval.DecimalPlaces=1;$interval.Value=30;$interval.SetBounds(260,148,140,32);$page.Controls.Add($interval);$ui.Interval=$interval
    $auto=New-Object Windows.Forms.CheckBox;$auto.Text='连续12秒找不到红色“完成”时自动停止';$auto.Checked=$true;$auto.SetBounds(20,198,570,30);$page.Controls.Add($auto);$ui.AutoStop=$auto
    $dry=New-Object Windows.Forms.CheckBox;$dry.Text='试运行：识别和记录，不点击';$dry.SetBounds(615,198,550,30);$page.Controls.Add($dry);$ui.DryRun=$dry
    $names=@('Start','Stop','Preview','File');$labels=@('开始 F8','停止 F9','仅识别游戏','从图片测试')
    for($i=0;$i -lt 4;$i++){$button=New-Object WowAuto.DimButton;$button.Text=$labels[$i];$button.SetBounds(20+$i*170,245,155,38);Set-UiButtonStyle $button ($i -eq 0);$page.Controls.Add($button);$ui[$names[$i]]=$button}
    $status=New-Object Windows.Forms.Label;$status.Text='就绪。首次点击前等待完整间隔；提前最多3秒切换前台，失败3次跳过本轮。';$status.SetBounds(20,300,1145,48);$status.Anchor='Top,Left,Right';$page.Controls.Add($status);$ui.Status=$status
    $counts=New-Object Windows.Forms.Label;$counts.Text='完成点击 0 次 · 确定点击 0 次';$counts.SetBounds(20,352,1145,30);$page.Controls.Add($counts);$ui.Counts=$counts
    $log=New-Object Windows.Forms.TextBox;$log.Multiline=$true;$log.ReadOnly=$true;$log.ScrollBars='Vertical';$log.SetBounds(20,395,1145,190);$log.Anchor='Top,Left,Right,Bottom';$log.BackColor=$script:uiColors.Input;$log.ForeColor=$script:uiColors.Text;$page.Controls.Add($log);$ui.Log=$log
    $path=Join-Path $PSScriptRoot 'character-create/data/settings.json'
    if(-not $UiTest -and [IO.File]::Exists($path)){try{$saved=[IO.File]::ReadAllText($path)|ConvertFrom-Json;if($saved.interval -ge 1 -and $saved.interval -le 86400){$interval.Value=$saved.interval};$auto.Checked=[bool]$saved.auto_stop;$filter.Text=[string]$saved.title_filter}catch{Write-CharacterStatus '角色创建设置读取失败，已使用默认值。'}}
    $refresh.Add_Click({if(-not $script:characterCreate.Busy){$null=Refresh-ProcessRows;Update-CharacterWindows}})
    $ui.Start.Add_Click({Start-CharacterCreate});$ui.Stop.Add_Click({Stop-CharacterCreate});$ui.Preview.Add_Click({Start-CharacterCreate preview})
    $ui.File.Add_Click({$dialog=New-Object Windows.Forms.OpenFileDialog;$dialog.Filter='图片|*.png;*.jpg;*.jpeg;*.bmp';try{if($dialog.ShowDialog($form) -eq 'OK'){Start-CharacterCreate preview $dialog.FileName}}finally{$dialog.Dispose()}})
    Update-CharacterWindows;Update-CharacterControls
    $timer=New-Object Windows.Forms.Timer;$timer.Interval=50;$timer.Add_Tick({Update-CharacterCreate});$script:characterCreate.Timer=$timer
    if(-not $UiTest){$timer.Start()}
}
