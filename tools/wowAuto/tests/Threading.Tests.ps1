$ErrorActionPreference='Stop'
$tool=Split-Path $PSScriptRoot -Parent
Add-Type -Path @((Join-Path $tool 'wowAuto.Threading.cs'),(Join-Path $tool 'autoFight.Native.cs'),(Join-Path $PSScriptRoot 'Threading.Fixtures.cs')) -ReferencedAssemblies System.Core,System.Drawing
function Assert-Threading($Condition,[string]$Message){if(-not $Condition){throw $Message}}
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-threading-'+[guid]::NewGuid().ToString('N'))
$hub=New-Object WowAuto.Threading.Hub($temporary,1)
try {
    $a=$hub.Register('11:1',11,1,'fixture','titan');$b=$hub.Register('12:1',12,1,'fixture','forerver')
    $null=$a.Send('Start','{}');$null=$b.Send('Start','{}')
    $low=$hub.Request($a,$a.Version,'Fish.Cast','Fish',70,'{}');$high=$hub.Request($b,$b.Version,'Fight.Combat','Fight',20,'{}')
    Assert-Threading ([object]::ReferenceEquals($hub.NextOperation(),$high)) 'Operation priority was lost.'
    $null=$a.Send('Stop','{}');Assert-Threading (-not $hub.NextOperation() -and $low.Done.IsSet -and -not $low.Success) 'Generation cancellation did not acknowledge obsolete operations.'
    $hub.Batch=New-Object WowAuto.Threading.RotationBatch(,[string[]]@($a.Key,$b.Key))
    $normal=$hub.Request($b,$b.Version,'Fight.Combat','Fight',20,'{}');$exit=$hub.Request($a,$a.Version,'Process.Exit','Process',90,'{}')
    Assert-Threading ([object]::ReferenceEquals($hub.NextOperation(),$exit)) 'Process exit deadlocked behind its own rotation barrier.'
    Assert-Threading (-not $hub.NextOperation()) 'Normal task input crossed an active rotation batch.'
    $hub.Batch.Drop($a.Key);Assert-Threading (-not $hub.Batch.All(8)) 'One completed member released the whole batch.'
    $hub.Batch.Drop($b.Key);Assert-Threading ([object]::ReferenceEquals($hub.NextOperation(),$normal)) 'Dropping stopped batch members did not release queued input.'
    Assert-Threading (-not [ThreadingChecks]::ReadIsolation()) 'Native read errors leaked between detector threads.'
    $timing=New-Object WowAuto.Threading.QueueTimings;$timing.ForegroundSettleMs=73;$hub.ConfigureTiming($timing)
    $null=$hub.Wake.Reset();$oldTiming=$hub.Request($a,$a.Version,'Fish.Cast','Fish',70,'{}')
    Assert-Threading ($hub.Wake.WaitOne(0)) 'A new request did not immediately wake the operator.'
    $timing.ForegroundSettleMs=147;$hub.ConfigureTiming($timing)
    $newTiming=$hub.Request($b,$b.Version,'Fish.Cast','Fish',70,'{}');$timing.ForegroundSettleMs=999
    Assert-Threading ($oldTiming.Timing.ForegroundSettleMs -eq 73 -and $newTiming.Timing.ForegroundSettleMs -eq 147 -and $hub.Timing.ForegroundSettleMs -eq 147) 'A timing update changed queued requests or kept a mutable caller object.'
    $ownerTiming=New-Object WowAuto.Threading.QueueTimings;$ownerTiming.ClickMinMs=11
    $owned=$hub.Request($a,$a.Version,'Rotation.Click','Rotation',50,'{}',$ownerTiming);$ownerTiming.ClickMinMs=19
    Assert-Threading ($owned.Timing.ClickMinMs -eq 11) 'Per-worker request body and timing snapshots were mixed during a global timing update.'
    $null=$hub.NextOperation();$null=$hub.NextOperation();$null=$hub.NextOperation()
    $hub.WriteInfo('{"StartTime":"fixture","Processes":[]}');[ThreadingChecks]::Logs($hub,$a)
    $size=(Get-Item (Join-Path $temporary 'wowAuto.log')).Length+(Get-Item (Join-Path $temporary 'info.log')).Length
    Assert-Threading ($size -le 1MB) 'Concurrent logs exceeded their combined size limit.'
    $lines=@([IO.File]::ReadAllLines((Join-Path $temporary 'wowAuto.log')) | ForEach-Object {$_ | ConvertFrom-Json})
    Assert-Threading ($lines.Count -gt 0 -and @($lines | Where-Object {$_.Pid -ne 11}).Count -eq 0 -and @($lines.ThreadId | Sort-Object -Unique).Count -ge 2) 'Concurrent log lines were lost/corrupted or lacked PID/thread identity.'
    $waiting=$hub.Request($a,$a.Version,'Fish.Cast','Fish',70,'{}');$hub.Close()
    Assert-Threading ($waiting.Done.IsSet -and -not $waiting.Success -and $a.Closed -and $b.Closed) 'Shutdown did not cancel and acknowledge pending work.'
    Write-Output 'PASS: priority ordering, generation cancellation, rotation/input barriers, process-exit progress, per-thread native read results, concurrent bounded JSON logging and shutdown acknowledgements. No game operations.'
}finally {
    $hub.Close()
    $resolved=[IO.Path]::GetFullPath($temporary)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'wowAuto-threading-*'){throw 'Unsafe fixture cleanup'}
    if([IO.Directory]::Exists($resolved)){[IO.Directory]::Delete($resolved,$true)}
}
