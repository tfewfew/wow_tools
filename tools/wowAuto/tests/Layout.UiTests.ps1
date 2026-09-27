# Executed in the stopped/mock UI immediately after the initial Shown layout.
if ($countLabel.Parent -ne $toolbar -or $countLabel.Left -le $stopAllButton.Right) {
    throw 'Process count must follow Stop All within the autofish toolbar.'
}
if (-not $toolbar.ClientRectangle.Contains($holdInput.Bounds)) { throw 'Hold input is clipped.' }
$holdInput.Value=275
if ($script:scheduler.ReelHoldMs -ne 275) { throw 'Hold input not connected to scheduler.' }
$holdInput.Value=100
$screenArea=[System.Windows.Forms.Screen]::FromControl($form).WorkingArea
if (-not $screenArea.Contains($form.Bounds)) { throw 'Startup window exceeds screen working area.' }
$totalRowsHeight=$list.Padding.Vertical
foreach ($row in $script:rows.Values) { $totalRowsHeight += $row.Panel.Height+$row.Panel.Margin.Vertical }
if ($form.Height -lt $screenArea.Height -and $totalRowsHeight -gt $list.ClientSize.Height) {
    throw 'Startup height clips rows even though screen space is available.'
}
Write-Output 'PASS: hold input binding, process count after Stop All, content-fit startup bounds and visible rows.'
