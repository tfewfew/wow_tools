# Read account folders and the addon's own character snapshots, never login credentials.
function ConvertFrom-WowCharacterRecord([string]$Text) {
    # Parse only our flat data table. SavedVariables are never executed.
    if ($Text.Length -gt 64KB) {return $null}
    $table=[regex]::Match($Text,'\A\s*wowToolsCharacterRecord\s*=\s*\{(?<body>[^{}]*)\}\s*\z')
    if (-not $table.Success) {return $null}
    $body=$table.Groups['body'].Value;$position=0;$values=@{}
    $field='\G\s*(?:\["(?<key>[A-Za-z]\w*)"\]|(?<key>[A-Za-z]\w*))\s*=\s*(?:"(?<text>(?:[^"\\\r\n]|\\(?:["\\nrt]|\d{1,3}))*)"|(?<number>-?\d+))\s*(?:,|\z)'
    $reader=[regex]::new($field,[Text.RegularExpressions.RegexOptions]::None,[timespan]::FromSeconds(1))
    try {
        while ($position -lt $body.Length -and $body.Substring($position).Trim()) {
            $match=$reader.Match($body,$position)
            if (-not $match.Success -or $match.Index -ne $position) {return $null}
            $key=$match.Groups['key'].Value
            if ($key -cnotin @('version','name','realm','level','freeBagSlots','recordedAt') -or $values.ContainsKey($key)) {return $null}
            if ($key -cin @('name','realm')) {
                if (-not $match.Groups['text'].Success) {return $null}
                $values[$key]=[regex]::Replace($match.Groups['text'].Value,'\\(?<escape>\d{1,3}|.)',{
                    param($escape)
                    $value=$escape.Groups['escape'].Value
                    switch ($value) {
                        'n' {return "`n"} 'r' {return "`r"} 't' {return "`t"}
                        '"' {return '"'} '\' {return '\'}
                        default {if ([int]$value -gt 255) {throw 'Invalid Lua string escape.'};return [string][char][int]$value}
                    }
                })
            } else {
                $number=0L
                if (-not $match.Groups['number'].Success -or -not [long]::TryParse($match.Groups['number'].Value,[ref]$number)) {return $null}
                $values[$key]=$number
            }
            $position=$match.Index+$match.Length
        }
        if ($values.Count -ne 6 -or $values.version -ne 1 -or $values.name -notmatch '^[\p{L}\p{M}]{1,24}$' -or
            -not $values.realm -or $values.realm.Length -gt 128 -or $values.realm -match '[\p{C}\\/]' -or
            $values.level -lt 0 -or $values.level -gt 1000 -or $values.freeBagSlots -lt -1 -or $values.freeBagSlots -gt 11000 -or
            $values.recordedAt -lt 1 -or $values.recordedAt -gt 253402300799) {return $null}
        return [pscustomobject]@{Name=$values.name;Realm=$values.realm;
            Level=$(if ($values.level -gt 0) {$values.level} else {$null});
            FreeBagSlots=$(if ($values.freeBagSlots -ge 0) {$values.freeBagSlots} else {$null});RecordedAt=$values.recordedAt}
    } catch {return $null}
}
function Read-WowCharacterRecord([string]$CharacterDirectory,[string]$Name,[string]$Realm) {
    try {
        $saved=Join-Path $CharacterDirectory 'SavedVariables';$path=Join-Path $saved 'wow_tools.lua'
        foreach ($itemPath in @($saved,$path)) {
            $item=Get-Item -LiteralPath $itemPath -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {return $null}
        }
        if ($item.Length -gt 64KB) {return $null}
        $text=[IO.File]::ReadAllText($path)
        $record=ConvertFrom-WowCharacterRecord $text
        if (-not $record -or $record.Name -cne $Name -or $record.Realm -cne $Realm) {return $null}
        return $record
    } catch {return $null}
}
function ConvertTo-RotationGameDirectories($Value) {
    $roots=@{}
    $keys=if ($Value -is [Collections.IDictionary]) {@($Value.Keys)} else {@($Value.PSObject.Properties.Name)}
    if ($keys.Count -ne 2 -or @($keys | Where-Object {$_ -cnotin @('titan','forerver')}).Count) {throw '游戏目录须分别配置两服。'}
    foreach ($flavor in @('titan','forerver')) {
        $path=$Value.$flavor
        if ($path -isnot [string] -or $path -match '[\p{C}]' -or ($path -and -not [IO.Path]::IsPathRooted($path))) {throw '游戏目录格式无效。'}
        # Reading existing config does not require the disk/client to be online.
        $roots[$flavor]=$path
    }
    return $roots
}
function Set-RowSlotTask($Row,$Slot) {
    $Row.SlotUseItem=$Slot.Mode -eq 'fish' -and $Slot.PSObject.Properties['UseItem'] -and [bool]$Slot.UseItem
    Set-RowTaskMode $Row $Slot.Mode
}
function Get-WowAccountCatalog([string]$GameDirectory) {
    $accounts=@()
    if (-not $GameDirectory) {return $accounts}
    $root=Join-Path $GameDirectory 'WTF\Account'
    if (-not [IO.Directory]::Exists($root)) {return $accounts}
    foreach ($account in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction Stop | Sort-Object Name)) {
        if ($account.Name -eq 'SavedVariables' -or ($account.Attributes -band [IO.FileAttributes]::ReparsePoint)) {continue}
        $characters=@()
        foreach ($realm in @(Get-ChildItem -LiteralPath $account.FullName -Directory -ErrorAction Stop)) {
            if ($realm.Name -eq 'SavedVariables' -or ($realm.Attributes -band [IO.FileAttributes]::ReparsePoint)) {continue}
            foreach ($role in @(Get-ChildItem -LiteralPath $realm.FullName -Directory -ErrorAction Stop)) {
                if ($role.Name -notmatch '^[\p{L}\p{M}]{1,24}$' -or $role.Name -eq 'SavedVariables' -or ($role.Attributes -band [IO.FileAttributes]::ReparsePoint)) {continue}
                $record=Read-WowCharacterRecord $role.FullName $role.Name $realm.Name
                if ($record) {$characters+=,$record}
            }
        }
        # Empty accounts are selectable too, but do not invent character names for them.
        $accounts+=,[pscustomobject]@{Name=$account.Name;Characters=$characters}
    }
    return $accounts
}
function Resolve-WowGameDirectory([string]$Path,[string]$Flavor) {
    if ($Flavor -cnotin @('titan','forerver')) {throw '客户端版本无效。'}
    if (-not $Path.Trim()) {return ''}
    if (-not [IO.Path]::IsPathRooted($Path)) {throw '游戏目录须为绝对路径。'}
    $full=[IO.Path]::GetFullPath($Path.Trim())
    if ($full -ne [IO.Path]::GetPathRoot($full)) {$full=$full.TrimEnd('\','/')}
    $product=if ($Flavor -eq 'titan') {'_classic_titan_'} else {'_cn_beta_'}
    if ((Split-Path $full -Leaf) -ne $product) {$full=Join-Path $full $product}
    $exe=Join-Path $full $(if ($Flavor -eq 'titan') {'WowClassic.exe'} else {'Wow.exe'})
    if (-not [IO.File]::Exists($exe)) {throw "目录内没有对应客户端：$exe"}
    $version=[Diagnostics.FileVersionInfo]::GetVersionInfo($exe).FileVersion
    if ([WowAuto.NativeInput]::GetClientFlavor($exe,$version) -ne $Flavor) {throw '游戏目录与所选版本不符。'}
    return $full
}
function Get-RowAccounts($Row) {
    $root=$script:rotation.GameDirectories[$Row.Client.Flavor]
    if ($root -and -not [string]::Equals([IO.Path]::GetFullPath($root).TrimEnd('\','/'),(Split-Path $Row.Client.ExecutablePath -Parent),[StringComparison]::OrdinalIgnoreCase)) {
        throw '进程的客户端目录与设置中的游戏目录不一致，请修改对应版本的目录。'
    }
    return @(Get-WowAccountCatalog $root)
}
function Get-RowAccountNames($Row,[string]$Account=$Row.AccountName) {
    $entry=@(Get-RowAccounts $Row | Where-Object {$_.Name -ceq $Account})
    if ($entry.Count -ne 1) {return @()}
    return @($entry[0].Characters.Name | Sort-Object -Unique)
}
function Test-RowAccountPlan($Row,$Plan,[string]$Account=$Row.AccountName) {
    $accounts=@(Get-RowAccounts $Row)
    if (-not $Account -or -not @($accounts | Where-Object {$_.Name -ceq $Account}).Count) {throw '请设置游戏目录，并为当前进程选择存在的子战网。'}
    $names=@(Get-RowAccountNames $Row $Account)
    foreach ($slot in $Plan.Slots) {
        if ($slot.Name -and $slot.Name -cnotin $names) {throw "子战网 $Account 的插件记录中没有角色：$($slot.Name)。请登录该角色，启动钓鱼或战斗检测后正常下线，再刷新。"}
    }
}
function Update-RowAccountChoices($Row) {
    if (-not $Row.PSObject.Properties['AccountBox']) {return}
    $Row.UpdatingAccount=$true
    try {
        $accounts=@(Get-RowAccounts $Row)
        $plan=Get-RowRotationPlan $Row
        $selected=if ($plan.PSObject.Properties['Account']) {[string]$plan.Account} else {''}
        # A sole account or a uniquely matching legacy plan is safe to suggest; timestamps are not process identity.
        if (-not $plan.PSObject.Properties['Account']) {
            $used=@($plan.Slots | Where-Object {$_.Name} | ForEach-Object {$_.Name})
            $candidates=@($accounts | Where-Object {
                $names=@($_.Characters.Name)
                -not @($used | Where-Object {$_ -cnotin $names}).Count
            })
            if ($candidates.Count -eq 1) {$selected=$candidates[0].Name}
        }
        $Row.AccountBox.Items.Clear();[void]$Row.AccountBox.Items.Add('请选择子战网')
        foreach ($account in $accounts) {[void]$Row.AccountBox.Items.Add($account.Name)}
        $Row.AccountName=$selected
        $Row.AccountBox.SelectedIndex=if ($selected -and $Row.AccountBox.Items.Contains($selected)) {$Row.AccountBox.Items.IndexOf($selected)} else {0}
        $Row.AccountHint.Text=if ($selected -and $Row.AccountBox.SelectedIndex -eq 0) {'已保存子战网不存在，请重新选择'} else {'角色列表来自所选子战网的插件下线记录'}
    } catch {
        $Row.AccountName='';$Row.AccountBox.Items.Clear();[void]$Row.AccountBox.Items.Add('请选择子战网');$Row.AccountBox.SelectedIndex=0
        $Row.AccountHint.Text='账号目录读取失败：'+$_.Exception.Message
    } finally {$Row.UpdatingAccount=$false}
}
function Add-RowAccountControls($Row) {
    $Row | Add-Member NoteProperty AccountName ''
    $Row | Add-Member NoteProperty UpdatingAccount $false
    $label=New-Object System.Windows.Forms.Label;$label.Text='子战网';$label.SetBounds(165,106,80,28)
    $box=New-Object System.Windows.Forms.ComboBox;$box.DropDownStyle='DropDownList';$box.SetBounds(245,102,260,34)
    $box.BackColor=$script:uiColors.Input;$box.ForeColor=$script:uiColors.Text;$box.FlatStyle='Flat'
    $hint=New-Object System.Windows.Forms.Label;$hint.SetBounds(520,106,700,30);$hint.AutoEllipsis=$true
    $Row | Add-Member NoteProperty AccountBox $box;$Row | Add-Member NoteProperty AccountHint $hint
    $Row.Panel.Controls.AddRange([System.Windows.Forms.Control[]]@($label,$box,$hint));$box.Tag=$Row
    Update-RowAccountChoices $Row
    $box.Add_SelectedIndexChanged({param($sender,$e)
        $row=$sender.Tag;if ($row.UpdatingAccount -or $sender.SelectedIndex -lt 0) {return}
        try {
            $account=if ($sender.SelectedIndex -gt 0) {[string]$sender.SelectedItem} else {''}
            $plan=Copy-RotationPlan (Get-RowRotationPlan $row)
            $plan | Add-Member NoteProperty Account $account -Force
            # Preserve old slots visibly; invalid names must be corrected in the editor before starting.
            $next=$script:rotation.Plans.Clone();$next[$row.Key]=$plan
            Save-RotationConfiguration -Plans $next
            Stop-Row $row '子战网已保存，任务停止；请核对角色编排后开始。' -CancelExit
            $row.Validated=$false;Update-RowAccountChoices $row;Set-RowControls $row
        } catch {$message=$_.Exception.Message;Update-RowAccountChoices $row;$row.AccountHint.Text='子战网保存失败：'+$message}
    })
}
function New-GameDirectorySettingsPage {
    $page=New-Object System.Windows.Forms.TabPage;$page.Text='游戏目录';$page.BackColor=$script:uiColors.Background;$page.AutoScroll=$true
    $hint=New-Object System.Windows.Forms.Label;$hint.Text='选择客户端目录，或包含客户端的魔兽世界总目录。读取 WTF\\Account 下的子战网及插件角色记录；账号归属由每个进程的子战网选项指定。';$hint.SetBounds(20,20,920,70);$page.Controls.Add($hint)
    $inputs=@{}
    $i=0
    foreach ($flavor in @('titan','forerver')) {
        $y=110+$i*95;$i++
        $label=New-Object System.Windows.Forms.Label;$label.Text=if ($flavor -eq 'titan') {'时光服目录'} else {'无限服目录'};$label.SetBounds(20,$y,140,32)
        $text=New-Object System.Windows.Forms.TextBox;$text.Text=$script:rotation.GameDirectories[$flavor];$text.SetBounds(165,$y,620,34);$text.BackColor=$script:uiColors.Input;$text.ForeColor=$script:uiColors.Text
        $browse=New-Object WowAuto.DimButton;$browse.Text='浏览';$browse.SetBounds(805,$y,100,34);Set-UiButtonStyle $browse;$browse.Tag=$text
        $browse.Add_Click({param($sender,$e)
            $picker=New-Object System.Windows.Forms.FolderBrowserDialog
            try {$picker.SelectedPath=$sender.Tag.Text;if ($picker.ShowDialog($sender.FindForm()) -eq 'OK') {$sender.Tag.Text=$picker.SelectedPath}} finally {$picker.Dispose()}
        })
        $inputs[$flavor]=$text;$page.Controls.AddRange([System.Windows.Forms.Control[]]@($label,$text,$browse))
    }
    $errorLabel=New-Object System.Windows.Forms.Label;$errorLabel.SetBounds(20,305,900,110)
    $errorLabel.Text='角色列表只显示有插件下线记录的角色。请先登录角色，启动过钓鱼或战斗检测后正常下线，再刷新。等级与背包空格为最近下线快照。留空可停用该版本扫描。'
    $save=New-Object WowAuto.DimButton;$save.Text='保存游戏目录';$save.SetBounds(20,440,180,38);Set-UiButtonStyle $save $true
    $page.Tag=[pscustomobject]@{Inputs=$inputs;Error=$errorLabel;Save=$save};$save.Tag=$page
    $save.Add_Click({param($sender,$e)
        $editor=$sender.Tag.Tag
        try {
            $roots=@{};foreach ($flavor in @('titan','forerver')) {$roots[$flavor]=Resolve-WowGameDirectory $editor.Inputs[$flavor].Text $flavor;[void](Get-WowAccountCatalog $roots[$flavor])}
            Save-RotationConfiguration -GameDirectories $roots
            foreach ($row in $script:rows.Values) {Stop-Row $row '游戏目录已保存，请核对子战网和角色编排。' -CancelExit;$row.Validated=$false;Update-RowAccountChoices $row}
            foreach ($flavor in @('titan','forerver')) {$editor.Inputs[$flavor].Text=$roots[$flavor]}
            $editor.Error.Text='游戏目录已保存，子战网列表已刷新。'
        } catch {$editor.Error.Text=$_.Exception.Message}
    })
    $page.Controls.AddRange([System.Windows.Forms.Control[]]@($errorLabel,$save));return $page
}
