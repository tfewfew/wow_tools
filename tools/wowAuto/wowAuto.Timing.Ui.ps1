function New-OperationTimingSettingsPage {
    $page=New-Object Windows.Forms.TabPage;$page.Text='操作队列';$page.BackColor=$script:uiColors.Background;$page.AutoScroll=$true
    $hint=New-Object Windows.Forms.Label;$hint.Text='两服所有进程共用，单位为毫秒（ms）。保存并关闭设置后用于后续操作；已提交的操作保留原参数。';$hint.SetBounds(18,12,1280,36)
    $page.Controls.Add($hint);$specs=Get-OperationTimingSpecs;$inputs=@{};$y=54
    foreach($groupName in @('线程与界面','前台与重试','按键与动作等待','点击与画面重试')){
        $keys=@($specs.Keys | Where-Object {$specs[$_][4] -ceq $groupName});$height=42+[int][Math]::Ceiling($keys.Count/2.0)*40
        $group=New-Object Windows.Forms.GroupBox;$group.Text=$groupName+'（ms）';$group.SetBounds(18,$y,1280,$height)
        $group.BackColor=$script:uiColors.Surface;$group.ForeColor=$script:uiColors.Text;$i=0
        foreach($key in $keys){
            $spec=$specs[$key];$x=18+($i%2)*630;$rowY=30+[Math]::Floor($i/2)*40;$i++
            $label=New-Object Windows.Forms.Label;$label.Text=$spec[0];$label.SetBounds($x,$rowY,390,30)
            $value=New-Object Windows.Forms.NumericUpDown;$value.Minimum=$spec[2];$value.Maximum=$spec[3];$value.Increment=1
            $value.Value=$script:accountTasks.Config.Operations[$key];$value.SetBounds(($x+395),($rowY-2),200,30)
            $value.BackColor=$script:uiColors.Input;$value.ForeColor=$script:uiColors.Text;$inputs[$key]=$value
            $group.Controls.AddRange([Windows.Forms.Control[]]@($label,$value))
        }
        $page.Controls.Add($group);$y+=$height+12
    }
    $errorLabel=New-Object Windows.Forms.Label;$errorLabel.SetBounds(18,$y,1280,42)
    $save=New-Object WowAuto.DimButton;$save.Text='保存操作队列设置';$save.SetBounds(18,($y+48),230,36);Set-UiButtonStyle $save $true
    $editor=[pscustomobject]@{Values=$inputs;Save=$save;Error=$errorLabel};$page.Tag=$editor;$save.Tag=$editor
    $save.Add_Click({param($sender,$e)
        $editor=$sender.Tag
        try {
            $next=ConvertTo-TaskMap ($script:accountTasks.Config | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
            $values=@{};foreach($key in $editor.Values.Keys){$values[$key]=[int]$editor.Values[$key].Value}
            $next.Operations=$values;Save-AccountTasks $next
            $editor.Error.Text='操作队列设置已保存，关闭设置窗口后应用。'
        }catch{$editor.Error.Text=$_.Exception.Message}
    })
    $page.Controls.AddRange([Windows.Forms.Control[]]@($errorLabel,$save))
    return $page
}
function New-GlobalTimingSettingsPage {
    $page=New-Object Windows.Forms.TabPage;$page.Text='检测与操作';$page.BackColor=$script:uiColors.Background
    $tabs=New-Object WowAuto.DimTabControl;$tabs.Dock='Fill';$tabs.HeaderBackground=[Drawing.Color]::Black;$tabs.HeaderSurface=$script:uiColors.Tab
    $tabs.ForeColor=$script:uiColors.Text;$tabs.SizeMode='Fixed';$tabs.ItemSize=New-Object Drawing.Size(180,32)
    $detection=New-DetectionPeriodSettingsPage;$operations=New-OperationTimingSettingsPage
    $tabs.TabPages.AddRange([Windows.Forms.TabPage[]]@($detection,$operations));$page.Controls.Add($tabs)
    $page.Tag=[pscustomobject]@{Tabs=$tabs;Detection=$detection;Operations=$operations}
    return $page
}
function Hide-LegacyTimingInput($Control,[string]$Label) {
    $Control.Visible=$false
    foreach($child in $Control.Parent.Controls){if($child -is [Windows.Forms.Label] -and $child.Text -ceq $Label){$child.Visible=$false}}
}
