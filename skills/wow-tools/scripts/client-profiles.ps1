# Read-only deployment planning. Keep each client's source and destination separate.
function Get-WowToolsDeploymentProfiles {
    param(
        [Parameter(Mandatory=$true)][string]$RepoRoot,
        [ValidateSet('all','titan','forerver')][string]$Flavor='all',
        [string]$GameRoot,
        [string]$TitanGameRoot='C:\Program Files (x86)\World of Warcraft\_classic_titan_',
        [string]$ForerverGameRoot='C:\Program Files (x86)\World of Warcraft\_cn_beta_'
    )
    if ($GameRoot -and $Flavor -eq 'all') { throw 'Choose -Flavor titan or forerver when passing -GameRoot.' }
    $repoPath=[IO.Path]::GetFullPath($RepoRoot)
    $profiles=@(
        [pscustomobject]@{Flavor='titan'; GameRoot=$TitanGameRoot; Executable='WowClassic.exe'; VersionPrefix='3.80.'; Interface=38002},
        [pscustomobject]@{Flavor='forerver'; GameRoot=$ForerverGameRoot; Executable='Wow.exe'; VersionPrefix='1.60.'; Interface=16001}
    )
    $targets=@{}
    foreach ($profile in $profiles) {
        if ($Flavor -ne 'all' -and $profile.Flavor -ne $Flavor) { continue }
        $gamePath=if ($GameRoot) { $GameRoot } else { $profile.GameRoot }
        # Remove optional trailing separators before comparing Windows directory identities.
        $fullGamePath=[IO.Path]::GetFullPath($gamePath)
        $profile.GameRoot=if ($fullGamePath -eq [IO.Path]::GetPathRoot($fullGamePath)) { $fullGamePath } else {
            $fullGamePath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        }
        if ($targets.ContainsKey($profile.GameRoot)) { throw 'Client profiles must use different game directories.' }
        $targets[$profile.GameRoot]=$true
        $profile | Add-Member NoteProperty Source (Join-Path $repoPath "addon\$($profile.Flavor)\wow_tools")
        $profile | Add-Member NoteProperty AddOns ([IO.Path]::GetFullPath((Join-Path $profile.GameRoot 'Interface\AddOns')))
        $profile | Add-Member NoteProperty Target (Join-Path $profile.AddOns 'wow_tools')
        $profile
    }
}

function Test-WowToolsClientVersion($Profile, [string]$Version) {
    return $Version.StartsWith($Profile.VersionPrefix, [StringComparison]::Ordinal)
}
