$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path (Join-Path $PSScriptRoot '..\autoFight.Native.cs') -ReferencedAssemblies System.Drawing
. (Join-Path $PSScriptRoot '..\autoFight.Engine.ps1')
function Assert-Recovery($Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
function Pixel([int]$R,[int]$G,[int]$B) {return [uint32]($R -bor ($G -shl 8) -bor ($B -shl 16))}
foreach ($flavor in @('titan','forerver')) {
    $profile=New-AutoFightProfile $flavor 1
    $profile.RecoveryKey='Ctrl+F8'
    $effective=Get-AutoFightEffectiveProfile $profile (New-AutoFightCommon)
    Assert-Recovery ($effective.RecoveryKey -eq 'Ctrl+F8' -and $effective.RecoveryCooldownSeconds -eq 30 -and
        -not $effective.PSObject.Properties['EmergencyKey']) 'Recovery key/cooldown settings are incomplete.'
    $identity=if($flavor -eq 'titan'){0}else{13}
    $main=Pixel 27 (4*$identity) 0
    $normal=[WowAutoFight.Native]::Decode(([uint32[]]@($main,(Pixel 38 38 38))),$flavor)
    $low=[WowAutoFight.Native]::Decode(([uint32[]]@($main,(Pixel 0 102 255))),$flavor)
    $unknown=[WowAutoFight.Native]::Decode(([uint32[]]@($main,(Pixel 128 128 128))),$flavor)
    $session=New-AutoFightSession 0 1
    Assert-Recovery ($normal.Action -eq 'idle' -and $normal.Recovery -eq 'none' -and
        (Get-AutoFightAction $session $normal $effective 0) -eq 'wait') 'Normal health should not request recovery.'
    Assert-Recovery ($low.Action -eq 'idle' -and $low.Recovery -eq 'recover' -and
        (Get-AutoFightAction $session $low $effective 1) -eq 'recover') 'Low health did not request recovery.'
    Assert-Recovery ($session.RecoveryReadyAt -eq 0 -and (Get-AutoFightAction $session $low $effective 2) -eq 'recover') 'An unsent recovery was consumed.'
    Complete-AutoFightAction $session $effective 'recover' 3
    Assert-Recovery ($session.RecoveryReadyAt -eq 30003 -and (Get-AutoFightAction $session $low $effective 30002) -eq 'wait') 'Recovery repeated before cooldown expired.'
    Assert-Recovery ((Get-AutoFightAction $session $unknown $effective 5) -eq 'wait' -and $session.RecoveryReadyAt -eq 30003) 'Unknown health reset cooldown.'
    Assert-Recovery ((Get-AutoFightAction $session $normal $effective 6) -eq 'wait' -and $session.RecoveryReadyAt -eq 30003) 'Healthy hint reset cooldown.'
    Assert-Recovery ((Get-AutoFightAction $session $low $effective 30003) -eq 'recover') 'Still-low health did not retrigger at cooldown boundary.'
    $low.Action='waiting';$low.Combat=$true
    $combatSession=New-AutoFightSession 0 1
    Assert-Recovery ((Get-AutoFightAction $combatSession $low $effective 0) -eq 'recover') 'Combat waiting suppressed unified recovery.'
    $low.Busy=$true
    Assert-Recovery ((Get-AutoFightAction $combatSession $low $effective 1) -eq 'wait' -and $combatSession.RecoveryReadyAt -eq 0) 'Busy combat sent or consumed recovery.'
    $low.Busy=$false
    Assert-Recovery ((Get-AutoFightAction $combatSession $low $effective 2) -eq 'recover') 'Recovery did not resume after busy combat.'
    $combatSession.RecoveryReadyAt=30000
    $low.Action='combat'
    Assert-Recovery ((Get-AutoFightAction $combatSession $low $effective 1000) -eq 'combat') 'Recovery cooldown blocked main-color combat.'
    $unknown.Action='combat';$unknown.Combat=$true
    Assert-Recovery ((Get-AutoFightAction $combatSession $unknown $effective 1000) -eq 'combat') 'Unknown auxiliary blocked main color during recovery cooldown.'
    $low.Action='waiting'
    $low.Action='recover'
    Assert-Recovery ((Get-AutoFightAction $combatSession $low $effective 3) -eq 'identity-changed') 'Recovery was accepted as a main state.'
}
Write-Output 'PASS: V8 auxiliary health hint, per-class recovery cooldown and exact boundary, unsent/busy deferral, main-color progress during cooldown. No game input.'
