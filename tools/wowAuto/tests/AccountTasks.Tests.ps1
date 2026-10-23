$ErrorActionPreference='Stop'
$tool=Split-Path $PSScriptRoot -Parent
. (Join-Path $tool 'wowAuto.Accounts.ps1')
. (Join-Path $tool 'wowAuto.AccountTasks.ps1')
. (Join-Path $PSScriptRoot 'CharacterRecords.Fixtures.ps1')
function Assert-AccountTask($Condition,[string]$Message){if(-not $Condition){throw $Message}}
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-account-tasks-'+[guid]::NewGuid().ToString('N'))
$script:rotation=[pscustomobject]@{GameDirectories=@{titan=(Join-Path $temporary '_classic_titan_');forerver=(Join-Path $temporary '_cn_beta_')};OcrIntervalMs=900;Plans=@{}}
$script:scheduler=[pscustomobject]@{FocusRetryIntervalMs=17000;ReelHoldMs=140}
$script:autoFight=[pscustomobject]@{CommandGate=[pscustomobject]@{IntervalMs=1100};Common=[pscustomobject]@{InteractionHoldMs=2300}}
try {
    foreach($name in @('角色甲','角色乙','角色丙','角色丁','冲突角色','从未配置')){Write-TestCharacterRecord (Join-Path $script:rotation.GameDirectories.titan ('WTF\Account\ACCOUNT-A\测试服\'+$name)) $name '测试服'}
    foreach($flavor in @('titan','forerver')){Write-TestCharacterRecord (Join-Path $script:rotation.GameDirectories[$flavor] 'WTF\Account\SHARED\测试服\同名角色') '同名角色' '测试服'}
    $script:rotation.Plans=@{
        '11:1'=@{Account='ACCOUNT-A';Slots=@(@{Name='角色甲';Mode='fish';UseItem=$true},@{Name='角色乙';Mode='fight';UseItem=$false},@{Name='冲突角色';Mode='fish';UseItem=$false})};
        '12:1'=@{Account='ACCOUNT-A';Slots=@(@{Name='角色丙';Mode='fish';UseItem=$false},@{Name='角色丁';Mode='fight';UseItem=$false},@{Name='冲突角色';Mode='fight';UseItem=$false})};
        '13:1'=@{Account='SHARED';Slots=@(@{Name='同名角色';Mode='fish';UseItem=$true})}
    }
    $path=Join-Path $temporary 'account-tasks.json'
    [IO.File]::WriteAllText($path,(@{Version=1;Accounts=@{};Bindings=@{};Periods=(New-DetectionPeriods)} | ConvertTo-Json -Depth 12))
    $before=(Get-FileHash $path).Hash;Initialize-AccountTasks $path
    $roles=$script:accountTasks.Config.Accounts['titan:ACCOUNT-A'];$enabled=@($roles | Where-Object {$_.Enabled})
    Assert-AccountTask ($enabled.Count -eq 4 -and ($enabled | Where-Object {$_.Name -ceq '角色甲'}).UseItem -and ($enabled | Where-Object {$_.Name -ceq '角色乙'}).Mode -eq 'fight') 'Account migration lost tasks/items or retained the three-role limit.'
    Assert-AccountTask (-not ($roles | Where-Object {$_.Name -ceq '冲突角色'}).Enabled -and -not ($roles | Where-Object {$_.Name -ceq '从未配置'}).Enabled -and $script:accountTasks.Warnings.Count) 'Conflicting or new roles were silently enabled.'
    Assert-AccountTask (-not $script:accountTasks.Config.Accounts['titan:SHARED'][0].Enabled -and -not $script:accountTasks.Config.Accounts['forerver:SHARED'][0].Enabled) 'Ambiguous legacy client ownership leaked across clients.'
    Assert-AccountTask ($script:accountTasks.Config.Periods.OcrMs -eq 900 -and (Get-FileHash $path).Hash -eq $before) 'Read-only migration rewrote configuration or lost the old OCR interval.'
    $timing=$script:accountTasks.Config.Operations
    Assert-AccountTask ($timing.Count -eq 22 -and $timing.FocusRetryMs -eq 17000 -and $timing.ReelHoldMs -eq 140 -and $timing.CommandIntervalMs -eq 1100 -and $timing.InteractionHoldMs -eq 2300) 'Existing scattered timing settings were not migrated read-only.'
    foreach($case in @('missing','extra','type','range','click','retry')){
        $bad=$timing.Clone()
        switch($case){'missing'{$bad.Remove('KeyPressMs')}'extra'{$bad.Other=1}'type'{$bad.KeyPressMs='30'}'range'{$bad.KeyPressMs=0}'click'{$bad.ClickMinMs=500}'retry'{$bad.ForegroundRetryMs=1000}}
        $failed=$false;try{Test-OperationTimings $bad}catch{$failed=$true};Assert-AccountTask $failed ('Invalid operation timing accepted: '+$case)
    }
    $row=[pscustomobject]@{Client=[pscustomobject]@{Flavor='titan';ExecutablePath=(Join-Path $script:rotation.GameDirectories.titan 'WowClassic.exe')};AccountName='ACCOUNT-A'}
    Assert-AccountTask (@(Get-AccountTaskRoles $row).Count -eq 4) 'Account role membership filtering failed.'
    $row.AccountName=''
    $candidates=@(Get-AccountDiscoveryCandidates $row);$accountCandidate=@($candidates | Where-Object Account -ceq 'ACCOUNT-A')[0]
    Assert-AccountTask (@(Get-AccountTaskRoles $row).Count -eq 0 -and $accountCandidate.Roles.Count -eq 4 -and
        '从未配置' -cin $accountCandidate.Names -and '冲突角色' -cin $accountCandidate.Names) 'Discovery requires a manual binding or excludes inactive saved character records.'
    Assert-AccountTask (Test-AccountDiscoveryAvailable $row) 'An unknown process with configured same-client tasks cannot start discovery.'
    $row.Client.ExecutablePath='C:\another\_classic_titan_\WowClassic.exe';Assert-AccountTask (@(Get-AccountTaskRoles $row).Count -eq 0) 'Another installation inherited account tasks.'
    Assert-AccountTask (@(Get-AccountDiscoveryCandidates $row).Count -eq 0) 'Discovery leaked a different installation catalog.'
    Assert-AccountTask (-not (Test-AccountDiscoveryAvailable $row)) 'A different installation can start discovery.'
    foreach($invalid in @('period','switch','duplicate','unknown','partial')) {
        $next=ConvertTo-TaskMap ($script:accountTasks.Config | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
        switch($invalid) {
            'period' {$next.Periods.FishMs=24}
            'switch' {$next.Accounts['titan:ACCOUNT-A'][0].Enabled='true'}
            'duplicate' {$next.Accounts['titan:ACCOUNT-A']+=,$next.Accounts['titan:ACCOUNT-A'][0].Clone()}
            'unknown' {$next.Surprise='unsupported'}
            'partial' {$next.Periods.Remove('DeathMs')}
        }
        $failed=$false;try{Save-AccountTasks $next}catch{$failed=$true};Assert-AccountTask ($failed -and (Get-FileHash $path).Hash -eq $before) ('Invalid '+$invalid+' configuration was saved or partly applied.')
    }
    Save-AccountTasks;$saved=(Get-FileHash $path).Hash;Initialize-AccountTasks $path
    Assert-AccountTask ((Get-FileHash $path).Hash -eq $saved -and $script:accountTasks.Config.Accounts['titan:ACCOUNT-A'].Count -eq 6) 'Account-task save/reload changed data or rewrote the file.'
    $empty=@{Version=1;Accounts=@{};Bindings=@{};Periods=(New-DetectionPeriods)};$empty.Periods.OcrMs=1500
    Save-AccountTasks $empty;Initialize-AccountTasks $path
    Assert-AccountTask ($script:accountTasks.Config.Periods.OcrMs -eq 1500 -and -not @($script:accountTasks.Config.Accounts['titan:ACCOUNT-A'] | Where-Object {$_.Enabled}).Count) 'A saved empty profile reapplied legacy OCR settings or re-enabled old roles.'
    Write-Output 'PASS: read-only account-scoped legacy migration, more than three roles, preserved modes/items/OCR period, disabled conflicts/new/cross-client ambiguous roles, installation membership, schema/period/switch/duplicate validation and atomic save/reload. Temporary records only.'
}finally {
    $resolved=[IO.Path]::GetFullPath($temporary)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'wowAuto-account-tasks-*'){throw 'Unsafe account test cleanup'}
    if([IO.Directory]::Exists($resolved)){[IO.Directory]::Delete($resolved,$true)}
}
