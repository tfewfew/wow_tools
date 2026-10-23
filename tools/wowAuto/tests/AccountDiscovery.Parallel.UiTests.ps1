# Live worker/queue topology with synthetic character screens and no real game input.
$discoveryConfigBytes=[IO.File]::ReadAllBytes($script:accountTasks.Path)
$discoveryAccounts=ConvertTo-TaskMap ($script:accountTasks.Config.Accounts | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
$discoveryNamesA=[ParallelFixture]::CharacterNames[101]
try {
    Stop-AllRows
    $roleA=@($script:accountTasks.Config.Accounts['titan:ACCOUNT-A'] | Where-Object Name -ceq '角色丙')[0]
    $roleA.Enabled=$false
    [ParallelFixture]::DiscoveryNames[101]='角色丙';[ParallelFixture]::DiscoveryNames[202]='角色甲';[ParallelFixture]::DiscoveryNames[303]='角色丙乙'
    $discoveryBefore=@{};foreach($row in $rows){$discoveryBefore[$row.Key]=[ParallelFixture]::DiscoveryReads[$row.Process.Id]}
    $startAllButton.PerformClick();Pump-Parallel {@($rows | Where-Object {$_.RuntimeRunning -and $_.CurrentRole -ceq '角色甲'}).Count -eq 3}
    foreach($row in $rows){Assert-Parallel ([ParallelFixture]::DiscoveryReads[$row.Process.Id] -eq $discoveryBefore[$row.Key]+1) 'Account discovery needed more than one anchored screen containing one unique known character.'}
    Assert-Parallel ($a.AccountName -ceq 'ACCOUNT-A' -and $c.AccountName -ceq 'ACCOUNT-B' -and -not $roleA.Enabled) 'An inactive character could not identify its account independently of enabled tasks.'
    Stop-AllRows;$roleA.Enabled=$true
    [ParallelFixture]::CharacterNames[101]=[ParallelFixture]::CharacterNames[303];[ParallelFixture]::DiscoveryNames[101]='角色丙乙'
    $a.Start.PerformClick()
    Assert-Parallel (-not $a.AccountName -and $a.AccountText.Text -match '识别中') 'A fresh start trusted the previous account instead of clearing its label.'
    Pump-Parallel {$a.CurrentRole -ceq '角色甲' -and $a.RuntimeRunning}
    Assert-Parallel ($a.AccountName -ceq 'ACCOUNT-B' -and $a.AccountText.Text -ceq 'ACCOUNT-B') 'The same process could not rediscover a different logged-in account.'
    $info=Get-WowAutoRunInfo;$entry=@($info.Processes | Where-Object Pid -eq 101)[0]
    Assert-Parallel ($entry.SubAccount -ceq 'ACCOUNT-B' -and $entry.SubAccountSource -eq 'ocr') 'Detected ownership was not included in the info snapshot.'
    $a.Stop.PerformClick()
    $b.Validated=$true;Set-RowControls $b;$beforeB=$b.ExecutionRound;$ocrB=[ParallelFixture]::Ocr[202];$b.DirectStart.PerformClick()
    Pump-Parallel {$b.ExecutionRound -gt $beforeB}
    [ParallelFixture]::DiscoveryBlockPid=101;[ParallelFixture]::DiscoveryBlockedPid=0;[ParallelFixture]::DiscoveryRelease.Reset()
    $a.Start.PerformClick();Pump-Parallel {[ParallelFixture]::DiscoveryBlockedPid -eq 101}
    $a.Stop.PerformClick();[ParallelFixture]::DiscoveryRelease.Set();[ParallelFixture]::DiscoveryBlockPid=0
    Pump-Parallel {-not $a.RuntimeRunning}
    Assert-Parallel (-not $a.AccountName -and $b.RuntimeRunning -and [ParallelFixture]::Ocr[202] -eq $ocrB) 'A cancelled ownership result applied or direct start triggered OCR/stopped another process.'
    [ParallelFixture]::CharacterNames[101]=$discoveryNamesA;[ParallelFixture]::DiscoveryNames[101]='角色甲'
    $clicks=[ParallelFixture]::Clicks;$arrows=[ParallelFixture]::UpCount
    $a.Start.PerformClick();Pump-Parallel {[ParallelFixture]::UpCount -gt $arrows}
    Assert-Parallel (-not $a.AccountName -and [ParallelFixture]::Clicks -eq $clicks) 'An account-shared character name guessed a binding or clicked a role.'
    $a.Stop.PerformClick()
    [ParallelFixture]::DiscoveryNames[101]='角色丙';[ParallelFixture]::DiscoveryBlockPid=101;[ParallelFixture]::DiscoveryBlockedPid=0;[ParallelFixture]::DiscoveryRelease.Reset()
    $a.Start.PerformClick();Pump-Parallel {[ParallelFixture]::DiscoveryBlockedPid -eq 101}
    $discoveryEditor=New-UnifiedSettingsDialog
    try {
        $discoveryEditor.Show($form);$discoveryEditor.Tag.Tabs.SelectedTab=$discoveryEditor.Tag.Accounts
        $clientEditor=$discoveryEditor.Tag.Accounts.Tag.Clients.titan
        (Get-ParallelRoleRow $clientEditor '角色丁').Cells['Enabled'].Value=$false
        $discoveryEditor.Tag.Accounts.Tag.Save.PerformClick()
        Assert-Parallel (-not $a.RuntimeRunning -and -not $a.AccountName -and $b.RuntimeRunning) 'Saving matching-client role settings failed to cancel unknown-account OCR or stopped a different client.'
    } finally {$discoveryEditor.Dispose();[ParallelFixture]::DiscoveryRelease.Set();[ParallelFixture]::DiscoveryBlockPid=0}
    $script:accountTasks.Config.Accounts=ConvertTo-TaskMap ($discoveryAccounts | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
    [IO.File]::WriteAllBytes($script:accountTasks.Path,$discoveryConfigBytes)
    foreach($role in $script:accountTasks.Config.Accounts['titan:ACCOUNT-B']){$role.Enabled=$false}
    [ParallelFixture]::CharacterNames[101]=[ParallelFixture]::CharacterNames[303];[ParallelFixture]::DiscoveryNames[101]='角色丙乙'
    $exits=[ParallelFixture]::ExitRequests;$a.Start.PerformClick()
    Pump-Parallel {$a.AccountName -ceq 'ACCOUNT-B' -and -not $a.RuntimeRunning}
    Assert-Parallel (-not $a.Exited -and [ParallelFixture]::ExitRequests -eq $exits -and $b.RuntimeRunning) 'Identified account with no enabled tasks exited the game or affected another process.'
    Assert-Parallel ([Convert]::ToBase64String([IO.File]::ReadAllBytes($script:accountTasks.Path)) -ceq [Convert]::ToBase64String($discoveryConfigBytes)) 'OCR discovery persisted a process binding or changed task configuration.'
    Write-Output 'PASS: single-character first-menu account discovery including inactive records, label/info, fresh-start account changes, stop/settings cancellation and stale OCR isolation, shared-name refusal, direct-start bypass and no-enabled-task stop without exit or automatic config writes. Game operations mocked.'
} finally {
    [ParallelFixture]::DiscoveryRelease.Set();[ParallelFixture]::DiscoveryBlockPid=0
    Stop-AllRows;$script:accountTasks.Config.Accounts=$discoveryAccounts
    [ParallelFixture]::CharacterNames[101]=$discoveryNamesA
    foreach($id in @(101,202,303)){[ParallelFixture]::DiscoveryNames[$id]=''}
    $a.Start.PerformClick();Pump-Parallel {$a.AccountName -ceq 'ACCOUNT-A' -and $a.CurrentRole -ceq '角色甲'}
    Stop-AllRows
}
