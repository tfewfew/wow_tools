$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\wowAuto.Engine.ps1')
function Assert-Item($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
$q=New-WowAutoScheduler
Set-WowAutoItemEnabled $q $true 0
$a=Add-WowAutoTask $q 'A' 100 100 0
$b=Add-WowAutoTask $q 'B' 100 100 0
Assert-Item ((Complete-WowAutoItemCheck $q 'A' 0 'present' 'red') -eq 'Continue' -and -not $a.InitialItemPending) 'Existing enchant forced item use.'
Assert-Item ((Complete-WowAutoItemCheck $q 'B' 0 'unknown' 'red') -eq 'Wait' -and $b.InitialItemPending) 'Unknown point allowed casting.'
Assert-Item ((Get-WowAutoWork $q 100).Key -eq 'A') 'Unknown point blocked another row.'
Assert-Item ((Complete-WowAutoItemCheck $q 'A' 100 'missing' 'green') -eq 'Continue') 'Missing enchant interrupted channel.'
$null=Complete-WowAutoPoll $q 'A' 100 'green'
Assert-Item ((Get-WowAutoWork $q 200).Kind -eq 'Reel') 'Enchant check preempted due reel.'
Complete-WowAutoReel $q 'A' 200 $true
Assert-Item ($null -eq (Get-WowAutoWork $q 299)) 'Enchant check interrupted post-reel hold.'
Assert-Item ((Complete-WowAutoItemCheck $q 'B' 300 'missing' 'red') -eq 'UseItem') 'Missing enchant did not request item.'
Complete-WowAutoItem $q 'B' 300 $true
Assert-Item ($q.ItemHoldUntil -eq 3300 -and $b.InitialItemPending) 'Item omitted full hold or confirmation gate.'
Assert-Item ($null -eq (Get-WowAutoWork $q 3299)) 'Other work interrupted three seconds.'
Assert-Item ((Complete-WowAutoItemCheck $q 'B' 3300 'missing' 'red') -eq 'Wait') 'Unconfirmed enchant retried immediately or allowed cast.'
Assert-Item ((Complete-WowAutoItemCheck $q 'B' 5300 'missing' 'red') -eq 'UseItem') 'Unconfirmed enchant never retried.'
Complete-WowAutoItem $q 'B' 5300 $false
Assert-Item ($q.ItemHoldUntil -eq 3300) 'Failed send added a hold.'
Assert-Item ((Complete-WowAutoItemCheck $q 'B' 5800 'present' 'red') -eq 'Continue' -and -not $b.InitialItemPending -and $b.ItemRetryAt -eq 0) 'Confirmation did not release casting.'
Set-WowAutoItemEnabled $q $false 5801
Assert-Item (-not $b.InitialItemPending -and $b.ItemDue -eq 0 -and $b.ItemStatus -eq '') 'Disable retained enchant gate.'
Write-Output 'PASS: enchant presence/missing/unknown, channel deferral, reel priority, row isolation, full hold, confirmation/retry and checkbox cancellation.'
