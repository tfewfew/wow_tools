$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\wowAuto.Engine.ps1')
function Assert-Audio($Condition, $Message) { if (-not $Condition) { throw $Message } }
$q=New-WowAutoScheduler
$a=Add-WowAutoTask $q 'A' 1 1 0 -UseAudio $true
$b=Add-WowAutoTask $q 'B' 1 1 0 -UseAudio $true
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
Assert-Audio (-not (Complete-WowAutoAudioBite $q 'A' 2001 $session)) 'Duplicate signal queued another reel.'
$q.ItemHoldUntil=3000; $q.ReelHoldUntil=3200
Assert-Audio ($null -eq (Get-WowAutoWork $q 3199)) 'Audio reel interrupted a global hold.'
Assert-Audio ((Get-WowAutoWork $q 3200).Key -eq 'A') 'Audio reel was not prioritized after the hold.'
Complete-WowAutoReel $q 'A' 3200 $false
Assert-Audio ((Get-WowAutoCycleCount $q 'A') -eq 0) 'Failed reel counted a cycle.'
Complete-WowAutoReel $q 'A' 3200 $true
Complete-WowAutoReel $q 'A' 3201 $true
Assert-Audio ((Get-WowAutoCycleCount $q 'A') -eq 1 -and $a.Mode -eq 'Cooldown') 'Audio reel counted twice or lost cooldown.'
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
Write-Output 'PASS: audio startup gate, green arms audio only, cast suppression, session isolation, deduplication, hold/focus/priority, successful reel counting, timeout recast and stop/restart cancellation.'
