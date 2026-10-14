$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path (Join-Path $PSScriptRoot '..\autoFight.Native.cs') -ReferencedAssemblies System.Drawing
. (Join-Path $PSScriptRoot '..\autoFight.Engine.ps1')
function Assert-Distance($Condition,[string]$Label) {if (-not $Condition) {throw $Label}}
function Pixel([int]$R,[int]$G,[int]$B) {return [uint32]($R -bor ($G -shl 8) -bor ($B -shl 16))}
function Test-Packet([string]$Flavor,[int]$Class,[int]$Action,[int]$Recovery=0,[bool]$Combat=$false,[bool]$Busy=$false,[int]$Encounter=17) {
    $identity=($Class-1)+$(if ($Flavor -eq 'titan') {0} else {13})
    return [uint32[]]@((Pixel (16+8*($Action*4+$Recovery)) (2+4*($identity+26*[int]$Busy)) (2+4*($Encounter+32*[int]$Combat))))
}
foreach ($flavor in @('titan','forerver')) {
    foreach ($class in (Get-AutoFightClassIds $flavor)) {
        foreach ($repeat in 1..2) {
            foreach ($encounter in @(0,17,31)) {
                foreach ($entry in @(@(1,0,$false,$false),@(2,0,$false,$false),@(3,0,$true,$false),
                    @(4,0,$true,$false),@(5,0,$false,$false),@(6,0,$false,$false),
                    @(1,1,$false,$true),@(4,2,$true,$true),@(3,2,$true,$false))) {
                    $packet=[WowAutoFight.Native]::Decode((Test-Packet $flavor $class $entry[0] $entry[1] $entry[2] $entry[3] $encounter),$flavor)
                    $action=@('unknown','idle','opening','waiting','combat','loot','skin')[$entry[0]]
                    Assert-Distance ($packet -and $packet.Action -eq $action -and $packet.ClassId -eq $class -and
                        $packet.EncounterId -eq $encounter -and $packet.Busy -eq $entry[3] -and
                        $packet.Combat -eq $entry[2]) 'Main color metadata / action / encounter failed.'
                }
            }
        }
    }
    foreach ($entry in @(@(240,0,$false,'none'),@(248,1,$false,'recover'),@(8,2,$true,'emergency'),@(240,0,$true,'none'))) {
        $packet=[WowAutoFight.Native]::Decode(([uint32[]]@((Pixel $entry[0] $(if($flavor -eq 'titan'){2}else{54}) $(if($entry[2]){130}else{2})))),$flavor)
        Assert-Distance ($packet -and $packet.Action -eq 'target' -and $packet.Recovery -eq $entry[3]) 'Target color / recovery decoding failed.'
    }
    foreach ($class in 1..13 | Where-Object {$_ -notin (Get-AutoFightClassIds $flavor)}) {
        Assert-Distance ($null -eq [WowAutoFight.Native]::Decode((Test-Packet $flavor $class 1),$flavor)) 'Unavailable class accepted.'
    }
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode(([uint32[]]@((Pixel 48 48 148),(Pixel 8 8 8))),$flavor)) 'Old two-cell protocol accepted.'
    $packet=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 2),$flavor)
    $p=Get-AutoFightEffectiveProfile (New-AutoFightProfile $flavor 4) (New-AutoFightCommon)
    $s=New-AutoFightSession 0 4
    $null=Update-AutoFightState $s $packet 0
    Assert-Distance ((Get-AutoFightAction $s $packet $p 0) -eq 'opening') 'Detected monster did not open.'
    Complete-AutoFightAction $s $p 'opening' 0
    $null=Update-AutoFightState $s $packet 999
    Assert-Distance ($s.State -eq 'waiting' -and (Get-AutoFightAction $s $packet $p 999) -eq 'wait') 'Opening retried before one second.'
    $null=Update-AutoFightState $s $packet 1000
    Assert-Distance ($s.State -eq 'target' -and (Get-AutoFightAction $s $packet $p 1000) -eq 'target') 'Retry did not relock the target first.'
    Complete-AutoFightAction $s $p 'target' 1000
    $null=Update-AutoFightState $s $packet 1001
    Assert-Distance ((Get-AutoFightAction $s $packet $p 1001) -eq 'opening') 'Confirmed retry did not reopen.'
    Complete-AutoFightAction $s $p 'opening' 1001
    $null=Update-AutoFightState $s $packet 2000
    Assert-Distance ((Get-AutoFightAction $s $packet $p 2000) -eq 'wait') 'Second opener retried early.'
    $packet=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 3 2 $true),$flavor)
    $null=Update-AutoFightState $s $packet 3000
    Assert-Distance ((Get-AutoFightAction $s $packet $p 3000) -eq 'wait') 'Waiting emitted a key.'
    $packet=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 4 0 $true),$flavor)
    $null=Update-AutoFightState $s $packet 4000
    Assert-Distance ((Get-AutoFightAction $s $packet $p 4000) -eq 'combat') 'Approach did not attack.'
    Complete-AutoFightAction $s $p 'combat' 4000
    Assert-Distance ((Get-AutoFightAction $s $packet $p 4499) -eq 'wait') 'Combat interval ignored.'
    $packet=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 3 0 $true),$flavor)
    $null=Update-AutoFightState $s $packet 5000
    Assert-Distance ((Get-AutoFightAction $s $packet $p 5000) -eq 'wait') 'Retreat did not stop attacks.'
    $packet=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 2 0 $false $false 17),$flavor)
    $null=Update-AutoFightState $s $packet 6000
    Assert-Distance ((Get-AutoFightAction $s $packet $p 6000) -eq 'wait') 'Combat encounter reopened after combat ended.'
    $packet=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 2 0 $false $false 18),$flavor)
    $null=Update-AutoFightState $s $packet 7000
    Assert-Distance (-not $s.OpeningSent -and (Get-AutoFightAction $s $packet $p 7000) -eq 'opening') 'New monster did not reset opening guard.'
    Complete-AutoFightAction $s $p 'opening' 7000
    $packet=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 1 0 $false $false 19),$flavor)
    $null=Update-AutoFightState $s $packet 8000
    Assert-Distance ((Get-AutoFightAction $s $packet $p 8000) -eq 'wait' -and -not $s.OpeningNeedsTarget) 'No nearby target kept retrying.'
    $rangeSession=New-AutoFightSession 0 4
    $packet=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 2 0 $false $false 20),$flavor)
    $null=Update-AutoFightState $rangeSession $packet 0
    Complete-AutoFightAction $rangeSession $p 'opening' 0
    $packet=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 3 0 $false $false 20),$flavor)
    $null=Update-AutoFightState $rangeSession $packet 1000
    Assert-Distance ($rangeSession.OpeningNeedsTarget -and (Get-AutoFightAction $rangeSession $packet $p 1000) -eq 'wait') 'Out-of-range target retried an opener.'
    $packet=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 2 0 $false $false 20),$flavor)
    $null=Update-AutoFightState $rangeSession $packet 1500
    Assert-Distance ((Get-AutoFightAction $rangeSession $packet $p 1500) -eq 'target') 'Returned target skipped relock.'
    $legacySession=New-AutoFightSession 0 4
    $packet=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 4 0 $false $false 21),$flavor)
    $null=Update-AutoFightState $legacySession $packet 0
    Assert-Distance ($legacySession.State -eq 'opening' -and (Get-AutoFightAction $legacySession $packet $p 0) -eq 'opening') 'Precombat cast result was treated as combat.'
    $cells=@(Test-Packet $flavor 4 2); $cells[0]=Pixel 255 255 255
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode($cells,$flavor)) 'Illegal main color accepted.'
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode((Test-Packet $flavor 4 0),$flavor)) 'Unknown data accepted.'
    $packet=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 0 2 $true),$flavor)
    Assert-Distance ($packet -and $packet.Recovery -eq 'emergency') 'Readable recovery lost solely because range was unknown.'
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode((Test-Packet $flavor 4 4 2 $false),$flavor)) 'Invalid recovery / combat combination accepted.'
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode((Test-Packet $flavor 4 2),$(if ($flavor -eq 'titan') {'forerver'} else {'titan'}))) 'Cross-flavor packet accepted.'
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode(([uint32[]]@(0,0,0,0,0,0,0,0,0)),$flavor)) 'Old protocol accepted.'
}
foreach ($size in @(@(1280,720),@(1920,1080),@(2560,1440),@(1279,719),@(3840,2160))) {
    $points=[WowAutoFight.Native]::SampleOffsets($size[0],$size[1])
    Assert-Distance ($points.Length -eq 2 -and $points[0] -eq [Math]::Floor($size[0]/2) -and
        $points[1] -eq [Math]::Floor($size[1]/2)) 'Window resize changed physical pixel offsets.'
}
Assert-Distance ($null -eq [WowAutoFight.Native]::SampleOffsets(100,100)) 'Too-small viewport accepted.'
$rendered=Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path '.local-backups\fight-v5-pixels.txt'
if (Test-Path -LiteralPath $rendered) {
    foreach ($line in [IO.File]::ReadAllLines($rendered)) {
        $fields=$line.Split(' ')
        $packet=[WowAutoFight.Native]::Decode(([uint32[]]@([uint32]$fields[2])),$fields[0])
        if ($fields[1] -eq 'unknown') {Assert-Distance ($null -eq $packet) 'Unknown plugin render accepted.'}
        else {Assert-Distance ($packet -and $packet.Action -eq $fields[1]) 'Plugin RGB / script decoder disagree.'}
    }
}
Write-Output 'PASS: main-color protocol across both clients, one-second relock/reopen retry, combat stop, approach/retreat, lost target, illegal/unknown/old packet rejection and resize geometry. No window or input calls.'

foreach ($entry in @(@(0,0,600,400,'左上'),@(1200,0,1800,400,'右上'),@(0,700,600,1100,'左下'),@(1200,700,1800,1100,'右下'),@(600,300,1320,780,'居中'))) {
    Assert-Distance ([WowAutoFight.Native]::ClassifyWindowPosition($entry[0],$entry[1],$entry[2],$entry[3],0,0,1920,1080) -eq $entry[4]) 'Window position classification differs from fishing.'
}
