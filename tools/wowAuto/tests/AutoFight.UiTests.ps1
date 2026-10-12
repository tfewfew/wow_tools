# This type substitutes every combat native operation before loading the UI module.
Add-Type -TypeDefinition @'
namespace WowAutoFight {
    public class Packet {
        public int ClassId=1, Heartbeat=1, EncounterId=1;
        public string Flavor="titan", Action="combat", Recovery="none";
        public bool Busy=false, Combat=false;
    }
    public static class Native {
        public static Packet Current=new Packet();
        public static int Sends=0, Releases=0;
        public static int ReadsUntilEncounterChange=0;
        public static bool FailSend=false, IsHolding=false;
        public static bool IsAlive(object client) { return true; }
        public static bool Foreground(object client) { return true; }
        public static bool Activate(object client) { return true; }
        public static object Read(object client) {
            Current.Heartbeat++;
            if (ReadsUntilEncounterChange>0 && --ReadsUntilEncounterChange==0) Current.EncounterId++;
            return new Packet {ClassId=Current.ClassId, Heartbeat=Current.Heartbeat, EncounterId=Current.EncounterId,
                Flavor=Current.Flavor, Action=Current.Action, Recovery=Current.Recovery, Busy=Current.Busy, Combat=Current.Combat};
        }
        public static bool Press(object client, ushort code, bool ctrl, bool shift, bool alt) {
            if (FailSend) return false; Sends++; return true;
        }
        public static bool BeginHold(object client, ushort code, bool ctrl, bool shift, bool alt) {
            if (!Press(client,code,ctrl,shift,alt)) return false; IsHolding=true; return true;
        }
        public static void ReleaseHold() { if (IsHolding) Releases++; IsHolding=false; }
        public static void Restore(object window) {}
    }
}
'@
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'autoFight.ps1')
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
        if ($env:WOWAUTO_NEW_SETTINGS_PREVIEW_DIRECTORY) {
            $bitmap=New-Object Drawing.Bitmap($dialog.Width,$dialog.Height)
            try {$dialog.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$dialog.Width,$dialog.Height))); $bitmap.Save((Join-Path $env:WOWAUTO_NEW_SETTINGS_PREVIEW_DIRECTORY 'combat-settings.png'),[Drawing.Imaging.ImageFormat]::Png)}
            finally {$bitmap.Dispose()}
        }
        Assert-Ui ($dialog.Tag.CommandInterval.Value -eq 500 -and $dialog.Tag.CommandInterval.Increment -eq 100) 'Combat common interval default / 100 ms step incorrect.'
        $dialog.Tag.CommandInterval.Value=800
        $dialog.Tag.Bindings.MoveLeftKey.Text='A';$dialog.Tag.Bindings.MoveRightKey.Text='D'
        $dialog.Tag.Bindings.SkinKey.Text='='
        $dialog.Tag.Numbers.MovementHoldMs.Value=600
        $dialog.Tag.Flavor.SelectedIndex=1; $dialog.Tag.Class.SelectedIndex=2
        Assert-Ui ($dialog.Tag.Bindings.MoveLeftKey.Text -eq 'A' -and $dialog.Tag.Bindings.SkinKey.Text -eq '=' -and
            $dialog.Tag.Numbers.MovementHoldMs.Value -eq 600 -and $script:autoFight.Common.MoveLeftKey -eq 'Q') 'Common draft lost on profile selection or applied early.'
        $dialog.Tag.Bindings.CombatKey.Text='Ctrl+7'
        Assert-Ui ($dialog.Tag.CommandInterval.Value -eq 800 -and $script:autoFight.CommandGate.IntervalMs -eq 500) 'Profile selection reset common draft or draft applied early.'
        $dialog.Tag.Save.PerformClick()
        Assert-Ui ($dialog.IsDisposed -or -not $dialog.Visible) 'Combat save did not close dialog.'
        $saved=Read-AutoFightConfiguration $fightPath
        Assert-Ui ($saved.Common.MoveLeftKey -eq 'A' -and $saved.Common.SkinKey -eq '=' -and $saved.Common.MovementHoldMs -eq 600 -and
            $null -eq $saved.Profiles['titan:1'].PSObject.Properties['MoveLeftKey'] -and $null -eq $dialog.Tag.Numbers.EmergencyIntervalMs) 'Common fields remain class-specific or obsolete recovery interval remains visible.'
        Assert-Ui ($saved.CommandIntervalMs -eq 800 -and $script:autoFight.Profiles['forerver:3'].CombatKey -eq 'Ctrl+7' -and $script:autoFight.Profiles['titan:3'].CombatKey -eq 'F6' -and $script:autoFight.CommandGate.LastSentAt -eq 100) 'Combat save lost common/profile isolation or reset last send.'
    } finally {$dialog.Dispose()}
    $dialog=New-AutoFightSettingsDialog
    try {$dialog.Show($form); Assert-Ui ($dialog.Tag.CommandInterval.Value -eq 800 -and $dialog.Tag.Bindings.MoveLeftKey.Text -eq 'A') 'Combat reopen lost saved interval/common key.'; $dialog.Tag.CommandInterval.Value=900; $dialog.Tag.Bindings.MoveLeftKey.Text='Z'; $dialog.Tag.Cancel.PerformClick()}
    finally {$dialog.Dispose()}
    Assert-Ui ($script:autoFight.CommandGate.IntervalMs -eq 800) 'Combat cancel applied draft.'
    Assert-Ui ($script:autoFight.Common.MoveLeftKey -eq 'A') 'Cancel applied common draft.'
    $locked=[IO.File]::Open($fightPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try {
        $dialog=New-AutoFightSettingsDialog
        try {
            $dialog.Show($form); $dialog.Tag.CommandInterval.Value=1000; $dialog.Tag.Bindings.CombatKey.Text='F12'
            $dialog.Tag.Bindings.MoveLeftKey.Text='Z';$dialog.Tag.Numbers.MovementHoldMs.Value=900;$dialog.Tag.Save.PerformClick()
            Assert-Ui ($dialog.Visible -and $dialog.Tag.Error.Text -ne '' -and $script:autoFight.CommandGate.IntervalMs -eq 800 -and $script:autoFight.Profiles['titan:1'].CombatKey -eq 'F6') 'Failed combat save partially applied draft.'
            Assert-Ui ($script:autoFight.Common.MoveLeftKey -eq 'A' -and $script:autoFight.Common.MovementHoldMs -eq 600) 'Failed save partially applied common fields.'
        } finally {$dialog.Dispose()}
    } finally {$locked.Dispose()}
    $script:autoFight.Editor=$null
    $script:autoFight.Clock=[pscustomobject]@{ElapsedMilliseconds=999L}
    $script:autoFight.CommandGate=New-AutoFightCommandGate 1000
    Complete-AutoFightCommand $script:autoFight.CommandGate 0 $true
    $fightRows=@()
    foreach($flavor in @('titan','forerver')) {
        $client=[pscustomobject]@{Key=$flavor; ProcessId=1; Flavor=$flavor; Title='模拟战斗窗口'}
        $row=New-AutoFightRow $client $fightRows.Count
        $row.ClassId=1; $row.CanStart=$true; $script:autoFight.Rows[$flavor]=$row
        $script:autoFight.List.Controls.Add($row.Panel); $fightRows+=$row
    }
    function Prepare-FightInput($Row,[string]$State,[long]$Now) {
        $script:autoFight.Clock.ElapsedMilliseconds=$Now
        [WowAutoFight.Native]::Current.Flavor=$Row.Client.Flavor
        [WowAutoFight.Native]::Current.Action=if ($State.StartsWith('move-')) {'idle'} elseif ($State -in @('recover','emergency')) {'idle'} else {$State}
        [WowAutoFight.Native]::Current.Recovery=if ($State -in @('recover','emergency')) {$State} else {'none'}
        $Row.Session=New-AutoFightSession $Now 1
        if ($State.StartsWith('move-')) {$Row.Session.MovementRequest=$State.Substring(5)}
        $pending=New-AutoFightPending $Row $Row.Session $false 0
        $pending.Activated=$true; $pending.SampleAt=0; $pending.FirstBeat=0; $pending.FirstClass=1
        $script:autoFight.Pending=$pending
    }
    foreach($state in @('opening','combat','recover','emergency','move-forward','move-backward','move-left','move-right','loot','skin')) {
        Prepare-FightInput $fightRows[0] $state 999
        Invoke-AutoFightTick
        Assert-Ui ([WowAutoFight.Native]::Sends -eq 0 -and $fightRows[0].Session.EntryPending) "Combat gate bypassed by $state."
    }
    Prepare-FightInput $fightRows[1] 'combat' 1000; Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 1 -and $script:autoFight.CommandGate.LastSentAt -eq 1000) 'Exact boundary did not send in second window.'
    Prepare-FightInput $fightRows[0] 'emergency' 1999; Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 1) 'Cross-window emergency bypassed common interval.'
    Prepare-FightInput $fightRows[0] 'move-forward' 2000; Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 2 -and [WowAutoFight.Native]::IsHolding) 'Movement start missing.'
    [WowAutoFight.Native]::Current.Action='combat'; $script:autoFight.Clock.ElapsedMilliseconds=2001
    Invoke-AutoFightTick
    Assert-Ui (-not [WowAutoFight.Native]::IsHolding -and [WowAutoFight.Native]::Releases -eq 1 -and $script:autoFight.CommandGate.LastSentAt -eq 2000) 'Release was delayed or consumed common interval.'
    Stop-AutoFightAll
    Prepare-FightInput $fightRows[0] 'loot' 2999; Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 2) 'Stopping/restarting bypassed common interval.'
    [WowAutoFight.Native]::FailSend=$true
    Prepare-FightInput $fightRows[0] 'combat' 3000; Invoke-AutoFightTick
    Assert-Ui ($script:autoFight.CommandGate.LastSentAt -eq 2000) 'Failed command advanced common clock.'
    [WowAutoFight.Native]::FailSend=$false
    Prepare-FightInput $fightRows[1] 'combat' 3000; Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 3) 'Failure prevented valid other-window retry.'
    Prepare-FightInput $fightRows[0] 'opening' 4000; Invoke-AutoFightTick
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 4 -and $fightRows[0].Session.OpeningSent) 'Initial encounter opening not sent.'
    function Tick-FightEncounter($Row,[string]$Action,[long]$Now,[string]$Recovery='none') {
        $script:autoFight.Clock.ElapsedMilliseconds=$Now
        [WowAutoFight.Native]::Current.Action=$Action; [WowAutoFight.Native]::Current.Recovery=$Recovery
        $pending=New-AutoFightPending $Row $Row.Session $false 0
        $pending.Activated=$true; $pending.SampleAt=0; $pending.FirstBeat=0; $pending.FirstClass=1
        $script:autoFight.Pending=$pending; Invoke-AutoFightTick
    }
    Tick-FightEncounter $fightRows[0] 'opening' 6000
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 4 -and $fightRows[0].Session.State -eq 'waiting') 'Opening repeated before monster approached.'
    [WowAutoFight.Native]::Current.Combat=$true
    Tick-FightEncounter $fightRows[0] 'waiting' 6500 'emergency'
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 4 -and $fightRows[0].Message -match '不下发按键') 'Waiting emitted combat/emergency keys.'
    Tick-FightEncounter $fightRows[0] 'combat' 7000
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 5) 'Entering attack range did not attack.'
    [WowAutoFight.Native]::Current.Combat=$false; [WowAutoFight.Native]::Current.EncounterId=2
    Tick-FightEncounter $fightRows[0] 'opening' 8000
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 6) 'Changing monsters failed to issue a fresh opener.'
    [WowAutoFight.Native]::Current.EncounterId=3; [WowAutoFight.Native]::ReadsUntilEncounterChange=2
    Tick-FightEncounter $fightRows[0] 'opening' 9000
    Assert-Ui ([WowAutoFight.Native]::Sends -eq 6) 'Encounter changed immediately before input but opener was sent.'
    $baseline=[WowAutoFight.Native]::Sends
    foreach ($mode in @('recover','emergency')) {
        $base=if ($mode -eq 'recover') {10000L} else {20000L}
        [WowAutoFight.Native]::Current.Combat=($mode -eq 'emergency')
        Tick-FightEncounter $fightRows[0] 'idle' $base $mode
        $baseline++
        Assert-Ui ([WowAutoFight.Native]::Sends -eq $baseline) 'Production adapter did not send recovery entry.'
        Tick-FightEncounter $fightRows[0] 'idle' ($base+2000) $mode
        [WowAutoFight.Native]::Current.EncounterId++
        Tick-FightEncounter $fightRows[0] 'combat' ($base+4000) $mode
        Assert-Ui ([WowAutoFight.Native]::Sends -eq $baseline) 'Production adapter repeated recovery.'
        Tick-FightEncounter $fightRows[0] 'idle' ($base+5000)
        Tick-FightEncounter $fightRows[0] 'idle' ($base+6000) $mode
        $baseline++
        Assert-Ui ([WowAutoFight.Native]::Sends -eq $baseline) 'Production adapter did not reset on recovery exit.'
        Tick-FightEncounter $fightRows[0] 'idle' ($base+7000)
    }
    [WowAutoFight.Native]::Current.Combat=$false
    Prepare-FightInput $fightRows[0] 'idle' 30000
    Update-AutoFightControls
    $fightRows[0].MoveButtons[2].PerformClick()
    Invoke-AutoFightTick
    $baseline++
    Assert-Ui ([WowAutoFight.Native]::Sends -eq $baseline -and [WowAutoFight.Native]::IsHolding -and
        $script:autoFight.ActiveHold.Until -eq 30600) 'Script movement button/common duration not dispatched.'
    $script:autoFight.Clock.ElapsedMilliseconds=30600;Invoke-AutoFightTick
    Assert-Ui (-not [WowAutoFight.Native]::IsHolding) 'Script movement did not release at deadline.'
    $fightRows[0].MoveButtons[2].PerformClick()
    Tick-FightEncounter $fightRows[0] 'idle' 31000
    $baseline++
    Assert-Ui ([WowAutoFight.Native]::Sends -eq $baseline -and [WowAutoFight.Native]::IsHolding) 'Repeated manual direction request stayed latched off.'
    Stop-AutoFightAll
    Prepare-FightInput $fightRows[0] 'combat' 32000
    Invoke-AutoFightTick
    $cooldown=$fightRows[0].Session.NextActionAt
    Update-AutoFightControls
    $fightRows[0].MoveButtons[0].PerformClick()
    Assert-Ui ($fightRows[0].Session.NextActionAt -eq $cooldown -and -not $fightRows[0].Session.EntryPending) 'Movement request reset combat cooldown.'
    Assert-Ui ($script:scheduler.JumpEveryCycles -eq $fishJump -and (Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $fishIniHash -and (Get-FileHash -LiteralPath $fightSource).Hash -eq $fightSourceHash) 'Combat changed fishing settings or source configuration.'
    Write-Output 'PASS: combat settings 100 ms step/common draft/profile isolation/save/cancel/locked failure; mocked production input gate for all states, cross-window, release, restart and send failure. No real native operations.'
    Write-Output 'PASS: production combat UI adapter opens once, stays quiet through waiting/combat/emergency, attacks on approach, reopens for new monster and rechecks encounter before input.'
} finally {
    Close-AutoFightTab
    $tabs.SelectedTab=$tab
    if ([IO.File]::Exists($fightPath)) {[IO.File]::Delete($fightPath)}
}
