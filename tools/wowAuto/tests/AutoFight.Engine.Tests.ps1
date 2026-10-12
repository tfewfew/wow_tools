$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot '..\autoFight.Engine.ps1')
function Assert-Fight($Condition,[string]$Label) { if (-not $Condition) { throw $Label } }
$path=Join-Path ([IO.Path]::GetTempPath()) ('autoFight-'+[Guid]::NewGuid()+'.json')
try {
    $config=Read-AutoFightConfiguration $path
    Assert-Fight ($config.Profiles.Count -eq 26 -and $config.CommandIntervalMs -eq 500) 'Defaults incomplete.'
    $profiles=$config.Profiles; $profiles['forerver:3'].CombatKey='Ctrl+7'
    $valid=Save-AutoFightProfiles $path $profiles 1200
    $config=Read-AutoFightConfiguration $path
    Assert-Fight ($config.CommandIntervalMs -eq 1200 -and $config.Profiles['forerver:3'].CombatKey -eq 'Ctrl+7' -and $config.Profiles['titan:3'].CombatKey -eq 'F6') 'Version 3 roundtrip / flavor isolation failed.'
    $original=[IO.File]::ReadAllText($path)
    foreach ($value in @('0','99','60001','1.5','no','99999999999999999999999')) {
        [IO.File]::WriteAllText($path,$original)
        $rejected=$false; try { $null=Save-AutoFightProfiles $path $profiles $value } catch { $rejected=$true }
        Assert-Fight ($rejected -and [IO.File]::ReadAllText($path) -ceq $original) 'Invalid common interval partially saved.'
        [IO.File]::WriteAllText($path,($original -replace '"CommandIntervalMs":\s*1200',('"CommandIntervalMs": "'+$value+'"')))
        $rejected=$false; try { $null=Read-AutoFightConfiguration $path } catch { $rejected=$true }
        Assert-Fight $rejected 'Invalid persisted interval accepted.'
    }
    $legacy=[pscustomobject]@{Version=2; Profiles=@($profiles.Values)} | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($path,$legacy)
    $config=Read-AutoFightConfiguration $path
    Assert-Fight ($config.CommandIntervalMs -eq 500 -and [IO.File]::ReadAllText($path) -ceq $legacy) 'Version 2 migration rewrote source / lost defaults.'
    $v1=@($profiles.Values | ForEach-Object { [pscustomobject]@{Flavor=$_.Flavor; ClassId=$_.ClassId; AttackKey='Alt+8'; SkinKey=$_.SkinKey; AttackIntervalMs=700; InteractionHoldMs=$_.InteractionHoldMs; SkinEnabled=$_.SkinEnabled} })
    [IO.File]::WriteAllText($path,([pscustomobject]@{Version=1; Profiles=$v1} | ConvertTo-Json -Depth 5))
    $config=Read-AutoFightConfiguration $path
    Assert-Fight ($config.Profiles['titan:1'].OpeningKey -eq 'Alt+8' -and $config.Profiles['titan:1'].CombatIntervalMs -eq 700 -and $config.CommandIntervalMs -eq 500) 'Version 1 migration failed.'
    $null=Save-AutoFightProfiles $path $profiles 900
    $original=[IO.File]::ReadAllText($path)
    $locked=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try { $rejected=$false; try { $null=Save-AutoFightProfiles $path $profiles 1000 } catch {$rejected=$true}; Assert-Fight $rejected 'Locked save succeeded.' }
    finally { $locked.Dispose() }
    Assert-Fight ([IO.File]::ReadAllText($path) -ceq $original) 'Locked save corrupted JSON.'
    $gate=New-AutoFightCommandGate 1000
    Assert-Fight (Test-AutoFightCommandReady $gate 0) 'Initial command blocked.'
    Complete-AutoFightCommand $gate 0 $true
    $packet=[pscustomobject]@{ClassId=1; Flavor='titan'; Busy=$false; Combat=$false; Action='opening'; Recovery='none'}
    $session=New-AutoFightSession 0 1; $p=$profiles['titan:1']
    foreach($state in @('opening','combat','recover','emergency','move-forward','move-backward','move-left','move-right','loot','skin')) {
        $packet.Action=$state; $packet.Recovery='none'
        $null=Update-AutoFightState $session $packet 999
        Assert-Fight ((Get-AutoFightAction $session $packet $p 999) -eq $state -and -not (Test-AutoFightCommandReady $gate 999)) 'State transition must not bypass common gate.'
    }
    Assert-Fight (Test-AutoFightCommandReady $gate 1000) 'Exact interval boundary blocked.'
    Complete-AutoFightCommand $gate 1000 $false
    Assert-Fight ($gate.LastSentAt -eq 0 -and (Test-AutoFightCommandReady $gate 1000)) 'Failed input advanced common timer.'
    Complete-AutoFightCommand $gate 1000 $true
    $gate.IntervalMs=2000
    Assert-Fight (-not (Test-AutoFightCommandReady $gate 2999) -and (Test-AutoFightCommandReady $gate 3000)) 'Interval edit reset successful send time.'
    $packet.Action='combat'; $null=Update-AutoFightState $session $packet 3000
    Complete-AutoFightAction $session $p 'combat' 3000
    Assert-Fight ((Get-AutoFightAction $session $packet $p 3499) -eq 'wait') 'Existing longer profile cooldown ignored.'
    Write-Output 'PASS: combat common interval boundaries/all states, failed sends, edits, profile cooldown, JSON v1/v2/v3 migration/isolation/invalid/atomic failure. No native input.'
} finally { if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) } }
