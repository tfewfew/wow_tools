$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot '..\autoFight.Engine.ps1')
function Assert-Recovery($Condition,[string]$Label) {if (-not $Condition) {throw $Label}}
foreach ($flavor in @('titan','forerver')) {
    $p=Get-AutoFightEffectiveProfile (New-AutoFightProfile $flavor 1) (New-AutoFightCommon)
    foreach ($recovery in @('recover','emergency')) {
        $packet=[pscustomobject]@{Action=$recovery;Recovery=$recovery;ClassId=1;Flavor=$flavor;Combat=($recovery -eq 'emergency');Busy=$true;EncounterId=1}
        $session=New-AutoFightSession 0 1
        $null=Update-AutoFightState $session $packet 0
        $action=Get-AutoFightAction $session $packet $p 0
        Assert-Recovery ($action -eq $(if ($recovery -eq 'emergency') {'emergency'} else {'wait'})) 'Busy recovery priority wrong.'
        $packet.Busy=$false
        $null=Update-AutoFightState $session $packet 10
        Assert-Recovery ((Get-AutoFightAction $session $packet $p 10) -eq $recovery) 'Pending recovery lost while busy.'
        Assert-Recovery ((Get-AutoFightAction $session $packet $p 20) -eq $recovery -and -not $session.RecoverySent) 'Failed input consumed recovery.'
        Complete-AutoFightAction $session $p $recovery 20
        for ($i=1;$i -le 100;$i++) {
            $packet.EncounterId=$i%32
            $packet.Action=if ($i%2) {'waiting'} else {$recovery}
            $packet.Busy=($i%3 -eq 0)
            $null=Update-AutoFightState $session $packet ($i*2000)
            Assert-Recovery ((Get-AutoFightAction $session $packet $p ($i*2000)) -eq 'wait') 'Same recovery repeated after main state / encounter / busy changed.'
        }
        $packet.Recovery='none';$packet.Busy=$false;$packet.Combat=$false;$packet.Action='idle'
        $null=Update-AutoFightState $session $packet 210000
        Assert-Recovery (-not $session.RecoverySent -and $session.RecoveryState -eq 'none') 'Exiting recovery did not reset latch.'
        $packet.Recovery=$recovery;$packet.Combat=($recovery -eq 'emergency');$packet.Action=$recovery
        $null=Update-AutoFightState $session $packet 211000
        Assert-Recovery ((Get-AutoFightAction $session $packet $p 211000) -eq $recovery) 'Second recovery entry not eligible.'
    }
}
Write-Output 'PASS: ordinary/emergency recovery once per entry, reset on exit, failed-send retry, busy handling, encounter/main changes, and both clients. No native input.'
