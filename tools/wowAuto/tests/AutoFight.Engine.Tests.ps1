$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot '..\autoFight.Engine.ps1')
function Assert-Fight($Condition,[string]$Label) { if (-not $Condition) { throw $Label } }
$path=Join-Path ([IO.Path]::GetTempPath()) ('autoFight-'+[Guid]::NewGuid()+'.json')
try {
    $config=Read-AutoFightConfiguration $path
    Assert-Fight ($config.Profiles.Count -eq 19 -and $config.CommandIntervalMs -eq 500 -and $config.Common.TargetKey -eq 'Tab') 'Defaults incomplete.'
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
        $legacyProfile.PSObject.Properties.Remove('TargetKey')
        $legacyProfile.PSObject.Properties.Remove('TargetIntervalMs')
        foreach ($field in @('BuffKey','BuffIntervalSeconds','BuffCount')) {$legacyProfile.PSObject.Properties.Remove($field)}
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
    $reserved=Copy-AutoFightProfiles $roundtrip.Profiles
    $reserved['titan:1'].OpeningKey='Tab'
    $rejected=$false;try {$null=Save-AutoFightProfiles $path $reserved 700} catch {$rejected=$true}
    Assert-Fight ($rejected -and [IO.File]::ReadAllText($path) -ceq $original) 'Target override key accepted as opener.'
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
    $oldDocument.Common.PSObject.Properties.Remove('TargetKey')
    $oldDocument.Profiles=@(foreach ($flavor in @('titan','forerver')) {foreach ($id in 1..13) {
        $profile=New-AutoFightProfile $flavor $id
        foreach ($field in @('BuffKey','BuffIntervalSeconds','BuffCount')) {$profile.PSObject.Properties.Remove($field)}
        $profile
    }})
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
    $oldJson=Get-Content -Raw $path | ConvertFrom-Json
    $oldJson.Version=5; $oldJson.Common.PSObject.Properties.Remove('TargetKey')
    foreach ($profile in $oldJson.Profiles) {foreach ($field in @('BuffKey','BuffIntervalSeconds','BuffCount')) {$profile.PSObject.Properties.Remove($field)}}
    $v5=$oldJson | ConvertTo-Json -Depth 5; [IO.File]::WriteAllText($path,$v5)
    $targetConfig=Read-AutoFightConfiguration $path
    Assert-Fight ($targetConfig.Common.TargetKey -eq 'Tab' -and [IO.File]::ReadAllText($path) -ceq $v5) 'V5 target migration rewrote preferences.'
    $targetConfig.Common.TargetKey='Ctrl+Tab'
    $null=Save-AutoFightProfiles $path $targetConfig.Profiles 700 $targetConfig.Common
    $targetConfig=Read-AutoFightConfiguration $path
    Assert-Fight ($targetConfig.Common.TargetKey -eq 'Ctrl+Tab' -and (Get-Content -Raw $path | ConvertFrom-Json).Version -eq 7) 'Target key roundtrip failed.'
    foreach ($profile in $targetConfig.Profiles.Values) {
        Assert-Fight ((Get-AutoFightEffectiveProfile $profile $targetConfig.Common).TargetKey -eq 'Ctrl+Tab') 'Target key not shared by all servers/classes.'
    }
    $original=[IO.File]::ReadAllText($path)
    foreach ($key in @('Space','Separator','W','F5','Ctrl+Ctrl+Tab','invalid')) {
        $targetConfig.Common.TargetKey=$key
        $rejected=$false;try {$null=Save-AutoFightProfiles $path $targetConfig.Profiles 700 $targetConfig.Common} catch {$rejected=$true}
        Assert-Fight ($rejected -and [IO.File]::ReadAllText($path) -ceq $original) 'Invalid/conflicting target key partially saved.'
    }
    $targetConfig.Common.TargetKey='F10'
    $null=Save-AutoFightProfiles $path $targetConfig.Profiles 700 $targetConfig.Common
    Assert-Fight ((Read-AutoFightConfiguration $path).Common.TargetKey -eq 'F10') 'Custom F10 target key rejected.'
    $original=[IO.File]::ReadAllText($path)
    $badDocument=$original | ConvertFrom-Json
    $badDocument.Common.PSObject.Properties.Remove('TargetKey')
    [IO.File]::WriteAllText($path,($badDocument | ConvertTo-Json -Depth 5))
    $rejected=$false;try {$null=Read-AutoFightConfiguration $path} catch {$rejected=$true}
    Assert-Fight $rejected 'V6 missing target key accepted.'
    [IO.File]::WriteAllText($path,$original)
    $targetConfig.Profiles['forerver:11'].EmergencyKey='F10'
    $rejected=$false;try {$null=Save-AutoFightProfiles $path $targetConfig.Profiles 700 $targetConfig.Common} catch {$rejected=$true}
    Assert-Fight ($rejected -and [IO.File]::ReadAllText($path) -ceq $original) 'Other server/class target conflict accepted.'
    $gate=New-AutoFightCommandGate 1000
    Assert-Fight (Test-AutoFightCommandReady $gate 0) 'Initial command blocked.'
    Complete-AutoFightCommand $gate 0 $true
    $packet=[pscustomobject]@{ClassId=1; Flavor='titan'; Busy=$false; Combat=$false; Action='opening'; Recovery='none'; EncounterId=1}
    $session=New-AutoFightSession 0 1; $p=Get-AutoFightEffectiveProfile $profiles['titan:1'] (New-AutoFightCommon)
    foreach($state in @('target','opening','combat','recover','emergency','move-forward','move-backward','move-left','move-right','loot','skin')) {
        $packet.Action=if ($state.StartsWith('move-') -or $state -in @('recover','emergency')) {'idle'} else {$state}
        $packet.Recovery=if ($state -in @('recover','emergency')) {$state} else {'none'}
        $packet.Combat=$state -in @('combat','emergency')
        $session.MovementRequest=if ($state.StartsWith('move-')) {$state.Substring(5)} else {''}
        $null=Update-AutoFightState $session $packet 999
        if ($state -eq 'skin') {$session.LootEncounterId=$packet.EncounterId}
        Assert-Fight ((Get-AutoFightAction $session $packet $p 999) -eq $state -and -not (Test-AutoFightCommandReady $gate 999)) 'State transition must not bypass common gate.'
    }
    $corpse=New-AutoFightSession 0 1
    $corpsePacket=[pscustomobject]@{ClassId=1;Flavor='titan';Busy=$false;Combat=$false;Action='skin';Recovery='none';EncounterId=11}
    $null=Update-AutoFightState $corpse $corpsePacket 0
    Assert-Fight ((Get-AutoFightAction $corpse $corpsePacket $p 0) -eq 'wait') 'Skinning began before this corpse was looted.'
    $corpsePacket.Action='loot';$null=Update-AutoFightState $corpse $corpsePacket 100
    Assert-Fight ((Get-AutoFightAction $corpse $corpsePacket $p 100) -eq 'loot') 'Lootable corpse was skipped.'
    Complete-AutoFightAction $corpse $p 'loot' 100
    $corpsePacket.Action='skin';$null=Update-AutoFightState $corpse $corpsePacket 200
    Assert-Fight ((Get-AutoFightAction $corpse $corpsePacket $p 200) -eq 'skin') 'Looted skinnable corpse did not get one attempt.'
    Complete-AutoFightAction $corpse $p 'skin' 200
    Assert-Fight ((Get-AutoFightAction $corpse $corpsePacket $p 10000) -eq 'wait') 'Same corpse was skinned twice after cooldown.'
    $corpsePacket.Action='idle';$null=Update-AutoFightState $corpse $corpsePacket 10100
    $corpsePacket.Action='skin';$null=Update-AutoFightState $corpse $corpsePacket 10200
    Assert-Fight ((Get-AutoFightAction $corpse $corpsePacket $p 10200) -eq 'wait') 'Same corpse was skinned twice after temporary disappearance.'
    $corpsePacket.EncounterId=12;$corpsePacket.Action='loot';$null=Update-AutoFightState $corpse $corpsePacket 10300
    Complete-AutoFightAction $corpse $p 'loot' 10300
    $corpsePacket.Action='skin';$null=Update-AutoFightState $corpse $corpsePacket 10400
    Assert-Fight ((Get-AutoFightAction $corpse $corpsePacket $p 10400) -eq 'skin') 'New corpse inherited previous skin attempt.'
    Assert-Fight ((Get-AutoFightHoldDuration $p 'skin') -eq 2000 -and
        (Get-AutoFightHoldDuration $p 'loot') -eq $p.InteractionHoldMs -and
        (Get-AutoFightHoldDuration $p 'move-forward') -eq $p.MovementHoldMs) 'Skin duration changed loot or movement settings.'
    $skinHold=[pscustomobject]@{State='skin';Movement=$false;Until=12400L}
    $corpsePacket.Action='idle'
    Assert-Fight (-not (Test-AutoFightHoldFinished $skinHold $corpsePacket 12399) -and
        (Test-AutoFightHoldFinished $skinHold $corpsePacket 12400)) 'Skin hold did not last exactly two seconds after action changed.'
    $corpsePacket.Recovery='recover'
    Assert-Fight (-not (Test-AutoFightHoldFinished $skinHold $corpsePacket 11000)) 'Ordinary recovery shortened the two-second skin hold.'
    $corpsePacket.Recovery='none'
    $corpsePacket.Combat=$true
    Assert-Fight (Test-AutoFightHoldFinished $skinHold $corpsePacket 11000) 'Combat failed to interrupt skin hold.'
    $corpsePacket.Combat=$false
    Assert-Fight (Test-AutoFightCommandReady $gate 1000) 'Exact interval boundary blocked.'
    Complete-AutoFightCommand $gate 1000 $false
    Assert-Fight ($gate.LastSentAt -eq 0 -and (Test-AutoFightCommandReady $gate 1000)) 'Failed input advanced common timer.'
    Complete-AutoFightCommand $gate 1000 $true
    $gate.IntervalMs=2000
    Assert-Fight (-not (Test-AutoFightCommandReady $gate 2999) -and (Test-AutoFightCommandReady $gate 3000)) 'Interval edit reset successful send time.'
    $packet.Action='combat'; $null=Update-AutoFightState $session $packet 3000
    Complete-AutoFightAction $session $p 'combat' 3000
    Assert-Fight ((Get-AutoFightAction $session $packet $p 3499) -eq 'wait') 'Existing longer profile cooldown ignored.'
    Write-Output 'PASS: combat common interval boundaries/all states, one skin attempt after loot per corpse, failed sends, edits, cooldown, JSON v1-v7 migration/custom common settings/conflict/isolation/invalid/atomic failure; default Tab and shared configurable target key. No native input.'
} finally { if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) } }
