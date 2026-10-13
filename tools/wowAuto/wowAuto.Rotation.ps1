# Three character slots per process; one monotonic deadline starts a batch for all active plans.
if (-not ('WowAutoRotation.Native' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'wowAuto.Rotation.Native.cs') -ReferencedAssemblies System.Drawing
}
$script:rotation=[pscustomobject]@{Path=(Join-Path $PSScriptRoot 'rotation.config.json');IntervalSeconds=0;Plans=@{};
    Active=@{};Queue=(New-Object Collections.Queue);Current=$null;NextAt=0L;ConfigReady=$true;Error='';Actions=@()}
function New-RotationPlan {
    return [pscustomobject]@{Slots=@(1..3 | ForEach-Object {[pscustomobject]@{Character=0;Mode='fish'}});Menu=$null}
}
function Copy-RotationPlan($Plan) {return ($Plan | ConvertTo-Json -Depth 8 | ConvertFrom-Json)}
function Test-RotationPlan($Plan) {
    if (-not $Plan -or @($Plan.Slots).Count -ne 3) {throw '每个进程必须配置三个槽位。'}
    foreach ($slot in $Plan.Slots) {
        $n=0
        if (-not [int]::TryParse([string]$slot.Character,[ref]$n) -or $n -lt 0 -or $n -gt 65 -or $slot.Mode -cnotin @('fish','fight')) {throw '角色号须为0–65，任务须为钓鱼或战斗。'}
    }
    if ($Plan.Menu) {
        $m=$Plan.Menu
        if ($m.Count -lt 1 -or $m.Count -gt 65 -or $m.Count -ne [int]$m.Count -or $m.Aspect -lt 0.5 -or $m.Aspect -gt 5 -or
            $m.FirstX -le 0 -or $m.FirstX -ge 1 -or $m.FirstY -le 0 -or $m.FirstY -ge 1 -or
            $m.X -lt 0 -or $m.Y -lt 0 -or $m.W -le 0 -or $m.H -le 0 -or $m.X+$m.W -gt 1 -or $m.Y+$m.H -gt 1 -or @($m.Pixels).Count -ne 384) {throw '角色选择界面标定无效。'}
        foreach ($v in $m.Pixels) {if ($v -lt 0 -or $v -gt 255 -or $v -ne [int]$v) {throw '角色选择界面特征无效。'}}
        if (-not [WowAutoRotation.Native]::Matches([int[]]$m.Pixels,[int[]]$m.Pixels)) {throw '请框选有清晰固定文字的界面区域，不能使用纯色或黑色区域。'}
        foreach ($slot in $Plan.Slots) {if ($slot.Character -gt $m.Count) {throw '角色号超过标定的角色总数。'}}
    }
}
function Save-RotationConfiguration($Interval=$script:rotation.IntervalSeconds,$Plans=$script:rotation.Plans) {
    $n=0
    if (-not [int]::TryParse([string]$Interval,[ref]$n) -or $n -lt 0 -or $n -gt 604800) {throw '轮换间隔须为0–604800秒，0关闭定时轮换。'}
    foreach ($key in $Plans.Keys) {
        $p=0;$ticks=0L
        if ($key -notmatch '^([1-9]\d*):([1-9]\d*)$' -or -not [int]::TryParse($matches[1],[ref]$p) -or
            -not [long]::TryParse($matches[2],[ref]$ticks) -or $ticks -gt [datetime]::MaxValue.Ticks) {throw '进程编排标识无效。'}
        Test-RotationPlan $Plans[$key]
    }
    $payload=[ordered]@{Version=1;IntervalSeconds=$n;Plans=$Plans}
    $temporary=$script:rotation.Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temporary,($payload | ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($script:rotation.Path)) {[IO.File]::Replace($temporary,$script:rotation.Path,[System.Management.Automation.Language.NullString]::Value)}
        else {[IO.File]::Move($temporary,$script:rotation.Path)}
    } finally {if ([IO.File]::Exists($temporary)) {[IO.File]::Delete($temporary)}}
    $changed=$script:rotation.IntervalSeconds -ne $n
    $script:rotation.IntervalSeconds=$n;$script:rotation.Plans=$Plans;$script:rotation.ConfigReady=$true;$script:rotation.Error=''
    if ($changed) {$script:rotation.NextAt=if ($n -and $script:rotation.Active.Count) {$script:schedulerClock.ElapsedMilliseconds+[long]$n*1000} else {0L}}
    foreach ($r in $script:rows.Values) {Update-RotationRow $r}
}
function Import-RotationConfiguration {
    if (-not [IO.File]::Exists($script:rotation.Path)) {return}
    try {
        $c=[IO.File]::ReadAllText($script:rotation.Path) | ConvertFrom-Json
        if ($c.Version -ne 1 -or $null -eq $c.IntervalSeconds -or -not $c.Plans -or
            @($c.PSObject.Properties.Name | Where-Object {$_ -notin @('Version','IntervalSeconds','Plans')}).Count) {throw '编排配置格式无效。'}
        $n=0;if (-not [int]::TryParse([string]$c.IntervalSeconds,[ref]$n) -or $n -lt 0 -or $n -gt 604800) {throw '编排间隔无效。'}
        $plans=@{}
        foreach ($prop in $c.Plans.PSObject.Properties) {
            $p=0;$t=0L
            if ($prop.Name -notmatch '^([1-9]\d*):([1-9]\d*)$' -or -not [int]::TryParse($matches[1],[ref]$p) -or
                -not [long]::TryParse($matches[2],[ref]$t) -or $t -gt [datetime]::MaxValue.Ticks) {throw '编排进程标识无效。'}
            Test-RotationPlan $prop.Value;$plans[$prop.Name]=$prop.Value
        }
        $script:rotation.IntervalSeconds=$n;$script:rotation.Plans=$plans;$script:rotation.ConfigReady=$true;$script:rotation.Error=''
    } catch {$script:rotation.ConfigReady=$false;$script:rotation.Error='编排配置读取失败：'+$_.Exception.Message}
}
function Get-RotationNextSlot($Plan,[int]$Current) {
    for ($i=1;$i -le 3;$i++) {$index=($Current+$i)%3;if ($Plan.Slots[$index].Character -gt 0) {return $index}}
    return -1
}
function Get-RowRotationPlan($Row) {
    if ($script:rotation.Plans.ContainsKey($Row.Key)) {return $script:rotation.Plans[$Row.Key]}
    return (New-RotationPlan)
}
function Test-RowHasRotation($Row) {return (Get-RotationNextSlot (Get-RowRotationPlan $Row) -1) -ge 0}
function Update-RotationRow($Row) {
    if (-not $Row.PSObject.Properties['RotationLabel']) {return}
    $plan=Get-RowRotationPlan $Row
    $labels=for ($i=0;$i -lt 3;$i++) {
        $slot=$plan.Slots[$i];$mode=if ($slot.Mode -eq 'fight') {'战斗'} else {'钓鱼'}
        if ($slot.Character) {"槽$($i+1)：角色$($slot.Character) / $mode"} else {"槽$($i+1)：空"}
    }
    $Row.RotationLabel.Text=($labels -join '    ')
    if ($script:rotation.Active.ContainsKey($Row.Key)) {$Row.RotationLabel.Text+='    当前槽：'+($script:rotation.Active[$Row.Key].Index+1)}
    $Row.RotationButton.Enabled=-not $script:scanning -and -not $script:editingSettings
}
function Add-RotationRow($Row) {
    $Row.Panel.Height=190
    $button=New-Object WowAuto.DimButton;$button.Text='角色编排';$button.SetBounds(252,102,130,32);Set-UiButtonStyle $button
    $label=New-Object System.Windows.Forms.Label;$label.SetBounds(12,146,1180,35);$label.AutoEllipsis=$true
    $Row | Add-Member NoteProperty RotationButton $button
    $Row | Add-Member NoteProperty RotationLabel $label
    $button.Tag=$Row;$button.Add_Click({param($sender,$e) Show-RotationEditor $sender.Tag})
    $Row.Panel.Controls.AddRange([System.Windows.Forms.Control[]]@($button,$label));Update-RotationRow $Row
}
function Stop-RowRotation($Row) {
    if (-not $script:rotation) {return}
    $script:rotation.Active.Remove($Row.Key)
    if ($script:rotation.Current -and $script:rotation.Current.Row.Key -eq $Row.Key) {$script:rotation.Current=$null}
    if (-not $script:rotation.Active.Count) {$script:rotation.NextAt=0L}
    Update-RotationRow $Row
}
function Start-RowRotation($Row) {
    if ($script:scanning -or $script:editingSettings -or -not $script:rotation.ConfigReady) {throw '请关闭设置，修复编排配置后开始。'}
    if ($script:rotation.Active.ContainsKey($Row.Key)) {return}
    $plan=Get-RowRotationPlan $Row;Test-RotationPlan $plan
    if (-not $plan.Menu) {throw '请在角色编排中标定角色选择界面。'}
    $index=Get-RotationNextSlot $plan -1
    Stop-Row $Row '开始角色编排，准备登录第一个有效槽位。' -CancelExit
    $entry=[pscustomobject]@{Row=$Row;Plan=(Copy-RotationPlan $plan);Index=$index;Token=(Get-Random -Minimum 1 -Maximum 201)}
    $script:rotation.Active[$Row.Key]=$entry;$script:rotation.Queue.Enqueue($entry)
    if (-not $script:rotation.NextAt -and $script:rotation.IntervalSeconds) {$script:rotation.NextAt=$script:schedulerClock.ElapsedMilliseconds+[long]$script:rotation.IntervalSeconds*1000}
    Update-RotationRow $Row
}
function Begin-RotationBatch([long]$Now) {
    # Stop every member before the first window is touched; foreground input is serialized afterward.
    $entries=@($script:rotation.Active.Values | Sort-Object {$_.Row.Process.Id})
    foreach ($entry in $entries) {
        Stop-Row $entry.Row '全局轮换到期，停止动作并切换下一角色。' -CancelExit -KeepRotation
        $entry.Index=Get-RotationNextSlot $entry.Plan $entry.Index
        $entry.Token=Get-Random -Minimum 1 -Maximum 201
        $script:rotation.Queue.Enqueue($entry);Update-RotationRow $entry.Row
    }
    if ($script:rotation.IntervalSeconds) {$script:rotation.NextAt=$Now+[long]$script:rotation.IntervalSeconds*1000}
}
function Send-RotationAction($Row,[string]$Action,[int]$Value=0) {
    if (-not (Test-RowProcessIdentity $Row) -or $Row.Process.HasExited -or -not (Test-WorkerForeground $Row)) {throw '角色切换期间进程身份或前台已变化。'}
    if ($UiTest) {$script:rotation.Actions+=,[pscustomobject]@{Key=$Row.Key;Action=$Action;Value=$Value};return}
    switch ($Action) {
        'arm' {$sent=[WowAuto.NativeInput]::SendRotationCommand($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath,'arm',$Value)}
        'logout' {$sent=[WowAuto.NativeInput]::SendRotationCommand($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath,'logout',0)}
        'top' {$m=(Get-RowRotationPlan $Row).Menu;[WowAutoRotation.Native]::MouseAction($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath,$m.FirstX,$m.FirstY,$true);$sent=$true}
        'first' {$m=(Get-RowRotationPlan $Row).Menu;[WowAutoRotation.Native]::MouseAction($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath,$m.FirstX,$m.FirstY,$false);$sent=$true}
        'down' {$sent=[WowAuto.NativeInput]::PressChord($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath,40,$false,$false,$false)}
        'enter' {$sent=[WowAuto.NativeInput]::PressChord($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath,13,$false,$false,$false)}
        default {throw '未知编排动作。'}
    }
    if (-not $sent) {throw '角色切换输入失败。'}
}
function Read-RotationScreen($Row,$Menu) {
    if ($UiTest) {return $Row.Process.RotationScreen}
    $bitmap=[WowAutoRotation.Native]::Capture($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath)
    try {
        $token=[WowAutoRotation.Native]::ReadyToken($bitmap)
        if ($token -ge 0) {return [pscustomobject]@{Kind='world';Token=$token}}
        $center=$bitmap.GetPixel([int]($bitmap.Width/2),[int]($bitmap.Height/2))
        if ($center.R -ge 20 -and $center.R -le 220 -and [Math]::Abs($center.G-231) -le 1 -and [Math]::Abs($center.B-181) -le 1) {return [pscustomobject]@{Kind='combat';Token=($center.R-20)}}
        $raw=[uint32]($center.R+256*$center.G+65536*$center.B)
        if ($Row.TaskMode -eq 'fish' -and [WowAuto.NativeInput]::ClassifyColor($raw) -in @('red','green','yellow')) {return [pscustomobject]@{Kind='world';Token=-1}}
        if ($Row.TaskMode -eq 'fight' -and [WowAutoFight.Native]::Decode([uint32[]]@($raw),$Row.Client.Flavor)) {return [pscustomobject]@{Kind='world';Token=-1}}
        if ([Math]::Abs($bitmap.Width/[double]$bitmap.Height-$Menu.Aspect) -gt 0.025) {return [pscustomobject]@{Kind='unknown';Token=-1}}
        $pixels=[WowAutoRotation.Native]::Fingerprint($bitmap,$Menu.X,$Menu.Y,$Menu.W,$Menu.H)
        if ([WowAutoRotation.Native]::Matches([int[]]$Menu.Pixels,$pixels)) {return [pscustomobject]@{Kind='menu';Token=-1}}
        return [pscustomobject]@{Kind='unknown';Token=-1}
    } finally {$bitmap.Dispose()}
}
function Invoke-RotationTick([long]$Now) {
    if ($script:scanning -or $script:editingSettings) {return $false}
    if (-not $script:rotation.Current -and -not $script:rotation.Queue.Count -and $script:rotation.NextAt -and $Now -ge $script:rotation.NextAt) {Begin-RotationBatch $Now}
    if (-not $script:rotation.Current) {
        while ($script:rotation.Queue.Count) {
            $entry=$script:rotation.Queue.Dequeue()
            if ($script:rotation.Active[$entry.Row.Key] -ne $entry) {continue}
            $script:rotation.Current=[pscustomobject]@{Entry=$entry;Row=$entry.Row;Phase='activate';Due=$Now;Deadline=($Now+180000);Stable=0;Down=0;LastLogout=-30000L;Armed=$false}
            break
        }
    }
    $work=$script:rotation.Current;if (-not $work) {return $false}
    if ($Now -lt $work.Due) {return $true}
    $row=$work.Row;$entry=$work.Entry
    try {
        $row.Process.Refresh()
        if ($row.Process.HasExited -or -not (Test-RowProcessIdentity $row)) {throw '角色轮换进程已退出或身份改变。'}
        if ($Now -ge $work.Deadline) {throw '角色切换超过180秒；检查战斗、排队、登录或界面标定后手动开始。'}
        if ($script:autoFight -and ($script:autoFight.ActiveHold -or [WowAutoFight.Native]::IsHolding)) {
            if (-not (Release-AutoFightHold)) {return $true}
        }
        if ($work.Phase -eq 'activate') {
            if (-not (Activate-ScanRow $row)) {throw '无法激活角色切换窗口。'}
            $work.Phase='inspect';$work.Due=$Now+200;return $true
        }
        if (-not (Test-WorkerForeground $row)) {throw '角色切换窗口失去前台，已停止本行。'}
        $screen=Read-RotationScreen $row $entry.Plan.Menu
        switch ($work.Phase) {
            'inspect' {
                if ($screen.Kind -eq 'menu') {$work.Phase='menu';$work.Stable=1}
                elseif ($screen.Kind -in @('world','combat')) {
                    Send-RotationAction $row 'arm' $entry.Token;$work.Armed=$true;$work.Phase='armed'
                }
                else {Set-RowStatusText $row '等待确认游戏内或已标定的角色选择界面。'}
            }
            'armed' {
                if ($screen.Kind -eq 'world' -and $screen.Token -eq $entry.Token) {
                    Send-RotationAction $row 'logout';$work.LastLogout=$Now;$work.Phase='menu';$row.Validated=$false
                } else {Set-RowStatusText $row '动作已停止，等待脱战后返回角色选择界面。'}
            }
            'menu' {
                if ($screen.Kind -eq 'menu') {
                    $work.Stable++
                    if ($work.Stable -ge 3) {Send-RotationAction $row 'top';$work.Phase='first'}
                } else {
                    $work.Stable=0
                    if ($work.Armed -and $screen.Kind -eq 'world' -and $screen.Token -eq $entry.Token -and $Now-$work.LastLogout -ge 30000) {Send-RotationAction $row 'logout';$work.LastLogout=$Now}
                    Set-RowStatusText $row '正在返回角色选择界面；等待退出倒计时完成。'
                }
            }
            'first' {
                if ($screen.Kind -ne 'menu') {throw '选角界面验证失败，未点击角色。'}
                Send-RotationAction $row 'first';$work.Down=[int]$entry.Plan.Slots[$entry.Index].Character-1;$work.Phase='select'
            }
            'select' {
                if ($screen.Kind -ne 'menu') {throw '选角期间界面已改变，未登录。'}
                if ($work.Down -gt 0) {Send-RotationAction $row 'down';$work.Down--}
                else {Send-RotationAction $row 'enter';$work.Phase='login';$work.Stable=0;Set-RowStatusText $row ('正在登录角色'+$entry.Plan.Slots[$entry.Index].Character+'，等待进入世界。')}
            }
            'login' {
                if ($screen.Kind -eq 'world' -and (($work.Armed -and $screen.Token -eq $entry.Token) -or (-not $work.Armed -and $screen.Token -ge 0))) {
                    $work.Stable++
                    if ($work.Stable -ge 2) {
                        $row.TaskMode=$entry.Plan.Slots[$entry.Index].Mode
                        $script:updatingPreferenceControls=$true
                        try {$row.ModeBox.SelectedIndex=if ($row.TaskMode -eq 'fight') {1} else {0}} finally {$script:updatingPreferenceControls=$false}
                        if ($row.TaskMode -eq 'fight') {Ensure-UnifiedFightRow $row}
                        if (-not (Send-ScanDetectorCommand $row)) {throw '登录后监控开启命令失败。'}
                        $work.Phase='validate';$work.Due=$Now+300;return $true
                    }
                } else {$work.Stable=0}
            }
            'validate' {
                if ($row.TaskMode -eq 'fight') {
                    $packet=Read-ScanFightPacket $row
                    if (-not $packet -or $packet.Flavor -ne $row.Client.Flavor) {$work.Due=$Now+300;return $true}
                    $row.FightRow.CanStart=$true;$row.FightRow.ClassId=$packet.ClassId
                } elseif ((Read-ScanColor $row) -notin @('red','green')) {$work.Due=$Now+300;return $true}
                $row.Validated=$true
                # Character-local counters must not make a newly logged-in character jump or exit.
                foreach ($table in @($script:scheduler.CompletedCycles,$script:scheduler.CyclesSinceJump)) {if ($null -ne $table) {$table.Remove($row.Key)}}
                Start-Row $row -TaskOnly
                if (-not (Test-UnifiedTaskRunning $row)) {throw '角色任务未能启动。'}
                Set-RowStatusText $row ('槽'+($entry.Index+1)+' / 角色'+$entry.Plan.Slots[$entry.Index].Character+' 已登录并开始任务。')
                $script:rotation.Current=$null
                if (-not $script:rotation.Queue.Count -and $script:rotation.NextAt -and $script:rotation.NextAt -le $Now) {$script:rotation.NextAt=$Now+[long]$script:rotation.IntervalSeconds*1000}
                Update-RotationRow $row;return $true
            }
        }
        $work.Due=$Now+300
    } catch {
        $reason=$_.Exception.Message
        Stop-Row $row ('角色编排停止：'+$reason) -CancelExit
        $row.Validated=$false;if ($row.FightRow) {$row.FightRow.CanStart=$false}
        $script:rotation.Current=$null
    }
    return $true
}

function New-RotationIntervalControls($SettingsOwner) {
    $bar=New-Object System.Windows.Forms.Panel;$bar.Dock='Top';$bar.Height=52;$bar.BackColor=$script:uiColors.Surface;$bar.ForeColor=$script:uiColors.Text
    $label=New-Object System.Windows.Forms.Label;$label.Text='全局角色轮换（秒，0关闭）';$label.SetBounds(12,12,285,30)
    $value=New-Object System.Windows.Forms.NumericUpDown;$value.Minimum=0;$value.Maximum=604800;$value.Value=$script:rotation.IntervalSeconds;$value.SetBounds(300,8,130,32)
    $value.BackColor=$script:uiColors.Input;$value.ForeColor=$script:uiColors.Text
    $save=New-Object WowAuto.DimButton;$save.Text='保存轮换间隔';$save.SetBounds(450,8,170,34);Set-UiButtonStyle $save
    $errorLabel=New-Object System.Windows.Forms.Label;$errorLabel.SetBounds(635,12,330,30);$errorLabel.AutoEllipsis=$true;$errorLabel.Text=$script:rotation.Error
    $save.Tag=[pscustomobject]@{Value=$value;Error=$errorLabel}
    $save.Add_Click({param($sender,$e) try {Save-RotationConfiguration $sender.Tag.Value.Value;$sender.Tag.Error.Text='已保存。'} catch {$sender.Tag.Error.Text=$_.Exception.Message}})
    $bar.Controls.AddRange([System.Windows.Forms.Control[]]@($label,$value,$save,$errorLabel));$SettingsOwner.Controls.Add($bar);$bar.SendToBack()
    return [pscustomobject]@{Value=$value;Save=$save;Error=$errorLabel}
}
function Get-CalibrationPoint($Picture,[int]$X,[int]$Y) {
    $scale=[Math]::Min($Picture.ClientSize.Width/[double]$Picture.Image.Width,$Picture.ClientSize.Height/[double]$Picture.Image.Height)
    $left=($Picture.ClientSize.Width-$Picture.Image.Width*$scale)/2;$top=($Picture.ClientSize.Height-$Picture.Image.Height*$scale)/2
    $nx=($X-$left)/($Picture.Image.Width*$scale);$ny=($Y-$top)/($Picture.Image.Height*$scale)
    if ($nx -le 0 -or $nx -ge 1 -or $ny -le 0 -or $ny -ge 1) {return $null}
    return [pscustomobject]@{X=$nx;Y=$ny}
}
function Get-RotationCalibration($Row,[int]$Count) {
    if ($UiTest) {return $Row.Process.Calibration}
    if (-not (Activate-ScanRow $Row)) {throw '无法激活待标定窗口。'}
    [Threading.Thread]::Sleep(200)
    $bitmap=[WowAutoRotation.Native]::Capture($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath)
    $dialog=New-Object WowAuto.DimForm;$dialog.Text='标定角色选择界面';$dialog.Font=$form.Font;$dialog.ClientSize=New-Object Drawing.Size(1000,700)
    $dialog.BackColor=$script:uiColors.Background;$dialog.ForeColor=$script:uiColors.Text;$dialog.AutoScaleMode='Dpi'
    $picture=New-Object System.Windows.Forms.PictureBox;$picture.Dock='Fill';$picture.SizeMode='Zoom';$picture.Image=$bitmap
    $hint=New-Object System.Windows.Forms.Label;$hint.Dock='Top';$hint.Height=68
    $hint.Text='确认截图是角色选择界面、列表已滚到最上方。先拖框圈出固定的标题文字（避开角色名 / 动画），再单击第一个角色的可选区域。未在角色选择界面请关闭重试。'
    $dialog.Controls.Add($picture);$dialog.Controls.Add($hint)
    $dialog.Tag=[pscustomobject]@{Start=$null;Patch=$null;Result=$null;Count=$Count;Hint=$hint}
    $picture.Tag=$dialog
    $picture.Add_MouseDown({param($sender,$e)
        $p=Get-CalibrationPoint $sender $e.X $e.Y;if (-not $p) {return}
        if (-not $sender.Tag.Tag.Patch) {$sender.Tag.Tag.Start=$p}
        else {
            $patch=$sender.Tag.Tag.Patch
            $pixels=[WowAutoRotation.Native]::Fingerprint($sender.Image,$patch.X,$patch.Y,$patch.W,$patch.H)
            if (-not [WowAutoRotation.Native]::Matches($pixels,$pixels)) {$sender.Tag.Tag.Hint.Text='区域缺少清晰特征，请关闭并重新标定。';return}
            $sender.Tag.Tag.Result=[pscustomobject]@{Count=$sender.Tag.Tag.Count;Aspect=$sender.Image.Width/[double]$sender.Image.Height;
                FirstX=$p.X;FirstY=$p.Y;X=$patch.X;Y=$patch.Y;W=$patch.W;H=$patch.H;Pixels=$pixels}
            $sender.Tag.DialogResult='OK';$sender.Tag.Close()
        }
    })
    $picture.Add_MouseUp({param($sender,$e)
        $s=$sender.Tag.Tag.Start;if (-not $s -or $sender.Tag.Tag.Patch) {return}
        $p=Get-CalibrationPoint $sender $e.X $e.Y;if (-not $p) {return}
        $w=[Math]::Abs($p.X-$s.X);$h=[Math]::Abs($p.Y-$s.Y)
        if ($w -lt 0.02 -or $h -lt 0.01) {return}
        $sender.Tag.Tag.Patch=[pscustomobject]@{X=[Math]::Min($p.X,$s.X);Y=[Math]::Min($p.Y,$s.Y);W=$w;H=$h}
        $sender.Tag.Tag.Hint.Text='已记录固定文字区域。现在单击第一个角色的可选区域，完成标定。'
    })
    try {[void]$dialog.ShowDialog($form);return $dialog.Tag.Result} finally {$dialog.Dispose();$bitmap.Dispose()}
}
function New-RotationEditor($Row) {
    $dialog=New-Object WowAuto.DimForm;$dialog.Text='PID '+$Row.Process.Id+' · 三槽位角色编排';$dialog.Font=$form.Font
    $dialog.BackColor=$script:uiColors.Background;$dialog.ForeColor=$script:uiColors.Text;$dialog.AutoScaleMode='Dpi'
    $dialog.StartPosition='CenterParent';$dialog.ClientSize=New-Object Drawing.Size(750,435)
    $plan=Copy-RotationPlan (Get-RowRotationPlan $Row)
    $hint=New-Object System.Windows.Forms.Label;$hint.Text='角色号是选择列表中的位次；0为空。开始先登录第一个有效槽位；每次轮换按顺序跳过空槽。';$hint.SetBounds(15,15,720,52);$dialog.Controls.Add($hint)
    $controls=@()
    for ($i=0;$i -lt 3;$i++) {
        $label=New-Object System.Windows.Forms.Label;$label.Text='槽位 '+($i+1)+' · 角色号';$label.SetBounds(20,(75+$i*48),190,30)
        $number=New-Object System.Windows.Forms.NumericUpDown;$number.Minimum=0;$number.Maximum=65;$number.Value=$plan.Slots[$i].Character;$number.SetBounds(220,(70+$i*48),100,34)
        $number.BackColor=$script:uiColors.Input;$number.ForeColor=$script:uiColors.Text
        $mode=New-Object System.Windows.Forms.ComboBox;$mode.DropDownStyle='DropDownList';$mode.Items.AddRange([object[]]@('钓鱼','战斗'));$mode.SelectedIndex=if ($plan.Slots[$i].Mode -eq 'fight') {1} else {0};$mode.SetBounds(355,(70+$i*48),160,34)
        $mode.BackColor=$script:uiColors.Input;$mode.ForeColor=$script:uiColors.Text;$mode.FlatStyle='Flat'
        $mode.DrawMode='OwnerDrawFixed';$mode.ItemHeight=26
        $mode.Add_DrawItem({param($sender,$e)
            if ($e.Index -lt 0) {return}
            $brush=New-Object Drawing.SolidBrush($sender.BackColor)
            try {$e.Graphics.FillRectangle($brush,$e.Bounds)} finally {$brush.Dispose()}
            [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics,[string]$sender.Items[$e.Index],$sender.Font,$e.Bounds,[Drawing.Color]::White)
        })
        $dialog.Controls.AddRange([System.Windows.Forms.Control[]]@($label,$number,$mode));$controls+=,[pscustomobject]@{Character=$number;Mode=$mode}
    }
    $countLabel=New-Object System.Windows.Forms.Label;$countLabel.Text='本账号角色总数';$countLabel.SetBounds(20,225,190,30)
    $count=New-Object System.Windows.Forms.NumericUpDown;$count.Minimum=1;$count.Maximum=65;$count.Value=if ($plan.Menu) {$plan.Menu.Count} else {1};$count.SetBounds(220,220,100,34)
    $count.BackColor=$script:uiColors.Input;$count.ForeColor=$script:uiColors.Text
    $calibrate=New-Object WowAuto.DimButton;$calibrate.Text='标定角色选择界面';$calibrate.SetBounds(355,220,240,34);Set-UiButtonStyle $calibrate
    $errorLabel=New-Object System.Windows.Forms.Label;$errorLabel.SetBounds(20,267,710,87);$errorLabel.Text=if ($plan.Menu) {'已有界面标定；调整列表 / 界面布局后须重新标定。'} else {'首次使用须手动返回角色选择界面、列表滚到最上方，再点击标定；标定只截图，不点击游戏。'}
    $save=New-Object WowAuto.DimButton;$save.Text='保存编排';$save.SetBounds(430,375,135,36);Set-UiButtonStyle $save $true
    $cancel=New-Object WowAuto.DimButton;$cancel.Text='取消';$cancel.SetBounds(585,375,125,36);Set-UiButtonStyle $cancel
    $dialog.Tag=[pscustomobject]@{Row=$Row;Plan=$plan;Slots=$controls;Count=$count;Error=$errorLabel;Save=$save;Calibration=$calibrate}
    $calibrate.Tag=$dialog
    $calibrate.Add_Click({param($sender,$e) try {$editor=$sender.Tag.Tag;$m=Get-RotationCalibration $editor.Row $editor.Count.Value;if ($m) {$editor.Plan.Menu=$m;$editor.Error.Text='标定已加入草稿，保存后生效。'}} catch {$sender.Tag.Tag.Error.Text=$_.Exception.Message}})
    $save.Tag=$dialog;$save.Add_Click({param($sender,$e)
        $editor=$sender.Tag.Tag
        try {
            for ($i=0;$i -lt 3;$i++) {$editor.Plan.Slots[$i].Character=[int]$editor.Slots[$i].Character.Value;$editor.Plan.Slots[$i].Mode=if ($editor.Slots[$i].Mode.SelectedIndex -eq 1) {'fight'} else {'fish'}}
            if ($editor.Plan.Menu) {$editor.Plan.Menu.Count=[int]$editor.Count.Value}
            Test-RotationPlan $editor.Plan
            $next=$script:rotation.Plans.Clone();$next[$editor.Row.Key]=Copy-RotationPlan $editor.Plan
            Save-RotationConfiguration -Plans $next
            Stop-Row $editor.Row '编排已保存，任务停止；点击开始从首个有效槽位运行。' -CancelExit
            $sender.Tag.Close()
        } catch {$editor.Error.Text=$_.Exception.Message}
    })
    $cancel.Tag=$dialog;$cancel.Add_Click({param($sender,$e) $sender.Tag.Close()})
    $dialog.Controls.AddRange([System.Windows.Forms.Control[]]@($countLabel,$count,$calibrate,$errorLabel,$save,$cancel))
    return $dialog
}
function Show-RotationEditor($Row) {
    if ($script:scanning -or $script:editingSettings) {return}
    $script:editingSettings=$true;$dialog=$null
    try {
        if ($script:autoFight -and -not (Release-AutoFightHold)) {throw '无法释放移动键。'}
        $dialog=New-RotationEditor $Row;[void]$dialog.ShowDialog($form)
    } catch {Set-RowStatusText $Row $_.Exception.Message}
    finally {if ($dialog) {$dialog.Dispose()};$script:editingSettings=$false;Update-BatchControls}
}
if (-not $UiTest) {Import-RotationConfiguration}
