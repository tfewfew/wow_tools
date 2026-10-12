# This type substitutes every combat native operation before loading the UI module.
Add-Type -TypeDefinition @'
namespace WowAutoFight {
    public class Packet {
        public int ClassId=1, Heartbeat=1;
        public string Flavor="titan", Action="combat", Recovery="none";
        public bool Busy=false, Combat=false;
    }
    public static class Native {
        public static Packet Current=new Packet();
        public static int Sends=0, Releases=0;
        public static bool FailSend=false, IsHolding=false;
        public static bool IsAlive(object client) { return true; }
        public static bool Foreground(object client) { return true; }
        public static bool Activate(object client) { return true; }
        public static object Read(object client) { Current.Heartbeat++; return Current; }
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
        $dialog.Tag.Flavor.SelectedIndex=1; $dialog.Tag.Class.SelectedIndex=2
        $dialog.Tag.Bindings.CombatKey.Text='Ctrl+7'
        Assert-Ui ($dialog.Tag.CommandInterval.Value -eq 800 -and $script:autoFight.CommandGate.IntervalMs -eq 500) 'Profile selection reset common draft or draft applied early.'
        $dialog.Tag.Save.PerformClick()
        Assert-Ui ($dialog.IsDisposed -or -not $dialog.Visible) 'Combat save did not close dialog.'
        $saved=Read-AutoFightConfiguration $fightPath
        Assert-Ui ($saved.CommandIntervalMs -eq 800 -and $script:autoFight.Profiles['forerver:3'].CombatKey -eq 'Ctrl+7' -and $script:autoFight.Profiles['titan:3'].CombatKey -eq 'F6' -and $script:autoFight.CommandGate.LastSentAt -eq 100) 'Combat save lost common/profile isolation or reset last send.'
    } finally {$dialog.Dispose()}
    $dialog=New-AutoFightSettingsDialog
    try {$dialog.Show($form); Assert-Ui ($dialog.Tag.CommandInterval.Value -eq 800) 'Combat reopen lost saved interval.'; $dialog.Tag.CommandInterval.Value=900; $dialog.Tag.Cancel.PerformClick()}
    finally {$dialog.Dispose()}
    Assert-Ui ($script:autoFight.CommandGate.IntervalMs -eq 800) 'Combat cancel applied draft.'
    $locked=[IO.File]::Open($fightPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try {
        $dialog=New-AutoFightSettingsDialog
        try {
            $dialog.Show($form); $dialog.Tag.CommandInterval.Value=1000; $dialog.Tag.Bindings.CombatKey.Text='F12'; $dialog.Tag.Save.PerformClick()
            Assert-Ui ($dialog.Visible -and $dialog.Tag.Error.Text -ne '' -and $script:autoFight.CommandGate.IntervalMs -eq 800 -and $script:autoFight.Profiles['titan:1'].CombatKey -eq 'F6') 'Failed combat save partially applied draft.'
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
        [WowAutoFight.Native]::Current.Action=$State
        [WowAutoFight.Native]::Current.Recovery='none'
        $Row.Session=New-AutoFightSession $Now 1
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
    [WowAutoFight.Native]::Current.Action='idle'; $script:autoFight.Clock.ElapsedMilliseconds=2001
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
    Assert-Ui ($script:scheduler.JumpEveryCycles -eq $fishJump -and (Get-FileHash -LiteralPath $script:settingsPath).Hash -eq $fishIniHash -and (Get-FileHash -LiteralPath $fightSource).Hash -eq $fightSourceHash) 'Combat changed fishing settings or source configuration.'
    Write-Output 'PASS: combat settings 100 ms step/common draft/profile isolation/save/cancel/locked failure; mocked production input gate for all states, cross-window, release, restart and send failure. No real native operations.'
} finally {
    Close-AutoFightTab
    $tabs.SelectedTab=$tab
    if ([IO.File]::Exists($fightPath)) {[IO.File]::Delete($fightPath)}
}
