$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot '..\autoFight.Engine.ps1')
function Assert-Fight($Condition,[string]$Label) { if (-not $Condition) { throw $Label } }
$path=Join-Path ([IO.Path]::GetTempPath()) ('autoFight-'+[Guid]::NewGuid()+'.json')
try {
    $config=Read-AutoFightConfiguration $path
    Assert-Fight ($config.Profiles.Count -eq 19 -and $config.CommandIntervalMs -eq 500) 'Defaults incomplete.'
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
    $oldProfiles=@($profiles.Values | ForEach-Object {
        $legacyProfile=Get-AutoFightEffectiveProfile $_ (New-AutoFightCommon)
        $legacyProfile.PSObject.Properties.Remove('JumpKey')
        $legacyProfile.PSObject.Properties.Remove('JumpIntervalSeconds')
        $legacyProfile | Add-Member NoteProperty OpeningIntervalMs 2000
        $legacyProfile | Add-Member NoteProperty EmergencyIntervalMs 1500
        $legacyProfile
    })
    $oldProfiles[0].MoveLeftKey='A';$oldProfiles[0].MoveRightKey='D';$oldProfiles[0].SkinKey='='
    $legacy=[pscustomobject]@{Version=2; Profiles=$oldProfiles} | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($path,$legacy)
    $config=Read-AutoFightConfiguration $path
    Assert-Fight ($config.CommandIntervalMs -eq 500 -and [IO.File]::ReadAllText($path) -ceq $legacy) 'Version 2 migration rewrote source / lost defaults.'
    Assert-Fight ($config.Common.MoveLeftKey -eq 'A' -and $config.Common.MoveRightKey -eq 'D' -and $config.Common.SkinKey -eq '=') 'Customized legacy general keys were lost.'
    $oldProfiles[1].MoveLeftKey='Z'
    $conflict=[pscustomobject]@{Version=3;CommandIntervalMs=700;Profiles=$oldProfiles}|ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($path,$conflict)
    $rejected=$false;try {$null=Read-AutoFightConfiguration $path} catch {$rejected=$true}
    Assert-Fight ($rejected -and [IO.File]::ReadAllText($path) -ceq $conflict) 'Ambiguous legacy common settings silently overwritten.'
    $oldProfiles[1].MoveLeftKey='Q'
    [IO.File]::WriteAllText($path,([pscustomobject]@{Version=3;CommandIntervalMs=700;Profiles=$oldProfiles}|ConvertTo-Json -Depth 5))
    $config=Read-AutoFightConfiguration $path
    $null=Save-AutoFightProfiles $path $config.Profiles $config.CommandIntervalMs $config.Common
    $roundtrip=Read-AutoFightConfiguration $path
    Assert-Fight ($roundtrip.Common.MoveLeftKey -eq 'A' -and $roundtrip.Common.SkinKey -eq '=' -and $roundtrip.CommandIntervalMs -eq 700 -and
        $null -eq $roundtrip.Profiles['titan:1'].PSObject.Properties['MoveLeftKey']) 'V3 -> V4 migration lost custom common values or retained class movement.'
    $original=[IO.File]::ReadAllText($path)
    $badCommon=Copy-AutoFightCommon $roundtrip.Common;$badCommon.MoveRightKey=$badCommon.MoveLeftKey
    $rejected=$false;try {$null=Save-AutoFightProfiles $path $roundtrip.Profiles 700 $badCommon} catch {$rejected=$true}
    Assert-Fight ($rejected -and [IO.File]::ReadAllText($path) -ceq $original) 'Invalid common draft partially saved.'
    $v1=@($profiles.Values | ForEach-Object { [pscustomobject]@{Flavor=$_.Flavor; ClassId=$_.ClassId; AttackKey='Alt+8'; SkinKey='F7'; AttackIntervalMs=700; InteractionHoldMs=3500; SkinEnabled=$true} })
    [IO.File]::WriteAllText($path,([pscustomobject]@{Version=1; Profiles=$v1} | ConvertTo-Json -Depth 5))
    $config=Read-AutoFightConfiguration $path
    Assert-Fight ($config.Profiles['titan:1'].OpeningKey -eq 'Alt+8' -and $config.Profiles['titan:1'].CombatIntervalMs -eq 700 -and $config.CommandIntervalMs -eq 500) 'Version 1 migration failed.'
    $null=Save-AutoFightProfiles $path $profiles 900
    $original=[IO.File]::ReadAllText($path)
    $locked=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try { $rejected=$false; try { $null=Save-AutoFightProfiles $path $profiles 1000 } catch {$rejected=$true}; Assert-Fight $rejected 'Locked save succeeded.' }
    finally { $locked.Dispose() }
    Assert-Fight ([IO.File]::ReadAllText($path) -ceq $original) 'Locked save corrupted JSON.'
    $oldDocument=Get-Content -Raw (Join-Path $PSScriptRoot '..\autoFight.config.json') | ConvertFrom-Json
    # Construct a real V4 document with all 26 old classes; loading drops unavailable profiles only.
    $oldDocument.Version=4
    $oldDocument.Common.PSObject.Properties.Remove('JumpIntervalSeconds')
    $oldDocument.Profiles=@(foreach ($flavor in @('titan','forerver')) {foreach ($id in 1..13) {New-AutoFightProfile $flavor $id}})
    $oldDocument.Profiles[4].RecoveryKey='Alt+9'
    $legacyJson=$oldDocument | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($path,$legacyJson)
    $migrated=Read-AutoFightConfiguration $path
    Assert-Fight ($migrated.Profiles.Count -eq 19 -and -not $migrated.Profiles.ContainsKey('forerver:6') -and
        $migrated.Profiles['titan:5'].RecoveryKey -eq 'Alt+9' -and $migrated.Common.JumpIntervalSeconds -eq 0 -and
        [IO.File]::ReadAllText($path) -ceq $legacyJson) 'V4 read-only class/jump migration lost existing preferences.'
    $migrated.Common.JumpIntervalSeconds=60
    $null=Save-AutoFightProfiles $path $migrated.Profiles 700 $migrated.Common
    Assert-Fight ((Read-AutoFightConfiguration $path).Common.JumpIntervalSeconds -eq 60) 'Jump roundtrip failed.'
    $original=[IO.File]::ReadAllText($path)
    foreach ($value in @(-1,3601,'1.5')) {
        $migrated.Common.JumpIntervalSeconds=$value
        $rejected=$false;try {$null=Save-AutoFightProfiles $path $migrated.Profiles 700 $migrated.Common} catch {$rejected=$true}
        Assert-Fight ($rejected -and [IO.File]::ReadAllText($path) -ceq $original) 'Invalid jump partially saved.'
    }
    $gate=New-AutoFightCommandGate 1000
    Assert-Fight (Test-AutoFightCommandReady $gate 0) 'Initial command blocked.'
    Complete-AutoFightCommand $gate 0 $true
    $packet=[pscustomobject]@{ClassId=1; Flavor='titan'; Busy=$false; Combat=$false; Action='opening'; Recovery='none'; EncounterId=1}
    $session=New-AutoFightSession 0 1; $p=Get-AutoFightEffectiveProfile $profiles['titan:1'] (New-AutoFightCommon)
    foreach($state in @('opening','combat','recover','emergency','move-forward','move-backward','move-left','move-right','loot','skin')) {
        $packet.Action=if ($state.StartsWith('move-') -or $state -in @('recover','emergency')) {'idle'} else {$state}
        $packet.Recovery=if ($state -in @('recover','emergency')) {$state} else {'none'}
        $session.MovementRequest=if ($state.StartsWith('move-')) {$state.Substring(5)} else {''}
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
    Write-Output 'PASS: combat common interval boundaries/all states, failed sends, edits, cooldown, JSON v1/v2/v3/v4/v5 migration/custom common settings/conflict/isolation/invalid/atomic failure. No native input.'
} finally { if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) } }
