$ErrorActionPreference='Stop'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\wowAuto.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$source=$ast.Find({param($node)
    $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $node.Value.Contains('namespace WowAuto')
},$true)
Add-Type -TypeDefinition $source.Value
# Only pure production methods are called. No window/process/input APIs execute.
$titan='D:\games\_classic_titan_\WowClassic.exe'
$forever='D:\games\_cn_beta_\Wow.exe'
foreach ($case in @(
    @($titan,'3.80.2.70177','titan'), @($forever,'1.60.1.70338','forerver'),
    @('d:\GAMES\_CN_BETA_\WOW.EXE','1.60.2.99999','forerver'),
    @('D:\games\_retail_\Wow.exe','12.1.0.69933',$null),
    @('D:\games\_retail_\Wow.exe','1.60.1.70338',$null),
    @($forever,'12.1.0.69933',$null), @($titan,'1.60.1.70338',$null),
    @('D:\games\_classic_era_\WowClassic.exe','1.15.0',$null), @($forever,'',$null)
)) {
    if ([WowAuto.NativeInput]::GetClientFlavor($case[0],$case[1]) -cne $case[2]) { throw "Wrong client classification: $($case[0]) / $($case[1])" }
}
if (-not [WowAuto.NativeInput]::MatchesClientIdentity('Wow',123,$forever,'1.60.1.70338',123,$forever)) { throw 'Valid Infinite process rejected.' }
foreach ($case in @(
    @('Wow',124,$forever,'1.60.1.70338',123,$forever),
    @('Other',123,$forever,'1.60.1.70338',123,$forever),
    @('Wow',123,$forever,'1.60.1.70338',123,'C:\other\_cn_beta_\Wow.exe'),
    @('Wow',123,$forever,'12.1.0.69933',123,$forever)
)) {
    if ([WowAuto.NativeInput]::MatchesClientIdentity($case[0],$case[1],$case[2],$case[3],$case[4],$case[5])) { throw 'Changed/unsupported client passed native identity validation.' }
}
foreach ($case in @(
    @(@(20,20,820,520),@(0,0,1920,1080),'左上'),
    @(@(1100,20,1900,520),@(0,0,1920,1080),'右上'),
    @(@(20,560,820,1060),@(0,0,1920,1080),'左下'),
    @(@(1100,560,1900,1060),@(0,0,1920,1080),'右下'),
    @(@(560,290,1360,790),@(0,0,1920,1080),'居中'),
    @(@(0,0,1920,1080),@(0,0,1920,1080),'居中'),
    @(@(-1900,20,-1100,520),@(-1920,0,0,1080),'左上'),
    @(@(20,-1060,820,-560),@(0,-1080,1920,0),'左上'),
    @(@(0,0,0,0),@(0,0,1920,1080),'位置未知')
)) {
    $r=$case[0]; $s=$case[1]
    if ([WowAuto.NativeInput]::ClassifyWindowPosition($r[0],$r[1],$r[2],$r[3],$s[0],$s[1],$s[2],$s[3]) -ne $case[2]) { throw "Wrong window position: $($case[2])" }
}
Write-Output 'PASS: native client/path/build identity, retail rejection, PID reuse/path/name changes, quadrants/center/fullscreen and negative monitor coordinates. Pure methods only.'
