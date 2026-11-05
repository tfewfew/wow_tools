param([string]$BasePython)
$ErrorActionPreference='Stop'
if(-not $BasePython){
    $bundled=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    if(Test-Path -LiteralPath $bundled){$BasePython=$bundled}else{$BasePython=(Get-Command python.exe -ErrorAction Stop).Source}
}
$runtime=Join-Path $PSScriptRoot '.runtime'
& $BasePython -m venv $runtime
if($LASTEXITCODE -ne 0){throw 'Cannot create the private Python environment.'}
& (Join-Path $runtime 'Scripts/python.exe') -m pip install --disable-pip-version-check --timeout 120 --only-binary=:all: --index-url https://pypi.org/simple -r (Join-Path $PSScriptRoot 'requirements.txt')
if($LASTEXITCODE -ne 0){throw 'Character creation dependencies were not installed. Retry this script.'}
Write-Output 'Character creation runtime is ready. Restart wowAuto to use the embedded page.'
