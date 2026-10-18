$ErrorActionPreference='Stop'
$tool=Split-Path $PSScriptRoot -Parent
Add-Type -Path (Join-Path $tool 'wowAuto.Threading.cs') -ReferencedAssemblies System.Core
function Assert-Writer($Condition,[string]$Message){if(-not $Condition){throw $Message}}
$directory=Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-logwriter-'+[guid]::NewGuid().ToString('N'))
$writer=$null;$locked=$null
try {
    [void][IO.Directory]::CreateDirectory($directory)
    $log=Join-Path $directory 'wowAuto.log';$info=Join-Path $directory 'info.log'
    [IO.File]::WriteAllText($log,'old launch');[IO.File]::WriteAllText($info,'old launch')
    $writer=New-Object WowAuto.Threading.LogWriter($directory,2)
    $source=[Threading.Thread]::CurrentThread.ManagedThreadId
    $writer.WriteInfo('{"StartTime":"fixture","ProcessCount":1,"Processes":[{"Pid":123,"ExecutionRound":2}]}')
    foreach($index in 1..800){$writer.Log(123,'test',('角色消息 '+$index))}
    # Close itself must drain accepted messages; no preceding test flush.
    Assert-Writer ($writer.Close(5000) -and -not $writer.IsAlive -and -not $writer.LastError) 'Shutdown did not drain and stop the log thread.'
    $lines=@([IO.File]::ReadAllLines($log)|ForEach-Object{$_ | ConvertFrom-Json})
    Assert-Writer ($lines.Count -eq 800 -and $lines[0].Message -ceq '角色消息 1' -and $lines[-1].Message -ceq '角色消息 800') 'Shutdown lost, reordered or retained an old-launch log.'
    Assert-Writer (@($lines | Where-Object {$_.Pid -ne 123 -or $_.ThreadId -ne $source -or $_.WriterThreadId -ne $writer.ThreadId}).Count -eq 0 -and
        $writer.ThreadId -ne $source) 'A producer thread performed file writes or original PID/thread identity was lost.'
    $snapshot=[IO.File]::ReadAllText($info) | ConvertFrom-Json
    Assert-Writer ($snapshot.ProcessCount -eq 1 -and $snapshot.Processes[0].ExecutionRound -eq 2) 'Shutdown lost the latest info snapshot.'
    $rejected=$false;try{$writer.Log(123,'test','after close')}catch{$rejected=$true}
    Assert-Writer $rejected 'A closed writer accepted a message it could not persist.'
    $writer=New-Object WowAuto.Threading.LogWriter($directory,2)
    Assert-Writer ((Get-Item -LiteralPath $log).Length -eq 0 -and (Get-Item -LiteralPath $info).Length -eq 0) 'The next launch did not overwrite both files.'
    $locked=[IO.File]::Open($log,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $writer.Log(123,'test','locked file')
    Assert-Writer ($writer.Flush(5000) -and $writer.LastError -and $writer.IsAlive) 'An asynchronous file error was not reported or killed the log thread.'
    $locked.Dispose();$locked=$null
    $writer.WriteInfo('{"StartTime":"new","Processes":[]}')
    $payload='x'*4000
    foreach($index in 1..350){$writer.Log(123,'test',("event-$index $payload"))}
    $writer.MaxSizeMB=1
    Assert-Writer ($writer.Flush(5000) -and -not $writer.LastError) 'Writing did not recover after the file was unlocked.'
    Assert-Writer ($writer.TakeError() -and -not $writer.TakeError()) 'A later successful write hid the error before the UI received it.'
    Assert-Writer (((Get-Item -LiteralPath $log).Length+(Get-Item -LiteralPath $info).Length) -le 1MB) 'An asynchronous limit reduction did not trim the combined files.'
    $lines=@([IO.File]::ReadAllLines($log)|ForEach-Object{$_ | ConvertFrom-Json})
    Assert-Writer ($lines[-1].Message.StartsWith('event-350 ')) 'Rollover lost the newest queued event.'
    Write-Output 'PASS: one dedicated log writer, source/writer thread identities, FIFO shutdown drain, latest info snapshot, closed-queue rejection, overwrite on restart, asynchronous file errors/recovery and combined-size reduction. Temporary files only.'
}finally {
    if($locked){$locked.Dispose()}
    if($writer -and -not $writer.Close(5000)){throw 'Log writer is still running.'}
    $resolved=[IO.Path]::GetFullPath($directory)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'wowAuto-logwriter-*'){throw 'Unsafe fixture cleanup'}
    if([IO.Directory]::Exists($resolved)){[IO.Directory]::Delete($resolved,$true)}
}
