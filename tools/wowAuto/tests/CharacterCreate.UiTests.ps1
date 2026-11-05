# Production page/controller with a synthetic JSON worker; no OCR or game input.
$creation=$script:characterCreate;$editor=$creation.Ui
Assert-Parallel ($tabs.TabPages.Count -eq 2 -and $editor.Page.Text -eq '角色创建' -and $editor.AutoStop.Checked -and -not $editor.DryRun.Checked) 'Creation page or safe defaults are missing.'
$savedFactory=${function:New-CharacterCreateWorker};$savedFilter=$editor.Filter.Text
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('wowAuto-character-test-'+[guid]::NewGuid().ToString('N')+'.py')
$stub=@'
import json,sys
json.loads(sys.stdin.readline())
print(json.dumps(dict(kind='operation', id=1, action='State', data={})), flush=True)
reply=json.loads(sys.stdin.readline())
assert reply['id']==1 and 'data' in reply
print(json.dumps(dict(kind='counts', finish=7, confirm=3)), flush=True)
assert json.loads(sys.stdin.readline())['stop']
print(json.dumps(dict(kind='finished', text='mock creation stopped')), flush=True)
'@
[IO.File]::WriteAllText($fixture,$stub,(New-Object Text.UTF8Encoding($false)))
$script:characterTestStub=$fixture
${function:New-CharacterCreateWorker}={param($Python,$Script) return New-Object WowAuto.CharacterCreate.Worker($Python,$script:characterTestStub)}
try {
    $editor.Filter.Text='测试游戏';Update-CharacterWindows
    Assert-Parallel ($editor.Windows.Items.Count -eq 3) 'Creation page did not expose all supported process windows.'
    $a.RuntimeRunning=$true;Start-CharacterCreate
    Assert-Parallel (-not $creation.Busy -and $editor.Status.Text -match '先停止进程任务') 'Creation worker started while another game task was running.'
    $a.RuntimeRunning=$false
    Start-CharacterCreate
    Assert-Parallel ($creation.Busy -and -not $tab.Enabled -and $editor.Stop.Enabled) 'Creation did not lock competing game controls.'
    $round=$a.ExecutionRound;Start-RowDirect $a;Start-AllRows
    Assert-Parallel (-not $a.RuntimeRunning -and $a.ExecutionRound -eq $round) 'Competing fish task started during creation.'
    $deadline=[datetime]::UtcNow.AddSeconds(10)
    while($editor.Counts.Text -notmatch '7.*3' -and [datetime]::UtcNow -lt $deadline){Update-CharacterCreate;Update-ParallelMessages;[Windows.Forms.Application]::DoEvents();[Threading.Thread]::Sleep(10)}
    Assert-Parallel ($editor.Counts.Text -match '7.*3') ('Synthetic backend/host operator handshake failed: '+$editor.Status.Text)
    $endpoint=$creation.Endpoint;$version=$creation.Version
    Stop-CharacterCreate
    Assert-Parallel (-not $endpoint.Current($version) -and [WowAuto.CharacterCreate.Native]::Cancelled.IsSet) 'Stop did not invalidate queued creation operations.'
    $deadline=[datetime]::UtcNow.AddSeconds(8)
    while($creation.Busy -and [datetime]::UtcNow -lt $deadline){Update-CharacterCreate;Update-ParallelMessages;[Threading.Thread]::Sleep(10)}
    Assert-Parallel (-not $creation.Busy -and $tab.Enabled -and -not $editor.Stop.Enabled) 'Creation stop did not release the page/input exclusion gate.'
    if($env:WOWAUTO_PARALLEL_PREVIEW){
        $tabs.SelectedTab=$editor.Page;[Windows.Forms.Application]::DoEvents()
        $bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height)
        try{$form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$bitmap.Width,$bitmap.Height)));$bitmap.Save((Join-Path $env:WOWAUTO_PARALLEL_PREVIEW 'character-create.png'))}finally{$bitmap.Dispose()}
        $tabs.SelectedTab=$tab
    }
    'PASS: embedded creation page, synthetic JSON worker/operator handshake, live counters, competing-task exclusion, stop cancellation and control restoration; no game input.'
} finally {
    ${function:New-CharacterCreateWorker}=$savedFactory
    $editor.Filter.Text=$savedFilter;Update-CharacterWindows
    if($creation.Busy){Stop-CharacterCreate;$creation.Worker.Dispose();$creation.Worker=$null;$creation.Busy=$false;Update-CharacterControls}
    [IO.File]::Delete($fixture)
}
