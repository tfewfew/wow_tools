$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\wowAuto.Logging.ps1')
function Assert-Log($Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
$directory=Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-logging-'+[guid]::NewGuid().ToString('N'))
try {
    $started=[datetimeoffset]::Parse('2026-10-15T09:00:00+08:00')
    Initialize-WowAutoLogging $directory $started 1
    $row=[pscustomobject]@{Key='123:456';Process=[pscustomobject]@{Id=123};Client=[pscustomobject]@{Flavor='titan'};AccountName=''}
    $script:rows=@{'123:456'=$row}
    $plan=[pscustomobject]@{Account='WoW1';Slots=@(
        [pscustomobject]@{Name='角色甲';Mode='fish';UseItem=$true},
        [pscustomobject]@{Name='角色乙';Mode='fight';UseItem=$false},
        [pscustomobject]@{Name='';Mode='fish';UseItem=$false})}
    $script:rotation=[pscustomobject]@{Plans=@{'123:456'=$plan};Active=@{}}
    Update-WowAutoRunInfo
    Sync-WowAutoLogging
    $info=Get-Content -LiteralPath $script:wowAutoLog.InfoPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Log ($info.StartTime -eq $started.ToString('o') -and $info.ProcessCount -eq 1 -and
        $info.Processes[0].Pid -eq 123 -and $info.Processes[0].SubAccount -eq 'WoW1' -and
        $info.Processes[0].Slots[0].Role -eq '角色甲' -and $info.Processes[0].ExecutionRound -eq 0) 'Initial info snapshot lost process/account/role configuration.'
    $script:rotation.Active['123:456']=[pscustomobject]@{Index=1;Plan=$plan}
    Register-WowAutoExecutionRound $row
    Register-WowAutoExecutionRound $row
    Sync-WowAutoLogging
    $info=Get-Content -LiteralPath $script:wowAutoLog.InfoPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Log ($info.Processes[0].CurrentSlot -eq 2 -and $info.Processes[0].CurrentRole -eq '角色乙' -and
        $info.Processes[0].ExecutionRound -eq 2) 'Execution rounds or current role were not updated.'
    Write-WowAutoLog '状态更新' $row status
    Sync-WowAutoLogging
    $last=(Get-Content -LiteralPath $script:wowAutoLog.LogPath -Encoding UTF8 | Select-Object -Last 1) | ConvertFrom-Json
    Assert-Log ($last.Pid -eq 123 -and $last.Kind -eq 'status' -and $last.Message -eq '状态更新') 'Process log omitted PID or message.'
    $payload='x'*4000
    foreach ($index in 1..350) {Write-WowAutoLog ("event-$index $payload") $row action}
    Sync-WowAutoLogging
    $total=(Get-Item $script:wowAutoLog.LogPath).Length+(Get-Item $script:wowAutoLog.InfoPath).Length
    Assert-Log ($total -le 1MB -and $total -gt 0) 'Combined log files exceeded the configured size.'
    $lines=@(Get-Content -LiteralPath $script:wowAutoLog.LogPath -Encoding UTF8)
    Assert-Log ($lines.Count -gt 0 -and $lines[0] -match '^\{') 'Rollover cut through a JSON line.'
    foreach ($line in $lines) {$null=$line | ConvertFrom-Json}
    Assert-Log (($lines[-1] | ConvertFrom-Json).Message.StartsWith('event-350 ')) 'Rollover lost the newest event.'
    Clear-WowAutoCurrentRole $row
    Sync-WowAutoLogging
    $info=Get-Content -LiteralPath $script:wowAutoLog.InfoPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Log ($info.Processes[0].CurrentRole -eq '' -and $info.Processes[0].ExecutionRound -eq 2) 'Stop lost the cumulative execution round.'
    $script:rows=@{};Update-WowAutoRunInfo
    Sync-WowAutoLogging
    $info=Get-Content -LiteralPath $script:wowAutoLog.InfoPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Log ($info.ProcessCount -eq 0) 'Exited process remained in info snapshot.'
    foreach ($bad in @(0,1025,'1.5')) {
        $rejected=$false;try {$null=Set-WowAutoLogSizeMB $bad} catch {$rejected=$true}
        Assert-Log $rejected 'Invalid size limit was accepted.'
    }
    Initialize-WowAutoLogging $directory $started 1
    Sync-WowAutoLogging
    $after=@(Get-Content -LiteralPath $script:wowAutoLog.LogPath -Encoding UTF8)
    $info=Get-Content -LiteralPath $script:wowAutoLog.InfoPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Log ($after.Count -eq 1 -and ($after[0] | ConvertFrom-Json).Kind -eq 'system' -and
        $info.ProcessCount -eq 0 -and $info.StartTime -eq $started.ToString('o')) 'New launch did not overwrite both logs.'
    Write-Output 'PASS: per-launch overwrite, process PID, account/roles/rounds snapshot, one-MB combined cap, complete JSON lines and invalid limits. No game input.'
}
finally {Stop-WowAutoLogging;if ([IO.Directory]::Exists($directory)) {[IO.Directory]::Delete($directory,$true)}}
