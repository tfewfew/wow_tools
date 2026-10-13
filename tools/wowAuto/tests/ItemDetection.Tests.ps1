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
Assert-Item ($q.ItemHoldUntil -eq 3300 -and $b.ItemConfirmUntil -eq 5300 -and $b.InitialItemPending) 'Item attempt omitted the hold or confirmation deadline.'
Assert-Item ($null -eq (Get-WowAutoWork $q 3299)) 'Other work interrupted three seconds.'
Assert-Item ((Complete-WowAutoItemCheck $q 'B' 3300 'missing' 'red') -eq 'Wait' -and $b.InitialItemPending) 'Unconfirmed item allowed casting or immediate reuse.'
Assert-Item ((Complete-WowAutoItemCheck $q 'B' 5300 'present' 'red') -eq 'Continue' -and -not $b.InitialItemPending -and $b.ItemConfirmUntil -eq 0) 'Confirmation at the deadline was rejected.'
Assert-Item ((Complete-WowAutoItemCheck $q 'B' 6300 'missing' 'red') -eq 'UseItem') 'Expired enchant did not request another item.'
Complete-WowAutoItem $q 'B' 6300 $true
Assert-Item ($b.ItemConfirmUntil -eq 11300 -and $q.ItemHoldUntil -eq 9300) 'Later item attempt did not start a new deadline and hold.'
Assert-Item ((Complete-WowAutoItemCheck $q 'B' 11300 'unknown' 'red') -eq 'Continue' -and $b.ItemDetectionDisabled -and -not $b.InitialItemPending) 'Unconfirmed item did not disable detection at timeout.'
Assert-Item ($b.ItemDue -eq 0 -and (Complete-WowAutoItemCheck $q 'B' 12000 'missing' 'red') -eq 'Continue') 'Disabled detection scheduled another item.'
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
Assert-Item (-not $b.ItemDetectionDisabled -and $b.ItemConfirmUntil -eq 0) 'Disabling item failed to reset detection state.'
Stop-WowAutoTask $q 'A'
$fresh=Add-WowAutoTask $q 'A' 100 100 3200
Assert-Item (-not $fresh.UseItem -and -not $fresh.InitialItemPending) 'New session inherited old item selection.'

$retryQueue=New-WowAutoScheduler
$retry=Add-WowAutoTask $retryQueue 'retry' 100 100 0 -UseItem $true
Assert-Item ((Complete-WowAutoItemCheck $retryQueue 'retry' 0 'missing' 'red') -eq 'UseItem') 'Fresh task did not request the missing item.'
Complete-WowAutoItem $retryQueue 'retry' 0 $false
Assert-Item ($retry.ItemConfirmUntil -eq 5000 -and $retry.InitialItemPending -and $retry.ItemDue -eq 500 -and $retryQueue.ItemHoldUntil -eq 0) 'Failed send omitted the deadline or added a hold.'
Assert-Item ((Get-WowAutoWork $retryQueue 500).Kind -eq 'Item') 'Failed item send did not retry.'
Complete-WowAutoItem $retryQueue 'retry' 500 $true
Assert-Item ($retry.ItemConfirmUntil -eq 5000 -and $retryQueue.ItemHoldUntil -eq 3500) 'Successful retry reset the original deadline.'
$fresh=Add-WowAutoTask $retryQueue 'retry' 100 100 4000 -UseItem $true
Assert-Item (-not $fresh.ItemDetectionDisabled -and $fresh.ItemConfirmUntil -eq 0 -and $fresh.ItemDue -eq 4000) 'A new task inherited the previous item attempt.'

$failureQueue=New-WowAutoScheduler
$failure=Add-WowAutoTask $failureQueue 'failure' 100 100 0 -UseItem $true
Complete-WowAutoItem $failureQueue 'failure' 0 $false
foreach ($at in @(500,1000,1500,2000,2500,3000,3500,4000,4500)) {
    Assert-Item ((Complete-WowAutoItemCheck $failureQueue 'failure' $at 'missing' 'red') -eq 'UseItem') 'Failed send did not retry before timeout.'
    Complete-WowAutoItem $failureQueue 'failure' $at $false
}
Assert-Item ((Complete-WowAutoItemCheck $failureQueue 'failure' 5000 'missing' 'red') -eq 'Continue' -and $failure.ItemDetectionDisabled) 'Failed sends did not stop at the original five-second deadline.'
Assert-Item ((Get-WowAutoWork $failureQueue 5000).Kind -eq 'Poll') 'Timed-out item prevented fishing from continuing.'
Write-Output 'PASS: enchant confirmation, later replenishment, five-second timeout, failed-send retries, channel deferral, reel priority, row isolation and checkbox cancellation.'
