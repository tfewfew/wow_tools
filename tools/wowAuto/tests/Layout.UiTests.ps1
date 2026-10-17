# Executed in the stopped/mock UI immediately after the initial Shown layout.
if ($countLabel.Parent -ne $toolbar -or $countLabel.Left -le $stopAllButton.Right) {
    throw 'Process count must follow Stop All within the autofish toolbar.'
}
if (@($toolbar.Controls | Where-Object { $_ -is [System.Windows.Forms.NumericUpDown] }).Count) { throw 'Hold input remains in toolbar.' }
if (@($toolbar.Controls | Where-Object { $_ -is [System.Windows.Forms.CheckBox] -and $_ -ne $audioCheck }).Count) { throw 'Global item checkbox remains in toolbar.' }
if (-not $toolbar.ClientRectangle.Contains($audioCheck.Bounds)) { throw 'Audio mode checkbox is clipped.' }
if (-not $toolbar.ClientRectangle.Contains($restartButton.Bounds) -or $restartButton.Left -lt $audioCheck.Right) {
    throw 'Restart button is clipped or overlaps the audio checkbox.'
}
foreach ($row in $script:rows.Values) {
    if (-not $row.Panel.ClientRectangle.Contains($row.AccountBox.Bounds) -or $row.AccountBox.Left -le $row.RotationButton.Right) {
        throw 'Subaccount selector is clipped or overlaps rotation button.'
    }
    if (-not $row.Panel.ClientRectangle.Contains($row.RotationLabel.Bounds) -or
        -not $row.Panel.ClientRectangle.Contains($row.RotationProgress.Bounds) -or
        $row.RotationProgress.Top -lt $row.RotationLabel.Bottom -or $row.RotationProgress.Top -lt $row.AccountBox.Bottom) {
        throw 'Rotation summary/progress is clipped or overlaps other controls.'
    }
}
$screenArea=[System.Windows.Forms.Screen]::FromControl($form).WorkingArea
if (-not $screenArea.Contains($form.Bounds)) { throw 'Startup window exceeds screen working area.' }
$totalRowsHeight=$list.Padding.Vertical
foreach ($row in $script:rows.Values) { $totalRowsHeight += $row.Panel.Height+$row.Panel.Margin.Vertical }
if ($form.Height -lt $screenArea.Height -and $totalRowsHeight -gt $list.ClientSize.Height) {
    throw 'Startup height clips rows even though screen space is available.'
}
Write-Output 'PASS: settings-only hold input, process count after Stop All, visible rotation summary/progress, content-fit startup bounds and visible rows.'
