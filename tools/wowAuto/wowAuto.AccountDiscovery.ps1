# Pure account ownership matching. Callers provide one client's saved character catalog.
function Resolve-OcrAccount($Screen,$Candidates) {
    if($Screen.Kind -ne 'menu'){return [pscustomobject]@{Account='';Kind='unknown';Matches=@()}}
    $names=@($Candidates | ForEach-Object {$_.Names} | Sort-Object -Unique)
    $exact=@();$fuzzy=@()
    foreach($target in $Screen.Targets) {
        if($target.MenuRow -lt 1 -or $target.MenuRow -gt 10){continue}
        $text=if($target.PSObject.Properties['RawName'] -and $target.RawName){[string]$target.RawName}else{[string]$target.Name}
        if($text -cnotmatch '^[\p{L}\p{M}]{2,24}$'){continue}
        $name=$null;$isExact=$text -cin $names
        if($isExact){$name=$text}else{
            $match=Resolve-RotationOcrName $text $names
            if(-not $match.Ambiguous -and $match.Name -cin $names){$name=$match.Name}
        }
        if(-not $name){continue}
        $owners=@($Candidates | Where-Object {$name -cin $_.Names} | ForEach-Object Account | Sort-Object -Unique)
        $hit=[pscustomobject]@{Name=$name;RawName=$text;Owners=$owners}
        if($isExact){$exact+=,$hit}else{$fuzzy+=,$hit}
    }
    # Exact evidence takes precedence over a possible one-glyph coincidence.
    $hits=@(if($exact.Count){$exact}else{$fuzzy})
    if(-not $hits.Count){return [pscustomobject]@{Account='';Kind='missing';Matches=@()}}
    $possible=@($hits[0].Owners)
    foreach($hit in $hits){$possible=@($possible | Where-Object {$_ -cin $hit.Owners})}
    if($possible.Count -gt 1 -and $exact.Count -and $fuzzy.Count){
        foreach($hit in $fuzzy){$possible=@($possible | Where-Object {$_ -cin $hit.Owners})}
        $hits+=@($fuzzy)
    }
    if($possible.Count -eq 1){return [pscustomobject]@{Account=$possible[0];Kind='matched';Matches=@($hits.Name | Sort-Object -Unique)}}
    return [pscustomobject]@{Account='';Kind=$(if($possible.Count){'ambiguous'}else{'conflict'});Matches=@($hits.Name | Sort-Object -Unique)}
}
