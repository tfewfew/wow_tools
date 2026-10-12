$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path (Join-Path $PSScriptRoot '..\autoFight.Native.cs')
. (Join-Path $PSScriptRoot '..\autoFight.Engine.ps1')
function Assert-Distance($Condition,[string]$Label) {if (-not $Condition) {throw $Label}}
function Pixel([int]$R,[int]$G,[int]$B) {return [uint32]($R -bor ($G -shl 8) -bor ($B -shl 16))}
function Test-Packet([string]$Flavor,[int]$Class,[int]$Action,[int]$Recovery=0,[bool]$Combat=$false,[bool]$Busy=$false,[int]$Encounter=17,[int]$Beat=10) {
    $identity=($Class-1)+$(if ($Flavor -eq 'titan') {0} else {13})
    $aux=$Recovery*4+2*[int]$Combat+[int]$Busy
    return [uint32[]]@((Pixel (16+32*$Action) (16+8*$identity) (4+8*$Encounter)),
        (Pixel (8+16*$aux) (8+16*$Beat) (8+16*(($Action+$identity+$Encounter+$aux+$Beat+7)%16))))
}
foreach ($flavor in @('titan','forerver')) {
    foreach ($class in 1..13) {
        foreach ($beat in 0..15) {
            foreach ($encounter in @(0,17,31)) {
                foreach ($entry in @(@(1,0,$false,$false),@(2,0,$false,$false),@(3,0,$true,$false),
                    @(4,0,$true,$false),@(5,0,$false,$false),@(6,0,$false,$false),
                    @(1,1,$false,$true),@(4,2,$true,$true),@(3,2,$true,$false))) {
                    $packet=[WowAutoFight.Native]::Decode((Test-Packet $flavor $class $entry[0] $entry[1] $entry[2] $entry[3] $encounter $beat),$flavor)
                    $action=@('unknown','idle','opening','waiting','combat','loot','skin')[$entry[0]]
                    Assert-Distance ($packet -and $packet.Action -eq $action -and $packet.ClassId -eq $class -and
                        $packet.EncounterId -eq $encounter -and $packet.Heartbeat -eq $beat -and $packet.Busy -eq $entry[3] -and
                        $packet.Combat -eq $entry[2]) 'Two-cell metadata / action / heartbeat wrap failed.'
                }
            }
        }
    }
    $packet=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 2),$flavor)
    $p=Get-AutoFightEffectiveProfile (New-AutoFightProfile $flavor 4) (New-AutoFightCommon)
    $s=New-AutoFightSession 0 4
    $null=Update-AutoFightState $s $packet 0
    Assert-Distance ((Get-AutoFightAction $s $packet $p 0) -eq 'opening') 'Detected monster did not open.'
    Complete-AutoFightAction $s $p 'opening' 0
    $null=Update-AutoFightState $s $packet 2000
    Assert-Distance ($s.State -eq 'waiting' -and (Get-AutoFightAction $s $packet $p 2000) -eq 'wait') 'Opening repeated.'
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
    $packet=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 2 0 $false $false 18),$flavor)
    $null=Update-AutoFightState $s $packet 7000
    Assert-Distance (-not $s.OpeningSent -and (Get-AutoFightAction $s $packet $p 7000) -eq 'opening') 'New monster did not reset opening guard.'
    $cells=Test-Packet $flavor 4 2; $cells[1]=$cells[1] -bxor 0x100000
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode($cells,$flavor)) 'Torn checksum accepted.'
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode((Test-Packet $flavor 4 0),$flavor)) 'Unknown data accepted.'
    $packet=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 0 2 $true),$flavor)
    Assert-Distance ($packet -and $packet.Recovery -eq 'emergency') 'Readable recovery lost solely because range was unknown.'
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode((Test-Packet $flavor 4 4 2 $false),$flavor)) 'Invalid recovery / combat combination accepted.'
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode((Test-Packet $flavor 4 2),$(if ($flavor -eq 'titan') {'forerver'} else {'titan'}))) 'Cross-flavor packet accepted.'
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode(([uint32[]]@(0,0,0,0,0,0,0,0,0)),$flavor)) 'Old protocol accepted.'
}
foreach ($size in @(@(1280,720),@(1920,1080),@(2560,1440),@(1279,719),@(3840,2160))) {
    $points=[WowAutoFight.Native]::SampleOffsets($size[0],$size[1])
    Assert-Distance ($points[2]-$points[0] -eq 32 -and $points[0] -eq [Math]::Floor($size[0]/2)-16 -and
        $points[1] -eq [Math]::Floor($size[1]/2)-64) 'Window resize changed physical pixel offsets.'
}
Assert-Distance ($null -eq [WowAutoFight.Native]::SampleOffsets(100,100)) 'Too-small viewport accepted.'
$rendered=Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path '.local-backups\fight-v4-pixels.txt'
if (Test-Path -LiteralPath $rendered) {
    foreach ($line in [IO.File]::ReadAllLines($rendered)) {
        $fields=$line.Split(' ')
        $packet=[WowAutoFight.Native]::Decode(([uint32[]]@([uint32]$fields[2],[uint32]$fields[3])),$fields[0])
        if ($fields[1] -eq 'unknown') {Assert-Distance ($null -eq $packet) 'Unknown plugin render accepted.'}
        else {Assert-Distance ($packet -and $packet.Action -eq $fields[1]) 'Plugin RGB / script decoder disagree.'}
    }
}
Write-Output 'PASS: two-cell protocol across both clients/all classes/heartbeat and encounter wrap, opening once/approach/retreat, torn/unknown/old packet rejection, resize geometry and plugin RGB integration. No window or input calls.'
