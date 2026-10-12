$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path (Join-Path $PSScriptRoot '..\autoFight.Native.cs')
. (Join-Path $PSScriptRoot '..\autoFight.Engine.ps1')
function Assert-Distance($Condition,[string]$Label) {if (-not $Condition) {throw $Label}}
function Pixel([int]$R,[int]$G,[int]$B) {return [uint32]($R -bor ($G -shl 8) -bor ($B -shl 16))}
foreach($flavor in @('titan','forerver')) {
    $color=if($flavor -eq 'titan') {Pixel 255 128 0} else {Pixel 128 0 255}
    [uint32[]]$cells=@((Pixel 0 192 255),(Pixel 255 96 0),(Pixel 0 255 0),(Pixel 0 0 255),
        (Pixel 64 191 85),$color,(Pixel 10 245 170),(Pixel 255 255 255),(Pixel 17 238 102))
    $packet=[WowAutoFight.Native]::Decode($cells,(Pixel 0 0 255),$flavor)
    Assert-Distance ($packet.Action -eq 'opening' -and $packet.EncounterId -eq 17) 'V3 opening/encounter decode failed.'
    $p=New-AutoFightProfile $flavor 4
    $s=New-AutoFightSession 0 4
    $null=Update-AutoFightState $s $packet 0
    Assert-Distance ((Get-AutoFightAction $s $packet $p 0) -eq 'opening') 'Detected monster did not open.'
    Complete-AutoFightAction $s $p 'opening' 0
    $null=Update-AutoFightState $s $packet 2000
    Assert-Distance ($s.State -eq 'waiting' -and (Get-AutoFightAction $s $packet $p 2000) -eq 'wait') 'Opening repeated while waiting for combat evidence.'
    $cells[1]=Pixel 0 192 192; $cells[2]=Pixel 255 0 0
    $packet=[WowAutoFight.Native]::Decode($cells,(Pixel 255 128 0),$flavor)
    Assert-Distance ($null -ne $packet -and $packet.Action -eq 'waiting' -and $packet.Combat) 'Combat flag wrongly bypassed wait protocol.'
    $null=Update-AutoFightState $s $packet 3000
    Assert-Distance ($s.State -eq 'waiting' -and (Get-AutoFightAction $s $packet $p 3000) -eq 'wait') 'Waiting emitted emergency/recovery keys.'
    $cells[1]=Pixel 255 0 0
    $cells[2]=Pixel 0 255 0
    Assert-Distance ($null -ne [WowAutoFight.Native]::Decode($cells,(Pixel 0 0 255),$flavor)) 'Successful opener approaching before combat flag was rejected.'
    $cells[2]=Pixel 255 0 0
    $packet=[WowAutoFight.Native]::Decode($cells,(Pixel 0 0 255),$flavor)
    $null=Update-AutoFightState $s $packet 4000
    Assert-Distance ((Get-AutoFightAction $s $packet $p 4000) -eq 'combat') 'Close monster did not enable normal attack.'
    Complete-AutoFightAction $s $p 'combat' 4000
    Assert-Distance ((Get-AutoFightAction $s $packet $p 4499) -eq 'wait') 'Combat interval ignored.'
    $cells[1]=Pixel 0 192 192; $packet=[WowAutoFight.Native]::Decode($cells,(Pixel 0 0 255),$flavor)
    $null=Update-AutoFightState $s $packet 5000
    Assert-Distance ((Get-AutoFightAction $s $packet $p 5000) -eq 'wait') 'Retreating monster did not stop attacks.'
    $cells[1]=Pixel 255 96 0; $cells[2]=Pixel 0 255 0
    $packet=[WowAutoFight.Native]::Decode($cells,(Pixel 255 0 255),$flavor)
    $null=Update-AutoFightState $s $packet 6000
    Assert-Distance ((Get-AutoFightAction $s $packet $p 6000) -eq 'wait') 'Recovery transition reset opening-once guard.'
    $cells[8]=Pixel 18 237 102; $packet=[WowAutoFight.Native]::Decode($cells,(Pixel 0 0 255),$flavor)
    $null=Update-AutoFightState $s $packet 7000
    Assert-Distance (-not $s.OpeningSent -and (Get-AutoFightAction $s $packet $p 7000) -eq 'opening') 'New monster did not reset opening guard.'
    $cells[8]=Pixel 18 238 200
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode($cells,(Pixel 0 0 255),$flavor)) 'Malformed encounter accepted.'
    $cells[8]=Pixel 18 237 102; $cells[0]=Pixel 0 255 192
    Assert-Distance ($null -eq [WowAutoFight.Native]::Decode($cells,(Pixel 0 0 255),$flavor)) 'Old V2 protocol accepted.'
}
Write-Output 'PASS: both flavors V3 pure pixel decoding, opening once per encounter, quiet wait despite combat/recovery, approach/retreat, cooldown, new monster and old/malformed protocol rejection. No native window/input calls.'
