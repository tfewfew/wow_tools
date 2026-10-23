$ErrorActionPreference='Stop'
$tool=Split-Path $PSScriptRoot -Parent
. (Join-Path $tool 'wowAuto.Rotation.Match.ps1')
. (Join-Path $tool 'wowAuto.AccountDiscovery.ps1')
function Assert-Discovery($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function New-DiscoveryScreen([string[]]$Names,[string]$Kind='menu') {
    $row=0
    return [pscustomobject]@{Kind=$Kind;Targets=@(foreach($name in $Names){$row++;[pscustomobject]@{Name=$name;RawName=$name;MenuRow=$row;Ambiguous=$false}})}
}
$accounts=@(
    @{Account='ACCOUNT-A';Names=@('吔史呀嘞','双持船橘二咪','共同角色');Roles=@()},
    @{Account='ACCOUNT-B';Names=@('乌木力奇','铁皮小橘','共同角色');Roles=@()}
)
$firstScreen=New-DiscoveryScreen @('双持船橘二咪')
$firstAccount=Resolve-OcrAccount $firstScreen $accounts
Assert-Discovery ($firstAccount.Account -ceq 'ACCOUNT-A') ('One known character did not confirm its account: '+(@{Result=$firstAccount;Screen=$firstScreen;Candidates=$accounts} | ConvertTo-Json -Depth 7 -Compress))
Assert-Discovery ((Resolve-OcrAccount (New-DiscoveryScreen @('乌木力奇')) $accounts).Account -ceq 'ACCOUNT-B') 'A disabled/no-task record could not identify its account.'
Assert-Discovery ((Resolve-OcrAccount (New-DiscoveryScreen @('共同角色','铁皮小橘')) $accounts).Account -ceq 'ACCOUNT-B') 'A common name prevented independent unique ownership evidence.'
Assert-Discovery ((Resolve-OcrAccount (New-DiscoveryScreen @('共同角色','咆史呀嘞')) $accounts).Account -ceq 'ACCOUNT-A') 'Shared exact evidence prevented a unique one-glyph name from resolving ownership.'
foreach($case in @(
    @{Names=@('共同角色');Kind='ambiguous'},
    @{Names=@('双持船橘二咪','乌木力奇');Kind='conflict'},
    @{Names=@('完全陌生人');Kind='missing'}
)){
    $result=Resolve-OcrAccount (New-DiscoveryScreen $case.Names) $accounts
    Assert-Discovery (-not $result.Account -and $result.Kind -eq $case.Kind) ('Unsafe account inferred: '+$case.Kind)
}
Assert-Discovery (-not (Resolve-OcrAccount (New-DiscoveryScreen @('吔史呀嘞') unknown) $accounts).Account) 'Character names without a menu anchor inferred an account.'
Assert-Discovery ((Resolve-OcrAccount (New-DiscoveryScreen @('咆史呀嘞')) $accounts).Account -ceq 'ACCOUNT-A') 'Unique N-1 glyph match no longer identifies an account.'
Assert-Discovery (-not (Resolve-OcrAccount (New-DiscoveryScreen @('咆史呀吼')) $accounts).Account) 'Two OCR errors inferred an account.'
$similar=@(@{Account='EXACT';Names=@('吔史呀嘞')},@{Account='FUZZY';Names=@('咆史呀嘞')})
Assert-Discovery ((Resolve-OcrAccount (New-DiscoveryScreen @('吔史呀嘞')) $similar).Account -ceq 'EXACT') 'Fuzzy alternatives defeated exact ownership.'
$offPage=New-DiscoveryScreen @('吔史呀嘞');$offPage.Targets[0].MenuRow=11
Assert-Discovery (-not (Resolve-OcrAccount $offPage $accounts).Account) 'Off-page row inferred an account.'
Write-Output 'PASS: first-page anchored OCR account ownership from one character, inactive records, common names, conflicts/unknowns, N-1 fallback and exact-match precedence. Pure data only.'
