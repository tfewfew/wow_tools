$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path (Join-Path $PSScriptRoot '..\autoFight.Native.cs') -ReferencedAssemblies System.Drawing
. (Join-Path $PSScriptRoot '..\autoFight.Engine.ps1')
function Assert-Recovery($Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
foreach ($flavor in @('titan','forerver')) {
    $profile=New-AutoFightProfile $flavor 1
    $profile.RecoveryKey='Ctrl+F8';$profile.EmergencyKey='Ctrl+F9'
    $effective=Get-AutoFightEffectiveProfile $profile (New-AutoFightCommon)
    Assert-Recovery ($effective.RecoveryKey -eq 'Ctrl+F8' -and $effective.EmergencyKey -eq 'Ctrl+F9') 'Deferred recovery settings were removed.'
    $identity=if($flavor -eq 'titan'){0}else{13}
    $color=[uint32](25 -bor ((4*$identity) -shl 8))
    $packet=[WowAutoFight.Native]::Decode(([uint32[]]@($color)),$flavor)
    $session=New-AutoFightSession 0 1
    Assert-Recovery ($packet.Action -eq 'idle' -and -not $packet.PSObject.Properties['Recovery'] -and
        (Get-AutoFightAction $session $packet $effective 0) -eq 'wait') 'Recovery hint leaked into the main action channel.'
    Assert-Recovery (-not $script:autoFightStates.Contains('recover') -and -not $script:autoFightStates.Contains('emergency') -and
        -not $session.PSObject.Properties['RecoverySent']) 'Script still maintains automatic recovery states.'
}
Write-Output 'PASS: recovery key settings remain available, while V7 main actions and script state exclude recovery. Auxiliary hint is tested in Lua.'