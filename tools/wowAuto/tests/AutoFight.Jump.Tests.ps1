$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot '..\autoFight.Engine.ps1')
function Assert-Jump($Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
foreach ($flavor in @('titan','forerver')) {
    $common=New-AutoFightCommon; $common.JumpIntervalSeconds=2
    $profile=Get-AutoFightEffectiveProfile (New-AutoFightProfile $flavor 1) $common
    $session=New-AutoFightSession 100 1
    Set-AutoFightJumpInterval $session 2 100
    $packet=[pscustomobject]@{ClassId=1;Flavor=$flavor;Action='combat';Recovery='none';Combat=$true;Busy=$false;EncounterId=1}
    $null=Update-AutoFightState $session $packet 100
    Complete-AutoFightAction $session $profile 'combat' 100
    Assert-Jump ((Get-AutoFightAction $session $packet $profile 2099) -eq 'combat') 'Jump fired before exact interval.'
    Assert-Jump ((Get-AutoFightAction $session $packet $profile 2100) -eq 'jump') 'Due jump starved by repeated combat.'
    $deadline=$session.NextActionAt; $entry=$session.EntryPending
    # Failed sends never call Complete; the pending jump remains eligible.
    Assert-Jump ((Get-AutoFightAction $session $packet $profile 2200) -eq 'jump' -and $session.NextJumpAt -eq 2100) 'Failed jump consumed deadline.'
    $packet.Busy=$true
    Assert-Jump ((Get-AutoFightAction $session $packet $profile 2300) -eq 'wait') 'Jump interrupted casting.'
    $packet.Busy=$false; $packet.Action='waiting'
    $null=Update-AutoFightState $session $packet 2400
    Assert-Jump ((Get-AutoFightAction $session $packet $profile 2400) -eq 'wait') 'Jump bypassed waiting.'
    $packet.Action='emergency'; $packet.Recovery='emergency'
    $null=Update-AutoFightState $session $packet 2500
    Assert-Jump ((Get-AutoFightAction $session $packet $profile 2500) -eq 'emergency') 'Jump displaced emergency recovery.'
    Complete-AutoFightAction $session $profile 'emergency' 2500
    Assert-Jump ((Get-AutoFightAction $session $packet $profile 3000) -eq 'wait') 'Jump interrupted latched recovery.'
    $packet.Action='combat'; $packet.Recovery='none'
    $null=Update-AutoFightState $session $packet 3100
    $deadline=$session.NextActionAt; $entry=$session.EntryPending
    Complete-AutoFightAction $session $profile 'jump' 3100
    Assert-Jump ($session.NextJumpAt -eq 5100 -and $session.NextActionAt -eq $deadline -and $session.EntryPending -eq $entry) 'Jump changed attack cooldown / entry latch.'
    Set-AutoFightJumpInterval $session 2 4000
    Assert-Jump ($session.NextJumpAt -eq 5100) 'Saving same interval postponed jump.'
    Set-AutoFightJumpInterval $session 5 4000
    Assert-Jump ($session.NextJumpAt -eq 9000) 'Changed interval did not restart timer.'
    Set-AutoFightJumpInterval $session 0 4100
    Assert-Jump ($session.NextJumpAt -eq [long]::MaxValue) 'Disabled jump still scheduled.'
    $other=New-AutoFightSession 1000 1
    Set-AutoFightJumpInterval $other 2 1000
    Assert-Jump ($other.NextJumpAt -eq 3000 -and $session.NextJumpAt -eq [long]::MaxValue) 'Process jump timers shared state.'
}
Write-Output 'PASS: both clients timed jump boundaries, combat fairness, failed-send retry, busy/wait/recovery deferral, immutable action latches, same/changed/disabled setting and independent process timers. No native input.'
