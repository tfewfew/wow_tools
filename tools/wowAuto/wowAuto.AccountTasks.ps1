# Account-scoped task configuration. Loading and legacy migration never rewrite user files.
. (Join-Path $PSScriptRoot 'wowAuto.Timing.ps1')
function ConvertTo-TaskMap($Value) {
    if ($Value -is [Collections.IDictionary]) {$map=@{};foreach($key in $Value.Keys){$map[$key]=ConvertTo-TaskMap $Value[$key]};return $map}
    if ($Value -is [pscustomobject]) {$map=@{};foreach($property in $Value.PSObject.Properties){$map[$property.Name]=ConvertTo-TaskMap $property.Value};return $map}
    if ($Value -is [array]) {return ,@($Value | ForEach-Object {ConvertTo-TaskMap $_})}
    return $Value
}
function New-DetectionPeriods {
    return @{FishMs=100;FightMs=1000;MenuMs=300;LoginMs=300;BaitMs=300;DeathMs=1000;AudioMs=50;PositionMs=1000;CaptureRetryMs=100;OcrMs=1000}
}
function Test-AccountTaskConfiguration($Config) {
    if ($Config.Version -isnot [int] -or $Config.Version -ne 1 -or $Config.Accounts -isnot [Collections.IDictionary] -or $Config.Bindings -isnot [Collections.IDictionary] -or
        @($Config.Keys | Where-Object {$_ -cnotin @('Version','MigrationComplete','Accounts','Bindings','Periods','Operations')}).Count) {throw '子战网任务配置格式无效。'}
    if($Config.ContainsKey('Operations')){Test-OperationTimings $Config.Operations}
    if($Config.ContainsKey('MigrationComplete') -and $Config.MigrationComplete -isnot [bool]){throw '旧配置迁移标识无效。'}
    $defaults=New-DetectionPeriods
    if ($Config.Periods -isnot [Collections.IDictionary] -or $Config.Periods.Count -ne $defaults.Count) {throw '检测周期配置不完整。'}
    foreach($key in $defaults.Keys) {
        $value=$Config.Periods[$key]
        if ($value -isnot [int] -or $value -lt 25 -or $value -gt 60000) {throw "$key 检测周期须为25–60000ms整数。"}
    }
    foreach($key in $Config.Accounts.Keys) {
        if ($key -notmatch '^(titan|forerver):([^\\/\p{C}]+)$') {throw '子战网任务标识无效。'}
        if($Config.Accounts[$key] -isnot [array]){throw '子战网角色任务必须为列表。'}
        $names=@{}
        foreach($role in $Config.Accounts[$key]) {
            if ($role.Name -isnot [string] -or $role.Name -notmatch '^[\p{L}\p{M}]{1,24}$' -or
                $role.Realm -isnot [string] -or -not $role.Realm -or $role.Realm -match '[\\/\p{C}]' -or
                $role.Mode -cnotin @('fish','fight') -or $role.Enabled -isnot [bool] -or $role.UseItem -isnot [bool]) {throw '角色任务字段无效。'}
            if($role.Keys.Count -ne 5 -or @($role.Keys | Where-Object {$_ -cnotin @('Name','Realm','Mode','Enabled','UseItem')}).Count){throw '角色任务存在未知字段。'}
            $identity=$role.Realm+'|'+$role.Name
            if ($names.ContainsKey($identity)) {throw '子战网角色记录重复。'};$names[$identity]=$true
        }
        $enabled=@($Config.Accounts[$key] | Where-Object {$_.Enabled})
        if (@($enabled | Group-Object {$_.Name} | Where-Object Count -gt 1).Count) {throw '同一子战网存在跨服务器同名的已启用角色，OCR无法唯一定位，请只启用其中一个。'}
    }
    foreach($key in $Config.Bindings.Keys) {
        $binding=$Config.Bindings[$key]
        if ($key -notmatch '^[1-9]\d*:[1-9]\d*$' -or $binding.Flavor -cnotin @('titan','forerver') -or
            $binding.Account -isnot [string] -or $binding.Account -match '[\\/\p{C}]') {throw '进程与子战网绑定格式无效。'}
        if($binding.Keys.Count -ne 2 -or @($binding.Keys | Where-Object {$_ -cnotin @('Flavor','Account')}).Count){throw '进程绑定存在未知字段。'}
    }
}
function Initialize-AccountTasks([string]$Path=(Join-Path $PSScriptRoot 'account-tasks.config.json')) {
    $config=@{Version=1;Accounts=@{};Bindings=@{};Periods=(New-DetectionPeriods)}
    if ([IO.File]::Exists($Path)) {$config=ConvertTo-TaskMap ([IO.File]::ReadAllText($Path) | ConvertFrom-Json);Test-AccountTaskConfiguration $config}
    if(-not $config.ContainsKey('Operations')){$config.Operations=Get-LegacyOperationTimings}
    Test-OperationTimings $config.Operations
    if(-not $config.MigrationComplete -and -not $config.Accounts.Count -and $script:rotation.OcrIntervalMs){$config.Periods.OcrMs=[int]$script:rotation.OcrIntervalMs}
    $script:accountTasks=[pscustomobject]@{Path=$Path;Config=$config;Catalog=@{};Warnings=@()}
    Update-AccountTaskCatalog
}
function Update-AccountTaskCatalog {
    $catalog=@{}
    $byFlavor=@{};foreach($flavor in @('titan','forerver')){$byFlavor[$flavor]=@(Get-WowAccountCatalog $script:rotation.GameDirectories[$flavor])}
    foreach($flavor in @('titan','forerver')) {
        foreach($account in $byFlavor[$flavor]) {
            $key=$flavor+':'+$account.Name;$catalog[$key]=$account
            if (-not $script:accountTasks.Config.Accounts.ContainsKey($key)) {
                $roles=@(foreach($record in $account.Characters) {
                    # A conflicting legacy name/task is disabled for explicit review in Settings.
                    $legacy=@(foreach($plan in $script:rotation.Plans.Values) {if ($plan.Account -ceq $account.Name) {$plan.Slots | Where-Object {$_.Name -ceq $record.Name}}})
                    if($script:accountTasks.Config.MigrationComplete){$legacy=@()}
                    $modes=@($legacy.Mode | Sort-Object -Unique)
                    $ambiguous=@($account.Characters | Where-Object Name -ceq $record.Name).Count -gt 1
                    $other=if($flavor -eq 'titan'){'forerver'}else{'titan'}
                    if(@($byFlavor[$other] | Where-Object {$_.Name -ceq $account.Name}).Count){$ambiguous=$true}
                    if ($modes.Count -gt 1) {$script:accountTasks.Warnings+=($key+' / '+$record.Name+'：旧任务冲突，已停用，请核对。')}
                    @{Name=$record.Name;Realm=$record.Realm;Mode=$(if($modes.Count -eq 1){$modes[0]}else{'fish'});
                        Enabled=($legacy.Count -gt 0 -and $modes.Count -eq 1 -and -not $ambiguous);
                        UseItem=($modes.Count -eq 1 -and $modes[0] -eq 'fish' -and @($legacy | Where-Object UseItem).Count -gt 0)}
                })
                $script:accountTasks.Config.Accounts[$key]=$roles
            } else {
                # Newly recorded characters appear disabled; never silently enable a new role.
                foreach($record in $account.Characters) {
                    if (-not @($script:accountTasks.Config.Accounts[$key] | Where-Object {$_.Name -ceq $record.Name -and $_.Realm -ceq $record.Realm}).Count) {
                        $script:accountTasks.Config.Accounts[$key]+=,@{Name=$record.Name;Realm=$record.Realm;Mode='fish';Enabled=$false;UseItem=$false}
                    }
                }
            }
        }
    }
    $script:accountTasks.Catalog=$catalog
}
function Save-AccountTasks($Config=$script:accountTasks.Config) {
    Test-AccountTaskConfiguration $Config
    # The editor continues to live after Save; do not make its mutable draft the active configuration.
    $snapshot=ConvertTo-TaskMap ($Config | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
    if(-not $snapshot.ContainsKey('Operations')){$snapshot.Operations=if($script:accountTasks.Config.Operations){ConvertTo-TaskMap $script:accountTasks.Config.Operations}else{Get-LegacyOperationTimings}}
    Test-OperationTimings $snapshot.Operations
    $snapshot.MigrationComplete=$true
    $temporary=$script:accountTasks.Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temporary,($snapshot | ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($false)))
        if([IO.File]::Exists($script:accountTasks.Path)){[IO.File]::Replace($temporary,$script:accountTasks.Path,[System.Management.Automation.Language.NullString]::Value)}
        else{[IO.File]::Move($temporary,$script:accountTasks.Path)}
        $script:accountTasks.Config=$snapshot
    } finally {if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
function Get-AccountTaskSignature($Roles) {
    return ConvertTo-Json -InputObject @($Roles | ForEach-Object {[ordered]@{Name=$_.Name;Realm=$_.Realm;Mode=$_.Mode;Enabled=$_.Enabled;UseItem=$_.UseItem}}) -Depth 6 -Compress
}
function Get-AccountTaskRoles($Row) {
    $root=$script:rotation.GameDirectories[$Row.Client.Flavor]
    if($root -and -not [string]::Equals([IO.Path]::GetFullPath($root).TrimEnd('\','/'),(Split-Path $Row.Client.ExecutablePath -Parent),[StringComparison]::OrdinalIgnoreCase)){return @()}
    $key=$Row.Client.Flavor+':'+$Row.AccountName
    if (-not $script:accountTasks.Config.Accounts.ContainsKey($key) -or -not $script:accountTasks.Catalog.ContainsKey($key)) {return @()}
    $records=$script:accountTasks.Catalog[$key].Characters
    return @($script:accountTasks.Config.Accounts[$key] | Where-Object {
        $role=$_;$role.Enabled -and @($records | Where-Object {$_.Name -ceq $role.Name -and $_.Realm -ceq $role.Realm}).Count
    })
}
