$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\wowAuto.Engine.ps1')
function Assert-Item($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
$q=New-WowAutoScheduler
$a=Add-WowAutoTask $q 'A' 100 100 0 -UseItem $true
$b=Add-WowAutoTask $q 'B' 100 100 0 -UseItem $true
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
Set-WowAutoItemEnabled $q 'B' $false 5801
Assert-Item (-not $b.InitialItemPending -and $b.ItemDue -eq 0 -and $b.ItemStatus -eq '') 'Disable retained enchant gate.'
Assert-Item ($a.UseItem) 'Disabling B changed A selection.'

# Per-process selection must gate checks, dispatch and confirmation independently.
$q=New-WowAutoScheduler
$a=Add-WowAutoTask $q 'A' 100 100 0 -UseItem $true
$b=Add-WowAutoTask $q 'B' 100 100 0
Assert-Item ($a.UseItem -and -not $b.UseItem -and -not $b.InitialItemPending) 'Start selection leaked to another process.'
Assert-Item ((Complete-WowAutoItemCheck $q 'A' 0 'unknown' 'red') -eq 'Wait') 'Selected unknown point did not wait.'
$work=Get-WowAutoWork $q 1
Assert-Item ($work.Key -eq 'B' -and $work.Kind -eq 'Poll') 'Unselected row could not fish while A waited for lure.'
Assert-Item ((Complete-WowAutoItemCheck $q 'B' 1 'missing' 'red') -eq 'Continue') 'Unselected row requested item.'
Complete-WowAutoItem $q 'B' 1 $true
Assert-Item ($q.ItemHoldUntil -eq 0 -and $b.ItemDue -eq 0) 'Unselected completion registered an item hold.'
Set-WowAutoItemEnabled $q 'B' $true 100
Assert-Item ($b.UseItem -and $b.ItemDue -eq 100 -and $b.InitialItemPending -and $a.ItemDue -eq 1000) 'Runtime enabling B altered A check.'
Complete-WowAutoItem $q 'B' 100 $true
Set-WowAutoItemEnabled $q 'B' $false 101
Assert-Item ($q.ItemHoldUntil -eq 3100 -and $a.UseItem -and -not $b.UseItem) 'Unchecking B shortened shared hold or changed A.'
Assert-Item ($null -eq (Get-WowAutoWork $q 3099)) 'Other process interrupted shared item hold.'
Assert-Item ((Get-WowAutoWork $q 3100).Key -eq 'A') 'Checked process did not resume check after hold.'
Stop-WowAutoTask $q 'A'
$fresh=Add-WowAutoTask $q 'A' 100 100 3200
Assert-Item (-not $fresh.UseItem -and -not $fresh.InitialItemPending) 'New session inherited old item selection.'
Write-Output 'PASS: enchant presence/missing/unknown, channel deferral, reel priority, row isolation, full hold, confirmation/retry and checkbox cancellation.'
