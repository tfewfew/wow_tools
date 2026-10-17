# Executed in the stopped/mock UI immediately after the initial Shown layout.
if ($countLabel.Parent -ne $toolbar -or $countLabel.Left -le $stopAllButton.Right) {
    throw 'Process count must follow Stop All within the autofish toolbar.'
}
if (@($toolbar.Controls | Where-Object { $_ -is [System.Windows.Forms.NumericUpDown] }).Count) { throw 'Hold input remains in toolbar.' }
if (@($toolbar.Controls | Where-Object { $_ -is [System.Windows.Forms.CheckBox] }).Count) { throw 'Audio/item checkbox remains in toolbar.' }
if (-not $toolbar.ClientRectangle.Contains($restartButton.Bounds) -or $restartButton.Left -lt $settingsButton.Right) {
    throw 'Restart button is clipped or overlaps settings.'
}
foreach ($row in $script:rows.Values) {
    if (@($row.Panel.Controls | Where-Object {$_ -is [System.Windows.Forms.ComboBox] -or $_.Text -match '角色已刷新'}).Count) {
        throw 'Subaccount selector or refreshed-role text remains in main process row.'
    }
    if ($row.Panel.BackColor.ToArgb() -eq $headings.BackColor.ToArgb()) {throw 'Process headings and rows must use different grays.'}
    if (-not $row.Panel.ClientRectangle.Contains($row.Status.Bounds) -or $row.Status.Bottom -ne $row.Panel.ClientSize.Height -or
        -not ($row.Status.Anchor -band [Windows.Forms.AnchorStyles]::Bottom)) {
        throw 'Realtime status must extend and anchor to the bottom of its process panel.'
    }
    if (-not $row.Panel.ClientRectangle.Contains($row.RotationLabel.Bounds) -or
        -not $row.Panel.ClientRectangle.Contains($row.RotationProgress.Bounds) -or
        $row.RotationProgress.Top -lt $row.RotationLabel.Bottom -or $row.RotationLabel.Left -lt $row.RotationButton.Right -or
        $row.RotationLabel.Right -gt $row.Status.Left -or $row.RotationProgress.Right -gt $row.Status.Left) {
        throw 'Rotation summary/progress is clipped or overlaps other controls.'
    }
    $height=$row.Panel.Height
    try {
        $row.Panel.Height+=40;$row.Panel.PerformLayout()
        if ($row.Status.Bottom -ne $row.Panel.ClientSize.Height) {throw 'Status lost bottom alignment after resizing.'}
    } finally {$row.Panel.Height=$height}
}
$screenArea=[System.Windows.Forms.Screen]::FromControl($form).WorkingArea
if (-not $screenArea.Contains($form.Bounds)) { throw 'Startup window exceeds screen working area.' }
$totalRowsHeight=$list.Padding.Vertical
foreach ($row in $script:rows.Values) { $totalRowsHeight += $row.Panel.Height+$row.Panel.Margin.Vertical }
if ($form.Height -lt $screenArea.Height -and $totalRowsHeight -gt $list.ClientSize.Height) {
    throw 'Startup height clips rows even though screen space is available.'
}
Write-Output 'PASS: settings-only hold input, process count after Stop All, visible rotation summary/progress, content-fit startup bounds and visible rows.'
