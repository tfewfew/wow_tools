# This type substitutes every combat native operation before loading the UI module.
Add-Type -TypeDefinition @'
namespace WowAutoFight {
    public class Packet {
        public int ClassId=1, EncounterId=1;
        public string Flavor="titan", Action="combat", Recovery="none";
        public bool Busy=false, Combat=false;
    }
    public static class Native {
        public static Packet Current=new Packet();
        public static int Sends=0, Releases=0, LastCode=0;
        public static System.Collections.Generic.List<int> Codes=new System.Collections.Generic.List<int>();
        public static bool LastCtrl=false,LastShift=false,LastAlt=false;
        public static int ReadsUntilEncounterChange=0;
        public static int ReadsUntilActionChange=0;
        public static string NextAction="waiting";
        public static int ReadsUntilRecoveryChange=0;
        public static string NextRecovery="none";
        public static int MissingReads=0;
        public static bool LastReadPending=false;
        public static string LastReadError="模拟快照暂不可读";
        public static bool FailSend=false, IsHolding=false;
        public static string Position="左上";
        public static string ReadWindowPosition(object client) {return Position;}
        public static bool IsAlive(object client) { return true; }
        public static bool IsForeground=true;
        public static int Activations=0, Restores=0;
        public static bool Foreground(object client) { return IsForeground; }
        public static bool Activate(object client) { Activations++; return true; }
        public static object Read(object client) {
            if (MissingReads>0) { MissingReads--; return null; }
            if (ReadsUntilEncounterChange>0 && --ReadsUntilEncounterChange==0) Current.EncounterId++;
            if (ReadsUntilActionChange>0 && --ReadsUntilActionChange==0) Current.Action=NextAction;
            if (ReadsUntilRecoveryChange>0 && --ReadsUntilRecoveryChange==0) Current.Recovery=NextRecovery;
            return new Packet {ClassId=Current.ClassId, EncounterId=Current.EncounterId,
                Flavor=Current.Flavor, Action=Current.Action, Recovery=Current.Recovery, Busy=Current.Busy, Combat=Current.Combat};
        }
        public static bool Press(object client, ushort code, bool ctrl, bool shift, bool alt) {
            if (FailSend) return false; Sends++; LastCode=code; Codes.Add(code); LastCtrl=ctrl; LastShift=shift; LastAlt=alt; return true;
        }
        public static bool BeginHold(object client, ushort code, bool ctrl, bool shift, bool alt) {
            if (!Press(client,code,ctrl,shift,alt)) return false; IsHolding=true; return true;
        }
        public static void ReleaseHold() { if (IsHolding) Releases++; IsHolding=false; }
        public static void Restore(object window) {Restores++;}
    }
}
'@
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'autoFight.ps1')
Stop-AllRows
$script:scheduler.ReelHoldUntil=0L;$script:scheduler.ItemHoldUntil=0L
$fightSource=Join-Path (Split-Path $PSScriptRoot -Parent) 'autoFight.config.json'
$fightSourceHash=(Get-FileHash -LiteralPath $fightSource).Hash
$fishIniHash=(Get-FileHash -LiteralPath $script:settingsPath).Hash
$fishJump=$script:scheduler.JumpEveryCycles
$fightPath=Join-Path ([IO.Path]::GetTempPath()) ('autoFight-ui-'+[Guid]::NewGuid()+'.json')
try {
    Initialize-AutoFightTab $tabs $form
    $script:autoFight.Timer.Stop()
    $script:autoFight.ConfigPath=$fightPath
    $script:autoFight.Profiles=New-AutoFightProfiles
    $script:autoFight.Common=New-AutoFightCommon
    $script:autoFight.CommandGate=New-AutoFightCommandGate
    $script:autoFight.CommandGate.LastSentAt=100L
    $tabs.SelectedTab=$script:autoFight.Tab
    $dialog=New-AutoFightSettingsDialog
    try {
        $dialog.Show($form)
        [System.Windows.Forms.Application]::DoEvents()
        Assert-Ui (-not $dialog.Tag.Pages.titan.Tab.HorizontalScroll.Visible -and
            $dialog.Tag.Pages.titan.Bindings.CombatKey.Right -le $dialog.Tag.Pages.titan.Tab.ClientSize.Width) 'Default settings layout clips profession bindings.'
        if ($env:WOWAUTO_NEW_SETTINGS_PREVIEW_DIRECTORY) {
            $bitmap=New-Object Drawing.Bitmap($dialog.Width,$dialog.Height)
            try {$dialog.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$dialog.Width,$dialog.Height))); $bitmap.Save((Join-Path $env:WOWAUTO_NEW_SETTINGS_PREVIEW_DIRECTORY 'combat-settings.png'),[Drawing.Imaging.ImageFormat]::Png)}
            finally {$bitmap.Dispose()}
        }
        Assert-Ui ($dialog.Tag.CommandInterval.Value -eq 500 -and $dialog.Tag.CommandInterval.Increment -eq 100) 'Combat common interval default / 100 ms step incorrect.'
        Assert-Ui ($dialog.Tag.Bindings.BuffKey.Text -eq 'F11' -and $dialog.Tag.Numbers.BuffIntervalSeconds.Value -eq 0 -and
            $dialog.Tag.Numbers.BuffCount.Value -eq 1) 'Default per-class buff controls are incorrect.'
        Assert-Ui ($dialog.Tag.Numbers.RecoveryCooldownSeconds.Value -eq 30 -and
            $dialog.Tag.Numbers.RecoveryCooldownSeconds.Minimum -eq 1 -and
            $dialog.Tag.Numbers.RecoveryCooldownSeconds.Maximum -eq 3600 -and
            -not $dialog.Tag.Numbers.ContainsKey('CombatIntervalMs')) 'Recovery cooldown controls or removed combat interval are incorrect.'
        Assert-Ui ($dialog.Tag.Bindings.TargetKey.Text -eq 'Tab' -and $dialog.Tag.CommonBindings.ContainsKey('TargetKey')) 'Target key is not common/default Tab.'
        $previewKey=New-Object System.Windows.Forms.PreviewKeyDownEventArgs([System.Windows.Forms.Keys]::Tab)
        $previewMethod=[System.Windows.Forms.Control].GetMethod('OnPreviewKeyDown',[Reflection.BindingFlags]'Instance,NonPublic')
        $null=$previewMethod.Invoke($dialog.Tag.Bindings.TargetKey,@($previewKey.PSObject.BaseObject))
        Assert-Ui $previewKey.IsInputKey 'Tab moved focus instead of being recordable.'
        $keyEvent=New-Object System.Windows.Forms.KeyEventArgs([System.Windows.Forms.Keys]::Control -bor [System.Windows.Forms.Keys]::Tab)
        $keyMethod=[System.Windows.Forms.Control].GetMethod('OnKeyDown',[Reflection.BindingFlags]'Instance,NonPublic')
        $null=$keyMethod.Invoke($dialog.Tag.Bindings.TargetKey,@($keyEvent.PSObject.BaseObject))
        Assert-Ui ($dialog.Tag.Bindings.TargetKey.Text -eq 'Ctrl+Tab' -and $script:autoFight.Common.TargetKey -eq 'Tab') 'Target key recording applied early.'
        Assert-Ui ($dialog.Tag.Tabs.TabPages.Count -eq 2 -and $dialog.Tag.Pages.titan.Class.Items.Count -eq 10 -and
            $dialog.Tag.Pages.forerver.Class.Items.Count -eq 9 -and '武僧' -notin $dialog.Tag.Pages.titan.Class.Items -and
            '死亡骑士' -notin $dialog.Tag.Pages.forerver.Class.Items) 'Version tabs / class availability incorrect.'
        $dialog.Tag.Numbers.JumpIntervalSeconds.Value=20
        $dialog.Tag.CommandInterval.Value=800
        $dialog.Tag.Bindings.MoveLeftKey.Text='A';$dialog.Tag.Bindings.MoveRightKey.Text='D'
        $dialog.Tag.Bindings.SkinKey.Text='='
        $dialog.Tag.Numbers.MovementHoldMs.Value=600
        $dialog.Tag.Tabs.SelectedIndex=1; $dialog.Tag.Pages.forerver.Class.SelectedIndex=2
        Assert-Ui ($dialog.Tag.Bindings.MoveLeftKey.Text -eq 'A' -and $dialog.Tag.Bindings.SkinKey.Text -eq '=' -and
            $dialog.Tag.Bindings.TargetKey.Text -eq 'Ctrl+Tab' -and
            $dialog.Tag.Numbers.MovementHoldMs.Value -eq 600 -and $script:autoFight.Common.MoveLeftKey -eq 'Q') 'Common draft lost on profile selection or applied early.'
        $dialog.Tag.Bindings.CombatKey.Text='Ctrl+7'
        $dialog.Tag.Numbers.RecoveryCooldownSeconds.Value=45
        $dialog.Tag.Bindings.BuffKey.Text='Ctrl+F11'
        $dialog.Tag.Numbers.BuffIntervalSeconds.Value=60
        $dialog.Tag.Numbers.BuffCount.Value=3
        $dialog.Tag.Tabs.SelectedIndex=0
        Assert-Ui ($dialog.Tag.Class.SelectedIndex -eq 0 -and $dialog.Tag.Bindings.CombatKey.Text -eq 'F6' -and
            $dialog.Tag.Bindings.BuffKey.Text -eq 'F11' -and $dialog.Tag.Numbers.BuffIntervalSeconds.Value -eq 0 -and
            $dialog.Tag.Numbers.RecoveryCooldownSeconds.Value -eq 30) 'Tab changed the other server class or recovery draft.'
        $dialog.Tag.Pages.titan.Class.SelectedIndex=9
        Assert-Ui ($dialog.Tag.Pages.titan.CurrentKey -eq 'titan:11') 'Sparse class IDs interpreted as combo indices.'
        $dialog.Tag.Tabs.SelectedIndex=1
        Assert-Ui ($dialog.Tag.Class.SelectedIndex -eq 2 -and $dialog.Tag.Bindings.CombatKey.Text -eq 'Ctrl+7' -and
            $dialog.Tag.Bindings.BuffKey.Text -eq 'Ctrl+F11' -and $dialog.Tag.Numbers.BuffIntervalSeconds.Value -eq 60 -and
            $dialog.Tag.Numbers.BuffCount.Value -eq 3 -and $dialog.Tag.Numbers.RecoveryCooldownSeconds.Value -eq 45) 'Tab lost independently selected class / recovery draft.'
        Assert-Ui ($dialog.Tag.CommandInterval.Value -eq 800 -and $script:autoFight.CommandGate.IntervalMs -eq 500) 'Profile selection reset common draft or draft applied early.'
        $dialog.Tag.Save.PerformClick()
        Assert-Ui ($dialog.IsDisposed -or -not $dialog.Visible) 'Combat save did not close dialog.'
        $saved=Read-AutoFightConfiguration $fightPath
        Assert-Ui ($saved.Common.TargetKey -eq 'Ctrl+Tab' -and $script:autoFight.Common.TargetKey -eq 'Ctrl+Tab') 'Saved target key lost common configuration.'
        Assert-Ui ($saved.Common.MoveLeftKey -eq 'A' -and $saved.Common.SkinKey -eq '=' -and $saved.Common.MovementHoldMs -eq 600 -and
            $null -eq $saved.Profiles['titan:1'].PSObject.Properties['MoveLeftKey'] -and
            $null -eq $saved.Profiles['titan:1'].PSObject.Properties['EmergencyKey'] -and
            $dialog.Tag.Pages.titan.Bindings.Count -eq 4) 'Obsolete combat recovery field remains visible or persisted.'
        Assert-Ui ($saved.Common.JumpIntervalSeconds -eq 20 -and $saved.CommandIntervalMs -eq 800 -and $script:autoFight.Profiles['forerver:3'].CombatKey -eq 'Ctrl+7' -and $script:autoFight.Profiles['titan:3'].CombatKey -eq 'F6' -and $script:autoFight.CommandGate.LastSentAt -eq 100 -and
            $saved.Profiles['forerver:3'].BuffKey -eq 'Ctrl+F11' -and $saved.Profiles['forerver:3'].BuffIntervalSeconds -eq 60 -and
            $saved.Profiles['forerver:3'].BuffCount -eq 3 -and $saved.Profiles['forerver:3'].RecoveryCooldownSeconds -eq 45 -and
            $saved.Profiles['titan:3'].RecoveryCooldownSeconds -eq 30 -and $saved.Profiles['titan:3'].BuffIntervalSeconds -eq 0) 'Combat save lost common/profile/recovery isolation or reset last send.'
    } finally {$dialog.Dispose()}
    $dialog=New-AutoFightSettingsDialog
    try {
        $dialog.Show($form)
        Assert-Ui ($dialog.Tag.CommandInterval.Value -eq 800 -and $dialog.Tag.Bindings.TargetKey.Text -eq 'Ctrl+Tab' -and
            $dialog.Tag.Bindings.MoveLeftKey.Text -eq 'A' -and $dialog.Tag.Numbers.JumpIntervalSeconds.Value -eq 20) 'Combat reopen lost saved interval/common key/jump.'
        $dialog.Tag.Tabs.SelectedIndex=1;$dialog.Tag.Pages.forerver.Class.SelectedIndex=2
        Assert-Ui ($dialog.Tag.Bindings.BuffKey.Text -eq 'Ctrl+F11' -and $dialog.Tag.Numbers.BuffIntervalSeconds.Value -eq 60 -and
            $dialog.Tag.Numbers.BuffCount.Value -eq 3 -and $dialog.Tag.Numbers.RecoveryCooldownSeconds.Value -eq 45) 'Combat reopen lost per-class buff/recovery controls.'
        $dialog.Tag.Numbers.RecoveryCooldownSeconds.Value=60
        $dialog.Tag.Bindings.BuffKey.Text='F12';$dialog.Tag.Numbers.BuffIntervalSeconds.Value=90;$dialog.Tag.Numbers.BuffCount.Value=5
        $dialog.Tag.Bindings.TargetKey.Text='F10';$dialog.Tag.CommandInterval.Value=900
        $dialog.Tag.Bindings.MoveLeftKey.Text='Z';$dialog.Tag.Numbers.JumpIntervalSeconds.Value=30;$dialog.Tag.Cancel.PerformClick()
    }
    finally {$dialog.Dispose()}
    Assert-Ui ($script:autoFight.CommandGate.IntervalMs -eq 800) 'Combat cancel applied draft.'
    Assert-Ui ($script:autoFight.Common.MoveLeftKey -eq 'A') 'Cancel applied common draft.'
    Assert-Ui ($script:autoFight.Common.TargetKey -eq 'Ctrl+Tab') 'Cancel applied target draft.'
    Assert-Ui ($script:autoFight.Common.JumpIntervalSeconds -eq 20) 'Cancel applied jump draft.'
    Assert-Ui ($script:autoFight.Profiles['forerver:3'].BuffKey -eq 'Ctrl+F11' -and
        $script:autoFight.Profiles['forerver:3'].BuffIntervalSeconds -eq 60 -and
        $script:autoFight.Profiles['forerver:3'].BuffCount -eq 3 -and
        $script:autoFight.Profiles['forerver:3'].RecoveryCooldownSeconds -eq 45) 'Cancel applied buff or recovery draft.'
    $locked=[IO.File]::Open($fightPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try {
        $dialog=New-AutoFightSettingsDialog
        try {
            $dialog.Show($form); $dialog.Tag.CommandInterval.Value=1000; $dialog.Tag.Bindings.CombatKey.Text='F12'
            $dialog.Tag.Bindings.BuffKey.Text='Ctrl+F12';$dialog.Tag.Numbers.BuffIntervalSeconds.Value=45;$dialog.Tag.Numbers.BuffCount.Value=4
            $dialog.Tag.Numbers.RecoveryCooldownSeconds.Value=90
            $dialog.Tag.Bindings.TargetKey.Text='F10'
            $dialog.Tag.Bindings.MoveLeftKey.Text='Z';$dialog.Tag.Numbers.MovementHoldMs.Value=900;$dialog.Tag.Numbers.JumpIntervalSeconds.Value=30;$dialog.Tag.Save.PerformClick()
            Assert-Ui ($dialog.Visible -and $dialog.Tag.Error.Text -ne '' -and $script:autoFight.CommandGate.IntervalMs -eq 800 -and $script:autoFight.Profiles['titan:1'].CombatKey -eq 'F6') 'Failed combat save partially applied draft.'
            Assert-Ui ($script:autoFight.Common.MoveLeftKey -eq 'A' -and $script:autoFight.Common.MovementHoldMs -eq 600) 'Failed save partially applied common fields.'
            Assert-Ui ($script:autoFight.Common.JumpIntervalSeconds -eq 20) 'Failed save partially applied jump setting.'
            Assert-Ui ($script:autoFight.Common.TargetKey -eq 'Ctrl+Tab') 'Failed save partially applied target setting.'
            Assert-Ui ($script:autoFight.Profiles['titan:1'].BuffIntervalSeconds -eq 0 -and
                $script:autoFight.Profiles['titan:1'].BuffCount -eq 1 -and
                $script:autoFight.Profiles['titan:1'].RecoveryCooldownSeconds -eq 30) 'Failed save partially applied buff/recovery settings.'
        } finally {$dialog.Dispose()}
    } finally {$locked.Dispose()}
    $script:autoFight.Editor=$null
    $script:autoFight.Common.JumpIntervalSeconds=0
    $script:autoFight.Clock=[pscustomobject]@{ElapsedMilliseconds=999L}
    $script:autoFight.CommandGate=New-AutoFightCommandGate 1000
    Complete-AutoFightCommand $script:autoFight.CommandGate 0 $true
    $fightRows=@()
    foreach($flavor in @('titan','forerver')) {
        [WowAutoFight.Native]::Position='左上'
        $client=[pscustomobject]@{Key=$flavor; ProcessId=1; Flavor=$flavor; Title='模拟战斗窗口'}
        $row=New-AutoFightRow $client $fightRows.Count
        Assert-Ui ($row.Name.Text -match '左上') 'Process row omitted window position.'
        Assert-Ui ($row.Panel.Height -eq 110 -and $row.Panel.Controls.Count -eq 4 -and
            -not $row.PSObject.Properties['MoveButtons']) 'Combat row still exposes manual movement buttons.'
        [WowAutoFight.Native]::Position='右下'; Update-AutoFightRowName $row
        Assert-Ui ($row.Name.Text -match '右下') 'Process position did not update.'
        $row.ClassId=1; $row.CanStart=$true; $script:autoFight.Rows[$flavor]=$row
        $script:autoFight.List.Controls.Add($row.Panel); $fightRows+=$row
    }
    $fightRows[0].Session=New-AutoFightSession 0 1
    $fightRows[1].Session=New-AutoFightSession 0 1
    $script:autoFight.Pending=New-AutoFightPending $fightRows[0] $fightRows[0].Session $false 0
    Finish-AutoFightPending 100
    $script:autoFight.Pending=New-AutoFightPending $fightRows[1] $fightRows[1].Session $false 0
    Finish-AutoFightPending 400
    Assert-Ui ($fightRows[0].Session.Due -eq 1100 -and $fightRows[1].Session.Due -eq 1400 -and
        -not $script:autoFight.Pending) 'Combat sampling did not schedule each process independently at one second.'
    $fightRows[0].Session=$null;$fightRows[1].Session=$null
    function Prepare-FightInput($Row,[string]$Action,[long]$Now) {
        $script:autoFight.Clock.ElapsedMilliseconds=$Now
        [WowAutoFight.Native]::Current.Flavor=$Row.Client.Flavor
        [WowAutoFight.Native]::Current.Action=$Action
        [WowAutoFight.Native]::Current.Combat=$Action -in @('waiting','combat')
        [WowAutoFight.Native]::Current.Busy=$false
        $Row.Session=New-AutoFightSession $Now 1
        $pending=New-AutoFightPending $Row $Row.Session $false 0
        $pending.Activated=$true;$pending.SampleAt=0;$script:autoFight.Pending=$pending
    }
    function Tick-FightColor($Row,[string]$Action,[long]$Now) {
        $script:autoFight.Clock.ElapsedMilliseconds=$Now
        [WowAutoFight.Native]::Current.Action=$Action
        [WowAutoFight.Native]::Current.Combat=$Action -in @('waiting','combat')
        $pending=New-AutoFightPending $Row $Row.Session $false 0
        $pending.Activated=$true;$pending.SampleAt=0;$script:autoFight.Pending=$pending
        Invoke-AutoFightTick
    }
    $fightRows[0].CanStart=$false
    [WowAutoFight.Native]::Current.Flavor='titan'
    [WowAutoFight.Native]::Current.Action='idle'
    $script:autoFight.Scan=[pscustomobject]@{Order=@($fightRows[0]);Index=0;OriginalWindow=[IntPtr]::Zero}
    $script:autoFight.Pending=New-AutoFightPending $fightRows[0] $null $true 0
    $script:autoFight.Pending.Activated=$true;$script:autoFight.Pending.SampleAt=0
    Invoke-AutoFightTick
    Assert-Ui ($fightRows[0].CanStart -and $script:autoFight.Scan.Index -eq 1 -and
        -not $script:autoFight.Pending -and [WowAutoFight.Native]::Sends -eq 0) 'Stable V8 color failed background refresh.'
    Complete-AutoFightScan
    Prepare-FightInput $fightRows[0] 'opening' 999;Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 0) 'Common gate allowed early opening.'
    Prepare-FightInput $fightRows[0] 'opening' 1000;Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 2 -and [WowAutoFight.Native]::Codes[0] -eq 9 -and
        [WowAutoFight.Native]::Codes[1] -eq 116) 'Opening did not select with Ctrl+Tab before F5.'
    Tick-FightColor $fightRows[0] 'opening' 1999
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 2) 'Opening repeated before one second.'
    Tick-FightColor $fightRows[0] 'opening' 2000
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 4 -and [WowAutoFight.Native]::Codes[2] -eq 9 -and
        [WowAutoFight.Native]::Codes[3] -eq 116) 'Opening loop did not repeat target then opener.'
    Tick-FightColor $fightRows[0] 'waiting' 2100
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 4) 'Combat waiting sent a key.'
    Tick-FightColor $fightRows[0] 'combat' 3000
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 5) 'Combat color did not send attack key.'
    Tick-FightColor $fightRows[0] 'loot' 4000
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 6 -and $script:autoFight.ActiveHold) 'Loot color did not start interaction hold.'
    [void](Release-AutoFightHold)
    Tick-FightColor $fightRows[0] 'skin' 5000
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 7 -and $script:autoFight.ActiveHold.Until -eq 7000) 'Skin color did not start fixed hold.'
    [WowAutoFight.Native]::Current.Action='idle'
    $script:autoFight.Clock.ElapsedMilliseconds=5500;Invoke-AutoFightTick
    Assert-Ui ($script:autoFight.ActiveHold -and [WowAutoFight.Native]::Sends -eq 7) 'Skin hold stopped when color changed.'
    $script:autoFight.Clock.ElapsedMilliseconds=7000;Invoke-AutoFightTick
    Assert-Ui (-not $script:autoFight.ActiveHold) 'Skin hold ignored two-second limit.'
    [WowAutoFight.Native]::Current.EncounterId=3
    [WowAutoFight.Native]::ReadsUntilActionChange=3
    [WowAutoFight.Native]::NextAction='waiting'
    Tick-FightColor $fightRows[0] 'opening' 8000
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 7) 'Color changed before input but old opener ran.'
    [WowAutoFight.Native]::ReadsUntilActionChange=4
    Tick-FightColor $fightRows[0] 'opening' 9000
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 8 -and [WowAutoFight.Native]::LastCode -eq 9) 'Color changed after targeting but opener ran.'
    [WowAutoFight.Native]::IsForeground=$false
    [WowAutoFight.Native]::Activations=0
    Prepare-FightInput $fightRows[0] 'opening' 10000
    $script:autoFight.Pending.Activated=$false
    Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Activations -eq 1 -and [WowAutoFight.Native]::Sends -eq 8) 'Opening did not wait for foreground.'
    [WowAutoFight.Native]::IsForeground=$true
    $script:autoFight.Clock.ElapsedMilliseconds=10199;Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 8) 'Opening bypassed focus settling.'
    $script:autoFight.Clock.ElapsedMilliseconds=10200;Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 10) 'Foreground opening did not send two keys.'
    Prepare-FightInput $fightRows[0] 'combat' 12000
    [WowAutoFight.Native]::MissingReads=1;Invoke-AutoFightTick
    Assert-Ui ($fightRows[0].Session -and [WowAutoFight.Native]::Sends -eq 10) 'Transient read failure emitted input.'
    $script:autoFight.Clock.ElapsedMilliseconds=12050;Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 11) 'Fresh frame did not resume combat.'
    Prepare-FightInput $fightRows[0] 'combat' 13000
    [WowAutoFight.Native]::MissingReads=1000;Invoke-AutoFightTick
    $script:autoFight.Clock.ElapsedMilliseconds=13799;Invoke-AutoFightTick
    Assert-Ui ($fightRows[0].Session -and [WowAutoFight.Native]::Sends -eq 11) 'Unreadable grace stopped early.'
    $script:autoFight.Clock.ElapsedMilliseconds=13800;Invoke-AutoFightTick
    Assert-Ui (-not $fightRows[0].Session -and -not $fightRows[0].CanStart) 'Persistent unreadability did not stop.'
    [WowAutoFight.Native]::MissingReads=0
    $script:autoFight.Common.JumpIntervalSeconds=2
    Prepare-FightInput $fightRows[0] 'idle' 50000;Invoke-AutoFightTick
    Tick-FightColor $fightRows[0] 'waiting' 52000
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 11) 'Jump bypassed waiting color.'
    Tick-FightColor $fightRows[0] 'idle' 54000
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 12 -and [WowAutoFight.Native]::LastCode -eq 32) 'Due jump did not use Space.'
    $script:autoFight.Common.JumpIntervalSeconds=0
    $fightRows[0].Client | Add-Member NoteProperty LoginPointPresent $false
    Prepare-FightInput $fightRows[0] 'opening' 60000;Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 12 -and -not $fightRows[0].Session) 'Missing login point permitted opening.'
    $fightRows[0].Client.LoginPointPresent=$true
    [WowAutoFight.Native]::Current.Recovery='recover'
    Prepare-FightInput $fightRows[0] 'waiting' 62000;Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 13 -and [WowAutoFight.Native]::LastCode -eq 119 -and
        $fightRows[0].Session.RecoveryReadyAt -eq 92000 -and
        $script:gameActions.History[-1].Kind -eq 'Fight.Recover') 'Low health did not queue and cool down the class recovery key.'
    Tick-FightColor $fightRows[0] 'waiting' 63000
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 13) 'Recovery repeated before cooldown expired.'
    [WowAutoFight.Native]::Current.Recovery='unknown';Tick-FightColor $fightRows[0] 'waiting' 64000
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 13 -and $fightRows[0].Session.RecoveryReadyAt -eq 92000) 'Unknown health reset cooldown.'
    [WowAutoFight.Native]::Current.Recovery='none';Tick-FightColor $fightRows[0] 'waiting' 65000
    Assert-Ui ($fightRows[0].Session.RecoveryReadyAt -eq 92000) 'Healthy auxiliary color reset cooldown.'
    [WowAutoFight.Native]::Current.Recovery='recover'
    [WowAutoFight.Native]::ReadsUntilRecoveryChange=2
    Tick-FightColor $fightRows[0] 'waiting' 92000
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 13 -and $fightRows[0].Session.RecoveryReadyAt -eq 92000) 'Auxiliary color changed before input but stale recovery ran.'
    [WowAutoFight.Native]::Current.Recovery='recover';Tick-FightColor $fightRows[0] 'waiting' 93000
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 14 -and $fightRows[0].Session.RecoveryReadyAt -eq 123000) 'Still-low health did not recover after cooldown.'
    Stop-AutoFightAll
    $script:autoFight.Profiles['titan:1'].BuffKey='Ctrl+F11'
    $script:autoFight.Profiles['titan:1'].BuffIntervalSeconds=2
    $script:autoFight.Profiles['titan:1'].BuffCount=3
    $script:autoFight.CommandGate=New-AutoFightCommandGate 100
    $script:autoFight.Clock.ElapsedMilliseconds=100000L
    [WowAutoFight.Native]::Current.Flavor='titan';[WowAutoFight.Native]::Current.ClassId=1
    [WowAutoFight.Native]::Current.Action='idle';[WowAutoFight.Native]::Current.Recovery='none'
    [WowAutoFight.Native]::Current.Combat=$false;[WowAutoFight.Native]::Current.Busy=$false
    [WowAutoFight.Native]::IsForeground=$true
    $fightRows[0].CanStart=$true
    Start-AutoFightRow $fightRows[0]
    Assert-Ui ($fightRows[0].Session.NextBuffAt -eq 100000) 'Starting a logged-in combat role did not arm its first buff cycle.'
    $buffSends=[WowAutoFight.Native]::Sends
    Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Sends -eq $buffSends+1 -and [WowAutoFight.Native]::LastCode -eq 122 -and
        [WowAutoFight.Native]::LastCtrl -and $fightRows[0].Session.BuffRemaining -eq 2 -and
        $script:gameActions.History[-1].Kind -eq 'Fight.Buff') 'Initial buff did not use the queued per-class shortcut.'
    $script:autoFight.Clock.ElapsedMilliseconds=100999L;Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Sends -eq $buffSends+1) 'Buff loop ignored the one-second spacing.'
    $script:autoFight.Clock.ElapsedMilliseconds=101000L;Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Sends -eq $buffSends+2 -and $fightRows[0].Session.BuffRemaining -eq 1) 'Second buff did not run one second later.'
    $script:autoFight.Clock.ElapsedMilliseconds=102000L;Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Sends -eq $buffSends+3 -and $fightRows[0].Session.BuffRemaining -eq 0 -and
        $fightRows[0].Session.NextBuffAt -eq 104000) 'Third buff did not finish and arm the next interval.'
    $script:autoFight.Clock.ElapsedMilliseconds=103999L;Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Sends -eq $buffSends+3) 'Another buff cycle started before its interval.'
    $script:autoFight.Clock.ElapsedMilliseconds=104000L;Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Sends -eq $buffSends+3) 'Buff bypassed the one-second color sampling cadence.'
    $script:autoFight.Clock.ElapsedMilliseconds=104999L;Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Sends -eq $buffSends+4 -and $fightRows[0].Session.BuffRemaining -eq 2) 'Due buff did not run on the next color sample.'
    Stop-AutoFightRow $fightRows[0]
    Assert-Ui (-not $fightRows[0].Session -and -not @($script:gameActions.Events | Where-Object {$_.Domain -eq 'Fight' -and $_.Key -eq 'titan'}).Count) 'Stopping combat left a buff action queued.'
    Assert-Ui ($script:scheduler.JumpEveryCycles -eq $fishJump -and (Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $fishIniHash -and (Get-FileHash -LiteralPath $fightSource).Hash -eq $fightSourceHash) 'Combat changed fishing settings or source configuration.'
    Write-Output 'PASS: per-class buff settings save/reopen/cancel/locked rollback, initial and interval cycles through the production queue with one-second spacing. Mock input only.'
    Write-Output 'PASS: combat settings 100 ms step/common draft/profile isolation/save/cancel/locked failure; mocked production input gate for all states, cross-window, release, restart and send failure. No real native operations.'
    Write-Output 'PASS: unified window-frame login point permits background reads; missing point blocks foreground input and restored readiness unlocks start.'
    Write-Output 'PASS: production combat UI adapter samples each process on a one-second schedule, repeats opener, waits for range, applies recovery cooldown through the priority queue, and rechecks both colors before input.'
    Write-Output 'PASS: independent client tabs/class selection/sparse class IDs, supported classes, changing process positions, global jump save/cancel/failure/disabled/exact deadline/busy/wait deferral/Space/shared gate. Game operations mocked.'
} finally {
    Close-AutoFightTab
    $tabs.SelectedTab=$tab
    if ([IO.File]::Exists($fightPath)) {[IO.File]::Delete($fightPath)}
}
