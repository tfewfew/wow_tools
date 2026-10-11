$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\scripts\client-profiles.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
function Assert-Profile($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
$profiles=@(Get-WowToolsDeploymentProfiles -RepoRoot $repo)
Assert-Profile ($profiles.Count -eq 2) 'Default sync does not target both clients.'
$titan=$profiles[0]; $forever=$profiles[1]
Assert-Profile ($titan.Source -eq (Join-Path $repo 'addon\titan\wow_tools') -and $forever.Source -eq (Join-Path $repo 'addon\forerver\wow_tools')) 'Source archives are not independent.'
Assert-Profile ($titan.Target -ne $forever.Target -and $titan.Executable -eq 'WowClassic.exe' -and $forever.Executable -eq 'Wow.exe') 'Client destinations or executable identities mixed.'
Assert-Profile ((Test-WowToolsClientVersion $titan '3.80.2.70177') -and (Test-WowToolsClientVersion $forever '1.60.1.70338')) 'Expected client versions rejected.'
Assert-Profile (-not (Test-WowToolsClientVersion $forever '12.1.0.69933') -and -not (Test-WowToolsClientVersion $titan '1.60.1.70338')) 'Wrong-client deployment accepted.'
foreach ($profile in $profiles) {
    $toc=Join-Path $profile.Source 'wow_tools.toc'
    Assert-Profile (Select-String -LiteralPath $toc -Pattern "^## Interface:\s*$($profile.Interface)\s*$" -Quiet) 'Source interface does not match profile.'
}
$single=@(Get-WowToolsDeploymentProfiles -RepoRoot $repo -Flavor forerver -GameRoot 'C:\test-games\infinite')
Assert-Profile ($single.Count -eq 1 -and $single[0].Flavor -eq 'forerver' -and $single[0].Target -eq 'C:\test-games\infinite\Interface\AddOns\wow_tools') 'Explicit client override targets wrong archive.'
$rejected=$false
try { $null=@(Get-WowToolsDeploymentProfiles -RepoRoot $repo -GameRoot 'C:\test-games\ambiguous') } catch { $rejected=$true }
Assert-Profile $rejected 'Ambiguous all-client GameRoot override accepted.'
$rejected=$false
try { $null=@(Get-WowToolsDeploymentProfiles -RepoRoot $repo -TitanGameRoot 'C:\test-games\same' -ForerverGameRoot 'C:\test-games\same') } catch { $rejected=$true }
Assert-Profile $rejected 'Both archives could overwrite the same game directory.'
$rejected=$false
try { $null=@(Get-WowToolsDeploymentProfiles -RepoRoot $repo -TitanGameRoot 'C:\test-games\same' -ForerverGameRoot 'c:\test-games\SAME\') } catch { $rejected=$true }
Assert-Profile $rejected 'Directory case or trailing slash could bypass separate-client protection.'
Write-Output 'PASS: separate source/target profiles, TOC/client identity, retail rejection, single-client override and ambiguous/duplicate-root protection. Read-only checks.'
