$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\wowAuto.Engine.ps1')
. (Join-Path $PSScriptRoot '..\wowAuto.ActionQueue.ps1')
Initialize-GameActionQueue (Join-Path $PSScriptRoot '..\action-priorities.json')
$script:scanning=$false;$script:editingSettings=$false;$script:autoFight=$null
$script:rows=@{}
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '..\wowAuto.ps1'),[ref]$tokens,[ref]$errors)
if ($errors) { throw ($errors | Out-String) }
$source=$ast.Find({param($node)
    $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $node.Value.Contains('namespace WowAuto')
},$true)
Add-Type -TypeDefinition $source.Value
$identity=$ast.Find({param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-RowProcessIdentity'
},$true)
. ([scriptblock]::Create($identity.Extent.Text))
# Inert metadata reader, using the production pure classifier; no live process inspection.
function Get-ProcessClientInfo($Process) {
    $flavor=[WowAuto.NativeInput]::GetClientFlavor($Process.ExecutablePath,$Process.FileVersion)
    if (-not $flavor -or $Process.ProcessName -ne [IO.Path]::GetFileNameWithoutExtension($Process.ExecutablePath)) { return $null }
    [pscustomobject]@{Flavor=$flavor; ExecutablePath=$Process.ExecutablePath}
}
$function=$ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Close-WorkerGame'
},$true)
. ([scriptblock]::Create($function.Extent.Text))
$checks=$ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-GameExitChecks'
},$true)
. ([scriptblock]::Create($checks.Extent.Text))
foreach ($name in @('Invoke-CloseWorkerGame')) {
    $node=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    . ([scriptblock]::Create($node.Extent.Text))
}
# Run the production queue against inert process methods, never a real process.
$UiTest=$false
function Exclude-FullRotationRole($Row) {if ($Row.Process.Case -eq 'no-plan') {return 'NoPlan'};return 'Exhausted'}
function Stop-Row($Row,[string]$Reason) {
    Stop-WowAutoTask $script:scheduler $Row.Key $Reason
    Stop-WowAutoState $Row.State $Reason
}
foreach ($case in @('no-plan','zero-cycles','accepted','rejected','throws','forever','reused','exited')) {
    $script:scheduler=New-WowAutoScheduler
    $script:pendingGameExits=@{}
    $script:schedulerClock=[pscustomobject]@{ElapsedMilliseconds=1000L}
    $state=Add-WowAutoTask $script:scheduler 'target' 1 1 0
    $other=Add-WowAutoTask $script:scheduler 'other' 1 1 0
    $null=Complete-WowAutoPoll $script:scheduler 'target' 0 'green'
    $script:scheduler.CompletedCycles['target']=if ($case -eq 'zero-cycles') { 0 } else { 501 }
    $start=[datetime]'2026-01-01'
    $process=[pscustomobject]@{StartTime=$start; ProcessName='WowClassic'; HasExited=($case -eq 'exited'); Calls=0; Kills=0; Case=$case}
    $process | Add-Member NoteProperty ExecutablePath 'C:\games\_classic_titan_\WowClassic.exe'
    $process | Add-Member NoteProperty FileVersion '3.80.2.70177'
    if ($case -eq 'forever') { $process.ProcessName='Wow'; $process.ExecutablePath='C:\games\_cn_beta_\Wow.exe'; $process.FileVersion='1.60.1.70338' }
    if ($case -eq 'reused') { $process.StartTime=$start.AddSeconds(1) }
    $process | Add-Member ScriptMethod Refresh { }
    $process | Add-Member ScriptMethod Kill { $this.Kills++ }
    $process | Add-Member ScriptMethod CloseMainWindow {
        $this.Calls++
        if ($this.Case -eq 'throws') { throw 'Simulated close error.' }
        return $this.Case -ne 'rejected'
    }
    $row=[pscustomobject]@{Key='target'; Process=$process; StartTime=$start; State=$state; Validated=$true; Exited=$false}
    $row | Add-Member NoteProperty Client (Get-ProcessClientInfo $process)
    $script:rows[$row.Key]=$row
    Close-WorkerGame $row
    Invoke-GameActionQueue 1000
    $expectedCalls=if ($case -in @('zero-cycles','accepted','rejected','throws','forever')) { 1 } else { 0 }
    if ($process.Calls -ne $expectedCalls -or $row.Validated -or $state.Running -or -not $other.Running) { throw "Wrong close behavior: $case" }
    if (@($script:scheduler.Events | Where-Object { $_.Key -eq 'target' }).Count) { throw 'Target timers left behind.' }
    if ($case -eq 'accepted' -and ($process.HasExited -or $row.Exited -or $state.Status -notmatch '等待游戏完成退出')) { throw 'Accepted close incorrectly claims exit completed.' }
    if ($case -in @('rejected','throws','reused') -and $state.Status -notmatch '请求失败') { throw 'Close failure not reported.' }
    if ($case -eq 'exited' -and -not $row.Exited) { throw 'Already exited target not recognized.' }
    if ($case -in @('zero-cycles','accepted','rejected','throws','forever')) {
        if ($script:pendingGameExits['target'].Due -ne 31000) { throw 'Incorrect 30-second deadline.' }
        Invoke-GameExitChecks 30999;Invoke-GameActionQueue 30999
        if ($process.Kills) { throw 'Killed before full 30 seconds.' }
        Invoke-GameExitChecks 31000;Invoke-GameActionQueue 31000
        Invoke-GameExitChecks 99999;Invoke-GameActionQueue 99999
        if ($process.Kills -ne 1 -or $script:pendingGameExits.Count -or -not $other.Running) { throw 'Timeout must kill target once and leave other row running.' }
    } elseif ($script:pendingGameExits.Count) { throw 'Ineligible or changed process gained timeout protection.' }
}
foreach ($finish in @('normal','reused','renamed','path-changed','wrong-client','kill-error')) {
    $script:pendingGameExits=@{}
    $process.StartTime=$start; $process.ProcessName='WowClassic'; $process.HasExited=$false; $process.Case='accepted'; $process.Calls=0; $process.Kills=0
    $process.ExecutablePath=$row.Client.ExecutablePath; $process.FileVersion='3.80.2.70177'
    $row.StartTime=$start; $row.Exited=$false
    $script:scheduler.CompletedCycles['target']=0
    Close-WorkerGame $row
    Invoke-GameActionQueue 1000
    if ($finish -eq 'normal') { $process.HasExited=$true }
    if ($finish -eq 'reused') { $process.StartTime=$start.AddSeconds(1) }
    if ($finish -eq 'renamed') { $process.ProcessName='Other' }
    if ($finish -eq 'path-changed') { $process.ExecutablePath='D:\other\_classic_titan_\WowClassic.exe' }
    if ($finish -eq 'wrong-client') { $process.FileVersion='12.1.0.69933' }
    if ($finish -eq 'kill-error') { $process | Add-Member -Force ScriptMethod Kill { $this.Kills++; throw 'Denied' } }
    Invoke-GameExitChecks 31000;Invoke-GameActionQueue 31000
    Invoke-GameExitChecks 32000;Invoke-GameActionQueue 32000
    if ($script:pendingGameExits.Count) { throw 'Completed exit check remains queued.' }
    $expectedKills=if ($finish -eq 'kill-error') { 1 } else { 0 }
    if ($process.Kills -ne $expectedKills) { throw "Unsafe or repeated kill: $finish" }
    if ($finish -eq 'normal' -and -not $row.Exited) { throw 'Normal exit not recognized.' }
}
Write-Output 'PASS: exhausted-plan close independent of reel count, unplanned-row preservation, full 30-second timeout, normal exit, identity change and other-row isolation. No native actions.'
