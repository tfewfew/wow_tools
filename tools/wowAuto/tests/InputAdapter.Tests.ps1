$ErrorActionPreference='Stop'
# Execute the production PowerShell adapter against an inert C# stand-in.
# Refuse an existing NativeInput type to ensure this test can never emit real keys.
if ('WowAuto.NativeInput' -as [type]) { throw 'Run this test in a fresh PowerShell process.' }
Add-Type -TypeDefinition @'
namespace WowAuto {
    public static class NativeInput {
        public static int LastProcessId;
        public static ushort LastKey;
        public static int Calls;
        public static bool PressCtrlNumber(int processId, ushort number) {
            LastProcessId = processId;
            LastKey = number;
            Calls++;
            return true;
        }
    }
}
'@
$tokens=$null
$parseErrors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '..\wowAuto.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$adapter=$ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Send-WorkerKey'
}, $true)
if ($null -eq $adapter) { throw 'Send-WorkerKey adapter not found.' }
. ([scriptblock]::Create($adapter.Extent.Text))
$UiTest=$false
$row=[pscustomobject]@{ Process=[pscustomobject]@{ Id=12345 } }
foreach ($key in @(0x31,0x32)) {
    $sent=Send-WorkerKey $row $key
    if (-not $sent -or [WowAuto.NativeInput]::LastProcessId -ne 12345 -or [WowAuto.NativeInput]::LastKey -ne $key) {
        throw 'Production adapter did not pass the expected process/key to the stub.'
    }
}
if ([WowAuto.NativeInput]::Calls -ne 2) { throw 'Unexpected adapter call count.' }
Write-Output 'PASS: actual PowerShell input adapter converts both Ctrl+1/Ctrl+2 key codes under Windows PowerShell. Native input is replaced with an inert stub.'
