param([string]$PreviewDirectory)
$ErrorActionPreference='Stop'
$tool=Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'CharacterRecords.Fixtures.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-parallel-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($fixture)
$savedEnvironment=@{};foreach($name in @('WOWAUTO_PARALLEL_TEST_MODE','WOWAUTO_PARALLEL_CONFIG_PATH','WOWAUTO_PARALLEL_OPERATOR_MOCK','WOWAUTO_PARALLEL_DETECTOR_MOCK','WOWAUTO_PARALLEL_FIXTURE_ROOT','WOWAUTO_PARALLEL_PREVIEW')){$savedEnvironment[$name]=[Environment]::GetEnvironmentVariable($name)}
$sourceHashes=@{};foreach($name in @('config.ini','rotation.config.json','autoFight.config.json','account-tasks.config.json')){$sourceHashes[$name]=(Get-FileHash (Join-Path $tool $name)).Hash}
try {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Threading;
public static class ParallelFixture {
    public static readonly ConcurrentDictionary<int,int> World=new ConcurrentDictionary<int,int>();
    public static readonly ConcurrentDictionary<int,int> Reads=new ConcurrentDictionary<int,int>();
    public static readonly ConcurrentDictionary<int,int> Ocr=new ConcurrentDictionary<int,int>();
    public static readonly ConcurrentDictionary<int,int> Actions=new ConcurrentDictionary<int,int>();
    public static readonly ConcurrentDictionary<int,int> ReadThread=new ConcurrentDictionary<int,int>();
    public static readonly ConcurrentDictionary<int,int> OcrThread=new ConcurrentDictionary<int,int>();
    public static readonly ConcurrentDictionary<int,int> OpThread=new ConcurrentDictionary<int,int>();
    public static readonly ConcurrentDictionary<int,string> Colors=new ConcurrentDictionary<int,string>();
    public static readonly ConcurrentDictionary<int,int> RodEquips=new ConcurrentDictionary<int,int>();
    public static readonly ConcurrentDictionary<int,int> Enables=new ConcurrentDictionary<int,int>();
    public static readonly ConcurrentDictionary<int,int> UnknownReads=new ConcurrentDictionary<int,int>();
    public static readonly ConcurrentQueue<string> InputOrder=new ConcurrentQueue<string>();
    public static int BlockPid,BlockedPid,Clicks,Logouts,EarlyClicks,EarlyOcr,MissingPid,UpCount,ExitRequests,KillRequests,FailFocusPid,Reels,Jumps,EarlyJumps,NoBitePid;
    public static bool AutoFish;
    public static bool RestartLaunched;
    public static string RestartError;
    public static long LastReelAt;
    public static readonly ManualResetEventSlim Release=new ManualResetEventSlim(false);
    public static void Add(ConcurrentDictionary<int,int> target,int pid) {target.AddOrUpdate(pid,1,(key,value)=>value+1);}
}
'@
    $operator=@'
function Invoke-OperatorRequest($Request) {
    $id=$Request.Owner.Pid;[ParallelFixture]::OpThread[$id]=[Threading.Thread]::CurrentThread.ManagedThreadId
    if($Request.Kind -like 'Fish.*' -and $id -eq [ParallelFixture]::FailFocusPid){[ParallelFixture]::FailFocusPid=0;throw '操作线程未能在前台保护时间内取得窗口。'}
    if($Request.Kind -like 'Fish.*' -and $id -eq [ParallelFixture]::BlockPid) {
        [ParallelFixture]::BlockedPid=$id
        while(-not [ParallelFixture]::Release.Wait(10)){if(-not $Request.Current -or $Hub.Closing){return @{Executed=$false;SentAt=$Hub.Now}}}
    }
    if(-not $Request.Current){return @{Executed=$false;SentAt=$Hub.Now}}
    [ParallelFixture]::Add([ParallelFixture]::Actions,$id)
    [ParallelFixture]::InputOrder.Enqueue($id.ToString()+':'+$Request.Kind)
    if($Request.Kind -eq 'Rotation.EquipRod'){
        $body=$Request.Json | ConvertFrom-Json
        if($body.Mode -cne 'fish' -or $body.Key -cne 'Ctrl+F3'){throw 'Unexpected rod equip task/key.'}
        [ParallelFixture]::Add([ParallelFixture]::RodEquips,$id)
    }
    if($Request.Kind -eq 'Rotation.Enable'){
        [ParallelFixture]::Add([ParallelFixture]::Enables,$id)
        if($id -eq 101 -and [ParallelFixture]::Enables[$id] -eq 1){[ParallelFixture]::UnknownReads[$id]=1}
    }
    if($Request.Kind -eq 'Rotation.Logout'){[ParallelFixture]::World[$id]=0;[ParallelFixture]::Logouts++}
    if($Request.Kind -eq 'Rotation.Click'){
        if(-not $Hub.Batch.All(2)){[ParallelFixture]::EarlyClicks++}
        [ParallelFixture]::Clicks++;[ParallelFixture]::World[$id]=1
    }
    if($Request.Kind -like 'Process.*'){[ParallelFixture]::World[$id]=2}
    if($Request.Kind -eq 'Process.Exit'){[ParallelFixture]::ExitRequests++}
    if($Request.Kind -eq 'Process.Kill'){[ParallelFixture]::KillRequests++}
    if($Request.Kind -eq 'Rotation.Up'){[ParallelFixture]::UpCount++}
    if([ParallelFixture]::AutoFish -and $id -eq 101) {
        if($Request.Kind -eq 'Fish.Cast'){[ParallelFixture]::Colors[$id]='green'}
        if($Request.Kind -eq 'Fish.Reel'){[ParallelFixture]::Reels++;[ParallelFixture]::LastReelAt=$Hub.Now;[ParallelFixture]::Colors[$id]='red'}
        if($Request.Kind -eq 'Fish.Jump'){[ParallelFixture]::Jumps++;if($Hub.Now -lt [ParallelFixture]::LastReelAt+1000){[ParallelFixture]::EarlyJumps++}}
    }
    return @{Executed=$true;SentAt=$Hub.Now}
}
'@
    $detector=@'
function Get-DetectorObservation {
    [ParallelFixture]::Add([ParallelFixture]::Reads,$Endpoint.Pid)
    [ParallelFixture]::ReadThread[$Endpoint.Pid]=[Threading.Thread]::CurrentThread.ManagedThreadId
    $packet=New-Object WowAutoFight.Packet;$packet.Flavor=$Endpoint.Flavor;$packet.ClassId=1;$packet.Action='idle';$packet.Recovery='none'
    $color=if([ParallelFixture]::Colors.ContainsKey($Endpoint.Pid)){[ParallelFixture]::Colors[$Endpoint.Pid]}else{'red'}
    if([ParallelFixture]::UnknownReads[$Endpoint.Pid] -gt 0){[ParallelFixture]::UnknownReads[$Endpoint.Pid]--;$color='unknown';$packet=$null}
    return [pscustomobject]@{Login=([ParallelFixture]::World[$Endpoint.Pid] -eq 1);Color=$color;Packet=$packet;Lure='present'}
}
function Get-DetectorLure {return 'present'}
${function:Start-FixtureTask}=${function:Start-DetectorTask}
function Start-DetectorTask {
    Start-FixtureTask
    if($script:mode -eq 'fish' -and $Endpoint.Pid -eq [ParallelFixture]::NoBitePid){
        # Arm the production no-bite timer without creating any audio capture.
        $script:fish.UseAudio=$true;$script:fish.AudioReady=$true;$script:fish.AudioTimeoutMs=1000
        $script:audio=[pscustomobject]@{Status='Listening';Error='';MaximumPeak=0.009;ComparedCandidates=0;BestSimilarity=0;Similarity=0;Peak=0;CandidatePeakThreshold=0.0034}
        $script:audio | Add-Member ScriptMethod Arm {param([long]$session)}
        $script:audio | Add-Member ScriptMethod Dispose {}
        $script:audioFeature=$script:config.FeaturePath;$script:audioSession=-1L
    }
}
function Test-DetectorAlive {return [ParallelFixture]::World[$Endpoint.Pid] -ne 2}
function Get-DetectorPosition {return '左上'}
function Get-DetectorScreen {
    if(-not $script:batch.All(1)){[ParallelFixture]::EarlyOcr++}
    [ParallelFixture]::Add([ParallelFixture]::Ocr,$Endpoint.Pid)
    [ParallelFixture]::OcrThread[$Endpoint.Pid]=[Threading.Thread]::CurrentThread.ManagedThreadId
    if($Endpoint.Pid -eq 101 -and [ParallelFixture]::Ocr[101] -eq 1){[Threading.Thread]::Sleep(800)}
    if($Endpoint.Pid -eq [ParallelFixture]::MissingPid){return [pscustomobject]@{Kind='menu';Targets=@()}}
    $index=0;$targets=@(foreach($role in $script:roles){$index++;[pscustomobject]@{Name=$role.Name;RawName=$role.Name;Ambiguous=$false;MenuRow=$index;X=0.84;Y=(0.119+($index-1)*0.0743);ClientSize=[pscustomobject]@{Width=800;Height=500}}})
    return [pscustomobject]@{Kind='menu';Targets=$targets}
}
$script:originalFixtureWait=${function:Wait-Detector}
function Wait-Detector([int]$Milliseconds) {
    # Shorten only the arrow retry dwell; count/order use the production implementation.
    if($Milliseconds -eq 500){$Milliseconds=10}
    return & $script:originalFixtureWait $Milliseconds
}
'@
    $operatorPath=Join-Path $fixture 'operator.ps1';$detectorPath=Join-Path $fixture 'detector.ps1'
    [IO.File]::WriteAllText($operatorPath,$operator,(New-Object Text.UTF8Encoding($true)));[IO.File]::WriteAllText($detectorPath,$detector,(New-Object Text.UTF8Encoding($true)))
    $roles=@(@{Name='角色甲';Realm='测试服';Mode='fish';Enabled=$true;UseItem=$false},@{Name='角色乙';Realm='测试服';Mode='fight';Enabled=$true;UseItem=$false},@{Name='角色丙';Realm='测试服';Mode='fish';Enabled=$true;UseItem=$false},@{Name='角色丁';Realm='测试服';Mode='fish';Enabled=$true;UseItem=$false})
    $accounts=@{};$bindings=@{};$ticks=([datetime]'2026-09-27').Ticks
    foreach($spec in @(@(101,'titan','ACCOUNT-A'),@(202,'forerver','ACCOUNT-A'),@(303,'titan','ACCOUNT-B'))) {
        $product=if($spec[1] -eq 'titan'){'_classic_titan_'}else{'_cn_beta_'}
        $cap=if($spec[1] -eq 'titan'){80}else{60}
        Write-TestRealmLevels (Join-Path $fixture ($product+'\WTF\Account\'+$spec[2])) @{'测试服'=$cap}
        foreach($role in $roles){
            $freeSlots=if($role.Name -ceq '角色甲'){-1}elseif($role.Name -ceq '角色乙'){0}else{12}
            $skillArgs=@{};$roleLevel=0
            if($role.Name -ceq '角色乙'){$roleLevel=$cap;$skillArgs=@{Version=6;ClassId=5;Professions='';SecondarySkills=''}}
            if($role.Name -ceq '角色丙'){$roleLevel=$cap-1;$skillArgs=@{Version=6;ClassId=8;Professions='186|采矿|450|450;393|剥皮|425|450';SecondarySkills='185|烹饪|300|450;356|钓鱼|450|450';BindLocation=$(if($spec[1] -eq 'titan'){'达拉然'}else{'奥格瑞玛'})}}
            if($role.Name -ceq '角色丁'){$roleLevel=$cap-2;$skillArgs=@{Version=6;ClassId=11;Professions='171|炼金术|0|75';SecondarySkills='?';BindLocation='?'}}
            Write-TestCharacterRecord (Join-Path $fixture ($product+'\WTF\Account\'+$spec[2]+'\测试服\'+$role.Name)) $role.Name $role.Realm -Level $roleLevel -FreeBagSlots $freeSlots @skillArgs
        }
        $accounts[$spec[1]+':'+$spec[2]]=$roles;$bindings[([string]$spec[0]+':'+$ticks)]=@{Flavor=$spec[1];Account=$spec[2]};[ParallelFixture]::World[$spec[0]]=1
    }
    $accounts['forerver:ACCOUNT-A']=@($roles | ForEach-Object {$_.Clone()});$accounts['forerver:ACCOUNT-A'][0].Mode='fight'
    $periods=@{FishMs=50;FightMs=100;MenuMs=25;LoginMs=25;BaitMs=25;DeathMs=50;AudioMs=25;PositionMs=100;CaptureRetryMs=25;OcrMs=25}
    $configPath=Join-Path $fixture 'account-tasks.json';[IO.File]::WriteAllText($configPath,(@{Version=1;Accounts=$accounts;Bindings=$bindings;Periods=$periods} | ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($false)))
    $env:WOWAUTO_PARALLEL_TEST_MODE='1';$env:WOWAUTO_PARALLEL_CONFIG_PATH=$configPath;$env:WOWAUTO_PARALLEL_OPERATOR_MOCK=$operatorPath;$env:WOWAUTO_PARALLEL_DETECTOR_MOCK=$detectorPath;$env:WOWAUTO_PARALLEL_FIXTURE_ROOT=$fixture
    if($PreviewDirectory){$null=[IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($PreviewDirectory));$env:WOWAUTO_PARALLEL_PREVIEW=[IO.Path]::GetFullPath($PreviewDirectory)}
    $source=[IO.File]::ReadAllText((Join-Path $tool 'wowAuto.ps1'))
    $source=$source.Replace('param([string]$PreviewPath, [switch]$UiTest)',('param([string]$PreviewPath, [switch]$UiTest)'+"`r`n"+'$PSScriptRoot='''+$tool.Replace("'","''")+''''))
    $source=$source.Replace('C:\test-games\_classic_titan_\WowClassic.exe',(Join-Path $fixture '_classic_titan_\WowClassic.exe')).Replace('C:\test-games\_cn_beta_\Wow.exe',(Join-Path $fixture '_cn_beta_\Wow.exe'))
    & ([scriptblock]::Create($source)) -UiTest
    if(-not [ParallelFixture]::RestartLaunched){throw ('Threaded restart did not reach the substituted launcher after cleanup: '+[ParallelFixture]::RestartError)}
    Write-Output 'PASS: threaded restart cancels an in-flight operator request and ends all detector/operator runspaces before the substituted launcher; no application was actually restarted.'
    foreach($name in $sourceHashes.Keys){if((Get-FileHash (Join-Path $tool $name)).Hash -ne $sourceHashes[$name]){throw ('Production config changed: '+$name)}}
}finally {
    foreach($name in $savedEnvironment.Keys){[Environment]::SetEnvironmentVariable($name,$savedEnvironment[$name])}
    $resolved=[IO.Path]::GetFullPath($fixture)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'wowAuto-parallel-*'){throw 'Unsafe temporary test directory'}
    if([IO.Directory]::Exists($resolved)){[IO.Directory]::Delete($resolved,$true)}
}
