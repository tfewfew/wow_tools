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
    Assert-Fight (($config.Profiles['forerver:3'].RecoveryCooldownSeconds -eq 30) -and
        -not $config.Profiles['forerver:3'].PSObject.Properties['CombatIntervalMs']) 'V9 defaults retained the old combat interval.'
    $custom=Copy-AutoFightProfiles $config.Profiles
    $custom['forerver:3'].RecoveryCooldownSeconds=45
    $null=Save-AutoFightProfiles $path $custom 1200 $config.Common
    $config=Read-AutoFightConfiguration $path
    Assert-Fight ($config.Profiles['forerver:3'].RecoveryCooldownSeconds -eq 45 -and
        $config.Profiles['titan:3'].RecoveryCooldownSeconds -eq 30 -and
        (Get-Content -Raw $path | ConvertFrom-Json).Version -eq 9) 'Recovery cooldown was not saved per class and client.'
    $validSource=[IO.File]::ReadAllText($path)
    foreach ($seconds in @(0,3601,'1.5')) {
        $invalid=Copy-AutoFightProfiles $config.Profiles
        $invalid['forerver:3'].RecoveryCooldownSeconds=$seconds
        $rejected=$false;try {$null=Save-AutoFightProfiles $path $invalid 1200 $config.Common} catch {$rejected=$true}
        Assert-Fight ($rejected -and [IO.File]::ReadAllText($path) -ceq $validSource) 'Invalid recovery cooldown partially saved.'
    }
    $original=[IO.File]::ReadAllText($path)
    $v7=$original | ConvertFrom-Json
    $v7.Version=7
    foreach ($profile in $v7.Profiles) {
        $profile.PSObject.Properties.Remove('RecoveryCooldownSeconds')
        $profile | Add-Member NoteProperty CombatIntervalMs 500
        $profile | Add-Member NoteProperty EmergencyKey 'F9'
    }
    $v7.Profiles | Where-Object {$_.Flavor -eq 'forerver' -and $_.ClassId -eq 3} | ForEach-Object {
        $_.RecoveryKey='Alt+9';$_.EmergencyKey='Alt+8'
    }
    $legacyV7=$v7 | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($path,$legacyV7)
    $readV7=Read-AutoFightConfiguration $path
    Assert-Fight ($readV7.Profiles['forerver:3'].RecoveryKey -eq 'Alt+9' -and
        $readV7.Profiles['forerver:3'].RecoveryCooldownSeconds -eq 30 -and
        -not $readV7.Profiles['forerver:3'].PSObject.Properties['EmergencyKey'] -and
        [IO.File]::ReadAllText($path) -ceq $legacyV7) 'V7 recovery migration changed the ordinary recovery key or rewrote source.'
    $v8=$original | ConvertFrom-Json
    $v8.Version=8
    foreach ($profile in $v8.Profiles) {
        $profile.PSObject.Properties.Remove('RecoveryCooldownSeconds')
        $profile | Add-Member NoteProperty CombatIntervalMs 500
    }
    $legacyV8=$v8 | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($path,$legacyV8)
    $readV8=Read-AutoFightConfiguration $path
    Assert-Fight ($readV8.Profiles['forerver:3'].RecoveryCooldownSeconds -eq 30 -and
        [IO.File]::ReadAllText($path) -ceq $legacyV8) 'V8 recovery cooldown migration rewrote source.'
    [IO.File]::WriteAllText($path,$original)
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
        $legacyProfile.PSObject.Properties.Remove('RecoveryCooldownSeconds')
        $legacyProfile | Add-Member NoteProperty CombatIntervalMs 500
        $legacyProfile.PSObject.Properties.Remove('JumpIntervalSeconds')
        $legacyProfile.PSObject.Properties.Remove('TargetKey')
        $legacyProfile.PSObject.Properties.Remove('TargetIntervalMs')
        foreach ($field in @('BuffKey','BuffIntervalSeconds','BuffCount')) {$legacyProfile.PSObject.Properties.Remove($field)}
        $legacyProfile | Add-Member NoteProperty EmergencyKey 'F9'
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
    Assert-Fight ($config.Profiles['titan:1'].OpeningKey -eq 'Alt+8' -and $config.Profiles['titan:1'].CombatKey -eq 'Alt+8' -and
        $config.Profiles['titan:1'].RecoveryCooldownSeconds -eq 30 -and
        -not $config.Profiles['titan:1'].PSObject.Properties['CombatIntervalMs'] -and $config.CommandIntervalMs -eq 500) 'Version 1 migration failed.'
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
        $profile.PSObject.Properties.Remove('RecoveryCooldownSeconds')
        $profile | Add-Member NoteProperty CombatIntervalMs 500
        $profile | Add-Member NoteProperty EmergencyKey 'F9'
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
    foreach ($profile in $oldJson.Profiles) {
        $profile.PSObject.Properties.Remove('RecoveryCooldownSeconds')
        $profile | Add-Member NoteProperty CombatIntervalMs 500
        foreach ($field in @('BuffKey','BuffIntervalSeconds','BuffCount')) {$profile.PSObject.Properties.Remove($field)}
        $profile | Add-Member NoteProperty EmergencyKey 'F9'
    }
    $v5=$oldJson | ConvertTo-Json -Depth 5; [IO.File]::WriteAllText($path,$v5)
    $targetConfig=Read-AutoFightConfiguration $path
    Assert-Fight ($targetConfig.Common.TargetKey -eq 'Tab' -and [IO.File]::ReadAllText($path) -ceq $v5) 'V5 target migration rewrote preferences.'
    $targetConfig.Common.TargetKey='Ctrl+Tab'
    $null=Save-AutoFightProfiles $path $targetConfig.Profiles 700 $targetConfig.Common
    $targetConfig=Read-AutoFightConfiguration $path
    Assert-Fight ($targetConfig.Common.TargetKey -eq 'Ctrl+Tab' -and (Get-Content -Raw $path | ConvertFrom-Json).Version -eq 9) 'Target key roundtrip failed.'
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
    $targetConfig.Profiles['forerver:11'].RecoveryKey='F10'
    $rejected=$false;try {$null=Save-AutoFightProfiles $path $targetConfig.Profiles 700 $targetConfig.Common} catch {$rejected=$true}
    Assert-Fight ($rejected -and [IO.File]::ReadAllText($path) -ceq $original) 'Other server/class target conflict accepted.'
    $gate=New-AutoFightCommandGate 1000
    Assert-Fight (Test-AutoFightCommandReady $gate 0) 'Initial command blocked.'
    Complete-AutoFightCommand $gate 0 $true
    $session=New-AutoFightSession 0 1
    $p=Get-AutoFightEffectiveProfile $profiles['titan:1'] (New-AutoFightCommon)
    $packet=[pscustomobject]@{ClassId=1;Flavor='titan';Busy=$false;Combat=$false;Action='opening';Recovery='none';EncounterId=1}
    foreach($action in @('opening','interact','combat')) {
        $packet.Action=$action;$packet.Combat=$action -eq 'combat'
        Assert-Fight ((Get-AutoFightAction $session $packet $p 999) -eq $action -and
            -not (Test-AutoFightCommandReady $gate 999)) 'Plugin action bypassed the common input gate.'
    }
    Complete-AutoFightAction $session $p 'opening' 1000
    $packet.Action='opening';$packet.Combat=$false
    Assert-Fight ((Get-AutoFightAction $session $packet $p 1001) -eq 'opening' -and
        -not $session.PSObject.Properties['NextByAction']) 'Engine retained an independent opening cooldown.'
    $packet.Action='interact'
    Assert-Fight ((Get-AutoFightAction $session $packet $p 1001) -eq 'interact') 'Script retained a corpse history gate.'
    Complete-AutoFightAction $session $p 'interact' 1001
    Assert-Fight ((Get-AutoFightAction $session $packet $p 1002) -eq 'interact') 'Engine retained an independent interaction interval.'
    Assert-Fight ((Get-AutoFightHoldDuration $p 'interact') -eq $p.InteractionHoldMs) 'Interaction duration ignored the common setting.'
    $interactHold=[pscustomobject]@{State='interact';Movement=$false;Until=(1001L+$p.InteractionHoldMs)}
    $packet.Action='idle'
    Assert-Fight (-not (Test-AutoFightHoldFinished $interactHold $packet ($interactHold.Until-1)) -and
        (Test-AutoFightHoldFinished $interactHold $packet $interactHold.Until)) 'Interaction hold ended before its configured duration.'
    $packet.Combat=$true
    Assert-Fight (Test-AutoFightHoldFinished $interactHold $packet 1500) 'Combat failed to interrupt interaction hold.'
    $packet.Combat=$false
    Assert-Fight (Test-AutoFightCommandReady $gate 1000) 'Exact interval boundary blocked.'
    Complete-AutoFightCommand $gate 1000 $false
    Assert-Fight ($gate.LastSentAt -eq 0 -and (Test-AutoFightCommandReady $gate 1000)) 'Failed input advanced common timer.'
    Complete-AutoFightCommand $gate 1000 $true
    $gate.IntervalMs=2000
    Assert-Fight (-not (Test-AutoFightCommandReady $gate 2999) -and (Test-AutoFightCommandReady $gate 3000)) 'Interval edit reset successful send time.'
    Assert-Fight (@($session.PSObject.Properties.Name | Where-Object {$_ -in @('State','Substate','OpeningSent','LootEncounterId')}).Count -eq 0) 'Script retains combat main-state fields.'
    Write-Output 'PASS: five-state direct actions, recovery cooldown, common command gate, JSON v1-v8 migration to v9 and atomic settings. No native input.'} finally { if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) } }
