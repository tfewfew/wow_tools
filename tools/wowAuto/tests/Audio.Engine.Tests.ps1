$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\wowAuto.Engine.ps1')
function Assert-Audio($Condition, $Message) { if (-not $Condition) { throw $Message } }
$q=New-WowAutoScheduler
$a=Add-WowAutoTask $q 'A' 300 600 0 -UseAudio $true
$b=Add-WowAutoTask $q 'B' 600 600 0 -UseAudio $true
Assert-Audio ($null -eq (Get-WowAutoWork $q 0)) 'Audio startup emitted fishing work.'
$a.AudioReady=$true; $b.AudioReady=$true
$null=Complete-WowAutoPoll $q 'A' 0 'green'
$null=Complete-WowAutoPoll $q 'B' 10 'green'
$session=$a.AudioSession
Assert-Audio ($a.Mode -eq 'Wait' -and $a.Deadline -eq 35000 -and $b.Deadline -eq 35010) 'Audio mode used a random timed reel.'
Assert-Audio (@($q.Events | Where-Object Kind -eq 'Reel').Count -eq 0) 'Green scheduled a reel without an audio signal.'
Assert-Audio (-not (Complete-WowAutoAudioBite $q 'A' 999 $session)) 'Cast startup noise triggered a reel.'
Assert-Audio (-not (Complete-WowAutoAudioBite $q 'A' 2000 $b.AudioSession)) 'Another fishing session triggered this row.'
Assert-Audio (Complete-WowAutoAudioBite $q 'A' 2000 $session) 'Valid signal did not queue a reel.'
$deadline=$a.Deadline
Assert-Audio ($a.AudioReelPending -and $deadline -ge 2300 -and $deadline -le 2600 -and
    @($q.Events | Where-Object { $_.Key -eq 'A' -and $_.Kind -eq 'AudioTimeout' }).Count -eq 0) 'Audio delay was not sampled after matching or retained the no-signal timeout.'
Assert-Audio ($null -eq (Get-WowAutoWork $q ($deadline-1))) 'Audio reel ran before its random delay elapsed.'
$other=Add-WowAutoTask $q 'C' 1 1 2001
Assert-Audio ((Get-WowAutoWork $q 2001).Key -eq 'C') 'Audio delay blocked another window.'
Stop-WowAutoTask $q 'C'
Assert-Audio (-not (Complete-WowAutoAudioBite $q 'A' 2001 $session)) 'Duplicate signal queued another reel.'
Assert-Audio ($a.Deadline -eq $deadline -and @($q.Events | Where-Object { $_.Key -eq 'A' -and $_.Kind -eq 'Reel' }).Count -eq 1) 'Duplicate audio signal resampled the delay.'
$q.ItemHoldUntil=3000; $q.ReelHoldUntil=3200
Assert-Audio ($null -eq (Get-WowAutoWork $q 3199)) 'Audio reel interrupted a global hold.'
Assert-Audio ((Get-WowAutoWork $q 3200).Key -eq 'A') 'Audio reel was not prioritized after the hold.'
Complete-WowAutoReel $q 'A' 3200 $false
Assert-Audio ((Get-WowAutoCycleCount $q 'A') -eq 0) 'Failed reel counted a cycle.'
Complete-WowAutoReel $q 'A' 3200 $true
Complete-WowAutoReel $q 'A' 3201 $true
Assert-Audio ((Get-WowAutoCycleCount $q 'A') -eq 1 -and $a.Mode -eq 'Cooldown' -and -not $a.AudioReelPending) 'Audio reel counted twice or lost cooldown.'
Assert-Audio (-not (Complete-WowAutoAudioBite $q 'A' 3400 $session)) 'Cooldown accepted an old signal.'
Stop-WowAutoTask $q 'A'
$fresh=Add-WowAutoTask $q 'A' 1 1 5000 -UseAudio $true
$fresh.AudioReady=$true
$null=Complete-WowAutoPoll $q 'A' 5000 'green'
Assert-Audio (-not (Complete-WowAutoAudioBite $q 'A' 7000 $session)) 'Restart accepted an old listener signal.'
Suspend-WowAutoFocus $q 'A' 7000 'mock focus denial'
Assert-Audio (Complete-WowAutoAudioBite $q 'A' 8000 $fresh.AudioSession) 'Focus pause discarded a valid signal.'
Assert-Audio ((Get-WowAutoWork $q 35010).Kind -eq 'AudioTimeout') 'Other row timeout was blocked by focus pause.'
Complete-WowAutoAudioTimeout $q 'B' 35009 'too early'
Assert-Audio ((Get-WowAutoBiteTimeoutCount $q 'B') -eq 0 -and $b.Mode -eq 'Wait') 'No-bite timeout counted before its deadline.'
Complete-WowAutoAudioTimeout $q 'B' 35010 'mock timeout'
Complete-WowAutoAudioTimeout $q 'B' 35011 'duplicate timeout'
Complete-WowAutoAudioTimeout $q 'A' 40000 'already matched'
Assert-Audio ($b.AudioSession -eq 0 -and $b.ForceNextCast -and $b.AwaitingFishingTransition -and
    (Get-WowAutoCycleCount $q 'B') -eq 0 -and @($q.Events | Where-Object Key -eq 'B').Count -eq 0) 'Timeout sent/counted a reel or kept stale events.'
Assert-Audio ((Get-WowAutoBiteTimeoutCount $q 'B') -eq 1 -and (Get-WowAutoBiteTimeoutCount $q 'A') -eq 0) 'No-bite timeout duplicated, leaked across processes or counted a matched wait.'
Resume-WowAutoFocus $q 'A'
Assert-Audio ((Get-WowAutoWork $q 35011).Kind -eq 'Reel') 'Retained audio signal did not resume after focus recovery.'
Stop-WowAutoTask $q 'A'; Stop-WowAutoTask $q 'B'
Assert-Audio ($q.Tasks.Count -eq 0 -and $q.Events.Count -eq 0) 'Stopping left audio actions queued.'
$b=Add-WowAutoTask $q 'B' 300 300 50000 -UseAudio $true
$b.AudioReady=$true;$null=Complete-WowAutoPoll $q 'B' 50000 'green'
Reset-WowAutoAudioWait $q 'B' 51000 'state changed, not a timeout'
Complete-WowAutoAudioTimeout $q 'B' 85000 'cancelled wait'
Assert-Audio ((Get-WowAutoBiteTimeoutCount $q 'B') -eq 1 -and (Get-WowAutoBiteTimeoutCount $q 'new-process-identity') -eq 0) 'Restart lost the process timeout count or ordinary reset/reused PID inherited a timeout.'
Stop-WowAutoTask $q 'B';Complete-WowAutoAudioTimeout $q 'B' 90000 'stopped task'
$timed=Add-WowAutoTask $q 'timed' 1000 1000 0
$null=Complete-WowAutoPoll $q 'timed' 0 'green';Complete-WowAutoAudioTimeout $q 'timed' 1000 'timed reel'
Assert-Audio ((Get-WowAutoBiteTimeoutCount $q 'B') -eq 1 -and (Get-WowAutoBiteTimeoutCount $q 'timed') -eq 0) 'Stopped task or timed reel counted a no-bite timeout.'
# Each signal uses the current per-version range; existing deadlines remain fixed.
$q=New-WowAutoScheduler
Assert-Audio ((Get-WowAutoBiteTimeoutCount $q 'B') -eq 0) 'A new tool run inherited no-bite timeouts.'
$a=Add-WowAutoTask $q 'A' 300 300 0 -UseAudio $true
$b=Add-WowAutoTask $q 'B' 600 600 0 -UseAudio $true
foreach ($key in @('A','B')) { $q.Tasks[$key].AudioReady=$true; $null=Complete-WowAutoPoll $q $key 0 'green' }
$null=Complete-WowAutoAudioBite $q 'A' 34000 $a.AudioSession
$a.MinimumMs=900; $a.MaximumMs=900
$b.MinimumMs=800; $b.MaximumMs=800
$null=Complete-WowAutoAudioBite $q 'B' 34500 $b.AudioSession
Assert-Audio ($a.Deadline -eq 34300 -and $b.Deadline -eq 35300) 'Version range updates changed a pending reel or were ignored by the next signal.'
Assert-Audio ((Get-WowAutoWork $q 34300).Key -eq 'A') 'Fixed audio delay missed its exact deadline.'
Stop-WowAutoTask $q 'A'
Assert-Audio ($null -eq (Get-WowAutoWork $q 35000) -and (Get-WowAutoWork $q 35300).Key -eq 'B') 'Original no-signal timeout cancelled the post-match delay.'
Stop-WowAutoTask $q 'B'
Assert-Audio ($q.Events.Count -eq 0 -and $null -eq (Get-WowAutoWork $q 36000)) 'Stop retained a delayed reel.'
# Random-delay overruns count once against the immutable protection deadline.
$q=New-WowAutoScheduler
foreach($case in @(@('before',1699,0),@('equal',1700,0),@('after',1701,1))){
    $key=$case[0];$state=Add-WowAutoTask $q $key 300 300 0 -UseAudio $true -AudioTimeoutMs 2000
    $state.AudioReady=$true;$null=Complete-WowAutoPoll $q $key 0 green
    $state.AudioTimeoutMs=60000
    Assert-Audio (Complete-WowAutoAudioBite $q $key $case[1] $state.AudioSession) 'Valid near-boundary match was rejected.'
    Assert-Audio ($state.AudioProtectionDeadline -eq 2000 -and $state.Deadline -eq $case[1]+300 -and (Get-WowAutoBiteTimeoutCount $q $key) -eq $case[2]) 'Random reel delay ignored the original protection boundary or counted its exact boundary.'
    Assert-Audio (-not (Complete-WowAutoAudioBite $q $key ($case[1]+1) $state.AudioSession)) 'Duplicate match resampled a late reel or recounted its overrun.'
    Complete-WowAutoAudioTimeout $q $key 2100 'must not double count an already matched delay'
    Assert-Audio ((Get-WowAutoBiteTimeoutCount $q $key) -eq $case[2] -and $state.AudioReelPending) 'No-signal timeout duplicated the delayed-reel count or cancelled its action.'
}
$late=$q.Tasks.after
Assert-Audio ($late.ReelDelayExceededProtection -and $late.Status -match '随机收竿延迟超过' -and (Get-WowAutoCycleCount $q after) -eq 0 -and -not $late.PostReelJumpAllowed) 'Delay overrun omitted its reason, counted a fake successful reel or allowed jumping.'
Complete-WowAutoReel $q after 2001 $false
Assert-Audio ((Get-WowAutoBiteTimeoutCount $q after) -eq 1 -and (Get-WowAutoCycleCount $q after) -eq 0) 'Failed reel recounted the delay overrun.'
Complete-WowAutoReel $q after 2001 $true
Assert-Audio ((Get-WowAutoBiteTimeoutCount $q after) -eq 1 -and (Get-WowAutoCycleCount $q after) -eq 1 -and $late.AudioProtectionDeadline -eq 0) 'Registered successful late reel changed its counter or retained the old protection deadline.'
Stop-WowAutoTask $q after
$late=Add-WowAutoTask $q after 300 300 5000 -UseAudio $true -AudioTimeoutMs 2000
$late.AudioReady=$true;$null=Complete-WowAutoPoll $q after 5000 green
Assert-Audio ($late.AudioProtectionDeadline -eq 7000 -and -not $late.ReelDelayExceededProtection -and (Get-WowAutoBiteTimeoutCount $q after) -eq 1) 'Restart lost cumulative overrun count or inherited the prior protection deadline.'
Reset-WowAutoAudioWait $q after 5100 'ordinary cancellation'
Assert-Audio ((Get-WowAutoBiteTimeoutCount $q after) -eq 1 -and $late.AudioProtectionDeadline -eq 0) 'Ordinary cancellation invented an overrun.'
Write-Output 'PASS: audio matching/timing/holds/identity, no-bite and random-delay-overrun counters, strict protection boundary, immutable active deadlines, per-round deduplication and process isolation. No input.'
