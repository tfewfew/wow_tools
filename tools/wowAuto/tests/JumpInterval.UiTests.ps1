Stop-AllRows
$jumpSavedScheduler=$script:scheduler
$jumpSavedIni=[IO.File]::ReadAllBytes($script:settingsPath)
try {
    $script:scheduler=New-WowAutoScheduler
    Set-VersionWaitRanges 300 600 300 600 -JumpEveryCycles 0
    $s=Add-WowAutoTask $script:scheduler 'jump-ui-fixture' 300 600 0
    $script:scheduler.CyclesSinceJump['jump-ui-fixture']=1L
    $dialog=New-WaitSettingsDialog
    try {
        $dialog.Show($form)
        if ($env:WOWAUTO_NEW_SETTINGS_PREVIEW_DIRECTORY) {
            $bitmap=New-Object Drawing.Bitmap($dialog.Width,$dialog.Height)
            try {$dialog.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$dialog.Width,$dialog.Height))); $bitmap.Save((Join-Path $env:WOWAUTO_NEW_SETTINGS_PREVIEW_DIRECTORY 'fishing-settings.png'),[Drawing.Imaging.ImageFormat]::Png)}
            finally {$bitmap.Dispose()}
        }
        Assert-Ui ($dialog.Tag.JumpEveryCycles.Increment -eq 1 -and $dialog.Tag.JumpEveryCycles.Value -eq 0) 'Jump frequency control has bad default/step.'
        $dialog.Tag.JumpEveryCycles.Value=3
        Assert-Ui ($script:scheduler.JumpEveryCycles -eq 0) 'Editing jump draft changed active setting.'
        $dialog.Tag.Apply.PerformClick()
        Assert-Ui ($dialog.DialogResult -eq 'OK' -and $script:scheduler.JumpEveryCycles -eq 3 -and (Read-WowAutoSettingsIni $script:settingsPath).JumpEveryCycles -eq 3) 'Jump UI did not persist/apply.'
    } finally {$dialog.Dispose()}
    $script:scheduler.CyclesSinceJump['jump-ui-fixture']=2L
    $dialog=New-WaitSettingsDialog
    try {$dialog.Show($form); Assert-Ui ($dialog.Tag.JumpEveryCycles.Value -eq 3) 'Reopen lost frequency.'; $dialog.Tag.JumpEveryCycles.Value=4; $dialog.Tag.Cancel.PerformClick()}
    finally {$dialog.Dispose()}
    Assert-Ui ($script:scheduler.JumpEveryCycles -eq 3 -and $script:scheduler.CyclesSinceJump['jump-ui-fixture'] -eq 2) 'Cancel applied frequency/reset progress.'
    $locked=[IO.File]::Open($script:settingsPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try {
        $dialog=New-WaitSettingsDialog
        try {$dialog.Show($form); $dialog.Tag.JumpEveryCycles.Value=5; $dialog.Tag.Apply.PerformClick(); Assert-Ui ($dialog.DialogResult -ne 'OK' -and $dialog.Tag.Error.Text -ne '' -and $script:scheduler.JumpEveryCycles -eq 3 -and $script:scheduler.CyclesSinceJump['jump-ui-fixture'] -eq 2) 'Locked save applied jump settings.'}
        finally {$dialog.Dispose()}
    } finally {$locked.Dispose()}
    $full=[IO.File]::ReadAllText($script:settingsPath)
    foreach($value in @('-1','1.5','1000001','abc')) {
        $rejected=$false; try {Set-VersionWaitRanges 300 600 300 600 -JumpEveryCycles $value} catch {$rejected=$true}
        Assert-Ui ($rejected -and $script:scheduler.JumpEveryCycles -eq 3 -and [IO.File]::ReadAllText($script:settingsPath) -ceq $full) 'Invalid jump frequency applied.'
    }
    [IO.File]::WriteAllText($script:settingsPath,($full+"JumpEveryCycles=1`r`n"))
    $rejected=$false; try {$null=Read-WowAutoSettingsIni $script:settingsPath} catch {$rejected=$true}
    Assert-Ui $rejected 'Duplicate jump key accepted.'
    $legacy=$full -replace '(?m)^JumpEveryCycles=.*\r?\n?',''
    [IO.File]::WriteAllText($script:settingsPath,$legacy); Import-VersionWaitSettings
    Assert-Ui ($script:settingsWarning -eq '' -and $script:scheduler.JumpEveryCycles -eq 3 -and [IO.File]::ReadAllText($script:settingsPath) -ceq $legacy) 'Legacy INI changed frequency or was rewritten.'
    Set-WowAutoJumpInterval $script:scheduler 0
    [IO.File]::WriteAllText($script:settingsPath,$full); Import-VersionWaitSettings
    Assert-Ui ($script:scheduler.JumpEveryCycles -eq 3) 'Startup failed to read jump setting.'
    # Exercise the production UI scheduler with an inherited due jump, using mocked
    # process/color/input adapters. No initial green or waiting tick may send Space.
    $testRows=@($script:rows.Values)
    foreach ($flavor in @('titan','forerver')) {
        Stop-AllRows
        $script:scheduler=New-WowAutoScheduler
        Set-WowAutoJumpInterval $script:scheduler 1
        $row=@($testRows | Where-Object {$_.Client.Flavor -eq $flavor})[0]
        $row.Process.HasExited=$false; $row.Process.FocusAllowed=$true; $row.Process.ScanColor='green'
        $script:scheduler.CyclesSinceJump[$row.Key]=1L
        $row.State=Add-WowAutoTask $script:scheduler $row.Key 100 100 0
        $script:pendingWork=$null; $script:workerFocus=$row.Process.Id; $script:workerKeys=@()
        Invoke-SchedulerTick 0
        Assert-Ui ($script:workerKeys.Count -eq 0 -and $row.State.Mode -eq 'Wait' -and
            -not $row.State.PostReelJumpAllowed) 'Inherited due jump interrupted fishing on UI restart.'
        Invoke-SchedulerTick 99
        Assert-Ui ($script:workerKeys.Count -eq 0) 'Waiting for reel emitted an early jump.'
        Invoke-SchedulerTick 100
        Assert-Ui (($script:workerKeys -join ',') -eq "$($row.Process.Id):187" -and $row.State.PostReelJumpAllowed) 'Next successful reel was replaced by jump.'
        Invoke-SchedulerTick 1099
        Assert-Ui ($script:workerKeys.Count -eq 1) 'Post-reel jump bypassed cooldown.'
        Invoke-SchedulerTick 1100
        Assert-Ui (($script:workerKeys -join ',') -eq "$($row.Process.Id):187,$($row.Process.Id):32" -and
            -not $row.State.PostReelJumpAllowed) 'Post-reel UI jump missing or permission not consumed.'
    }
    Stop-AllRows
} finally {$script:scheduler=$jumpSavedScheduler; [IO.File]::WriteAllBytes($script:settingsPath,$jumpSavedIni); Import-VersionWaitSettings}
Write-Output 'PASS: fishing jump setting draft/save/reload/cancel/locked/invalid/duplicate/legacy INI. Temporary configuration only.'
Write-Output 'PASS: both clients production UI scheduler keeps inherited jump quiet during fishing, reels first, respects cooldown and jumps once afterward. All game operations mocked.'
