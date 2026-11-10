$ErrorActionPreference='Stop'
$tool=Split-Path $PSScriptRoot -Parent
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path (Join-Path $tool 'autoFight.Native.cs') -ReferencedAssemblies System.Drawing
. (Join-Path $tool 'autoFight.Engine.ps1')
. (Join-Path $tool 'autoTame.Engine.ps1')
function Assert-Tame($Condition,[string]$Text){if(-not $Condition){throw $Text}}
$config=New-AutoTameConfig
$config.TrapKey='F1';$config.OpeningKey='F2';$config.BackwardKey='S';$config.TameKey='F3'
$config.BackwardHoldMs=250
$config=ConvertTo-AutoTameConfig $config -RequireKey
$packet=[pscustomobject]@{State='matched';Combat=$false;TargetId=1}
$session=New-AutoTameSession
$now=0L
foreach($stage in @('Trap','Opening','Backward','Tame')) {
    $action=Get-AutoTameAction $session $packet $config $now
    Assert-Tame ($action.Stage -ceq $stage) ('Incorrect phase '+$stage)
    Assert-Tame ($action.KeyHoldMs -eq $(if($stage -eq 'Backward'){250}else{0})) 'Hold duration leaked into another phase.'
    # Queue delay must not count toward the configured post-send wait.
    $releasedAt=$now+200+$action.KeyHoldMs
    Complete-AutoTameAction $session $action $config $releasedAt
    Assert-Tame ($session.Due -eq $releasedAt+$config.($stage+'WaitMs')) 'Wait did not start after key release acknowledgement.'
    if($stage -eq 'Opening'){$packet.Combat=$true}
    Assert-Tame ($null -eq (Get-AutoTameAction $session $packet $config ($session.Due-1))) 'Phase executed before its exact deadline.'
    $now=$session.Due
}
$action=Get-AutoTameAction $session $packet $config $now
Assert-Tame ($action.Stage -eq 'Tame' -and $action.RequireCombat) 'Capture did not repeat after 10 seconds.'
Complete-AutoTameAction $session $action $config $now
$packet.Combat=$false
Assert-Tame ($null -eq (Get-AutoTameAction $session $packet $config ($now+1)) -and -not $session.Active) 'Leaving combat did not cancel a pending repeat.'
Assert-Tame ($null -eq (Get-AutoTameAction $session $packet $config ($now+20000))) 'The same ended target restarted its opener.'
$packet.TargetId=2
Assert-Tame ((Get-AutoTameAction $session $packet $config ($now+20001)).Stage -eq 'Trap') 'New target did not start a fresh sequence.'
$packet.TargetId=3
Assert-Tame ((Get-AutoTameAction $session $packet $config ($now+20002)).Stage -eq 'Trap') 'Same-name target identity change retained old stages.'
$packet.State='idle'
Assert-Tame ($null -eq (Get-AutoTameAction $session $packet $config $now) -and -not $session.Active) 'Lost or unmatched target did not cancel.'
$only=New-AutoTameConfig;$only.TameKey='F4';$only.BackwardHoldMs=500;$only=ConvertTo-AutoTameConfig $only -RequireKey
$packet.State='matched';$packet.TargetId=4
$session=New-AutoTameSession
$action=Get-AutoTameAction $session $packet $only 0
Assert-Tame ($action.Stage -eq 'Tame' -and $action.KeyHoldMs -eq 0) 'Empty optional keys introduced stages or holds.'
Complete-AutoTameAction $session $action $only 0
Assert-Tame ($null -eq (Get-AutoTameAction $session $packet $only 10000) -and -not $session.Active) 'An out-of-combat first capture retried endlessly.'
$session=New-AutoTameSession;$packet.Combat=$true
$null=Get-AutoTameAction $session $packet $only 0
foreach($state in @('unknown','idle','dead')){
    $packet.State=$state
    Assert-Tame ($null -eq (Get-AutoTameAction $session $packet $only 20000)) ('Unsafe state '+$state)
}
Assert-Tame ($null -eq (Get-AutoTameAction $session $null $only 20000)) 'Unreadable packet submitted input.'

$jumpConfig=New-AutoTameConfig
$jumpConfig.TameKey='F3';$jumpConfig.JumpIntervalSeconds=1
$idlePacket=[pscustomobject]@{State='idle';Combat=$false;TargetId=7}
$jumpSession=New-AutoTameSession 100 $jumpConfig
Assert-Tame ($null -eq (Get-AutoTameAction $jumpSession $idlePacket $jumpConfig 1099)) 'Initial jump executed before the configured interval.'
$jump=Get-AutoTameAction $jumpSession $idlePacket $jumpConfig 1100
Assert-Tame ($jump.Stage -eq 'Jump' -and $jump.Key -ceq 'Space' -and $jump.ExpectedState -eq 'idle') 'Default Space jump did not execute at the exact deadline.'
Complete-AutoTameAction $jumpSession $jump $jumpConfig 1300
Assert-Tame ($jumpSession.NextJumpAt -eq 2300 -and $jumpSession.ActionReadyAt -eq 2300 -and $jumpSession.Stage -eq 0) 'Jump timing did not start at acknowledgement or changed the taming phase.'
Assert-Tame ($null -eq (Get-AutoTameAction $jumpSession $idlePacket $jumpConfig 2299)) 'Idle jump ignored landing time.'
Assert-Tame ((Get-AutoTameAction $jumpSession $idlePacket $jumpConfig 2300).Stage -eq 'Jump') 'Idle jump did not repeat.'
foreach($state in @('unknown','dead')){
    $unreadable=[pscustomobject]@{State=$state;Combat=$false;TargetId=7}
    Assert-Tame ($null -eq (Get-AutoTameAction $jumpSession $unreadable $jumpConfig 5000)) ('Unsafe jump state '+$state)
}
$idlePacket.Combat=$true
Assert-Tame ($null -eq (Get-AutoTameAction $jumpSession $idlePacket $jumpConfig 5000)) 'Unmatched combat target allowed a jump.'
$idlePacket.Combat=$false
$disabled=New-AutoTameSession 100 $config
Assert-Tame ($null -eq (Get-AutoTameAction $disabled $idlePacket $config 900000)) 'Zero interval did not disable jumps.'

$capturePacket=[pscustomobject]@{State='matched';Combat=$true;TargetId=11}
$jumpSession=New-AutoTameSession 0 $jumpConfig
$capture=Get-AutoTameAction $jumpSession $capturePacket $jumpConfig 0
Complete-AutoTameAction $jumpSession $capture $jumpConfig 50
Assert-Tame ($null -eq (Get-AutoTameAction $jumpSession $capturePacket $jumpConfig 10049)) 'Overdue jump interrupted the configured capture duration.'
$lostSession=$jumpSession | ConvertTo-Json | ConvertFrom-Json
Assert-Tame ($null -eq (Get-AutoTameAction $lostSession $idlePacket $jumpConfig 5000)) 'Target loss allowed a jump before the capture duration ended.'
$jump=Get-AutoTameAction $jumpSession $capturePacket $jumpConfig 10050
Assert-Tame ($jump.Stage -eq 'Jump' -and $jump.ExpectedCombat) 'Overdue jump did not run between captures.'
Complete-AutoTameAction $jumpSession $jump $jumpConfig 10250
Assert-Tame ($null -eq (Get-AutoTameAction $jumpSession $capturePacket $jumpConfig 11249)) 'Capture ignored jump landing time.'
$capture=Get-AutoTameAction $jumpSession $capturePacket $jumpConfig 11250
Assert-Tame ($capture.Stage -eq 'Tame') 'A short jump interval starved capture.'
Complete-AutoTameAction $jumpSession $capture $jumpConfig 11270
Assert-Tame ($null -eq (Get-AutoTameAction $jumpSession $capturePacket $jumpConfig 21269)) 'Repeated jumps interrupted a subsequent capture.'
Assert-Tame ((Get-AutoTameAction $jumpSession $capturePacket $jumpConfig 21270).Stage -eq 'Jump') 'Missed intervals caused capture to suppress all future jumps.'
$capturePacket.TargetId=12
$null=Get-AutoTameAction $jumpSession $capturePacket $jumpConfig 21271
Assert-Tame ($jumpSession.NextJumpAt -eq 11250) 'Changing targets reset the per-process jump interval.'

$moveConfig=New-AutoTameConfig
$moveConfig.TameKey='F3';$moveConfig.BackwardKey='S';$moveConfig.BackwardHoldMs=2000;$moveConfig.JumpIntervalSeconds=1
$moveSession=New-AutoTameSession 0 $moveConfig
$backward=Get-AutoTameAction $moveSession $capturePacket $moveConfig 0
Complete-AutoTameAction $moveSession $backward $moveConfig 2000
Assert-Tame ($null -eq (Get-AutoTameAction $moveSession $capturePacket $moveConfig 2999)) 'Jump skipped post-release backward waiting.'
Assert-Tame ((Get-AutoTameAction $moveSession $capturePacket $moveConfig 3000).Stage -eq 'Jump') 'Jump did not resume after backward hold and wait.'
$other=New-AutoTameSession 5000 $jumpConfig
$restart=New-AutoTameSession 90000 $jumpConfig
Assert-Tame ($other.NextJumpAt -eq 6000 -and $restart.NextJumpAt -eq 91000 -and $jumpSession.NextJumpAt -eq 11250) 'Jump schedules leaked between processes or restarts.'

$path=Join-Path ([IO.Path]::GetTempPath()) ('wow-tame-test-'+[guid]::NewGuid()+'.json')
try {
    Assert-Tame (-not (Read-AutoTameConfig $path).TameKey) 'Missing config invented a capture key.'
    $legacy=$config | Select-Object * -ExcludeProperty BackwardHoldMs,JumpKey,JumpIntervalSeconds
    [IO.File]::WriteAllText($path,($legacy | ConvertTo-Json))
    $legacyContent=[IO.File]::ReadAllText($path)
    $legacyRead=Read-AutoTameConfig $path
    Assert-Tame ($legacyRead.BackwardHoldMs -eq 0 -and $legacyRead.JumpIntervalSeconds -eq 0 -and $legacyRead.JumpKey -ceq 'Space' -and [IO.File]::ReadAllText($path) -ceq $legacyContent) 'Legacy config did not retain defaults without rewriting.'
    $null=Save-AutoTameConfig $path $config
    Assert-Tame ((Read-AutoTameConfig $path).TameWaitMs -eq 10000 -and (Read-AutoTameConfig $path).BackwardHoldMs -eq 250) 'Config round trip failed.'
    $jumpConfig.JumpKey='Ctrl+Space';$jumpConfig.JumpIntervalSeconds=37
    $null=Save-AutoTameConfig $path $jumpConfig
    $jumpRead=Read-AutoTameConfig $path
    Assert-Tame ($jumpRead.JumpKey -ceq 'Ctrl+Space' -and $jumpRead.JumpIntervalSeconds -eq 37) 'Jump settings did not round-trip.'
    $before=[IO.File]::ReadAllText($path)
    foreach($bad in @('empty','invalid','negative','zero-repeat','negative-hold','long-hold','invalid-hold','negative-jump','long-jump','fractional-jump','empty-jump','invalid-jump')) {
        $draft=$config | ConvertTo-Json | ConvertFrom-Json
        switch($bad){'empty'{$draft.TameKey=''}'invalid'{$draft.TrapKey='Ctrl+Ctrl+A'}'negative'{$draft.BackwardWaitMs=-1}'zero-repeat'{$draft.TameWaitMs=0}}
        switch($bad){'negative-hold'{$draft.BackwardHoldMs=-1}'long-hold'{$draft.BackwardHoldMs=60001}'invalid-hold'{$draft.BackwardHoldMs='invalid'}}
        switch($bad){'negative-jump'{$draft.JumpIntervalSeconds=-1}'long-jump'{$draft.JumpIntervalSeconds=3601}'fractional-jump'{$draft.JumpIntervalSeconds=0.5}'empty-jump'{$draft.JumpIntervalSeconds=1;$draft.JumpKey=''}'invalid-jump'{$draft.JumpKey='Ctrl+Ctrl+Space'}}
        $failed=$false;try{$null=Save-AutoTameConfig $path $draft}catch{$failed=$true}
        Assert-Tame ($failed -and [IO.File]::ReadAllText($path) -ceq $before) ('Invalid config partially saved '+$bad)
    }
}finally{if([IO.File]::Exists($path)){[IO.File]::Delete($path)}}
foreach($flavor in @('titan','forerver')) {
    $blue=if($flavor -eq 'titan'){71}else{79}
    foreach($id in @(0,1,63,64,2048,4095)) {
        foreach($combat in @($false,$true)) {
            $green=11+24*(1+$(if($combat){4}else{0}))
            $main=[Drawing.Color]::FromArgb(211,$green,($id%64)*4)
            $aux=[Drawing.Color]::FromArgb((3+4*[Math]::Floor($id/64)),223,$blue)
            $decoded=[WowAutoFight.Native]::DecodeTame($main,$aux,$flavor)
            Assert-Tame ($decoded.State -eq 'matched' -and $decoded.TargetId -eq $id -and $decoded.Combat -eq $combat) 'Taming v1 round trip failed.'
            $other=if($flavor -eq 'titan'){'forerver'}else{'titan'}
            Assert-Tame ($null -eq [WowAutoFight.Native]::DecodeTame($main,$aux,$other)) 'Cross-client protocol accepted.'
        }
    }
}
Assert-Tame ($null -eq [WowAutoFight.Native]::DecodeTame([Drawing.Color]::Red,[Drawing.Color]::Blue,'titan')) 'Fishing colors decoded as taming.'
[WowAutoFight.Native]::FrameReader={
    param($processId,$startTicks,$path)
    if($processId -ne 123 -or $startTicks -ne 456 -or $path -cne 'mock-client'){throw 'Capture lost its process identity.'}
    $frame=New-Object Drawing.Bitmap(400,300)
    $frame.SetPixel(200,150,[Drawing.Color]::FromArgb(211,131,4))
    $frame.SetPixel(232,150,[Drawing.Color]::FromArgb(7,223,79))
    return $frame
}
try {
    $client=New-Object WowAutoFight.Client
    $client.ProcessId=123;$client.StartTicks=456;$client.Path='mock-client';$client.Flavor='forerver'
    $observed=[WowAutoFight.Native]::ReadTame($client)
    Assert-Tame ($observed.State -eq 'matched' -and $observed.Combat -and $observed.TargetId -eq 65) 'Production reader did not sample the correct frame pixels.'
}finally{[WowAutoFight.Native]::FrameReader=$null}
Write-Output 'PASS: taming sequence, timed jumps, landing and capture/backward deferral, process/restart isolation, configuration atomicity, target/combat checks and both client protocols. No game input.'
