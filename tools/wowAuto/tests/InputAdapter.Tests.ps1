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
        public static bool Ctrl, Shift, Alt;
        public static bool PressChord(int processId, ushort number, bool ctrl, bool shift, bool alt) {
            Ctrl=ctrl; Shift=shift; Alt=alt;
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
$script:keyBindings=@{
    Cast=[pscustomobject]@{Code=49; Ctrl=$true; Shift=$false; Alt=$false}
    Reel=[pscustomobject]@{Code=113; Ctrl=$false; Shift=$true; Alt=$true}
    Item=[pscustomobject]@{Code=51; Ctrl=$false; Shift=$false; Alt=$false}
    Jump=[pscustomobject]@{Code=32; Ctrl=$false; Shift=$false; Alt=$false}
}
foreach ($action in @('Cast','Reel','Item','Jump')) {
    $binding=$script:keyBindings[$action]
    $sent=Send-WorkerKey $row $action
    if (-not $sent -or [WowAuto.NativeInput]::LastProcessId -ne 12345 -or
        [WowAuto.NativeInput]::LastKey -ne $binding.Code -or
        [WowAuto.NativeInput]::Ctrl -ne $binding.Ctrl -or
        [WowAuto.NativeInput]::Shift -ne $binding.Shift -or
        [WowAuto.NativeInput]::Alt -ne $binding.Alt) { throw 'Wrong key/modifiers passed to native adapter.' }
}
if ([WowAuto.NativeInput]::Calls -ne 4) { throw 'Unexpected adapter call count.' }
Write-Output 'PASS: configured cast/reel/item key codes and modifiers reach inert native stub.'
