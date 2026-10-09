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
# Run the production function against inert process methods, never a real process.
$UiTest=$false
function Stop-Row($Row,[string]$Reason) {
    Stop-WowAutoTask $script:scheduler $Row.Key $Reason
    Stop-WowAutoState $Row.State $Reason
}
foreach ($case in @('low','boundary','accepted','rejected','throws','reused','exited')) {
    $script:scheduler=New-WowAutoScheduler
    $state=Add-WowAutoTask $script:scheduler 'target' 1 1 0
    $other=Add-WowAutoTask $script:scheduler 'other' 1 1 0
    $null=Complete-WowAutoPoll $script:scheduler 'target' 0 'green'
    $script:scheduler.CompletedCycles['target']=if ($case -eq 'low') { 0 } elseif ($case -eq 'boundary') { 500 } else { 501 }
    $start=[datetime]'2026-01-01'
    $process=[pscustomobject]@{StartTime=$start; ProcessName='WowClassic'; HasExited=($case -eq 'exited'); Calls=0; Case=$case}
    if ($case -eq 'reused') { $process.StartTime=$start.AddSeconds(1) }
    $process | Add-Member ScriptMethod Refresh { }
    $process | Add-Member ScriptMethod Kill { throw 'Force termination must never be used.' }
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
}
Write-Output 'PASS: normal-close adapter, 0/500/501 threshold, rejection/error, reused identity, existing exit, cancellation and other-row isolation. No native actions.'
