function Assert-ShutdownUi($Condition,[string]$Message){if(-not $Condition){throw $Message}}
# Test the real controls/countdown with a synthetic clock and queued exit acknowledgements.
Stop-AllRows
$savedShutdown=@{Start=${function:Start-WowAutoGameShutdown};Show=${function:Show-WowAutoShutdownDialog};State=$script:shutdownState;TabsEnabled=$tabs.Enabled}
$script:shutdownState=@{Deadline=0L;Started=$false;DialogOpen=$false;Operations=@()}
$script:shutdownTestStarts=0;$script:shutdownTestCloses=0;$script:shutdownTestChoice=$null
$shutdownClosingHandler=[Windows.Forms.FormClosingEventHandler]{param($sender,$eventArgs) $script:shutdownTestCloses++;$eventArgs.Cancel=$true}
$form.Add_FormClosing($shutdownClosingHandler)
function Start-WowAutoGameShutdown {$script:shutdownTestStarts++;return $script:shutdownTestOperations}
function Show-WowAutoShutdownDialog {return $script:shutdownTestChoice}
try {
    $dialog=New-WowAutoShutdownDialog
    try {
        $dialog.Show();[Windows.Forms.Application]::DoEvents()
        Assert-ShutdownUi ($dialog.Tag.Seconds.Minimum -eq 1 -and $dialog.Tag.Seconds.DecimalPlaces -eq 0 -and $dialog.Tag.Seconds.Value -eq 3600 -and -not $dialog.Tag.Cancel.Enabled) 'Shutdown dialog lost its seconds input/default/cancel state.'
        foreach($control in $dialog.Controls){Assert-ShutdownUi ($dialog.ClientRectangle.Contains($control.Bounds)) 'Shutdown dialog control is clipped.'}
    } finally {$dialog.Dispose()}
    $script:shutdownTestChoice=@{Seconds=10;Cancel=$false};$shutdownButton.PerformClick()
    Assert-ShutdownUi ($shutdownButton.Text -eq '倒计时：10秒' -and $script:shutdownState.Deadline -gt 0) 'Countdown button did not open the configured dialog or show its duration.'
    $original=$script:shutdownState.Deadline;$script:shutdownTestChoice=$null;$shutdownButton.PerformClick()
    Assert-ShutdownUi ($script:shutdownState.Deadline -eq $original) 'Dismissing the dialog altered the active countdown.'
    $script:shutdownTestChoice=@{Cancel=$true};$shutdownButton.PerformClick()
    Invoke-WowAutoShutdownTick ([long]::MaxValue-1)
    Assert-ShutdownUi ($shutdownButton.Text -eq '结束倒计时' -and $script:shutdownTestStarts -eq 0) 'Cancelled countdown still initiated an exit.'
    foreach($invalid in @('0','-1','1.5','abc','2147483648')){
        $failed=$false;try{Set-WowAutoShutdownCountdown $invalid 1000}catch{$failed=$true}
        Assert-ShutdownUi ($failed -and $script:shutdownState.Deadline -eq 0) 'Invalid countdown was accepted.'
    }
    Set-WowAutoShutdownCountdown 3 1000
    Invoke-WowAutoShutdownTick 1001
    Assert-ShutdownUi ($shutdownButton.Text -eq '倒计时：3秒') 'Countdown truncated the remaining partial second.'
    Invoke-WowAutoShutdownTick 3999
    Assert-ShutdownUi ($shutdownButton.Text -eq '倒计时：1秒' -and $script:shutdownTestStarts -eq 0) 'Countdown exited before its exact deadline.'
    $script:shutdownTestOperations=@(1,2 | ForEach-Object {
        $owner=New-Object WowAuto.Threading.Endpoint;$owner.Key='test-shutdown:'+$_;$owner.Pid=900+$_;$owner.StartTicks=1
        [pscustomobject]@{Done=[pscustomobject]@{IsSet=$false};Success=$true;Owner=$owner;Result='{"Exited":true}';Version=0}
    })
    Invoke-WowAutoShutdownTick 4000
    Assert-ShutdownUi ($shutdownButton.Text -eq '倒计时：0秒' -and $script:shutdownTestStarts -eq 1 -and $script:shutdownTestCloses -eq 0 -and -not $restartButton.Enabled -and -not $tabs.Enabled) 'Expiry did not start once and wait for all exit acknowledgements.'
    Invoke-WowAutoShutdownTick 9000;$script:shutdownTestOperations[0].Done.IsSet=$true
    Invoke-WowAutoShutdownTick 10000
    Assert-ShutdownUi ($script:shutdownTestStarts -eq 1 -and $script:shutdownTestCloses -eq 0) 'Countdown duplicated exits or closed before the last process replied.'
    $script:shutdownTestOperations[1].Done.IsSet=$true
    Invoke-WowAutoShutdownTick 10001;Invoke-WowAutoShutdownTick 10002
    Assert-ShutdownUi ($script:shutdownTestCloses -eq 0 -and -not $script:restartRequested -and $form.Visible -and -not $form.IsDisposed -and
        $script:shutdownState.Deadline -eq 0 -and -not $script:shutdownState.Started -and $tabs.Enabled -and $refreshButton.Enabled -and $restartButton.Enabled -and $shutdownButton.Enabled -and
        $shutdownButton.Text -eq '结束倒计时' -and $script:shutdownTestStarts -eq 1) 'Completed countdown closed/restarted the script, left controls locked or retriggered exits.'
    Set-WowAutoShutdownCountdown 1 1000;$script:shutdownTestOperations=@()
    Invoke-WowAutoShutdownTick 2000
    Assert-ShutdownUi ($script:shutdownTestStarts -eq 2 -and $script:shutdownTestCloses -eq 0 -and $script:shutdownState.Deadline -eq 0 -and $shutdownButton.Enabled -and $form.Visible) 'Empty-process countdown did not reset for reuse while keeping the script open.'
    Set-WowAutoShutdownCountdown 1 1000
    $script:shutdownTestOperations=@([pscustomobject]@{Done=[pscustomobject]@{IsSet=$true};Success=$false;Owner=$owner;Version=0;Error='fixture exit failure'})
    Invoke-WowAutoShutdownTick 2000
    Assert-ShutdownUi ($script:shutdownTestCloses -eq 0 -and -not $script:shutdownState.Started -and $refreshButton.Enabled -and $form.Visible) 'Failed exit left the script closed or controls locked.'
    Write-Output 'PASS: shutdown dialog/layout, seconds validation, countdown boundaries/cancel, all-reply barrier, no script close/restart, restored controls and repeat/empty/failed countdowns. No game input or termination.'
} finally {
    $form.Remove_FormClosing($shutdownClosingHandler)
    $script:shutdownState=$savedShutdown.State;$tabs.Enabled=$savedShutdown.TabsEnabled
    ${function:Start-WowAutoGameShutdown}=$savedShutdown.Start;${function:Show-WowAutoShutdownDialog}=$savedShutdown.Show
    $shutdownButton.Text='结束倒计时';Update-BatchControls
}
