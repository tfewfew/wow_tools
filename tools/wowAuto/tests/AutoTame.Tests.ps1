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
$path=Join-Path ([IO.Path]::GetTempPath()) ('wow-tame-test-'+[guid]::NewGuid()+'.json')
try {
    Assert-Tame (-not (Read-AutoTameConfig $path).TameKey) 'Missing config invented a capture key.'
    $legacy=$config | Select-Object * -ExcludeProperty BackwardHoldMs
    [IO.File]::WriteAllText($path,($legacy | ConvertTo-Json))
    $legacyContent=[IO.File]::ReadAllText($path)
    Assert-Tame ((Read-AutoTameConfig $path).BackwardHoldMs -eq 0 -and [IO.File]::ReadAllText($path) -ceq $legacyContent) 'Legacy config did not retain short-press behavior without rewriting.'
    $null=Save-AutoTameConfig $path $config
    Assert-Tame ((Read-AutoTameConfig $path).TameWaitMs -eq 10000 -and (Read-AutoTameConfig $path).BackwardHoldMs -eq 250) 'Config round trip failed.'
    $before=[IO.File]::ReadAllText($path)
    foreach($bad in @('empty','invalid','negative','zero-repeat','negative-hold','long-hold','invalid-hold')) {
        $draft=$config | ConvertTo-Json | ConvertFrom-Json
        switch($bad){'empty'{$draft.TameKey=''}'invalid'{$draft.TrapKey='Ctrl+Ctrl+A'}'negative'{$draft.BackwardWaitMs=-1}'zero-repeat'{$draft.TameWaitMs=0}}
        switch($bad){'negative-hold'{$draft.BackwardHoldMs=-1}'long-hold'{$draft.BackwardHoldMs=60001}'invalid-hold'{$draft.BackwardHoldMs='invalid'}}
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
Write-Output 'PASS: taming sequence, acknowledgement timing, optional stages, repeat boundaries, combat exit, target changes/loss, config atomicity and both client protocols. No game input.'
