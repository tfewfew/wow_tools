# Production UI and account discovery against temporary client trees. No game operations.
Stop-AllRows
Initialize-AutoFightTab $tabs $form -Unified
$savedAccountState=@{Path=$script:rotation.Path;Plans=$script:rotation.Plans;Roots=$script:rotation.GameDirectories;History=$script:rotation.NameHistory;Interval=$script:rotation.IntervalSeconds;Items=$script:processItemPreferences}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-account-ui-'+[Guid]::NewGuid())
$script:rotation.Path=Join-Path $fixture 'rotation.json';$script:rotation.Plans=@{};$script:rotation.NameHistory=@()
$script:rotation.GameDirectories=@{};$script:rotation.IntervalSeconds=0
$row=@($script:rows.Values | Sort-Object {$_.Process.Id})[0]
$oldPath=$row.Process.ExecutablePath;$oldClientPath=$row.Client.ExecutablePath
try {
    foreach ($flavor in @('titan','forerver')) {
        $product=if ($flavor -eq 'titan') {'_classic_titan_'} else {'_cn_beta_'}
        $game=Join-Path $fixture $product;$script:rotation.GameDirectories[$flavor]=$game
        foreach ($spec in @(@('ACCOUNT#1','RealmA','钓鱼角色'),@('ACCOUNT#1','RealmB','战斗角色'),@('ACCOUNT#1','RealmB','钓鱼角色'),@('ACCOUNT#2','RealmA','另一个角色'))) {
            [void][IO.Directory]::CreateDirectory((Join-Path $game ('WTF\Account\'+($spec -join '\'))))
        }
        [void][IO.Directory]::CreateDirectory((Join-Path $game 'WTF\Account\SavedVariables\FalseRealm\虚假角色'))
        [void][IO.Directory]::CreateDirectory((Join-Path $game 'WTF\Account\ACCOUNT#1\SavedVariables\虚假角色'))
        [void][IO.Directory]::CreateDirectory((Join-Path $game 'WTF\Account\EMPTY'))
        $version=if ($flavor -eq 'titan') {'3.80.2.1'} else {'1.60.1.1'}
        $exe=Join-Path $game $(if ($flavor -eq 'titan') {'WowClassic.exe'} else {'Wow.exe'})
        Add-Type -TypeDefinition ('using System.Reflection; [assembly:AssemblyFileVersion("'+$version+'")] public class Fixture'+$flavor+' { public static void Main() {} }') -OutputAssembly $exe -OutputType ConsoleApplication
        Assert-Ui ((Resolve-WowGameDirectory $game $flavor) -eq $game -and (Resolve-WowGameDirectory $fixture $flavor) -eq $game) 'Client/product parent directory resolution failed.'
        $wrongGame=Join-Path (Join-Path $fixture 'wrong-version') $product
        [void][IO.Directory]::CreateDirectory($wrongGame)
        $wrongExe=Join-Path $wrongGame ([IO.Path]::GetFileName($exe))
        Add-Type -TypeDefinition ('using System.Reflection; [assembly:AssemblyFileVersion("9.0.0.1")] public class WrongFixture'+$flavor+' { public static void Main() {} }') -OutputAssembly $wrongExe -OutputType ConsoleApplication
        $failed=$false;try {Resolve-WowGameDirectory $wrongGame $flavor} catch {$failed=$true};Assert-Ui $failed 'Wrong client build was accepted.'
    }
    $row.Process.ExecutablePath=Join-Path $script:rotation.GameDirectories[$row.Client.Flavor] ([IO.Path]::GetFileName($oldPath));$row.Client.ExecutablePath=$row.Process.ExecutablePath
    $catalog=@(Get-RowAccounts $row)
    Assert-Ui ($catalog.Count -eq 3 -and @($catalog | Where-Object {$_.Name -eq 'SavedVariables'}).Count -eq 0) 'Non-account folder leaked into catalog.'
    Assert-Ui (@(Get-RowAccountNames $row 'EMPTY').Count -eq 0) 'Empty account invented character names.'
    Update-RowAccountChoices $row
    Assert-Ui ($row.AccountBox.Items.Count -eq 4 -and $row.AccountBox.SelectedIndex -eq 0 -and -not $row.AccountName) 'Ambiguous process account was guessed.'
    Assert-Ui (-not $row.PSObject.Properties['ItemCheck']) 'Old per-process item checkbox remains.'
    $plan=New-RotationPlan;$plan.Slots[0].Name='钓鱼角色';$plan.Slots[0].UseItem=$true;$plan.Slots[2].Name='战斗角色';$plan.Slots[2].Mode='fight'
    $plans=@{};$plans[$row.Key]=$plan;Save-RotationConfiguration -Plans $plans;Update-RowAccountChoices $row
    Assert-Ui ($row.AccountName -ceq 'ACCOUNT#1') 'Unique legacy plan did not suggest its account.'
    $names=@(Get-RowAccountNames $row)
    Assert-Ui ($names.Count -eq 2 -and $names -ccontains '钓鱼角色' -and $names -cnotcontains '另一个角色' -and $names -cnotcontains '虚假角色') 'Account isolation, deduplication or SavedVariables exclusion failed.'
    $row.Validated=$true;$row.State=Add-WowAutoTask $script:scheduler $row.Key 1000 1000 0 -UseItem $true
    $row.AccountBox.SelectedItem='ACCOUNT#2'
    Assert-Ui ($row.AccountName -ceq 'ACCOUNT#2' -and $script:rotation.Plans[$row.Key].Account -ceq 'ACCOUNT#2' -and -not (Test-UnifiedTaskRunning $row) -and -not $row.Validated) 'Account change did not persist and stop/invalidate its task.'
    $failed=$false;try {Test-RowAccountPlan $row $plan} catch {$failed=$true};Assert-Ui $failed 'Foreign-account role was accepted.'
    $editor=New-RotationEditor $row
    try {
        Assert-Ui ($editor.Tag.Slots[0].Name.Items.Count -eq 1 -and $editor.Tag.Slots[0].Name.Items.Contains('另一个角色') -and $editor.Tag.Slots[0].Name.Text -ceq '钓鱼角色') 'Account dropdown leaked history or silently cleared old plan.'
        $editor.Show($form);[Windows.Forms.Application]::DoEvents();$editor.Tag.Save.PerformClick()
        Assert-Ui ($editor.Visible -and $editor.Tag.Error.Text -match '没有角色') 'Invalid old role was silently saved for another account.'
    } finally {$editor.Dispose()}
    $hash=(Get-FileHash $script:rotation.Path).Hash
    $locked=[IO.File]::Open($script:rotation.Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try {$row.AccountBox.SelectedItem='ACCOUNT#1'} finally {$locked.Dispose()}
    Assert-Ui ($row.AccountName -ceq 'ACCOUNT#2' -and $row.AccountBox.SelectedItem -ceq 'ACCOUNT#2' -and (Get-FileHash $script:rotation.Path).Hash -eq $hash) 'Failed account save was not rolled back.'
    $row.AccountBox.SelectedItem='ACCOUNT#1'
    $editor=New-RotationEditor $row
    try {
        $editor.Show($form);[Windows.Forms.Application]::DoEvents()
        Assert-Ui ($editor.Tag.Slots[0].UseItem.Checked -and $editor.Tag.Slots[0].UseItem.Enabled -and -not $editor.Tag.Slots[2].UseItem.Enabled) 'Per-slot item draft or combat disable missing.'
        $editor.Tag.Slots[0].UseItem.Checked=$false
        $locked=[IO.File]::Open($script:rotation.Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
        try {$editor.Tag.Save.PerformClick()} finally {$locked.Dispose()}
        Assert-Ui ($editor.Visible -and $script:rotation.Plans[$row.Key].Slots[0].UseItem) 'Failed slot save applied item draft.'
        $editor.Tag.Save.PerformClick()
        Assert-Ui (-not $editor.Visible -and -not $script:rotation.Plans[$row.Key].Slots[0].UseItem -and -not $row.SlotUseItem) 'Saved slot item did not apply.'
    } finally {$editor.Dispose()}
    $script:rotation.NameHistory=@('历史其他角色');$editor=New-RotationEditor $row
    try {Assert-Ui (-not $editor.Tag.Slots[0].Name.Items.Contains('历史其他角色')) 'Global name history bypassed account filter.'} finally {$editor.Dispose()}
    $dialog=New-UnifiedSettingsDialog
    try {
        $dialog.Show($form);$dialog.Tag.Tabs.SelectedIndex=2;[Windows.Forms.Application]::DoEvents()
        $page=$dialog.Tag.Directories
        $before=$script:rotation.GameDirectories.Clone()
        $page.Tag.Inputs.titan.Text=Join-Path $fixture 'missing'
        Assert-Ui ($script:rotation.GameDirectories.titan -eq $before.titan) 'Directory draft applied before save.'
        $page.Tag.Save.PerformClick()
        Assert-Ui ($script:rotation.GameDirectories.titan -eq $before.titan -and $script:rotation.GameDirectories.forerver -eq $before.forerver -and $page.Tag.Error.Text -match '没有对应客户端') 'Invalid directory partly applied.'
        $page.Tag.Inputs.titan.Text=$fixture;$page.Tag.Inputs.forerver.Text=$fixture
        $locked=[IO.File]::Open($script:rotation.Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
        try {$page.Tag.Save.PerformClick()} finally {$locked.Dispose()}
        Assert-Ui ($page.Tag.Error.Text -notmatch '^游戏目录已保存' -and $script:rotation.GameDirectories.titan -eq $before.titan) 'Locked directory save applied draft.'
        $page.Tag.Save.PerformClick()
        Assert-Ui ($page.Tag.Error.Text -match '^游戏目录已保存') 'Valid directory settings did not save.'
        if ($env:WOWAUTO_UNIFIED_PREVIEW_DIRECTORY) {
            $bitmap=New-Object Drawing.Bitmap($dialog.Width,$dialog.Height)
            try {$dialog.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$bitmap.Width,$bitmap.Height)));$bitmap.Save((Join-Path $env:WOWAUTO_UNIFIED_PREVIEW_DIRECTORY 'unified-settings-directories.png'))} finally {$bitmap.Dispose()}
        }
    } finally {$dialog.Dispose()}
    $hash=(Get-FileHash $script:rotation.Path).Hash;$script:rotation.Plans=@{};Import-RotationConfiguration
    Assert-Ui ($script:rotation.ConfigReady -and $script:rotation.Plans[$row.Key].Account -ceq 'ACCOUNT#1' -and $script:rotation.Plans[$row.Key].Slots[0].UseItem -is [bool] -and (Get-FileHash $script:rotation.Path).Hash -eq $hash) 'Account/slot/root roundtrip rewrote source or failed.'
    # Old v2 data migrates per-process item setting once into each fishing slot, without rewriting.
    $legacyPlan=Copy-RotationPlan $plan
    foreach ($slot in $legacyPlan.Slots) {$slot.PSObject.Properties.Remove('UseItem')}
    $legacyPlans=@{};$legacyPlans[$row.Key]=$legacyPlan
    [IO.File]::WriteAllText($script:rotation.Path,(@{Version=2;IntervalSeconds=0;Plans=$legacyPlans} | ConvertTo-Json -Depth 10))
    $script:processItemPreferences=@{};$script:processItemPreferences[$row.Key]=$true
    $hash=(Get-FileHash $script:rotation.Path).Hash;Import-RotationConfiguration
    Assert-Ui ($script:rotation.ConfigReady -and $script:rotation.Plans[$row.Key].Slots[0].UseItem -and -not $script:rotation.Plans[$row.Key].Slots[2].UseItem -and (Get-FileHash $script:rotation.Path).Hash -eq $hash) 'Legacy item migration not per fishing slot/read-only.'
    $bad=Copy-RotationPlan $plan;$bad.Slots[0].UseItem='true'
    $failed=$false;try {Test-RotationPlan $bad} catch {$failed=$true};Assert-Ui $failed 'String slot switch accepted.'
    $bad | Add-Member NoteProperty Account '..\other' -Force
    $failed=$false;try {Test-RotationPlan $bad} catch {$failed=$true};Assert-Ui $failed 'Path-like account identity accepted.'
    $row.Client.ExecutablePath='C:\another\_classic_titan_\WowClassic.exe'
    $failed=$false;try {Get-RowAccounts $row} catch {$failed=$true};Assert-Ui $failed 'Another installation inherited configured accounts.'
    Write-Output 'PASS: both client directories, parent paths/version checks, subaccount/realm/name isolation, unique legacy hint/no ambiguous guess, account persistence/rollback/stop, filtered editable dropdowns, per-slot item drafts/atomic saves, game-directory drafts/rollback/save, v2 read-only migration and installation mismatch. Temporary files and mock inputs only.'
} finally {
    Stop-AllRows;$row.Process.ExecutablePath=$oldPath;$row.Client.ExecutablePath=$oldClientPath
    $script:rotation.Path=$savedAccountState.Path;$script:rotation.Plans=$savedAccountState.Plans;$script:rotation.GameDirectories=$savedAccountState.Roots
    $script:rotation.NameHistory=$savedAccountState.History;$script:rotation.IntervalSeconds=$savedAccountState.Interval;$script:processItemPreferences=$savedAccountState.Items
    $cleanup=[IO.Path]::GetFullPath($fixture)
    if (-not $cleanup.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $cleanup -Leaf) -notlike 'wowAuto-account-ui-*') {throw 'Unsafe temporary fixture cleanup path.'}
    if ([IO.Directory]::Exists($cleanup)) {[IO.Directory]::Delete($cleanup,$true)}
}
