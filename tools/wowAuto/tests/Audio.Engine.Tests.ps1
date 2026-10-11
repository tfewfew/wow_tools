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
Reset-WowAutoAudioWait $q 'B' 35010 'mock timeout'
Assert-Audio ($b.AudioSession -eq 0 -and $b.ForceNextCast -and $b.AwaitingFishingTransition -and
    (Get-WowAutoCycleCount $q 'B') -eq 0 -and @($q.Events | Where-Object Key -eq 'B').Count -eq 0) 'Timeout sent/counted a reel or kept stale events.'
Resume-WowAutoFocus $q 'A'
Assert-Audio ((Get-WowAutoWork $q 35011).Kind -eq 'Reel') 'Retained audio signal did not resume after focus recovery.'
Stop-WowAutoTask $q 'A'; Stop-WowAutoTask $q 'B'
Assert-Audio ($q.Tasks.Count -eq 0 -and $q.Events.Count -eq 0) 'Stopping left audio actions queued.'
# Each signal uses the current per-version range; existing deadlines remain fixed.
$q=New-WowAutoScheduler
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
Write-Output 'PASS: audio startup gate, green arms audio only, random/fixed post-match delay, other-window scheduling, current ranges/immutable deadlines, cast suppression, session isolation/deduplication, hold/focus/priority, reel counting, timeout recast and delayed cancellation.'
