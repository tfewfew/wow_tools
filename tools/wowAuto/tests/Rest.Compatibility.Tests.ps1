$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\wowAuto.AccountTasks.ps1')
. (Join-Path $PSScriptRoot '..\wowAuto.AccountTasks.Ui.ps1')

function Assert-RestContract($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

# Validate persisted data and cross-module contracts without running a task or sending input.
$legacy = @{Version=1;Accounts=@{};Bindings=@{};Periods=(New-DetectionPeriods)}
Test-AccountTaskConfiguration $legacy
Assert-RestContract (-not $legacy.ContainsKey('Rest')) 'Reading an old configuration added a persisted field.'
$config = ConvertTo-TaskMap ($legacy | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
$config.Rest = New-RestTaskSettings
$config.Accounts['forerver:TEST'] = @(@{Name='测试角色';Realm='测试服务器';Mode='rest';Enabled=$true;UseItem=$false})
Test-AccountTaskConfiguration $config
$decoded = ConvertTo-TaskMap ($config | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
Test-AccountTaskConfiguration $decoded
Assert-RestContract ($decoded.Rest.DurationSeconds -eq 600 -and $decoded.Rest.Rounds -eq 5 -and
    $decoded.Rest.JumpIntervalSeconds -eq 60 -and $decoded.Accounts['forerver:TEST'][0].Mode -ceq 'rest') 'The rest configuration JSON contract lost units or task identity.'
Assert-RestContract ((Get-AccountTaskModeLabel 'rest') -ceq '放号') 'The rest mode label is unavailable.'

$invalid = @()
foreach ($key in @('DurationSeconds','Rounds','JumpIntervalSeconds')) {
    foreach ($value in @(0, -1, 1.5, $true, '600')) {
        $settings = New-RestTaskSettings
        $settings[$key] = $value
        $invalid += ,$settings
    }
}
$invalid += ,@{DurationSeconds=600;Rounds=5}
$invalid += ,@{DurationSeconds=600;Rounds=5;JumpIntervalSeconds=60;Unknown=1}
foreach ($settings in $invalid) {
    $rejected = $false
    try { Test-RestTaskSettings $settings } catch { $rejected = $true }
    Assert-RestContract $rejected 'Invalid rest settings were accepted.'
}
foreach ($variation in @('titan', 'item')) {
    $invalidConfig = ConvertTo-TaskMap ($config | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
    if ($variation -eq 'titan') {
        $invalidConfig.Accounts['titan:TEST'] = $invalidConfig.Accounts['forerver:TEST']
        $invalidConfig.Accounts.Remove('forerver:TEST')
    } else { $invalidConfig.Accounts['forerver:TEST'][0].UseItem = $true }
    $rejected = $false
    try { Test-AccountTaskConfiguration $invalidConfig } catch { $rejected = $true }
    Assert-RestContract $rejected 'The rest server or item compatibility contract was bypassed.'
}

$grid = [pscustomobject]@{Rows=@([pscustomobject]@{
    Tag=@{Name='测试角色';Realm='测试服务器'}
    Cells=@{Enabled=@{Value=$true};Mode=@{Value='放号'};UseItem=@{Value=$true}}
})}
$grid | Add-Member ScriptMethod EndEdit { return $true }
$editor = [pscustomobject]@{Selected='forerver:TEST';Draft=$decoded;Grids=@($grid)}
Save-AccountGridDraft $editor
Assert-RestContract ($decoded.Accounts['forerver:TEST'][0].Mode -ceq 'rest' -and
    -not $decoded.Accounts['forerver:TEST'][0].UseItem) 'The role editor did not preserve rest task identity.'
$priorities = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\action-priorities.json')) | ConvertFrom-Json
Assert-RestContract ($priorities.Events.'Rest.Jump' -is [int] -and $priorities.Events.'Rest.Jump' -eq 80) 'The rest jump operation priority is missing.'
Write-Output 'PASS: rest configuration schema, legacy JSON compatibility, Forever-only task and role editor contracts.'
