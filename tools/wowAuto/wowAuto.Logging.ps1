# Per-launch, bounded diagnostic files. UI tests supply a temporary directory.
if(-not ('WowAuto.Threading.LogWriter' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'wowAuto.Threading.cs') -ReferencedAssemblies System.Core}
function Initialize-WowAutoLogging([string]$Directory,[datetimeoffset]$StartedAt=([datetimeoffset]::Now),[int]$MaxSizeMB=50) {
    if ($MaxSizeMB -lt 1 -or $MaxSizeMB -gt 1024) {throw '日志总大小需为1–1024 MB。'}
    Stop-WowAutoLogging
    $writer=New-Object WowAuto.Threading.LogWriter($Directory,$MaxSizeMB)
    $script:wowAutoLog=[pscustomobject]@{
        Directory=$Directory; LogPath=(Join-Path $Directory 'wowAuto.log'); InfoPath=(Join-Path $Directory 'info.log')
        StartedAt=$StartedAt; MaxSizeMB=$MaxSizeMB; Rounds=@{}; CurrentRoles=@{}; LastError='';Writer=$writer
    }
    Update-WowAutoRunInfo
    Write-WowAutoLog '脚本启动。' -Kind system
}
function Stop-WowAutoLogging {
    if($script:wowAutoLog -and $script:wowAutoLog.Writer -and -not $script:wowAutoLog.Writer.Close(5000)){
        throw '日志线程尚未写完退出，暂不能重启脚本。'
    }
}
function Sync-WowAutoLogging {
    if($script:wowAutoLog -and -not $script:wowAutoLog.Writer.Flush(5000)){throw '等待日志写入超时。'}
    if($script:wowAutoLog -and $script:wowAutoLog.Writer.LastError){throw $script:wowAutoLog.Writer.LastError}
}
function Get-WowAutoLogPid($Row) {
    if (-not $Row) {return $null}
    if ($Row.PSObject.Properties['Process'] -and $Row.Process) {return [int]$Row.Process.Id}
    if ($Row.PSObject.Properties['Client'] -and $Row.Client -and $Row.Client.PSObject.Properties['ProcessId']) {return [int]$Row.Client.ProcessId}
    return $null
}
function Write-WowAutoLog([string]$Message,$Row=$null,[string]$Kind='status') {
    if (-not $script:wowAutoLog) {return}
    try {
        $script:wowAutoLog.Writer.Log((Get-WowAutoLogPid $Row),$Kind,$Message)
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
        $state.Writer.WriteInfo($json)
        $state.LastError=''
    }
    catch {$state.LastError=$_.Exception.Message}
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
        try {$script:wowAutoLog.Writer.MaxSizeMB=$size;$script:wowAutoLog.LastError=''} catch {$script:wowAutoLog.LastError=$_.Exception.Message}
    }
    return $size
}
