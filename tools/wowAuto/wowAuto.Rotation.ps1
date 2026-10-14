# Three character slots per process; one monotonic deadline starts a batch for all active plans.
if (-not ('WowAutoRotation.Native' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'wowAuto.Rotation.Native.cs') -ReferencedAssemblies System.Drawing
}
$script:rotation=[pscustomobject]@{Path=(Join-Path $PSScriptRoot 'rotation.config.json');IntervalSeconds=0;OcrIntervalMs=1000;NextOcrAt=0L;Plans=@{};
    Active=@{};LogoutQueue=(New-Object Collections.Queue);Queue=(New-Object Collections.Queue);Current=$null;NextAt=0L;ConfigReady=$true;Error='';Actions=@();OcrWork=$null;NameHistory=@();GameDirectories=@{titan=$(if ($UiTest) {''} else {'C:\Program Files (x86)\World of Warcraft\_classic_titan_'});forerver=$(if ($UiTest) {''} else {'C:\Program Files (x86)\World of Warcraft\_cn_beta_'})};
    OcrSource=([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'wowAuto.Rotation.Ocr.ps1')))}
function New-RotationPlan {
    return [pscustomobject]@{Slots=@(1..3 | ForEach-Object {[pscustomobject]@{Name='';Mode='fish';UseItem=$false}})}
}
function Copy-RotationPlan($Plan) {return ($Plan | ConvertTo-Json -Depth 8 | ConvertFrom-Json)}
function Test-RotationPlan($Plan) {
    if (-not $Plan -or @($Plan.Slots).Count -ne 3) {throw '每个进程必须配置三个槽位。'}
    if ($Plan.PSObject.Properties['Account'] -and ($Plan.Account -isnot [string] -or $Plan.Account -match '[\\/\p{C}]' -or $Plan.Account.Length -gt 128)) {throw '子战网标识无效。'}
    foreach ($slot in $Plan.Slots) {
        if ($slot.PSObject.Properties['UseItem'] -and $slot.UseItem -isnot [bool]) {throw '槽位道具开关须为布尔值。'}
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
function Get-RotationNameHistory($Plans=$script:rotation.Plans,$History=$script:rotation.NameHistory) {
    $names=New-Object 'System.Collections.Generic.List[string]'
    foreach ($name in @($History)) {
        if ($name -isnot [string] -or -not $name -or $name.Length -gt 24 -or $name -match '[^\p{L}\p{M}]') {throw '历史角色名称无效。'}
        if (-not $names.Contains($name)) {$names.Add($name)}
    }
    foreach ($key in @($Plans.Keys | Sort-Object)) {
        foreach ($slot in $Plans[$key].Slots) {if ($slot.Name -and -not $names.Contains($slot.Name)) {$names.Add($slot.Name)}}
    }
    return $names.ToArray()
}
function Save-RotationConfiguration($Interval=$script:rotation.IntervalSeconds,$Plans=$script:rotation.Plans,$OcrIntervalMs=$script:rotation.OcrIntervalMs,$GameDirectories=$script:rotation.GameDirectories) {
    $n=0
    if (-not [int]::TryParse([string]$Interval,[ref]$n) -or $n -lt 0 -or $n -gt 604800) {throw '轮换间隔须为0–604800秒，0关闭定时轮换。'}
    $ocrInterval=Get-RotationOcrInterval $OcrIntervalMs
    foreach ($key in $Plans.Keys) {
        $p=0;$ticks=0L
        if ($key -notmatch '^([1-9]\d*):([1-9]\d*)$' -or -not [int]::TryParse($matches[1],[ref]$p) -or
            -not [long]::TryParse($matches[2],[ref]$ticks) -or $ticks -gt [datetime]::MaxValue.Ticks) {throw '进程编排标识无效。'}
        Test-RotationPlan $Plans[$key]
    }
    $roots=ConvertTo-RotationGameDirectories $GameDirectories
    $nextHistory=@(Get-RotationNameHistory $Plans @(Get-RotationNameHistory))
    $payload=[ordered]@{Version=2;IntervalSeconds=$n;OcrIntervalMs=$ocrInterval;NameHistory=$nextHistory;GameDirectories=$roots;Plans=$Plans}
    $temporary=$script:rotation.Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temporary,($payload | ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($script:rotation.Path)) {[IO.File]::Replace($temporary,$script:rotation.Path,[System.Management.Automation.Language.NullString]::Value)}
        else {[IO.File]::Move($temporary,$script:rotation.Path)}
    } finally {if ([IO.File]::Exists($temporary)) {[IO.File]::Delete($temporary)}}
    $changed=$script:rotation.IntervalSeconds -ne $n
    $script:rotation.IntervalSeconds=$n;$script:rotation.OcrIntervalMs=$ocrInterval;$script:rotation.Plans=$Plans;$script:rotation.GameDirectories=$roots;$script:rotation.NameHistory=$nextHistory;$script:rotation.ConfigReady=$true;$script:rotation.Error=''
    if ($changed) {$script:rotation.NextAt=if ($n -and $script:rotation.Active.Count) {$script:schedulerClock.ElapsedMilliseconds+[long]$n*1000} else {0L}}
    foreach ($r in $script:rows.Values) {Update-RotationRow $r}
}
function Import-RotationConfiguration {
    if (-not [IO.File]::Exists($script:rotation.Path)) {return}
    try {
        $c=[IO.File]::ReadAllText($script:rotation.Path) | ConvertFrom-Json
        if ($c.Version -eq 1) {throw '旧角色号配置须改填角色名称后保存；不会按位次猜测名称。'}
        if ($c.Version -ne 2 -or $null -eq $c.IntervalSeconds -or -not $c.Plans -or
            @($c.PSObject.Properties.Name | Where-Object {$_ -notin @('Version','IntervalSeconds','OcrIntervalMs','NameHistory','GameDirectories','Plans')}).Count) {throw '编排配置格式无效。'}
        $n=0;if (-not [int]::TryParse([string]$c.IntervalSeconds,[ref]$n) -or $n -lt 0 -or $n -gt 604800) {throw '编排间隔无效。'}
        $ocrInterval=1000
        if ($c.PSObject.Properties['OcrIntervalMs']) {$ocrInterval=Get-RotationOcrInterval $c.OcrIntervalMs}
        $roots=$script:rotation.GameDirectories
        if ($c.PSObject.Properties['GameDirectories']) {$roots=ConvertTo-RotationGameDirectories $c.GameDirectories}
        $plans=@{}
        foreach ($prop in $c.Plans.PSObject.Properties) {
            $p=0;$t=0L
            if ($prop.Name -notmatch '^([1-9]\d*):([1-9]\d*)$' -or -not [int]::TryParse($matches[1],[ref]$p) -or
                -not [long]::TryParse($matches[2],[ref]$t) -or $t -gt [datetime]::MaxValue.Ticks) {throw '编排进程标识无效。'}
            Test-RotationPlan $prop.Value
            foreach ($slot in $prop.Value.Slots) {
                if (-not $slot.PSObject.Properties['UseItem']) {
                    $enabled=$script:processItemPreferences.ContainsKey($prop.Name) -and $script:processItemPreferences[$prop.Name] -and $slot.Mode -eq 'fish'
                    $slot | Add-Member NoteProperty UseItem ([bool]$enabled)
                }
            }
            $plans[$prop.Name]=$prop.Value
        }
        $history=@()
        if ($c.PSObject.Properties['NameHistory']) {
            if ($c.NameHistory -isnot [array]) {throw '历史角色名称必须为列表。'}
            $history=@($c.NameHistory)
        }
        $history=@(Get-RotationNameHistory $plans $history)
        $script:rotation.IntervalSeconds=$n;$script:rotation.OcrIntervalMs=$ocrInterval;$script:rotation.Plans=$plans;$script:rotation.GameDirectories=$roots;$script:rotation.NameHistory=$history;$script:rotation.ConfigReady=$true;$script:rotation.Error=''
    } catch {$script:rotation.ConfigReady=$false;$script:rotation.Error='编排配置读取失败：'+$_.Exception.Message}
}
function Get-RotationNextSlot($Plan,[int]$Current,[string[]]$ExcludedNames=@()) {
    for ($i=1;$i -le 3;$i++) {
        $index=($Current+$i)%3;$name=$Plan.Slots[$index].Name
        if ($name -and $name -cnotin $ExcludedNames) {return $index}
    }
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
    $excluded=if ($script:rotation.Active.ContainsKey($Row.Key)) {@($script:rotation.Active[$Row.Key].ExcludedNames)} else {@()}
    $labels=for ($i=0;$i -lt 3;$i++) {
        $slot=$plan.Slots[$i];$mode=if ($slot.Mode -eq 'fight') {'战斗'} else {'钓鱼'}
        if ($slot.Name) {"槽$($i+1)：$($slot.Name) / $mode$(if ($slot.Name -cin $excluded) {'（包满跳过）'})"} else {"槽$($i+1)：空"}
    }
    $Row.RotationLabel.Text=($labels -join '    ')
    if ($script:rotation.Active.ContainsKey($Row.Key)) {$Row.RotationLabel.Text+='    当前槽：'+($script:rotation.Active[$Row.Key].Index+1)}
    $Row.RotationButton.Enabled=-not $script:scanning -and -not $script:editingSettings
}
function Add-RotationRow($Row) {
    $Row.Panel.Height=190
    $button=New-Object WowAuto.DimButton;$button.Text='角色编排';$button.SetBounds(12,102,130,32);Set-UiButtonStyle $button
    $label=New-Object System.Windows.Forms.Label;$label.SetBounds(12,146,1180,35);$label.AutoEllipsis=$true
    $Row | Add-Member NoteProperty RotationButton $button
    $Row | Add-Member NoteProperty RotationLabel $label
    $button.Tag=$Row;$button.Add_Click({param($sender,$e) Show-RotationEditor $sender.Tag})
    $Row.Panel.Controls.AddRange([System.Windows.Forms.Control[]]@($button,$label));Update-RotationRow $Row
}
function Stop-RowRotation($Row) {
    Remove-GameActions -Key $Row.Key -Domain Rotation
    if (-not $script:rotation) {return}
    if ($script:rotation.OcrWork -and $script:rotation.OcrWork.Key -eq $Row.Key) {Stop-RotationOcr}
    $script:rotation.Active.Remove($Row.Key)
    if ($script:rotation.Current -and $script:rotation.Current.Row.Key -eq $Row.Key) {$script:rotation.Current=$null;$script:rotation.NextOcrAt=0L}
    if (-not $script:rotation.Active.Count) {$script:rotation.NextAt=0L;$script:rotation.LogoutQueue.Clear();$script:rotation.Queue.Clear()}
    Update-RotationRow $Row
}
function Start-RowRotation($Row) {
    if ($script:scanning -or $script:editingSettings -or -not $script:rotation.ConfigReady) {throw '请关闭设置，修复编排配置后开始。'}
    if ($script:rotation.Active.ContainsKey($Row.Key)) {return}
    $plan=Get-RowRotationPlan $Row;Test-RotationPlan $plan;Test-RowAccountPlan $Row $plan
    $index=Get-RotationNextSlot $plan -1
    Stop-Row $Row '开始角色编排，准备登录第一个有效槽位。' -CancelExit
    $entry=[pscustomobject]@{Row=$Row;Plan=(Copy-RotationPlan $plan);Index=$index;ExcludedNames=@();LastLogout=-30000L}
    $script:rotation.Active[$Row.Key]=$entry;$script:rotation.LogoutQueue.Enqueue($entry)
    if (-not $script:rotation.NextAt -and $script:rotation.IntervalSeconds) {$script:rotation.NextAt=$script:schedulerClock.ElapsedMilliseconds+[long]$script:rotation.IntervalSeconds*1000}
    Update-RotationRow $Row
}
function Begin-RotationBatch([long]$Now) {
    # Stop every member before the first window is touched; foreground input is serialized afterward.
    $entries=@($script:rotation.Active.Values | Sort-Object {$_.Row.Process.Id})
    foreach ($entry in $entries) {
        Stop-Row $entry.Row '全局轮换到期，停止动作并切换下一角色。' -CancelExit -KeepRotation
        $entry.Index=Get-RotationNextSlot $entry.Plan $entry.Index $entry.ExcludedNames
        $entry.LastLogout=-30000L
        $script:rotation.LogoutQueue.Enqueue($entry);Update-RotationRow $entry.Row
    }
    if ($script:rotation.IntervalSeconds) {$script:rotation.NextAt=$Now+[long]$script:rotation.IntervalSeconds*1000}
}
function Exclude-FullRotationRole($Row) {
    if (-not $script:rotation.Active.ContainsKey($Row.Key)) {return 'NoPlan'}
    $entry=$script:rotation.Active[$Row.Key]
    $name=$entry.Plan.Slots[$entry.Index].Name
    if ($name -cnotin $entry.ExcludedNames) {$entry.ExcludedNames+=,$name}
    $next=Get-RotationNextSlot $entry.Plan $entry.Index $entry.ExcludedNames
    if ($next -lt 0) {return 'Exhausted'}
    Stop-Row $Row ('背包已满：“'+$name+'”已移出本进程轮换，准备切换下一角色。') -KeepRotation
    if ($script:rotation.Current -and $script:rotation.Current.Row.Key -eq $Row.Key) {
        $script:rotation.Current=$null;$script:rotation.NextOcrAt=0L
    }
    $entry.Index=$next
    $entry.LastLogout=-30000L
    $script:rotation.LogoutQueue.Enqueue($entry)
    Update-RotationRow $Row
    Set-RowStatusText $Row ('背包已满：“'+$name+'”已跳过，下一角色为“'+$entry.Plan.Slots[$next].Name+'”。')
    return 'Next'
}
function Send-RotationAction($Row,[string]$Action,$Target=$null) {
    Assert-GameActionContext
    if (-not (Test-RowProcessIdentity $Row) -or $Row.Process.HasExited) {throw '角色切换期间进程身份已变化。'}
    if (-not (Test-WorkerForeground $Row)) {throw '角色切换窗口暂时失去前台。'}
    if ($UiTest) {$script:rotation.Actions+=,[pscustomobject]@{Key=$Row.Key;Action=$Action;Target=$Target};return $true}
    switch ($Action) {
        'logout' {$sent=[WowAuto.NativeInput]::SendRotationCommand($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath,'logout',0)}
        'doubleclick' {
            if (-not $Target -or -not $Target.Name) {throw '未定位完整角色名。'}
            if (-not [WowAutoRotation.Native]::SnapshotMatches($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath,$Target.Width,$Target.Height)) {return $false}
            [WowAutoRotation.Native]::MouseAction($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath,$Target.X,$Target.Y,0,$true);$sent=$true
        }
        default {throw '未知编排动作。'}
    }
    if (-not $sent) {throw '角色切换输入失败。'}
    return $true
}
function Stop-RotationOcr {
    $work=$script:rotation.OcrWork;$script:rotation.OcrWork=$null;$script:rotation.NextOcrAt=0L
    if ($work) {try {$work.Pipeline.Stop()} finally {$work.Pipeline.Dispose()}}
}
function Resolve-RotationOcrName([string]$Text,[string[]]$Configured) {
    # OCR may misread one glyph. Keep the text length and every other position exact.
    $matches=@(foreach ($name in $Configured) {
        if ($Text.Length -ne $name.Length -or $name.Length -lt 2) {continue}
        $different=0
        for ($i=0;$i -lt $name.Length;$i++) {
            if ($Text[$i] -cne $name[$i]) {$different++;if ($different -gt 1) {break}}
        }
        if ($different -le 1) {$name}
    })
    if ($matches.Count -eq 1) {return [pscustomobject]@{Name=$matches[0];Ambiguous=$false}}
    return [pscustomobject]@{Name=$Text;Ambiguous=($matches.Count -gt 1)}
}
function Get-RotationMenuRow($Bounds,[double]$TextY) {
    # The first-page character rows occupy fixed, height-scaled positions. OCR
    # identifies the row; the click uses its stable center instead of an OCR box.
    $first=0.119;$step=0.0743
    $index=[int][Math]::Round(($TextY-$first)/$step,[MidpointRounding]::AwayFromZero)+1
    $centerY=$first+($index-1)*$step
    if ($index -lt 1 -or $index -gt 10 -or [Math]::Abs($TextY-$centerY) -gt 0.02) {return $null}
    return [pscustomobject]@{Index=$index;X=($Bounds.X+$Bounds.W/2);Y=$centerY}
}
function ConvertFrom-RotationOcr($Ocr,$Plan,[switch]$MenuWasConfirmed) {
    $configured=@($Plan.Slots | Where-Object {$_.Name} | ForEach-Object {$_.Name} | Select-Object -Unique)
    $bounds=if ($Ocr.PSObject.Properties['NamesBounds'] -and $Ocr.NamesBounds) {$Ocr.NamesBounds} else {[pscustomobject]@{X=0.79;Y=0;W=0.21;H=0.84}}
    $server=@($Ocr.Lines | Where-Object {$_.X -gt 0.65 -and $_.Y -lt 0.15 -and $_.Text -match '^[0一_—\-口□]*选择服务器[一_—\-口□]*$'}).Count -gt 0
    # The name-text pass also isolates the yellow server button from its border.
    $server=$server -or @($Ocr.Names | Where-Object {$_.Text -eq '选择服务器' -and ($bounds.X+$_.X*$bounds.W) -gt 0.65 -and ($bounds.Y+$_.Y*$bounds.H) -lt 0.15}).Count -gt 0
    $enter=@($Ocr.Lines | Where-Object {$_.X -gt 0.25 -and $_.X -lt 0.70 -and $_.Y -gt 0.85 -and $_.Text -match '^[0一_—\-口□]*进入魔兽世界[一_—\-口□]*$'}).Count -gt 0
    $targets=@(foreach ($line in $Ocr.Names) {
        $y=$bounds.Y+($line.Y+$line.H/2)*$bounds.H
        if ($y -lt 0.08 -or $y -gt 0.80 -or ($y -lt 0.15 -and $line.Text -eq '选择服务器') -or $line.Text -notmatch '^[\p{L}\p{M}]+$') {continue}
        $row=Get-RotationMenuRow $bounds $y
        if (-not $row) {continue}
        $match=Resolve-RotationOcrName $line.Text $configured
        [pscustomobject]@{Name=$match.Name;Ambiguous=$match.Ambiguous;MenuRow=$row.Index;X=$row.X;Y=$row.Y}
    })
    # The normal pass can recover names that yellow-text preprocessing misread twice.
    foreach ($line in $Ocr.Lines) {
        if ($line.X -gt $bounds.X -and $line.Y -gt 0.08 -and $line.Y -lt 0.80) {
            $match=Resolve-RotationOcrName $line.Text $configured
            if (-not $match.Ambiguous -and $match.Name -cin $configured -and $match.Name -cnotin $targets.Name) {
                $row=Get-RotationMenuRow $bounds ($line.Y+$line.H/2)
                if ($row) {$targets+=,[pscustomobject]@{Name=$match.Name;Ambiguous=$false;MenuRow=$row.Index;X=$row.X;Y=$row.Y}}
            }
        }
    }
    if ($server -or $enter) {
        return [pscustomobject]@{Kind='menu';Targets=$targets;RoleName=$null}
    }
    return [pscustomobject]@{Kind='unknown';Targets=@();RoleName=$null}
}
function Read-RotationScreen($Row,$Plan,[switch]$MenuWasConfirmed) {
    if ($UiTest) {
        if (-not $Row.Process.PSObject.Properties['RotationOcrReads']) {$Row.Process | Add-Member NoteProperty RotationOcrReads 0}
        if (-not $Row.Process.PSObject.Properties['RotationCursorParks']) {$Row.Process | Add-Member NoteProperty RotationCursorParks 0}
        $Row.Process.RotationCursorParks++
        $Row.Process.RotationOcrReads++
        return $Row.Process.RotationScreen
    }
    $work=$script:rotation.OcrWork
    if ($work) {
        if ($work.Key -ne $Row.Key) {Stop-RotationOcr;throw 'OCR任务进程不一致。'}
        if (-not $work.Async.IsCompleted) {return [pscustomobject]@{Kind='pending'}}
        $script:rotation.OcrWork=$null
        try {
            $result=$work.Pipeline.EndInvoke($work.Async)
            if ($work.Pipeline.Streams.Error.Count) {throw $work.Pipeline.Streams.Error[0].ToString()}
            if (-not [WowAutoRotation.Native]::SnapshotMatches($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath,$work.Width,$work.Height)) {return [pscustomobject]@{Kind='pending'}}
            if ($script:schedulerClock.ElapsedMilliseconds-$work.At -gt 3000) {return [pscustomobject]@{Kind='pending'}}
            $screen=ConvertFrom-RotationOcr ($result[0] | ConvertFrom-Json) $Plan -MenuWasConfirmed:$MenuWasConfirmed
            foreach ($target in @($screen.Targets)) {
                $target | Add-Member NoteProperty Width $work.Width
                $target | Add-Member NoteProperty Height $work.Height
            }
            return $screen
        } finally {$work.Pipeline.Dispose()}
    }
    # Limit capture starts; completion polling must never create another in-flight OCR task.
    $sampleAt=$script:schedulerClock.ElapsedMilliseconds
    if ($sampleAt -lt $script:rotation.NextOcrAt) {return [pscustomobject]@{Kind='pending'}}
    Assert-GameActionContext
    try {
        [WowAutoRotation.Native]::ParkCursor($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath)
        $bitmap=[WowAutoRotation.Native]::Capture($Row.Process.Id,$Row.StartTime.Ticks,$Row.Client.ExecutablePath)
    } catch {
        if (-not (Test-RowProcessIdentity $Row) -or $Row.Process.HasExited) {throw}
        if (-not (Test-WorkerForeground $Row)) {throw '角色切换窗口暂时失去前台。'}
        if ($_.Exception.Message -match 'Window moved during (cursor parking|capture)|Client geometry unavailable') {return [pscustomobject]@{Kind='pending'}}
        throw
    }
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
    if (-not $script:gameActions.Current) {
        Submit-RotationAction $Now
        if ($UiTest) {Invoke-GameActionQueue $Now}
        return [bool]($script:rotation.Current -or $script:rotation.LogoutQueue.Count -or $script:rotation.Queue.Count)
    }
    if ($script:scanning -or $script:editingSettings) {return $false}
    if (-not $script:rotation.Current -and -not $script:rotation.LogoutQueue.Count -and -not $script:rotation.Queue.Count -and
        $script:rotation.NextAt -and $Now -ge $script:rotation.NextAt) {Begin-RotationBatch $Now}
    if (-not $script:rotation.Current) {
        while ($script:rotation.LogoutQueue.Count -or $script:rotation.Queue.Count) {
            $logout=$script:rotation.LogoutQueue.Count -gt 0
            $entry=if ($logout) {$script:rotation.LogoutQueue.Dequeue()} else {$script:rotation.Queue.Dequeue()}
            if ($script:rotation.Active[$entry.Row.Key] -ne $entry) {continue}
            $phase=if ($logout) {'logout-activate'} else {'activate'}
            $script:rotation.Current=[pscustomobject]@{Entry=$entry;Row=$entry.Row;Phase=$phase;Due=$Now;Deadline=($Now+180000);FocusUntil=0L;
                Stable=0;LastLogout=$entry.LastLogout;Candidate=$null;FindMisses=0;MonitorEnabled=$false}
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
        if ($work.Phase -in @('logout-activate','activate')) {
            if (-not (Activate-ScanRow $row)) {
                if (-not $work.FocusUntil) {$work.FocusUntil=$Now+5000}
                if ($Now -ge $work.FocusUntil) {throw '连续5秒无法激活角色切换窗口。'}
                $work.Due=[Math]::Min($Now+500,$work.FocusUntil);return $true
            }
            $work.Phase=if ($work.Phase -eq 'logout-activate') {'logout-inspect'} else {'menu'}
            $work.Due=$Now+200;return $true
        }
        if (-not (Test-WorkerForeground $row)) {
            if (-not $work.FocusUntil) {$work.FocusUntil=$Now+5000}
            if ($Now -ge $work.FocusUntil) {throw '连续5秒未能取得角色切换窗口前台。'}
            $activated=Activate-ScanRow $row
            $delay=if ($activated) {200} else {500}
            $work.Due=[Math]::Min($Now+$delay,$work.FocusUntil)
            return $true
        }
        $work.FocusUntil=0L
        # First issue logout to every queued process. OCR starts only after this queue drains.
        if ($work.Phase -eq 'logout-inspect') {
            if (Test-RowLoginPoint $row) {
                $null=Send-RotationAction $row 'logout';$entry.LastLogout=$Now
            }
            $row.Validated=$false
            $script:rotation.Queue.Enqueue($entry)
            $script:rotation.Current=$null
            Set-RowStatusText $row '步骤1/3：已处理本进程登出，等待所有进程完成登出请求后再逐个选角。'
            return $true
        }
        if ($work.Phase -eq 'menu' -and (Test-RowLoginPoint $row)) {
            $work.Stable=0
            if ($Now-$work.LastLogout -ge 30000) {$null=Send-RotationAction $row 'logout';$work.LastLogout=$Now}
            $work.Due=$Now+300
            Set-RowStatusText $row '步骤1/3：等待退出倒计时 / 脱战，每30秒重试退出。'
            return $true
        }
        # Stage 2: login is checked only by the permanent addon point, never OCR or HUD text.
        if ($work.Phase -eq 'login') {
            if (Test-RowLoginPoint $row) {$work.Stable++} else {$work.Stable=0}
            if ($work.Stable -ge 3) {
                Set-RowSlotTask $row $entry.Plan.Slots[$entry.Index]
                $work.Phase='validate';$work.Due=$Now
            } else {
                $work.Due=$Now+300
                Set-RowStatusText $row ('步骤2/3：等待“'+$name+'”进入游戏并连续三次确认右下角常驻白点。')
            }
            return $true
        }
        # Stage 3: recheck the point before enabling either detector and before starting its task.
        if ($work.Phase -eq 'validate') {
            if (-not (Test-RowLoginPoint $row)) {
                $work.Phase='login';$work.Stable=0;$work.MonitorEnabled=$false;$work.Due=$Now+300
                return $true
            }
            if (-not $work.MonitorEnabled) {
                if (-not (Send-ScanDetectorCommand $row)) {throw '登录后监控开启命令失败。'}
                $work.MonitorEnabled=$true;$work.Due=$Now+300
                Set-RowStatusText $row '步骤3/3：白点确认通过，已开启监控，等待任务色块。'
                return $true
            }
            if ($row.TaskMode -eq 'fight') {
                $packet=Read-ScanFightPacket $row
                if (-not $packet -or $packet.Flavor -ne $row.Client.Flavor) {$work.Due=$Now+300;return $true}
                $row.FightRow.CanStart=$true;$row.FightRow.ClassId=$packet.ClassId
            } else {
                $color=Read-ScanColor $row
                if ($color -eq 'yellow') {Close-WorkerGame $row;return $true}
                if ($color -notin @('red','green')) {$work.Due=$Now+300;return $true}
            }
            $row.Validated=$true
            foreach ($table in @($script:scheduler.CompletedCycles,$script:scheduler.CyclesSinceJump)) {if ($null -ne $table) {$table.Remove($row.Key)}}
            Start-Row $row -TaskOnly
            if (-not (Test-UnifiedTaskRunning $row)) {throw '角色任务未能启动。'}
            Set-RowStatusText $row ('槽'+($entry.Index+1)+' / '+$name+' 已确认登录并开始任务。')
            $script:rotation.Current=$null
            if (-not $script:rotation.Queue.Count -and $script:rotation.NextAt -and $script:rotation.NextAt -le $Now) {$script:rotation.NextAt=$Now+[long]$script:rotation.IntervalSeconds*1000}
            Update-RotationRow $row;return $true
        }
        $screen=Read-RotationScreen $row $entry.Plan -MenuWasConfirmed:($work.Phase -eq 'find')
        if ($screen.Kind -eq 'pending') {$work.Due=$Now+100;return $true}
        switch ($work.Phase) {
            'menu' {
                if ($screen.Kind -eq 'menu') {
                    $work.Stable++
                    if ($work.Stable -ge 3) {$work.Phase='find';$work.Stable=0}
                } else {
                    $work.Stable=0
                    Set-RowStatusText $row '步骤1/3：等待OCR识别选择服务器或进入魔兽世界。'
                }
            }
            'find' {
                if ($screen.Kind -ne 'menu') {$work.Stable=0;Set-RowStatusText $row '选角锚点未识别，等待重新识别。';break}
                $targets=@($screen.Targets | Where-Object {$_.Name -ceq $name -and -not $_.Ambiguous})
                if ($targets.Count -gt 1) {throw '列表出现多个相同名称，未双击。'}
                if ($targets.Count -eq 1) {
                    $work.FindMisses=0
                    $target=$targets[0]
                    if ($work.Candidate -and [Math]::Abs($target.X-$work.Candidate.X) -lt 0.005 -and [Math]::Abs($target.Y-$work.Candidate.Y) -lt 0.005) {$work.Stable++} else {$work.Stable=1}
                    $work.Candidate=$target
                    if ($work.Stable -ge 2) {
                        if (-not (Send-RotationAction $row 'doubleclick' $target)) {
                            $work.Stable=0;$work.Candidate=$null;$work.Due=$Now+100
                            Set-RowStatusText $row '窗口缩放，重新OCR定位角色名。'
                            return $true
                        }
                        Stop-RotationOcr
                        $work.Phase='login';$work.Stable=0
                        Set-RowStatusText $row ('步骤2/3：已快速双击“'+$name+'”，OCR结束，等待常驻白点。')
                    }
                } else {
                    $work.Candidate=$null;$work.Stable=0
                    $work.FindMisses++
                    if ($work.FindMisses -ge 3) {throw ('第一页未找到角色“'+$name+'”；请将角色放在第一页并核对名称及服务器。')}
                    Set-RowStatusText $row ('第一页未找到“'+$name+'”，再次识别同一页（'+$work.FindMisses+'/3）。')
                }
            }
        }
        $work.Due=$Now+300
    } catch {
        $reason=$_.Exception.Message
        if ($reason -eq '角色切换窗口暂时失去前台。') {
            if (-not $work.FocusUntil) {$work.FocusUntil=$Now+5000}
            if ($Now -lt $work.FocusUntil) {$work.Due=[Math]::Min($Now+500,$work.FocusUntil);return $true}
            $reason='连续5秒未能取得角色切换窗口前台。'
        }
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
    $dialog.StartPosition='CenterParent';$dialog.ClientSize=New-Object Drawing.Size(950,355)
    Update-RowAccountChoices $Row
    $names=@(Get-RowAccountNames $Row)
    $plan=Copy-RotationPlan (Get-RowRotationPlan $Row)
    foreach ($slot in $plan.Slots) {if (-not $slot.PSObject.Properties['UseItem']) {$slot | Add-Member NoteProperty UseItem $false}}
    $hint=New-Object System.Windows.Forms.Label;$hint.Text='子战网：'+$Row.AccountName+'。输入或选择该子战网本地记录中的完整角色名；留空为空槽，每槽独立选择任务与钓鱼道具。';$hint.SetBounds(15,15,920,52);$dialog.Controls.Add($hint)
    $controls=@()
    for ($i=0;$i -lt 3;$i++) {
        $label=New-Object System.Windows.Forms.Label;$label.Text='槽位 '+($i+1)+' · 角色名称';$label.SetBounds(20,(75+$i*48),190,30)
        $text=New-Object System.Windows.Forms.ComboBox;$text.DropDownStyle='DropDown';$text.MaxLength=24
        $text.Items.AddRange([object[]]$names);$text.Text=$plan.Slots[$i].Name;$text.SetBounds(220,(70+$i*48),270,34)
        $text.FlatStyle='Flat';$text.AutoCompleteMode='Suggest';$text.AutoCompleteSource='ListItems'
        $text.BackColor=$script:uiColors.Input;$text.ForeColor=$script:uiColors.Text
        $mode=New-Object System.Windows.Forms.ComboBox;$mode.DropDownStyle='DropDownList';$mode.Items.AddRange([object[]]@('钓鱼','战斗'));$mode.SelectedIndex=if ($plan.Slots[$i].Mode -eq 'fight') {1} else {0};$mode.SetBounds(525,(70+$i*48),170,34)
        $mode.BackColor=$script:uiColors.Input;$mode.ForeColor=$script:uiColors.Text;$mode.FlatStyle='Flat';$mode.DrawMode='OwnerDrawFixed';$mode.ItemHeight=26
        $mode.Add_DrawItem({param($sender,$e)
            if ($e.Index -lt 0) {return}
            $brush=New-Object Drawing.SolidBrush($sender.BackColor)
            try {$e.Graphics.FillRectangle($brush,$e.Bounds)} finally {$brush.Dispose()}
            [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics,[string]$sender.Items[$e.Index],$sender.Font,$e.Bounds,[Drawing.Color]::White)
        })
        $item=New-Object WowAuto.DimCheckBox;$item.Text='钓鱼道具';$item.SetBounds(720,(70+$i*48),190,34);$item.FlatStyle='Flat';$item.Checked=[bool]$plan.Slots[$i].UseItem;$item.Enabled=$mode.SelectedIndex -eq 0
        $mode.Tag=$item;$mode.Add_SelectedIndexChanged({param($sender,$e) $sender.Tag.Enabled=$sender.SelectedIndex -eq 0})
        $dialog.Controls.AddRange([System.Windows.Forms.Control[]]@($label,$text,$mode,$item));$controls+=,[pscustomobject]@{Name=$text;Mode=$mode;UseItem=$item}
    }
    $errorLabel=New-Object System.Windows.Forms.Label;$errorLabel.SetBounds(20,223,910,70)
    $errorLabel.Text='下拉框仅显示所选子战网的本地角色记录；旧名称仍保留在输入框，保存前须改成该子战网中的名称。战斗槽不使用钓鱼道具。'
    $save=New-Object WowAuto.DimButton;$save.Text='保存编排';$save.SetBounds(430,300,135,36);Set-UiButtonStyle $save $true
    $cancel=New-Object WowAuto.DimButton;$cancel.Text='取消';$cancel.SetBounds(585,300,125,36);Set-UiButtonStyle $cancel
    $dialog.Tag=[pscustomobject]@{Row=$Row;Plan=$plan;Slots=$controls;Error=$errorLabel;Save=$save}
    $save.Tag=$dialog;$save.Add_Click({param($sender,$e)
        $editor=$sender.Tag.Tag
        try {
            for ($i=0;$i -lt 3;$i++) {$editor.Plan.Slots[$i].Name=$editor.Slots[$i].Name.Text.Trim();$editor.Plan.Slots[$i].Mode=if ($editor.Slots[$i].Mode.SelectedIndex -eq 1) {'fight'} else {'fish'};$editor.Plan.Slots[$i].UseItem=$editor.Slots[$i].UseItem.Checked -and $editor.Plan.Slots[$i].Mode -eq 'fish'}
            $editor.Plan | Add-Member NoteProperty Account $editor.Row.AccountName -Force
            Test-RotationPlan $editor.Plan;Test-RowAccountPlan $editor.Row $editor.Plan
            $next=$script:rotation.Plans.Clone();$next[$editor.Row.Key]=Copy-RotationPlan $editor.Plan
            Save-RotationConfiguration -Plans $next
            Stop-Row $editor.Row '编排已保存，任务停止；点击开始从首个有效槽位运行。' -CancelExit
            $editor.Row.Validated=$false
            $index=Get-RotationNextSlot $editor.Plan -1
            if ($index -ge 0) {Set-RowSlotTask $editor.Row $editor.Plan.Slots[$index]} else {Set-RowSlotTask $editor.Row ([pscustomobject]@{Mode='fish';UseItem=$false})}
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
