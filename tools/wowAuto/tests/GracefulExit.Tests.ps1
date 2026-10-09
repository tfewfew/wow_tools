$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\wowAuto.Engine.ps1')
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '..\wowAuto.ps1'),[ref]$tokens,[ref]$errors)
if ($errors) { throw ($errors | Out-String) }
$function=$ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Close-WorkerGame'
},$true)
. ([scriptblock]::Create($function.Extent.Text))
$checks=$ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-GameExitChecks'
},$true)
. ([scriptblock]::Create($checks.Extent.Text))
# Run the production function against inert process methods, never a real process.
$UiTest=$false
function Stop-Row($Row,[string]$Reason) {
    Stop-WowAutoTask $script:scheduler $Row.Key $Reason
    Stop-WowAutoState $Row.State $Reason
}
foreach ($case in @('low','boundary','accepted','rejected','throws','reused','exited')) {
    $script:scheduler=New-WowAutoScheduler
    $script:pendingGameExits=@{}
    $script:schedulerClock=[pscustomobject]@{ElapsedMilliseconds=1000L}
    $state=Add-WowAutoTask $script:scheduler 'target' 1 1 0
    $other=Add-WowAutoTask $script:scheduler 'other' 1 1 0
    $null=Complete-WowAutoPoll $script:scheduler 'target' 0 'green'
    $script:scheduler.CompletedCycles['target']=if ($case -eq 'low') { 0 } elseif ($case -eq 'boundary') { 500 } else { 501 }
    $start=[datetime]'2026-01-01'
    $process=[pscustomobject]@{StartTime=$start; ProcessName='WowClassic'; HasExited=($case -eq 'exited'); Calls=0; Kills=0; Case=$case}
    if ($case -eq 'reused') { $process.StartTime=$start.AddSeconds(1) }
    $process | Add-Member ScriptMethod Refresh { }
    $process | Add-Member ScriptMethod Kill { $this.Kills++ }
    $process | Add-Member ScriptMethod CloseMainWindow {
        $this.Calls++
        if ($this.Case -eq 'throws') { throw 'Simulated close error.' }
        return $this.Case -ne 'rejected'
    }
    $row=[pscustomobject]@{Key='target'; Process=$process; StartTime=$start; State=$state; Validated=$true; Exited=$false}
    Close-WorkerGame $row
    $expectedCalls=if ($case -in @('accepted','rejected','throws')) { 1 } else { 0 }
    if ($process.Calls -ne $expectedCalls -or $row.Validated -or $state.Running -or -not $other.Running) { throw "Wrong close behavior: $case" }
    if (@($script:scheduler.Events | Where-Object { $_.Key -eq 'target' }).Count) { throw 'Target timers left behind.' }
    if ($case -eq 'accepted' -and ($process.HasExited -or $row.Exited -or $state.Status -notmatch '等待游戏完成退出')) { throw 'Accepted close incorrectly claims exit completed.' }
    if ($case -in @('rejected','throws','reused') -and $state.Status -notmatch '请求失败') { throw 'Close failure not reported.' }
    if ($case -eq 'exited' -and -not $row.Exited) { throw 'Already exited target not recognized.' }
    if ($case -in @('accepted','rejected','throws')) {
        if ($script:pendingGameExits['target'].Due -ne 31000) { throw 'Incorrect 30-second deadline.' }
        Invoke-GameExitChecks 30999
        if ($process.Kills) { throw 'Killed before full 30 seconds.' }
        Invoke-GameExitChecks 31000
        Invoke-GameExitChecks 99999
        if ($process.Kills -ne 1 -or $script:pendingGameExits.Count -or -not $other.Running) { throw 'Timeout must kill target once and leave other row running.' }
    } elseif ($script:pendingGameExits.Count) { throw 'Ineligible or changed process gained timeout protection.' }
}
foreach ($finish in @('normal','reused','renamed','kill-error')) {
    $script:pendingGameExits=@{}
    $process.StartTime=$start; $process.ProcessName='WowClassic'; $process.HasExited=$false; $process.Case='accepted'; $process.Calls=0; $process.Kills=0
    $row.StartTime=$start; $row.Exited=$false
    $script:scheduler.CompletedCycles['target']=501
    Close-WorkerGame $row
    if ($finish -eq 'normal') { $process.HasExited=$true }
    if ($finish -eq 'reused') { $process.StartTime=$start.AddSeconds(1) }
    if ($finish -eq 'renamed') { $process.ProcessName='Other' }
    if ($finish -eq 'kill-error') { $process | Add-Member -Force ScriptMethod Kill { $this.Kills++; throw 'Denied' } }
    Invoke-GameExitChecks 31000
    Invoke-GameExitChecks 32000
    if ($script:pendingGameExits.Count) { throw 'Completed exit check remains queued.' }
    $expectedKills=if ($finish -eq 'kill-error') { 1 } else { 0 }
    if ($process.Kills -ne $expectedKills) { throw "Unsafe or repeated kill: $finish" }
    if ($finish -eq 'normal' -and -not $row.Exited) { throw 'Normal exit not recognized.' }
}
Write-Output 'PASS: normal-close threshold/failure, full 30-second timeout, normal exit, identity change, one-shot kill/error and other-row isolation. No native actions.'
