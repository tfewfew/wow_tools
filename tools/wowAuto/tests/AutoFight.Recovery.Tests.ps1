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
    Assert-Recovery ($effective.RecoveryKey -eq 'Ctrl+F8' -and -not $effective.PSObject.Properties['EmergencyKey']) 'Recovery key is not the sole class recovery binding.'
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
    Assert-Recovery (-not $session.RecoverySent -and (Get-AutoFightAction $session $low $effective 2) -eq 'recover') 'An unsent recovery was consumed.'
    Complete-AutoFightAction $session $effective 'recover' 3
    Assert-Recovery ($session.RecoverySent -and (Get-AutoFightAction $session $low $effective 4) -eq 'wait') 'Successful recovery repeated while health remained low.'
    Assert-Recovery ((Get-AutoFightAction $session $unknown $effective 5) -eq 'wait' -and $session.RecoverySent) 'Unknown health reset recovery or sent input.'
    Assert-Recovery ((Get-AutoFightAction $session $normal $effective 6) -eq 'wait' -and -not $session.RecoverySent) 'Recovered health did not reset the one-shot latch.'
    Assert-Recovery ((Get-AutoFightAction $session $low $effective 7) -eq 'recover') 'A new low-health episode did not trigger recovery.'
    $low.Action='waiting';$low.Combat=$true
    $combatSession=New-AutoFightSession 0 1
    Assert-Recovery ((Get-AutoFightAction $combatSession $low $effective 0) -eq 'recover') 'Combat waiting suppressed unified recovery.'
    $low.Busy=$true
    Assert-Recovery ((Get-AutoFightAction $combatSession $low $effective 1) -eq 'wait' -and -not $combatSession.RecoverySent) 'Busy combat sent or consumed recovery.'
    $low.Busy=$false
    Assert-Recovery ((Get-AutoFightAction $combatSession $low $effective 2) -eq 'recover') 'Recovery did not resume after busy combat.'
    $low.Action='recover'
    Assert-Recovery ((Get-AutoFightAction $combatSession $low $effective 3) -eq 'identity-changed') 'Recovery was accepted as a main state.'
}
Write-Output 'PASS: V8 auxiliary health hint, sole class recovery key, one successful press per low-health episode, unknown/busy deferral and combat priority. No game input.'
