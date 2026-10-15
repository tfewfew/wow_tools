$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path (Join-Path $PSScriptRoot '..\autoFight.Native.cs') -ReferencedAssemblies System.Drawing
. (Join-Path $PSScriptRoot '..\autoFight.Engine.ps1')
function Assert-Distance($Condition,[string]$Label) {if (-not $Condition) {throw $Label}}
function Pixel([int]$R,[int]$G,[int]$B) {return [uint32]($R -bor ($G -shl 8) -bor ($B -shl 16))}
function Test-Packet([string]$Flavor,[int]$Class,[int]$Action,[bool]$Combat=$false,[bool]$Busy=$false,[int]$Encounter=17) {
    $identity=($Class-1)+$(if ($Flavor -eq 'titan') {0} else {13})
    return [uint32[]]@((Pixel (5+20*$Action) (4*($identity+26*[int]$Busy)) (4*($Encounter+32*[int]$Combat))))
}
$actions=@('unknown','idle','opening','waiting','combat','loot','skin')
foreach ($flavor in @('titan','forerver')) {
    foreach ($class in (Get-AutoFightClassIds $flavor)) {
        foreach ($encounter in @(0,17,31)) {
            foreach ($entry in @(@(1,$false,$false),@(2,$false,$false),@(3,$true,$false),
                @(4,$true,$true),@(5,$false,$false),@(6,$false,$false))) {
                $packet=[WowAutoFight.Native]::Decode((Test-Packet $flavor $class $entry[0] $entry[1] $entry[2] $encounter),$flavor)
                Assert-Distance ($packet -and $packet.Action -eq $actions[$entry[0]] -and $packet.ClassId -eq $class -and
                    $packet.EncounterId -eq $encounter -and $packet.Busy -eq $entry[2] -and
                    $packet.Combat -eq $entry[1]) 'V7 main-state decoding or metadata failed.'
            }
        }
    }
    foreach ($class in 1..13 | Where-Object {$_ -notin (Get-AutoFightClassIds $flavor)}) {
        Assert-Distance ($null -eq [WowAutoFight.Native]::Decode((Test-Packet $flavor $class 1),$flavor)) 'Unavailable class accepted.'
    }
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode((Test-Packet $flavor 4 0),$flavor)) 'Unknown main state accepted.'
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode((Test-Packet $flavor 4 2 $true),$flavor)) 'Opening accepted during combat.'
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode((Test-Packet $flavor 4 4 $false),$flavor)) 'Combat action accepted out of combat.'
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode((Test-Packet $flavor 4 3 $false),$flavor)) 'Waiting accepted out of combat.'
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode((Test-Packet $flavor 4 5 $true),$flavor)) 'Loot accepted during combat.'
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode(([uint32[]]@((Pixel 62 12 68))),$flavor)) 'Old V6 main color accepted.'
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode((Test-Packet $flavor 4 2),$(if ($flavor -eq 'titan') {'forerver'} else {'titan'}))) 'Cross-flavor color accepted.'
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode(([uint32[]]@((Pixel 45 12 68),(Pixel 8 8 8))),$flavor)) 'Old two-cell protocol accepted.'
    $profile=Get-AutoFightEffectiveProfile (New-AutoFightProfile $flavor 4) (New-AutoFightCommon)
    $session=New-AutoFightSession 0 4
    $opening=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 2),$flavor)
    $waiting=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 3 $true),$flavor)
    $combat=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 4 $true),$flavor)
    $loot=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 5),$flavor)
    $skin=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 6),$flavor)
    $idle=[WowAutoFight.Native]::Decode((Test-Packet $flavor 4 1),$flavor)
    Assert-Distance ((Get-AutoFightAction $session $opening $profile 0) -eq 'opening') 'Opening color did not request targeting and opener.'
    Complete-AutoFightAction $session $profile 'opening' 0
    Assert-Distance ((Get-AutoFightAction $session $opening $profile 999) -eq 'wait') 'Opening repeated before its one-second interval.'
    Assert-Distance ((Get-AutoFightAction $session $waiting $profile 100) -eq 'wait') 'Waiting color sent input.'
    Assert-Distance ((Get-AutoFightAction $session $combat $profile 200) -eq 'combat') 'Combat color did not immediately replace opener cooldown.'
    Complete-AutoFightAction $session $profile 'combat' 200
    Assert-Distance ((Get-AutoFightAction $session $combat $profile 699) -eq 'wait') 'Combat interval ignored.'
    Assert-Distance ((Get-AutoFightAction $session $loot $profile 300) -eq 'loot') 'Loot color did not request interaction.'
    Complete-AutoFightAction $session $profile 'loot' 300
    Assert-Distance ((Get-AutoFightAction $session $skin $profile 400) -eq 'skin') 'Skin color was blocked by script-side corpse history.'
    Complete-AutoFightAction $session $profile 'skin' 400
    Assert-Distance ((Get-AutoFightAction $session $idle $profile 500) -eq 'wait') 'Idle color sent a fight key.'
    Assert-Distance ((Get-AutoFightAction $session $opening $profile 1000) -eq 'opening') 'Opening color did not retry after one second.'
    Assert-Distance (@($session.PSObject.Properties.Name | Where-Object {$_ -in @('State','Substate','OpeningSent','RecoverySent','LootEncounterId','SkinnedEncounterId')}).Count -eq 0) 'Combat state-machine fields remain in the script session.'
}
foreach ($size in @(@(1280,720),@(1920,1080),@(2560,1440),@(1279,719),@(3840,2160))) {
    $points=[WowAutoFight.Native]::SampleOffsets($size[0],$size[1])
    Assert-Distance ($points.Length -eq 2 -and $points[0] -eq [Math]::Floor($size[0]/2) -and
        $points[1] -eq [Math]::Floor($size[1]/2)) 'Window resize changed main-cell sample.'
}
Assert-Distance ($null -eq [WowAutoFight.Native]::SampleOffsets(100,100)) 'Too-small viewport accepted.'
$rendered=Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path '.local-backups\fight-v7-pixels.txt'
if (Test-Path -LiteralPath $rendered) {
    foreach ($line in [IO.File]::ReadAllLines($rendered)) {
        $fields=$line.Split(' ')
        $packet=[WowAutoFight.Native]::Decode(([uint32[]]@([uint32]$fields[2])),$fields[0])
        if ($fields[1] -eq 'unknown') {Assert-Distance ($null -eq $packet) 'Unknown plugin render accepted.'}
        else {Assert-Distance ($packet -and $packet.Action -eq $fields[1]) 'Plugin RGB / script decoder disagree.'}
    }
}
foreach ($entry in @(@(0,0,600,400,'左上'),@(1200,0,1800,400,'右上'),@(0,700,600,1100,'左下'),
    @(1200,700,1800,1100,'右下'),@(600,300,1320,780,'居中'))) {
    Assert-Distance ([WowAutoFight.Native]::ClassifyWindowPosition($entry[0],$entry[1],$entry[2],$entry[3],0,0,1920,1080) -eq $entry[4]) 'Window position classification differs from fishing.'
}
Write-Output 'PASS: six V7 plugin main states, cross-client RGB metadata, direct action mapping, cooldowns, illegal/old color rejection and resize geometry. No game input.'