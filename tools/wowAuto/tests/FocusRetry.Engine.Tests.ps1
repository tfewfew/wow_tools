$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\wowAuto.Engine.ps1')
function Assert-Focus($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

foreach ($mode in @('poll','reel','item','cooldown')) {
    $q=New-WowAutoScheduler
    if ($mode -eq 'item') { Set-WowAutoItemEnabled $q $true 0 }
    $a=Add-WowAutoTask $q 'A' 100 100 0
    if ($mode -in @('reel','cooldown')) {
        $null=Complete-WowAutoPoll $q 'A' 0 'green'
        if ($mode -eq 'cooldown') { Complete-WowAutoReel $q 'A' 100 $true }
    }
    if ($mode -eq 'poll') { $null=Get-WowAutoWork $q 0 }
    $savedMode=$a.Mode; $savedDeadline=$a.Deadline; $savedStatus=$a.Status
    $savedEvents=@($q.Events).Count
    Suspend-WowAutoFocus $q 'A' 1000 'Focus denied.'
    Assert-Focus ($a.Running -and $a.FocusRetryAt -eq 31000 -and $null -eq $q.ActiveKey) 'Suspension stopped task or retained active focus.'
    Assert-Focus ($null -eq (Get-WowAutoWork $q 30999)) "Work escaped suspension: $mode"
    Assert-Focus ($a.Mode -eq $savedMode -and $a.Deadline -eq $savedDeadline -and $q.Events.Count -eq $savedEvents) "Suspension changed workflow: $mode"
    $work=Get-WowAutoWork $q 31000
    Assert-Focus ($work.Key -eq 'A' -and $work.Kind -eq 'FocusRetry') "Missing retry at 30-second boundary: $mode"
    Suspend-WowAutoFocus $q 'A' 31000 'Still denied.'
    Assert-Focus ($a.FocusRetryAt -eq 61000 -and $null -eq (Get-WowAutoWork $q 60999)) 'Repeated failure did not wait another 30 seconds.'
    Resume-WowAutoFocus $q 'A'
    Assert-Focus ($a.FocusRetryAt -eq 0 -and $a.Status -eq $savedStatus) 'Recovery lost previous status.'
    $expected=if ($mode -eq 'reel') { 'Reel' } elseif ($mode -eq 'item') { 'Item' } else { 'Poll' }
    Assert-Focus ((Get-WowAutoWork $q 61000).Kind -eq $expected) "Recovery lost pending work: $mode"
}

# A suspended overdue reel must not starve another row's reel, item or poll.
foreach ($otherKind in @('Reel','Item','Poll')) {
    $q=New-WowAutoScheduler
    $a=Add-WowAutoTask $q 'A' 100 100 0
    $b=Add-WowAutoTask $q 'B' 100 100 0
    $null=Complete-WowAutoPoll $q 'A' 0 'green'
    Suspend-WowAutoFocus $q 'A' 100 'Denied.'
    if ($otherKind -eq 'Reel') { $null=Complete-WowAutoPoll $q 'B' 0 'green' }
    if ($otherKind -eq 'Item') { Set-WowAutoItemEnabled $q $true 0; $b.ItemDue=100 }
    $work=Get-WowAutoWork $q 100
    Assert-Focus ($work.Key -eq 'B' -and $work.Kind -eq $otherKind) "Suspension blocked another row's $otherKind"
    Stop-WowAutoTask $q 'B'
    $q.ReelHoldUntil=30200
    Assert-Focus ($null -eq (Get-WowAutoWork $q 30100)) 'Focus retry interrupted reel hold.'
    $q.ItemHoldUntil=30300
    Assert-Focus ($null -eq (Get-WowAutoWork $q 30200)) 'Focus retry interrupted item hold.'
    Assert-Focus ((Get-WowAutoWork $q 30300).Kind -eq 'FocusRetry') 'Retry did not resume after holds.'
    Stop-WowAutoTask $q 'A'
    Assert-Focus ($a.FocusRetryAt -eq 0 -and $null -eq (Get-WowAutoWork $q 99999)) 'Stop left a retry behind.'
    $fresh=Add-WowAutoTask $q 'A' 100 100 100000
    $firstKind=if ($q.UseItem) { 'Item' } else { 'Poll' }
    Assert-Focus ($fresh.FocusRetryAt -eq 0 -and (Get-WowAutoWork $q 100000).Kind -eq $firstKind) 'Restart inherited suspension.'
}
Write-Output 'PASS: focus retry boundaries, repeated failure, retained poll/reel/item/cooldown, row isolation, uninterrupted holds and cancellation.'
