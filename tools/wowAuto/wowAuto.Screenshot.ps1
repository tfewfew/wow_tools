if (-not ('WowAuto.ScreenshotHotkey' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'wowAuto.Screenshot.cs') -ReferencedAssemblies System.Drawing,System.Windows.Forms
}
$script:screenshotListener=$null
$script:screenshotInitialized=$false
$script:screenshotBusy=$false
$script:screenshotKeyEditing=$false
$script:screenshotWarning=''

function New-WowAutoScreenshotListener($Binding) {
    try {
        $listener=New-Object WowAuto.ScreenshotHotkey($Binding.Code,$Binding.Ctrl,$Binding.Shift,$Binding.Alt)
        $listener.Add_Pressed({Invoke-WowAutoScreenshot})
        return $listener
    }
    catch {throw ('截图热键 '+$Binding.Text+' 注册失败，请更换组合键或释放其他程序占用。'+$_.Exception.Message)}
}

function Initialize-WowAutoScreenshot {
    $script:screenshotInitialized=$true
    if (-not $script:screenshotBinding) {return}
    try {$script:screenshotListener=New-WowAutoScreenshotListener $script:screenshotBinding}
    catch {
        $script:screenshotWarning=$_.Exception.Message
        Write-WowAutoLog $script:screenshotWarning -Kind error
        $settingsSummary.Text=$script:screenshotWarning+' 可在“设置 → 截图”修改。'
    }
}

function Close-WowAutoScreenshot {
    $script:screenshotInitialized=$false
    if ($script:screenshotListener) {$script:screenshotListener.Dispose();$script:screenshotListener=$null}
}

function Invoke-WowAutoScreenshot {
    if ($script:screenshotBusy -or $script:screenshotKeyEditing -or $script:restartRequested -or $form.IsDisposed) {return}
    $script:screenshotBusy=$true
    $wasPaused=$false
    $shutdownWasEnabled=$shutdownTimer.Enabled
    $shutdownTimer.Stop()
    try {
        if ($script:useWorkers) {
            $wasPaused=$script:parallelHub.Paused
            if (-not $script:parallelHub.PauseAndWait(1500)) {throw '当前操作尚未结束，请稍后重新截图。'}
        }
        if ([WowAuto.ScreenshotSelection]::CopySelection()) {
            Write-WowAutoLog '框选截图已复制到剪贴板。' -Kind system
        }
    }
    catch {
        Write-WowAutoLog ('截图失败：'+$_.Exception.Message) -Kind error
        [void][Windows.Forms.MessageBox]::Show(('截图失败：'+$_.Exception.Message),'wowAuto 截图','OK','Warning')
    }
    finally {
        if ($shutdownWasEnabled -and -not $form.IsDisposed) {$shutdownTimer.Start()}
        if ($script:useWorkers) {$script:parallelHub.Paused=$wasPaused;$script:parallelHub.Wake.Set() | Out-Null}
        $script:screenshotBusy=$false
    }
}

function New-WowAutoScreenshotSettingsPage {
    $page=New-Object Windows.Forms.TabPage
    $page.Text='截图';$page.BackColor=$script:uiColors.Background;$page.AutoScroll=$true
    $label=New-Object Windows.Forms.Label
    $label.Text='全局截图组合键';$label.SetBounds(18,24,260,30)
    $bindings=@{Screenshot=$script:screenshotBinding}
    $inputBox=New-Object Windows.Forms.TextBox
    $inputBox.ReadOnly=$true;$inputBox.SetBounds(18,62,300,34)
    $inputBox.BackColor=$script:uiColors.Input;$inputBox.ForeColor=$script:uiColors.Text
    $inputBox.Text=if ($script:screenshotBinding) {$script:screenshotBinding.Text} else {'已停用'}
    $inputBox.Tag=[pscustomobject]@{Action='Screenshot';Bindings=$bindings}
    $inputBox.Add_Enter({$script:screenshotKeyEditing=$true})
    $inputBox.Add_Leave({$script:screenshotKeyEditing=$false})
    $page.Add_Disposed({$script:screenshotKeyEditing=$false})
    $inputBox.Add_PreviewKeyDown({param($sender,$e) $e.IsInputKey=$true})
    $inputBox.Add_KeyDown({param($sender,$e)
        $e.SuppressKeyPress=$true;$e.Handled=$true
        Set-KeyBinding $sender ([int]$e.KeyCode) $e.Control $e.Shift $e.Alt
    })
    $clear=New-Object WowAuto.DimButton
    $clear.Text='停用';$clear.SetBounds(334,60,100,36);Set-UiButtonStyle $clear
    $clear.Tag=$inputBox
    $clear.Add_Click({param($sender,$e) $sender.Tag.Tag.Bindings.Screenshot=$null;$sender.Tag.Text='已停用'})
    $hint=New-Object Windows.Forms.Label
    $hint.Text="点击输入框后按下包含 Ctrl 或 Alt 的组合键，默认 Ctrl+Alt+A。`r`n按热键后拖动鼠标框选，松开鼠标复制到剪贴板，可直接 Ctrl+V 粘贴。`r`nEsc 或右键取消。框选期间暂停自动操作，结束后恢复。"
    $hint.SetBounds(18,116,900,110)
    $status=New-Object Windows.Forms.Label
    $status.SetBounds(18,240,900,90)
    $status.Text=if ($script:screenshotWarning) {$script:screenshotWarning} elseif ($script:screenshotBinding) {'正在监听 '+$script:screenshotBinding.Text} else {'截图热键已停用。'}
    $save=New-Object WowAuto.DimButton
    $save.Text='保存截图设置';$save.SetBounds(18,346,220,38);Set-UiButtonStyle $save $true
    $save.Tag=[pscustomobject]@{Bindings=$bindings;Status=$status}
    $save.Add_Click({param($sender,$e)
        try {
            $t=$script:versionRanges.titan;$f=$script:versionRanges.forerver
            Set-VersionWaitRanges $t.MinimumMs $t.MaximumMs $f.MinimumMs $f.MaximumMs -ScreenshotKey $sender.Tag.Bindings.Screenshot.Text
            $sender.Tag.Status.Text=if ($script:screenshotBinding) {'已保存，正在监听 '+$script:screenshotBinding.Text} else {'已保存，截图热键已停用。'}
        }
        catch {$sender.Tag.Status.Text=$_.Exception.Message}
    })
    $page.Controls.AddRange([Windows.Forms.Control[]]@($label,$inputBox,$clear,$hint,$status,$save))
    return $page
}
