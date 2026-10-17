# Pure OCR interpretation shared by independent detector runspaces.
function Resolve-RotationOcrName([string]$Text,[string[]]$Configured) {
    # OCR may misread one glyph. Keep the text length and every other position exact.
    $matches=@(foreach ($name in $Configured) {
        if ($Text.Length -ne $name.Length -or $name.Length -lt 2) {continue}
        $different=0
        for ($i=0;$i -lt $name.Length;$i++) {
            if ($Text[$i] -cne $name[$i]) {$different++;if ($different -gt 1) {break}}
        }
        if ($different -le 1) {$name}
    })
    if ($matches.Count -eq 1) {return [pscustomobject]@{Name=$matches[0];Ambiguous=$false}}
    return [pscustomobject]@{Name=$Text;Ambiguous=($matches.Count -gt 1)}
}
function Get-RotationMenuGeometry($Ocr,$Bounds) {
    # The character list keeps its own UI scale when the game window changes size.
    # Calibrate a row grid from several yellow name lines, never from one target box.
    $centers=@($Ocr.Names | Where-Object {$_.Text -match '^[\p{L}\p{M}]+$'} |
        ForEach-Object {$Bounds.Y+($_.Y+$_.H/2)*$Bounds.H} |
        Where-Object {$_ -ge 0.08 -and $_ -le 0.80} | Sort-Object)
    $distinct=New-Object 'System.Collections.Generic.List[double]'
    foreach ($center in $centers) {
        if (-not $distinct.Count -or $center-$distinct[$distinct.Count-1] -gt 0.025) {$distinct.Add([double]$center)}
    }
    if ($distinct.Count -lt 3) {return $null}
    $gaps=@(for ($i=1;$i -lt $distinct.Count;$i++) {
        $gap=$distinct[$i]-$distinct[$i-1]
        if ($gap -ge 0.05 -and $gap -le 0.11) {$gap}
    })
    $gaps=@($gaps | Sort-Object)
    if ($gaps.Count -lt 2) {return $null}
    $step=[double]$gaps[[int][Math]::Floor($gaps.Count/2)]
    if (@($gaps | Where-Object {[Math]::Abs($_-$step) -gt 0.012}).Count -gt [Math]::Floor($gaps.Count/3)) {return $null}
    $firstIndex=[int][Math]::Round(($distinct[0]-0.119)/$step,[MidpointRounding]::AwayFromZero)
    if ($firstIndex -lt 0 -or $firstIndex -gt 3) {return $null}
    $offsets=@(for ($i=0;$i -lt $distinct.Count;$i++) {
        $index=$firstIndex+[int][Math]::Round(($distinct[$i]-$distinct[0])/$step,[MidpointRounding]::AwayFromZero)
        if ($index -ge 0 -and $index -lt 10) {$distinct[$i]-$index*$step}
    })
    $offsets=@($offsets | Sort-Object)
    if ($offsets.Count -lt 3) {return $null}
    $first=[double]$offsets[[int][Math]::Floor($offsets.Count/2)]
    if ($first -lt 0.08 -or $first -gt 0.17 -or
        @($distinct | Where-Object {[Math]::Abs(($_-$first)/$step-[Math]::Round(($_-$first)/$step)) -gt 0.20}).Count -gt 1) {return $null}
    return [pscustomobject]@{First=$first;Step=$step}
}
function Get-RotationMenuRow($Bounds,[double]$TextY,[double]$Tolerance=0.02,$Geometry=$null) {
    # The first-page character rows occupy fixed, height-scaled positions. OCR
    # identifies the row; the click uses its stable center instead of an OCR box.
    $first=if ($Geometry) {$Geometry.First} else {0.119}
    $step=if ($Geometry) {$Geometry.Step} else {0.0743}
    $index=[int][Math]::Round(($TextY-$first)/$step,[MidpointRounding]::AwayFromZero)+1
    $centerY=$first+($index-1)*$step
    if ($index -lt 1 -or $index -gt 10 -or [Math]::Abs($TextY-$centerY) -gt $Tolerance) {return $null}
    return [pscustomobject]@{Index=$index;X=($Bounds.X+$Bounds.W/2);Y=$centerY}
}
function Get-RotationOcrLog($Screen,[string]$Name) {
    $recognized=@(foreach ($target in @($Screen.Targets | Sort-Object MenuRow,Name)) {
        $position=if ($target.MenuRow) {'第'+$target.MenuRow+'个角色槽位'} else {'槽位未知'}
        $raw=if ($target.PSObject.Properties['RawName'] -and $target.RawName) {$target.RawName} else {$target.Name}
        if ($raw -cne $target.Name) {$position+' '+$raw+'→'+$target.Name} else {$position+' '+$raw}
    })
    $list=if ($recognized.Count) {$recognized -join '、'} else {'未识别到角色名'}
    $matched=@($Screen.Targets | Where-Object {$_.Name -ceq $Name -and -not $_.Ambiguous})
    $selection=if ($matched.Count -eq 1) {'已定位第'+$matched[0].MenuRow+'个角色槽位（'+$Name+'）'} else {'目标“'+$Name+'”未唯一定位，暂不点击'}
    return 'OCR角色列表：'+$list+'；'+$selection+'。'
}
function ConvertFrom-RotationOcr($Ocr,$Plan,[switch]$MenuWasConfirmed) {
    $configured=@($Plan.Slots | Where-Object {$_.Name} | ForEach-Object {$_.Name} | Select-Object -Unique)
    $bounds=if ($Ocr.PSObject.Properties['NamesBounds'] -and $Ocr.NamesBounds) {$Ocr.NamesBounds} else {[pscustomobject]@{X=0.79;Y=0;W=0.21;H=0.84}}
    $geometry=Get-RotationMenuGeometry $Ocr $bounds
    $server=@($Ocr.Lines | Where-Object {$_.X -gt 0.65 -and $_.Y -lt 0.15 -and $_.Text -match '^[0一_—\-口□]*选择服务器[一_—\-口□]*$'}).Count -gt 0
    # The name-text pass also isolates the yellow server button from its border.
    $server=$server -or @($Ocr.Names | Where-Object {$_.Text -eq '选择服务器' -and ($bounds.X+$_.X*$bounds.W) -gt 0.65 -and ($bounds.Y+$_.Y*$bounds.H) -lt 0.15}).Count -gt 0
    $enter=@($Ocr.Lines | Where-Object {$_.X -gt 0.25 -and $_.X -lt 0.70 -and $_.Y -gt 0.85 -and $_.Text -match '^[0一_—\-口□]*进入魔兽世界[一_—\-口□]*$'}).Count -gt 0
    $targets=@(foreach ($line in $Ocr.Names) {
        $y=$bounds.Y+($line.Y+$line.H/2)*$bounds.H
        if ($y -lt 0.08 -or $y -gt 0.80 -or ($y -lt 0.15 -and $line.Text -eq '选择服务器') -or $line.Text -notmatch '^[\p{L}\p{M}]+$') {continue}
        $match=Resolve-RotationOcrName $line.Text $configured
        # A uniquely matched name may have a shifted OCR box; unrelated text
        # retains the tighter 2% threshold.
        $tolerance=if (-not $match.Ambiguous -and $match.Name -cin $configured) {0.034} else {0.02}
        $row=Get-RotationMenuRow $bounds $y $tolerance $geometry
        if (-not $row) {continue}
        [pscustomobject]@{Name=$match.Name;RawName=$line.Text;Ambiguous=$match.Ambiguous;MenuRow=$row.Index;X=$row.X;Y=$row.Y}
    })
    # The normal pass can recover names that yellow-text preprocessing misread twice.
    foreach ($line in $Ocr.Lines) {
        if ($line.X -gt $bounds.X -and $line.Y -gt 0.08 -and $line.Y -lt 0.80) {
            $match=Resolve-RotationOcrName $line.Text $configured
            if (-not $match.Ambiguous -and $match.Name -cin $configured -and $match.Name -cnotin $targets.Name) {
                $row=Get-RotationMenuRow $bounds ($line.Y+$line.H/2) 0.034 $geometry
                if ($row) {$targets+=,[pscustomobject]@{Name=$match.Name;RawName=$line.Text;Ambiguous=$false;MenuRow=$row.Index;X=$row.X;Y=$row.Y}}
            }
        }
    }
    if ($server -or $enter) {
        return [pscustomobject]@{Kind='menu';Targets=$targets;RoleName=$null}
    }
    return [pscustomobject]@{Kind='unknown';Targets=@();RoleName=$null}
}
