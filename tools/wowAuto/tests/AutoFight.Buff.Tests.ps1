$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot '..\autoFight.Engine.ps1')
function Assert-Buff($Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
$path=Join-Path ([IO.Path]::GetTempPath()) ('autoFight-buff-'+[guid]::NewGuid().ToString('N')+'.json')
try {
    $v6Profiles=@(foreach ($profile in (New-AutoFightProfiles).Values) {
        $fields=[ordered]@{}
        foreach ($field in $script:autoFightV6ProfileFields) {$fields[$field]=$profile.$field}
        $fields['EmergencyKey']='F9'
        $fields['CombatIntervalMs']=500
        [pscustomobject]$fields
    })
    $v6=[pscustomobject]@{Version=6;CommandIntervalMs=500;Common=(New-AutoFightCommon);Profiles=$v6Profiles} | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($path,$v6)
    $oldTarget=$v6 | ConvertFrom-Json
    $oldTarget.Common.TargetKey='F11'
    [IO.File]::WriteAllText($path,($oldTarget | ConvertTo-Json -Depth 5))
    Assert-Buff ((Read-AutoFightConfiguration $path).Common.TargetKey -eq 'F11') 'Disabled default buff key broke an existing F11 target binding.'
    [IO.File]::WriteAllText($path,$v6)
    $config=Read-AutoFightConfiguration $path
    Assert-Buff ($config.Profiles['titan:1'].BuffKey -eq 'F11' -and $config.Profiles['titan:1'].BuffIntervalSeconds -eq 0 -and
        $config.Profiles['forerver:11'].BuffCount -eq 1 -and [IO.File]::ReadAllText($path) -ceq $v6) 'V6 read-only migration changed or enabled a buff.'
    $config.Profiles['titan:9'].BuffKey='Ctrl+F11'
    $config.Profiles['titan:9'].BuffIntervalSeconds=60
    $config.Profiles['titan:9'].BuffCount=3
    $null=Save-AutoFightProfiles $path $config.Profiles 500 $config.Common
    $saved=Read-AutoFightConfiguration $path
    Assert-Buff ((Get-Content -Raw $path | ConvertFrom-Json).Version -eq 9 -and
        $saved.Profiles['titan:9'].BuffKey -eq 'Ctrl+F11' -and $saved.Profiles['titan:9'].BuffIntervalSeconds -eq 60 -and
        $saved.Profiles['titan:9'].BuffCount -eq 3 -and $saved.Profiles['forerver:9'].BuffIntervalSeconds -eq 0) 'Buff settings lost class/client isolation.'
    $original=[IO.File]::ReadAllText($path)
    foreach ($case in @(@('BuffIntervalSeconds',86401),@('BuffIntervalSeconds','1.5'),@('BuffCount',0),@('BuffCount',21),@('BuffKey','Tab'))) {
        $draft=Copy-AutoFightProfiles $saved.Profiles
        $draft['titan:9'].($case[0])=$case[1]
        $rejected=$false
        try {$null=Save-AutoFightProfiles $path $draft 500 $saved.Common} catch {$rejected=$true}
        Assert-Buff ($rejected -and [IO.File]::ReadAllText($path) -ceq $original) 'Invalid buff draft partially saved.'
    }
    $profile=Get-AutoFightEffectiveProfile $saved.Profiles['titan:9'] $saved.Common
    $profile.BuffIntervalSeconds=5
    $session=New-AutoFightSession 100 9
    Set-AutoFightBuffSchedule $session $profile 100 -AfterLogin
    $packet=[pscustomobject]@{ClassId=9;Flavor='titan';Action='idle';Recovery='none';Combat=$false;Busy=$false;EncounterId=1}
    Assert-Buff ((Get-AutoFightAction $session $packet $profile 100) -eq 'buff' -and $session.BuffRemaining -eq 3) 'Login did not trigger the first buff cycle.'
    Assert-Buff ((Get-AutoFightAction $session $packet $profile 300) -eq 'buff' -and $session.BuffRemaining -eq 3) 'Unsent buff advanced the cycle.'
    Complete-AutoFightAction $session $profile 'buff' 300
    Assert-Buff ($session.BuffRemaining -eq 2 -and $session.NextBuffAt -eq 1300 -and
        (Get-AutoFightAction $session $packet $profile 1299) -eq 'wait') 'Buff repeats sooner than one second after successful send.'
    $packet.Busy=$true
    Assert-Buff ((Get-AutoFightAction $session $packet $profile 1300) -eq 'wait') 'Buff interrupted a busy action.'
    $packet.Busy=$false;$packet.Combat=$true;$packet.Action='combat'
    Assert-Buff ((Get-AutoFightAction $session $packet $profile 1400) -ne 'buff' -and $session.BuffRemaining -eq 2) 'Buff ran in combat or lost remaining count.'
    $packet.Combat=$true;$packet.Action='waiting'
    Assert-Buff ((Get-AutoFightAction $session $packet $profile 1500) -ne 'buff') 'Buff displaced combat waiting.'
    $packet.Combat=$false;$packet.Action='idle'
    Assert-Buff ((Get-AutoFightAction $session $packet $profile 1600) -eq 'buff') 'Deferred buff did not resume after combat waiting.'
    Complete-AutoFightAction $session $profile 'buff' 1600
    Assert-Buff ((Get-AutoFightAction $session $packet $profile 2599) -eq 'wait' -and
        (Get-AutoFightAction $session $packet $profile 2600) -eq 'buff') 'Third buff ignored one-second spacing.'
    Complete-AutoFightAction $session $profile 'buff' 2600
    Assert-Buff ($session.BuffRemaining -eq 0 -and $session.NextBuffAt -eq 7600 -and
        (Get-AutoFightAction $session $packet $profile 7599) -eq 'wait' -and
        (Get-AutoFightAction $session $packet $profile 7600) -eq 'buff') 'Interval did not start a single new cycle after the last buff.'
    $profile.BuffIntervalSeconds=0
    Assert-Buff ((Get-AutoFightAction $session $packet $profile 7600) -eq 'wait' -and
        $session.NextBuffAt -eq [long]::MaxValue -and $session.BuffRemaining -eq 0) 'Disabling buff left a pending action.'
    $other=New-AutoFightSession 9000 9
    Set-AutoFightBuffSchedule $other $saved.Profiles['titan:9'] 9000 -AfterLogin
    Assert-Buff ($other.NextBuffAt -eq 9000 -and $session.NextBuffAt -eq [long]::MaxValue) 'Buff timer leaked between process sessions.'
    Write-Output 'PASS: V6 read-only migration, V9 per-class buff key/interval/count persistence and atomic validation; login/interval cycles, one-second successful-send spacing, unsafe-state deferral and process isolation. No native input.'
} finally {if ([IO.File]::Exists($path)) {[IO.File]::Delete($path)}}
