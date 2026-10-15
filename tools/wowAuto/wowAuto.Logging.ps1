# Per-launch, bounded diagnostic files. UI tests supply a temporary directory.
function Initialize-WowAutoLogging([string]$Directory,[datetimeoffset]$StartedAt=([datetimeoffset]::Now),[int]$MaxSizeMB=50) {
    if ($MaxSizeMB -lt 1 -or $MaxSizeMB -gt 1024) {throw '日志总大小需为1–1024 MB。'}
    [IO.Directory]::CreateDirectory($Directory) | Out-Null
    $script:wowAutoLog=[pscustomobject]@{
        Directory=$Directory; LogPath=(Join-Path $Directory 'wowAuto.log'); InfoPath=(Join-Path $Directory 'info.log')
        StartedAt=$StartedAt; MaxSizeMB=$MaxSizeMB; Rounds=@{}; CurrentRoles=@{}; LastError=''
    }
    $utf8=New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($script:wowAutoLog.LogPath,'',$utf8)
    [IO.File]::WriteAllText($script:wowAutoLog.InfoPath,'',$utf8)
    Update-WowAutoRunInfo
    Write-WowAutoLog '脚本启动。' -Kind system
}
function Get-WowAutoLogPid($Row) {
    if (-not $Row) {return $null}
    if ($Row.PSObject.Properties['Process'] -and $Row.Process) {return [int]$Row.Process.Id}
    if ($Row.PSObject.Properties['Client'] -and $Row.Client -and $Row.Client.PSObject.Properties['ProcessId']) {return [int]$Row.Client.ProcessId}
    return $null
}
function Copy-WowAutoLogTail([string]$Path,[string]$Temporary,[long]$KeepBytes,[byte[]]$AppendBytes) {
    $source=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $target=[IO.File]::Open($Temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {
        if ($KeepBytes -gt 0 -and $source.Length -gt 0) {
            $start=[Math]::Max(0L,$source.Length-$KeepBytes)
            if ($start -gt 0) {
                $source.Position=$start-1
                if ($source.ReadByte() -ne 10) {
                    while ($source.Position -lt $source.Length -and $source.ReadByte() -ne 10) {}
                }
            } else {$source.Position=0}
            $source.CopyTo($target)
        }
        if ($AppendBytes.Length) {$target.Write($AppendBytes,0,$AppendBytes.Length)}
    }
    finally {$target.Dispose();$source.Dispose()}
}
function Limit-WowAutoLog([byte[]]$AppendBytes=([byte[]]@())) {
    $state=$script:wowAutoLog
    if (-not $state) {return}
    $maximum=[long]$state.MaxSizeMB*1MB
    $infoSize=(Get-Item -LiteralPath $state.InfoPath).Length
    $budget=$maximum-$infoSize
    if ($budget -le 0 -or $AppendBytes.Length -gt $budget) {throw 'info.log 或单条日志超过配置的总大小限制。'}
    $current=(Get-Item -LiteralPath $state.LogPath).Length
    if ($current+$AppendBytes.Length -le $budget) {
        if ($AppendBytes.Length) {
            $stream=[IO.File]::Open($state.LogPath,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::Read)
            try {$stream.Write($AppendBytes,0,$AppendBytes.Length)} finally {$stream.Dispose()}
        }
        return
    }
    # Leave headroom so a busy action queue does not recopy a near-full log for every event.
    $keep=[long][Math]::Floor(($budget-$AppendBytes.Length)*0.9)
    $temporary=$state.LogPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        Copy-WowAutoLogTail $state.LogPath $temporary $keep $AppendBytes
        [IO.File]::Replace($temporary,$state.LogPath,[System.Management.Automation.Language.NullString]::Value)
    }
    finally {if ([IO.File]::Exists($temporary)) {[IO.File]::Delete($temporary)}}
}
function Write-WowAutoLog([string]$Message,$Row=$null,[string]$Kind='status') {
    if (-not $script:wowAutoLog) {return}
    try {
        $record=[ordered]@{Time=([datetimeoffset]::Now.ToString('o'));Pid=(Get-WowAutoLogPid $Row);Kind=$Kind;Message=$Message}
        $line=($record | ConvertTo-Json -Compress -Depth 5)+"`n"
        $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($line)
        Limit-WowAutoLog $bytes
        $script:wowAutoLog.LastError=''
    } catch {$script:wowAutoLog.LastError=$_.Exception.Message}
}
function Get-WowAutoRunInfo {
    $state=$script:wowAutoLog
    $processes=@(if ($script:rows) {
        foreach ($row in @($script:rows.Values | Sort-Object {$_.Process.Id})) {
            $plan=$null
            if ($script:rotation -and $script:rotation.Plans -and $script:rotation.Plans.ContainsKey($row.Key)) {$plan=$script:rotation.Plans[$row.Key]}
            $slots=@(if ($plan) {for ($i=0;$i -lt @($plan.Slots).Count;$i++) {
                $slot=$plan.Slots[$i]
                [ordered]@{Slot=($i+1);Role=([string]$slot.Name);Task=([string]$slot.Mode);UseItem=([bool]$slot.UseItem)}
            }})
            $account=if ($plan -and $plan.PSObject.Properties['Account']) {[string]$plan.Account} else {''}
            $current=if ($state.CurrentRoles.ContainsKey($row.Key)) {$state.CurrentRoles[$row.Key]} else {$null}
            [ordered]@{Pid=(Get-WowAutoLogPid $row);Client=([string]$row.Client.Flavor);SubAccount=$account;
                Slots=$slots;CurrentSlot=$(if ($current) {$current.Slot} else {$null});
                CurrentRole=([string]$(if ($current) {$current.Role} else {''}));
                ExecutionRound=$(if ($state.Rounds.ContainsKey($row.Key)) {[int]$state.Rounds[$row.Key]} else {0})}
        }
    })
    return [ordered]@{StartTime=$state.StartedAt.ToString('o');ProcessCount=$processes.Count;Processes=$processes}
}
function Update-WowAutoRunInfo {
    if (-not $script:wowAutoLog) {return}
    $state=$script:wowAutoLog
    try {
        $json=(Get-WowAutoRunInfo | ConvertTo-Json -Depth 8)
        $temporary=$state.InfoPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
        [IO.File]::WriteAllText($temporary,$json+"`n",(New-Object Text.UTF8Encoding($false)))
        [IO.File]::Replace($temporary,$state.InfoPath,[System.Management.Automation.Language.NullString]::Value)
        Limit-WowAutoLog
        $state.LastError=''
    }
    catch {$state.LastError=$_.Exception.Message}
    finally {if ($temporary -and [IO.File]::Exists($temporary)) {[IO.File]::Delete($temporary)}}
}
function Register-WowAutoExecutionRound($Row) {
    if (-not $script:wowAutoLog) {return}
    $state=$script:wowAutoLog
    $round=if ($state.Rounds.ContainsKey($Row.Key)) {[int]$state.Rounds[$Row.Key]+1} else {1}
    $state.Rounds[$Row.Key]=$round
    $slot=$null;$name=''
    if ($script:rotation -and $script:rotation.Active -and $script:rotation.Active.ContainsKey($Row.Key)) {
        $entry=$script:rotation.Active[$Row.Key]
        $slot=$entry.Index+1;$name=[string]$entry.Plan.Slots[$entry.Index].Name
    }
    $state.CurrentRoles[$Row.Key]=[pscustomobject]@{Slot=$slot;Role=$name}
    Update-WowAutoRunInfo
    Write-WowAutoLog "任务开始；执行轮次 $round；角色 $name。" $Row task
}
function Clear-WowAutoCurrentRole($Row) {
    if (-not $script:wowAutoLog) {return}
    if ($script:wowAutoLog.CurrentRoles.ContainsKey($Row.Key)) {
        $script:wowAutoLog.CurrentRoles.Remove($Row.Key)
        Update-WowAutoRunInfo
    }
}
function Set-WowAutoLogSizeMB($Value) {
    $size=0
    if ([string]$Value -notmatch '^\d+$' -or -not [int]::TryParse([string]$Value,[ref]$size) -or $size -lt 1 -or $size -gt 1024) {
        throw '日志总大小需为1–1024 MB。'
    }
    if ($script:wowAutoLog) {
        $script:wowAutoLog.MaxSizeMB=$size
        try {Limit-WowAutoLog;$script:wowAutoLog.LastError=''} catch {$script:wowAutoLog.LastError=$_.Exception.Message}
    }
    return $size
}
