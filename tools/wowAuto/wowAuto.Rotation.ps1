# Three character slots per process; one monotonic deadline starts a batch for all active plans.
if (-not ('WowAutoRotation.Native' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'wowAuto.Rotation.Native.cs') -ReferencedAssemblies System.Drawing
}
$script:rotation=[pscustomobject]@{Path=(Join-Path $PSScriptRoot 'rotation.config.json');IntervalSeconds=0;OcrIntervalMs=1000;NextOcrAt=0L;Plans=@{};
    Active=@{};Queue=(New-Object Collections.Queue);Current=$null;NextAt=0L;ConfigReady=$true;Error='';Actions=@();OcrWork=$null;
    OcrSource=([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'wowAuto.Rotation.Ocr.ps1')))}
function New-RotationPlan {
    return [pscustomobject]@{Slots=@(1..3 | ForEach-Object {[pscustomobject]@{Name='';Mode='fish'}})}
}
function Copy-RotationPlan($Plan) {return ($Plan | ConvertTo-Json -Depth 8 | ConvertFrom-Json)}
function Test-RotationPlan($Plan) {
    if (-not $Plan -or @($Plan.Slots).Count -ne 3) {throw '每个进程必须配置三个槽位。'}
    foreach ($slot in $Plan.Slots) {
        if ($null -eq $slot.Name -or $slot.Name -isnot [string] -or $slot.Name.Length -gt 24 -or
            $slot.Name -match '[\s\p{C}]' -or $slot.Name -match '[^\p{L}\p{M}]' -or $slot.Mode -cnotin @('fish','fight')) {throw '角色名须为完整名称（不含空格，最多24字）；留空表示空槽，任务须为钓鱼或战斗。'}
    }
}
function Get-RotationOcrInterval($Value) {
    $number=0
    if (-not [int]::TryParse([string]$Value,[ref]$number) -or $number -lt 100 -or $number -gt 60000 -or ($number % 100) -ne 0) {
        throw 'OCR采样周期须为100–60000ms的整数，步进100ms。'
    }
    return $number
}
function Save-RotationConfiguration($Interval=$script:rotation.IntervalSeconds,$Plans=$script:rotation.Plans,$OcrIntervalMs=$script:rotation.OcrIntervalMs) {
    $n=0
    if (-not [int]::TryParse([string]$Interval,[ref]$n) -or $n -lt 0 -or $n -gt 604800) {throw '轮换间隔须为0–604800秒，0关闭定时轮换。'}
    $ocrInterval=Get-RotationOcrInterval $OcrIntervalMs
    foreach ($key in $Plans.Keys) {
        $p=0;$ticks=0L
        if ($key -notmatch '^([1-9]\d*):([1-9]\d*)$' -or -not [int]::TryParse($matches[1],[ref]$p) -or
            -not [long]::TryParse($matches[2],[ref]$ticks) -or $ticks -gt [datetime]::MaxValue.Ticks) {throw '进程编排标识无效。'}
        Test-RotationPlan $Plans[$key]
    }
    $payload=[ordered]@{Version=2;IntervalSeconds=$n;OcrIntervalMs=$ocrInterval;Plans=$Plans}
    $temporary=$script:rotation.Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temporary,($payload | ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($script:rotation.Path)) {[IO.File]::Replace($temporary,$script:rotation.Path,[System.Management.Automation.Language.NullString]::Value)}
        else {[IO.File]::Move($temporary,$script:rotation.Path)}
    } finally {if ([IO.File]::Exists($temporary)) {[IO.File]::Delete($temporary)}}
    $changed=$script:rotation.IntervalSeconds -ne $n
    $script:rotation.IntervalSeconds=$n;$script:rotation.OcrIntervalMs=$ocrInterval;$script:rotation.Plans=$Plans;$script:rotation.ConfigReady=$true;$script:rotation.Error=''
    if ($changed) {$script:rotation.NextAt=if ($n -and $script:rotation.Active.Count) {$script:schedulerClock.ElapsedMilliseconds+[long]$n*1000} else {0L}}
    foreach ($r in $script:rows.Values) {Update-RotationRow $r}
}
function Import-RotationConfiguration {
    if (-not [IO.File]::Exists($script:rotation.Path)) {return}
    try {
        $c=[IO.File]::ReadAllText($script:rotation.Path) | ConvertFrom-Json
        if ($c.Version -eq 1) {throw '旧角色号配置须改填角色名称后保存；不会按位次猜测名称。'}
        if ($c.Version -ne 2 -or $null -eq $c.IntervalSeconds -or -not $c.Plans -or
            @($c.PSObject.Properties.Name | Where-Object {$_ -notin @('Version','IntervalSeconds','OcrIntervalMs','Plans')}).Count) {throw '编排配置格式无效。'}
        $n=0;if (-not [int]::TryParse([string]$c.IntervalSeconds,[ref]$n) -or $n -lt 0 -or $n -gt 604800) {throw '编排间隔无效。'}
        $ocrInterval=1000
        if ($c.PSObject.Properties['OcrIntervalMs']) {$ocrInterval=Get-RotationOcrInterval $c.OcrIntervalMs}
        $plans=@{}
        foreach ($prop in $c.Plans.PSObject.Properties) {
            $p=0;$t=0L
            if ($prop.Name -notmatch '^([1-9]\d*):([1-9]\d*)$' -or -not [int]::TryParse($matches[1],[ref]$p) -or
                -not [long]::TryParse($matches[2],[ref]$t) -or $t -gt [datetime]::MaxValue.Ticks) {throw '编排进程标识无效。'}
            Test-RotationPlan $prop.Value;$plans[$prop.Name]=$prop.Value
        }
        $script:rotation.IntervalSeconds=$n;$script:rotation.OcrIntervalMs=$ocrInterval;$script:rotation.Plans=$plans;$script:rotation.ConfigReady=$true;$script:rotation.Error=''
    } catch {$script:rotation.ConfigReady=$false;$script:rotation.Error='编排配置读取失败：'+$_.Exception.Message}
}
function Get-RotationNextSlot($Plan,[int]$Current) {
    for ($i=1;$i -le 3;$i++) {$index=($Current+$i)%3;if ($Plan.Slots[$index].Name) {return $index}}
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
        if ($slot.Name) {"槽$($i+1)：$($slot.Name) / $mode"} else {"槽$($i+1)：空"}
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
    if ($script:rotation.OcrWork -and $script:rotation.OcrWork.Key -eq $Row.Key) {Stop-RotationOcr}
    $script:rotation.Active.Remove($Row.Key)
    if ($script:rotation.Current -and $script:rotation.Current.Row.Key -eq $Row.Key) {$script:rotation.Current=$null;$script:rotation.NextOcrAt=0L}
    if (-not $script:rotation.Active.Count) {$script:rotation.NextAt=0L}
    Update-RotationRow $Row
}
function Start-RowRotation($Row) {
    if ($script:scanning -or $script:editingSettings -or -not $script:rotation.ConfigReady) {throw '请关闭设置，修复编排配置后开始。'}
    if ($script:rotation.Active.ContainsKey($Row.Key)) {return}
    $plan=Get-RowRotationPlan $Row;Test-RotationPlan $plan
    $index=Get-RotationNextSlot $plan -1
    Stop-Row $Row '开始角色编排，准备登录第一个有效槽位。' -CancelExit
    $entry=[pscustomobject]@{Row=$Row;Plan=(Copy-RotationPlan $plan);Index=$index}
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
        $script:rotation.Queue.Enqueue($entry);Update-RotationRow $entry.Row
    }
    if ($script:rotation.IntervalSeconds) {$script:rotation.NextAt=$Now+[long]$script:rotation.IntervalSeconds*1000}
}
function Send-RotationAction($Row,[string]$Action,$Target=$null) {
    if (-not (Test-RowProcessIdentity $Row) -or $Row.Process.HasExited -or -not (Test-WorkerForeground $Row)) {throw '角色切换期间进程身份或前台已变化。'}
    if ($UiTest) {$script:rotation.Actions+=,[pscustomobject]@{Key=$Row.Key;Action=$Action;Target=$Target};return}
    switch ($Action) {
        'logout' {$sent=[WowAuto.NativeInput]::SendRotationCommand($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath,'logout',0)}
        'top' {[WowAutoRotation.Native]::MouseAction($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath,0.88,0.45,12000,$false);$sent=$true}
        'scroll' {[WowAutoRotation.Native]::MouseAction($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath,0.88,0.65,-600,$false);$sent=$true}
        'doubleclick' {
            if (-not $Target -or -not $Target.Name) {throw '未定位完整角色名。'}
            [WowAutoRotation.Native]::MouseAction($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath,$Target.X,$Target.Y,0,$true);$sent=$true
        }
        default {throw '未知编排动作。'}
    }
    if (-not $sent) {throw '角色切换输入失败。'}
}
function Stop-RotationOcr {
    $work=$script:rotation.OcrWork;$script:rotation.OcrWork=$null;$script:rotation.NextOcrAt=0L
    if ($work) {try {$work.Pipeline.Stop()} finally {$work.Pipeline.Dispose()}}
}
function ConvertFrom-RotationOcr($Ocr,$Plan,[switch]$MenuWasConfirmed) {
    $configured=@($Plan.Slots | Where-Object {$_.Name} | ForEach-Object {$_.Name} | Select-Object -Unique)
    $announcement=@($Ocr.Lines | Where-Object {$_.X -lt 0.25 -and $_.Text -eq '系统公告'}).Count -gt 0
    $targets=@(foreach ($line in $Ocr.Names) {
        $y=$line.Y*0.84
        if ($y -lt 0.08 -or $y -gt 0.80 -or $line.Text -notmatch '^[\p{L}\p{M}]+$') {continue}
        [pscustomobject]@{Name=$line.Text;X=(0.79+0.21*($line.X+$line.W/2));Y=($y+0.84*$line.H/2)}
    })
    # The normal pass can recover names whose font is not yellow. Never fuzzy-match.
    foreach ($line in $Ocr.Lines) {
        if ($line.X -gt 0.79 -and $line.Y -gt 0.08 -and $line.Y -lt 0.80 -and $line.Text -cin $configured -and $line.Text -cnotin $targets.Name) {
            $targets+=,[pscustomobject]@{Name=$line.Text;X=($line.X+$line.W/2);Y=($line.Y+$line.H/2)}
        }
    }
    $match=@($targets | Where-Object {$_.Name -cin $configured}).Count -gt 0
    if ($announcement -and ($match -or ($MenuWasConfirmed -and $targets.Count))) {
        return [pscustomobject]@{Kind='menu';Targets=$targets;RoleName=$null}
    }
    $health=@($Ocr.Lines | Where-Object {$_.X -lt 0.25 -and $_.Y -lt 0.18 -and $_.Text -match '^\d{1,3}[％%]\d*$'}).Count -gt 0
    $stats=@($Ocr.Lines | Where-Object {$_.X -lt 0.25 -and $_.Y -lt 0.50 -and ($_.Text -match '开怪[：:]' -or $_.Text -match '^自身Buff')}).Count -gt 0
    if (-not $announcement -and $health -and $stats) {
        $roles=@(foreach ($name in $configured) {
            if (@($Ocr.Lines | Where-Object {$_.X -lt 0.25 -and $_.Y -lt 0.50 -and $_.Text -cmatch ('^\d*'+[regex]::Escape($name)+'$')}).Count) {$name}
        })
        if ($roles.Count -gt 1) {return [pscustomobject]@{Kind='unknown';Targets=@();RoleName=$null}}
        return [pscustomobject]@{Kind='world';Targets=@();RoleName=$(if ($roles.Count -eq 1) {[string]$roles[0]} else {$null})}
    }
    return [pscustomobject]@{Kind='unknown';Targets=@();RoleName=$null}
}
function Read-RotationScreen($Row,$Plan,[switch]$MenuWasConfirmed) {
    if ($UiTest) {return $Row.Process.RotationScreen}
    $work=$script:rotation.OcrWork
    if ($work) {
        if ($work.Key -ne $Row.Key) {Stop-RotationOcr;throw 'OCR任务进程不一致。'}
        if (-not $work.Async.IsCompleted) {return [pscustomobject]@{Kind='pending'}}
        $script:rotation.OcrWork=$null
        try {
            $result=$work.Pipeline.EndInvoke($work.Async)
            if ($work.Pipeline.Streams.Error.Count) {throw $work.Pipeline.Streams.Error[0].ToString()}
            [WowAutoRotation.Native]::ValidateSnapshot($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath,$work.Width,$work.Height)
            if ($script:schedulerClock.ElapsedMilliseconds-$work.At -gt 3000) {return [pscustomobject]@{Kind='pending'}}
            return ConvertFrom-RotationOcr ($result[0] | ConvertFrom-Json) $Plan -MenuWasConfirmed:$MenuWasConfirmed
        } finally {$work.Pipeline.Dispose()}
    }
    # Limit capture starts; completion polling must never create another in-flight OCR task.
    $sampleAt=$script:schedulerClock.ElapsedMilliseconds
    if ($sampleAt -lt $script:rotation.NextOcrAt) {return [pscustomobject]@{Kind='pending'}}
    $bitmap=[WowAutoRotation.Native]::Capture($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath)
    $script:rotation.NextOcrAt=$sampleAt+[long]$script:rotation.OcrIntervalMs
    $pipeline=[powershell]::Create()
    try {
        $null=$pipeline.AddScript($script:rotation.OcrSource).AddArgument([WowAutoRotation.Native]::Png($bitmap))
        $script:rotation.OcrWork=[pscustomobject]@{Key=$Row.Key;Pipeline=$pipeline;Async=$pipeline.BeginInvoke();
            Width=$bitmap.Width;Height=$bitmap.Height;At=$script:schedulerClock.ElapsedMilliseconds}
    } catch {$pipeline.Dispose();throw} finally {$bitmap.Dispose()}
    return [pscustomobject]@{Kind='pending'}
}
function Invoke-RotationTick([long]$Now) {
    if ($script:scanning -or $script:editingSettings) {return $false}
    if (-not $script:rotation.Current -and -not $script:rotation.Queue.Count -and $script:rotation.NextAt -and $Now -ge $script:rotation.NextAt) {Begin-RotationBatch $Now}
    if (-not $script:rotation.Current) {
        while ($script:rotation.Queue.Count) {
            $entry=$script:rotation.Queue.Dequeue()
            if ($script:rotation.Active[$entry.Row.Key] -ne $entry) {continue}
            $script:rotation.Current=[pscustomobject]@{Entry=$entry;Row=$entry.Row;Phase='activate';Due=$Now;Deadline=($Now+180000);
                Stable=0;LastLogout=-30000L;Candidate=$null;Pages=0;Signature='';Repeated=0}
            $script:rotation.NextOcrAt=0L
            break
        }
    }
    $work=$script:rotation.Current;if (-not $work) {return $false}
    if ($Now -lt $work.Due) {return $true}
    $row=$work.Row;$entry=$work.Entry;$name=$entry.Plan.Slots[$entry.Index].Name
    try {
        $row.Process.Refresh()
        if ($row.Process.HasExited -or -not (Test-RowProcessIdentity $row)) {throw '角色轮换进程已退出或身份改变。'}
        if ($Now -ge $work.Deadline) {throw '角色切换超过180秒；检查战斗、登录及OCR识别后手动开始。'}
        if ($script:autoFight -and ($script:autoFight.ActiveHold -or [WowAutoFight.Native]::IsHolding)) {if (-not (Release-AutoFightHold)) {return $true}}
        if ($work.Phase -eq 'activate') {
            if (-not (Activate-ScanRow $row)) {throw '无法激活角色切换窗口。'}
            $work.Phase='inspect';$work.Due=$Now+200;return $true
        }
        if (-not (Test-WorkerForeground $row)) {throw '角色切换窗口失去前台，已停止本行。'}
        $screen=Read-RotationScreen $row $entry.Plan -MenuWasConfirmed:($work.Phase -eq 'find')
        if ($screen.Kind -eq 'pending') {$work.Due=$Now+100;return $true}
        switch ($work.Phase) {
            'inspect' {
                if ($screen.Kind -eq 'menu') {$work.Phase='menu';$work.Stable=1}
                elseif ($screen.Kind -eq 'world') {
                    $work.Stable++
                    if ($work.Stable -ge 2) {Send-RotationAction $row 'logout';$work.LastLogout=$Now;$work.Phase='menu';$work.Stable=0;$row.Validated=$false}
                } else {$work.Stable=0;Set-RowStatusText $row '等待OCR确认游戏画面，或系统公告与配置的角色名。'}
            }
            'menu' {
                if ($screen.Kind -eq 'menu') {
                    $work.Stable++
                    if ($work.Stable -ge 3) {Send-RotationAction $row 'top';$work.Phase='find';$work.Stable=0}
                } else {
                    $work.Stable=0
                    if ($screen.Kind -eq 'world' -and $Now-$work.LastLogout -ge 30000) {Send-RotationAction $row 'logout';$work.LastLogout=$Now}
                    Set-RowStatusText $row '等待脱战、退出倒计时及OCR确认角色选择界面。'
                }
            }
            'find' {
                if ($screen.Kind -ne 'menu') {$work.Stable=0;Set-RowStatusText $row '选角锚点未完整识别，等待重新识别。';break}
                $targets=@($screen.Targets | Where-Object {$_.Name -ceq $name})
                if ($targets.Count -gt 1) {throw '列表出现多个相同名称，未双击。'}
                if ($targets.Count -eq 1) {
                    $target=$targets[0]
                    if ($work.Candidate -and [Math]::Abs($target.X-$work.Candidate.X) -lt 0.005 -and [Math]::Abs($target.Y-$work.Candidate.Y) -lt 0.005) {$work.Stable++} else {$work.Stable=1}
                    $work.Candidate=$target
                    if ($work.Stable -ge 2) {
                        Send-RotationAction $row 'doubleclick' $target;$work.Phase='login';$work.Stable=0
                        Set-RowStatusText $row ('已快速双击“'+$name+'”，等待OCR确认进入游戏。')
                    }
                } else {
                    $work.Candidate=$null;$work.Stable=0
                    $signature=($screen.Targets.Name -join '|')
                    if ($signature -ceq $work.Signature) {$work.Repeated++} else {$work.Repeated=0}
                    $work.Signature=$signature
                    if ($work.Repeated -ge 2 -or $work.Pages -ge 40) {throw ('角色列表未找到完整名称“'+$name+'”；请核对名称及服务器。')}
                    Send-RotationAction $row 'scroll';$work.Pages++
                }
            }
            'login' {
                if ($screen.Kind -eq 'world' -and (-not $screen.RoleName -or $screen.RoleName -ceq $name)) {
                    $work.Stable++
                    if ($work.Stable -ge 3) {
                        $row.TaskMode=$entry.Plan.Slots[$entry.Index].Mode;$script:updatingPreferenceControls=$true
                        try {$row.ModeBox.SelectedIndex=if ($row.TaskMode -eq 'fight') {1} else {0}} finally {$script:updatingPreferenceControls=$false}
                        if ($row.TaskMode -eq 'fight') {Ensure-UnifiedFightRow $row}
                        if (-not (Send-ScanDetectorCommand $row)) {throw '登录后监控开启命令失败。'}
                        $work.Phase='validate';$work.Due=$Now+300;return $true
                    }
                } else {
                    $work.Stable=0
                    if ($screen.Kind -eq 'world' -and $screen.RoleName -and $screen.RoleName -cne $name) {throw ('OCR识别到其他角色“'+$screen.RoleName+'”，未启动任务。')}
                    Set-RowStatusText $row ('等待“'+$name+'”加载结束，并连续确认游戏画面。')
                }
            }
            'validate' {
                if ($row.TaskMode -eq 'fight') {
                    $packet=Read-ScanFightPacket $row
                    if (-not $packet -or $packet.Flavor -ne $row.Client.Flavor) {$work.Due=$Now+300;return $true}
                    $row.FightRow.CanStart=$true;$row.FightRow.ClassId=$packet.ClassId
                } elseif ((Read-ScanColor $row) -notin @('red','green')) {$work.Due=$Now+300;return $true}
                $row.Validated=$true
                foreach ($table in @($script:scheduler.CompletedCycles,$script:scheduler.CyclesSinceJump)) {if ($null -ne $table) {$table.Remove($row.Key)}}
                Start-Row $row -TaskOnly
                if (-not (Test-UnifiedTaskRunning $row)) {throw '角色任务未能启动。'}
                Set-RowStatusText $row ('槽'+($entry.Index+1)+' / '+$name+' 已登录并开始任务。')
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
    $bar=New-Object System.Windows.Forms.Panel;$bar.Dock='Top';$bar.Height=104;$bar.BackColor=$script:uiColors.Surface;$bar.ForeColor=$script:uiColors.Text
    $label=New-Object System.Windows.Forms.Label;$label.Text='全局角色轮换（秒，0关闭）';$label.SetBounds(12,12,285,30)
    $value=New-Object System.Windows.Forms.NumericUpDown;$value.Minimum=0;$value.Maximum=604800;$value.Value=$script:rotation.IntervalSeconds;$value.SetBounds(300,8,130,32)
    $value.BackColor=$script:uiColors.Input;$value.ForeColor=$script:uiColors.Text
    $ocrLabel=New-Object System.Windows.Forms.Label;$ocrLabel.Text='OCR 采样周期（ms）';$ocrLabel.SetBounds(12,64,285,30)
    $ocrValue=New-Object System.Windows.Forms.NumericUpDown
    $ocrValue.Minimum=100;$ocrValue.Maximum=60000;$ocrValue.Increment=100;$ocrValue.Value=$script:rotation.OcrIntervalMs;$ocrValue.SetBounds(300,60,130,32)
    $ocrValue.BackColor=$script:uiColors.Input;$ocrValue.ForeColor=$script:uiColors.Text
    $hint=New-Object System.Windows.Forms.Label;$hint.Text='全局共用，默认1000ms，步进100ms。';$hint.SetBounds(450,64,515,30)
    $save=New-Object WowAuto.DimButton;$save.Text='保存全局设置';$save.SetBounds(450,8,170,34);Set-UiButtonStyle $save
    $errorLabel=New-Object System.Windows.Forms.Label;$errorLabel.SetBounds(635,12,330,30);$errorLabel.AutoEllipsis=$true;$errorLabel.Text=$script:rotation.Error
    $save.Tag=[pscustomobject]@{Value=$value;OcrValue=$ocrValue;Error=$errorLabel}
    $save.Add_Click({param($sender,$e)
        try {
            Save-RotationConfiguration -Interval $sender.Tag.Value.Value -OcrIntervalMs $sender.Tag.OcrValue.Value
            $sender.Tag.Error.Text='已保存。'
        } catch {$sender.Tag.Error.Text=$_.Exception.Message}
    })
    $bar.Controls.AddRange([System.Windows.Forms.Control[]]@($label,$value,$ocrLabel,$ocrValue,$hint,$save,$errorLabel));$SettingsOwner.Controls.Add($bar);$bar.SendToBack()
    return [pscustomobject]@{Value=$value;OcrValue=$ocrValue;Save=$save;Error=$errorLabel}
}
function New-RotationEditor($Row) {
    $dialog=New-Object WowAuto.DimForm;$dialog.Text='PID '+$Row.Process.Id+' · 三槽位角色编排';$dialog.Font=$form.Font
    $dialog.BackColor=$script:uiColors.Background;$dialog.ForeColor=$script:uiColors.Text;$dialog.AutoScaleMode='Dpi'
    $dialog.StartPosition='CenterParent';$dialog.ClientSize=New-Object Drawing.Size(750,355)
    $plan=Copy-RotationPlan (Get-RowRotationPlan $Row)
    $hint=New-Object System.Windows.Forms.Label;$hint.Text='填写角色完整名称，留空为空槽。OCR确认系统公告与列表名称后，快速双击该名称登录。';$hint.SetBounds(15,15,720,52);$dialog.Controls.Add($hint)
    $controls=@()
    for ($i=0;$i -lt 3;$i++) {
        $label=New-Object System.Windows.Forms.Label;$label.Text='槽位 '+($i+1)+' · 角色名称';$label.SetBounds(20,(75+$i*48),190,30)
        $text=New-Object System.Windows.Forms.TextBox;$text.MaxLength=24;$text.Text=$plan.Slots[$i].Name;$text.SetBounds(220,(70+$i*48),270,34)
        $text.BackColor=$script:uiColors.Input;$text.ForeColor=$script:uiColors.Text
        $mode=New-Object System.Windows.Forms.ComboBox;$mode.DropDownStyle='DropDownList';$mode.Items.AddRange([object[]]@('钓鱼','战斗'));$mode.SelectedIndex=if ($plan.Slots[$i].Mode -eq 'fight') {1} else {0};$mode.SetBounds(525,(70+$i*48),170,34)
        $mode.BackColor=$script:uiColors.Input;$mode.ForeColor=$script:uiColors.Text;$mode.FlatStyle='Flat';$mode.DrawMode='OwnerDrawFixed';$mode.ItemHeight=26
        $mode.Add_DrawItem({param($sender,$e)
            if ($e.Index -lt 0) {return}
            $brush=New-Object Drawing.SolidBrush($sender.BackColor)
            try {$e.Graphics.FillRectangle($brush,$e.Bounds)} finally {$brush.Dispose()}
            [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics,[string]$sender.Items[$e.Index],$sender.Font,$e.Bounds,[Drawing.Color]::White)
        })
        $dialog.Controls.AddRange([System.Windows.Forms.Control[]]@($label,$text,$mode));$controls+=,[pscustomobject]@{Name=$text;Mode=$mode}
    }
    $errorLabel=New-Object System.Windows.Forms.Label;$errorLabel.SetBounds(20,223,710,70)
    $errorLabel.Text='不需要角色号、角色总数或菜单标定。登录后通过血条及统计面板确认游戏画面，请保持录制中的这些界面可见。'
    $save=New-Object WowAuto.DimButton;$save.Text='保存编排';$save.SetBounds(430,300,135,36);Set-UiButtonStyle $save $true
    $cancel=New-Object WowAuto.DimButton;$cancel.Text='取消';$cancel.SetBounds(585,300,125,36);Set-UiButtonStyle $cancel
    $dialog.Tag=[pscustomobject]@{Row=$Row;Plan=$plan;Slots=$controls;Error=$errorLabel;Save=$save}
    $save.Tag=$dialog;$save.Add_Click({param($sender,$e)
        $editor=$sender.Tag.Tag
        try {
            for ($i=0;$i -lt 3;$i++) {$editor.Plan.Slots[$i].Name=$editor.Slots[$i].Name.Text.Trim();$editor.Plan.Slots[$i].Mode=if ($editor.Slots[$i].Mode.SelectedIndex -eq 1) {'fight'} else {'fish'}}
            Test-RotationPlan $editor.Plan
            $next=$script:rotation.Plans.Clone();$next[$editor.Row.Key]=Copy-RotationPlan $editor.Plan
            Save-RotationConfiguration -Plans $next
            Stop-Row $editor.Row '编排已保存，任务停止；点击开始从首个有效槽位运行。' -CancelExit
            $sender.Tag.Close()
        } catch {$editor.Error.Text=$_.Exception.Message}
    })
    $cancel.Tag=$dialog;$cancel.Add_Click({param($sender,$e) $sender.Tag.Close()})
    $dialog.Controls.AddRange([System.Windows.Forms.Control[]]@($errorLabel,$save,$cancel))
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
