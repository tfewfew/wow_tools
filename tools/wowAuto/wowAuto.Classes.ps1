# Classic class identities and their representative text colors, shared by all UI pages.
$script:wowClassNames=[ordered]@{'1'='战士';'2'='圣骑士';'3'='猎人';'4'='潜行者';'5'='牧师';'6'='死亡骑士';'7'='萨满祭司';'8'='法师';'9'='术士';'11'='德鲁伊'}
$script:wowClassColors=@{'1'='#C79C6E';'2'='#F58CBA';'3'='#ABD473';'4'='#FFF569';'5'='#FFFFFF';'6'='#C41F3B';'7'='#0070DE';'8'='#69CCF0';'9'='#9482C9';'11'='#FF7D0A'}
function Get-WowClassName([int]$ClassId=0) {
    if($script:wowClassNames.Contains([string]$ClassId)){return $script:wowClassNames[[string]$ClassId]}
    return '未知'
}
function Get-WowClassColor([int]$ClassId=0) {
    $hex=$script:wowClassColors[[string]$ClassId]
    if(-not $hex){$hex='#FFFFFF'}
    return [Drawing.ColorTranslator]::FromHtml($hex)
}
function Get-WowClassId([string]$Name) {
    foreach($key in $script:wowClassNames.Keys){if($script:wowClassNames[$key] -ceq $Name){return [int]$key}}
    return 0
}
