# One executor for every game window. Producers only describe work; callbacks own input.
function New-GameActionQueue {
    return [pscustomobject]@{Events=(New-Object Collections.ArrayList); Sequence=0L; Current=$null;
        Focus=$null; History=(New-Object Collections.ArrayList); Priorities=@{}; Closing=$false}
}
function Initialize-GameActionQueue([string]$Path) {
    $script:gameActions=New-GameActionQueue
    $config=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($config.Version -ne 1) {throw 'Unsupported action-priorities.json version.'}
    foreach ($property in $config.Events.PSObject.Properties) {
        $value=$property.Value
        if ($value -isnot [int] -or $value -lt 0 -or $value -gt 999) {throw "Invalid priority: $($property.Name)"}
        $script:gameActions.Priorities[$property.Name]=[int]$value
    }
    if ($script:gameActions.Priorities['Safety.Release'] -ne 0 -or $script:gameActions.Priorities['Hold.Pulse'] -ne 5) {
        throw 'Safety.Release=0 and Hold.Pulse=5 are reserved.'
    }
    foreach ($kind in $script:gameActions.Priorities.Keys) {
        if ($kind -notin @('Safety.Release','Hold.Pulse') -and $script:gameActions.Priorities[$kind] -lt 10) {
            throw "Priority 0..9 is reserved for safety: $kind"
        }
    }
}
function Assert-GameActionContext {
    if (-not $script:gameActions -or -not $script:gameActions.Current) {throw 'Game input must run inside the shared action queue.'}
}
function Test-GameActionForeground($Event) {
    if ($Event.Domain -eq 'Fight' -and -not $Event.Row.PSObject.Properties['Process']) {
        return [WowAutoFight.Native]::Foreground($Event.Data.Row.Client)
    }
    return Test-WorkerForeground $Event.Row
}
function Add-GameAction([string]$Id,[string]$Kind,[string]$Domain,[string]$Key,$Row,$Owner,[long]$Due,
    [scriptblock]$Execute,$Data=$null,[bool]$Foreground=$false) {
    if (-not $script:gameActions.Priorities.ContainsKey($Kind)) {throw "Missing action priority: $Kind"}
    if ($script:gameActions.Closing -and $Domain -ne 'Safety') {return}
    $existing=@($script:gameActions.Events | Where-Object {$_.Id -eq $Id})
    foreach ($event in $existing) {
        $sameOwner=if ($Domain -in @('Scan','Restore')) {$event.Owner -eq $Owner} else {[object]::ReferenceEquals($event.Owner,$Owner)}
        if ($sameOwner -and $event.Kind -eq $Kind) {
            if ($Domain -eq 'Scan') {$event.Data=$Data}
            return
        }
        $event.Cancelled=$true; [void]$script:gameActions.Events.Remove($event)
    }
    $script:gameActions.Sequence++
    $event=[pscustomobject]@{Id=$Id;Kind=$Kind;Domain=$Domain;Key=$Key;Row=$Row;Owner=$Owner;Due=$Due;RequestedDue=$Due;
        Priority=$script:gameActions.Priorities[$Kind];Sequence=$script:gameActions.Sequence;
        Execute=$Execute;Data=$Data;Foreground=$Foreground;Cancelled=$false;ReadyAt=0L;FocusUntil=0L}
    [void]$script:gameActions.Events.Add($event)
}
function Remove-GameActions([string]$Key,[switch]$IncludeProcess,[string]$Domain='') {
    foreach ($event in @($script:gameActions.Events)) {
        if ($Key -and $event.Key -ne $Key) {continue}
        if ($Domain -and $event.Domain -ne $Domain) {continue}
        if ($event.Domain -eq 'Safety' -or ($event.Domain -eq 'Process' -and -not $IncludeProcess)) {continue}
        $event.Cancelled=$true; [void]$script:gameActions.Events.Remove($event)
    }
    if ($script:gameActions.Focus -and $script:gameActions.Focus.Cancelled) {$script:gameActions.Focus=$null}
}
function Test-GameActionValid($Event) {
    if ($Event.Cancelled) {return $false}
    switch ($Event.Domain) {
        'Fish' {
            $state=$script:scheduler.Tasks[$Event.Key]
            if (-not $state -or -not $state.Running -or -not [object]::ReferenceEquals($state,$Event.Owner)) {return $false}
            $work=$Event.Data
            if ($work.Kind -in @('Reel','AudioTimeout')) {
                return @($script:scheduler.Events | Where-Object {$_.Key -eq $Event.Key -and $_.Kind -eq $work.Kind -and
                    $_.Due -eq $work.Due -and [object]::ReferenceEquals($_.State,$state)}).Count -gt 0 -and $state.FocusRetryAt -eq 0
            }
            if ($work.Kind -eq 'FocusRetry') {return $state.FocusRetryAt -eq $work.Due -and $state.FocusRetryAt -gt 0}
            if ($state.FocusRetryAt -gt 0 -or $state.Mode -notin @('Ready','Casting')) {return $false}
            if ($work.Kind -eq 'Item') {return $state.UseItem -and $state.ItemDue -eq $work.Due}
            return $state.NextDue -eq $work.Due -and -not $state.InitialItemPending
        }
        'Fight' {return -not $script:autoFight.Editing -and [object]::ReferenceEquals($Event.Data.Row.Session,$Event.Owner)}
        'Hold' {return [object]::ReferenceEquals($script:autoFight.ActiveHold,$Event.Owner)}
        'Rotation' {
            if (-not $Event.Owner) {return -not $script:rotation.Current -and $script:rotation.Queue.Count -gt 0}
            return [object]::ReferenceEquals($script:rotation.Current,$Event.Owner) -and
                [object]::ReferenceEquals($script:rotation.Active[$Event.Key],$Event.Owner.Entry) -and $Event.Owner.Phase -eq $Event.Data
        }
        'Scan' {return $script:scanning -and $script:scanGeneration -eq $Event.Owner -and $script:scanIndex -eq $Event.Data.Index -and $script:scanPhase -eq $Event.Data.Phase}
        'Restore' {return -not $script:scanning -and $script:scanGeneration -eq $Event.Owner}
        'Process' {
            if ($Event.Kind -eq 'Process.Close') {return [object]::ReferenceEquals($script:rows[$Event.Key],$Event.Row)}
            return [object]::ReferenceEquals($script:pendingGameExits[$Event.Key],$Event.Owner)
        }
    }
    return $true
}
function Test-GameActionHold([long]$Now) {
    return ($Now -lt $script:scheduler.ReelHoldUntil -or $Now -lt $script:scheduler.ItemHoldUntil -or
        ($script:autoFight -and ($script:autoFight.ActiveHold -or [WowAutoFight.Native]::IsHolding)))
}
function Test-GameActionUsesFocus($Event) {
    # These callbacks can change the foreground themselves, without the activation precheck.
    return $Event.Foreground -or $Event.Kind -in @('Scan.Activate','Rotation.Activate','Scan.Restore','Process.Close','Process.Kill')
}
function Invoke-GameActionQueue([long]$Now,[switch]$SafetyOnly) {
    if ($script:gameActions.Current -and -not $SafetyOnly) {return}
    $clock=$script:schedulerClock
    $clockAtEntry=if ($clock) {[long]$clock.ElapsedMilliseconds} else {0L}
    $batchAt=if (-not $UiTest -and $clock -is [Diagnostics.Stopwatch]) {[Math]::Max($Now,$clockAtEntry)} else {$Now}
    $deferred=@{}
    while ($true) {
        # Inputs take time. Re-evaluate deadlines and holds using the current monotonic time.
        $Now=$batchAt
        if ($clock) {$Now += [Math]::Max(0,([long]$clock.ElapsedMilliseconds-$clockAtEntry))}
        foreach ($event in @($script:gameActions.Events)) {
            if (-not (Test-GameActionValid $event)) {[void]$script:gameActions.Events.Remove($event);$event.Cancelled=$true}
            elseif ($event.Domain -eq 'Fight') {
                $gate=$script:autoFight.CommandGate
                $ready=if ($gate.LastSentAt -lt 0) {$event.RequestedDue} else {$gate.LastSentAt+$gate.IntervalMs}
                $event.Due=[Math]::Max($event.RequestedDue,$ready)
            }
        }
        $focus=$script:gameActions.Focus
        if ($focus -and ($focus.Cancelled -or -not $script:gameActions.Events.Contains($focus))) {
            $script:gameActions.Focus=$null;$focus=$null
        }
        $held=Test-GameActionHold $Now
        $eligible=@($script:gameActions.Events | Where-Object {
            $_.Due -le $Now -and (-not $deferred.ContainsKey($_.Sequence) -or $Now -ge $deferred[$_.Sequence]) -and
            (-not $SafetyOnly -or $_.Domain -eq 'Safety') -and
            (-not $held -or $_.Domain -in @('Safety','Hold')) -and
            (-not $script:editingSettings -or $_.Domain -eq 'Safety') -and
            (-not $focus -or $_ -eq $focus -or -not (Test-GameActionUsesFocus $_) -or $_.Priority -lt $focus.Priority)
        } | Sort-Object Priority,Due,Sequence)
        if (-not $eligible.Count) {return}
        $event=$eligible[0]
        if ($focus -and $focus -ne $event -and (Test-GameActionUsesFocus $event)) {
            # Higher priority foreground work preempts an activation; reads leave it intact.
            $focus.ReadyAt=0L;$focus.FocusUntil=0L;$script:gameActions.Focus=$null
            [void]$deferred.Remove($focus.Sequence)
        }
        $completed=Invoke-QueuedGameAction $event $Now
        if (-not $completed) {
            # No sleep or retry loop for a pending activation. Continue independent work.
            $deferred[$event.Sequence]=if ($Now -lt $event.ReadyAt) {$event.ReadyAt} else {[Math]::Max($Now+1,$event.FocusUntil)}
        }
    }
}
function Invoke-QueuedGameAction($event,[long]$Now) {
    $previous=$script:gameActions.Current;$script:gameActions.Current=$event
    try {
        if ($event.Foreground) {
            $row=$event.Row
            if ($row.PSObject.Properties['Process']) {
                $row.Process.Refresh()
                if ($row.Process.HasExited -or -not (Test-RowProcessIdentity $row)) {throw '进程已退出或身份改变，取消排队动作。'}
            }
            elseif (-not [WowAutoFight.Native]::IsAlive($event.Data.Row.Client)) {throw '战斗进程身份已改变。'}
            if (-not (Test-GameActionForeground $event)) {
                if ($event.FocusUntil -and $Now -ge $event.FocusUntil) {throw '排队动作未能取得前台。'}
                if ($script:gameActions.Focus -ne $event -or -not $event.FocusUntil) {
                    $activated=if ($row.PSObject.Properties['Process']) {Activate-WorkerRow $row} else {[WowAutoFight.Native]::Activate($event.Data.Row.Client)}
                    if (-not $activated) {throw '无法切换到排队动作的游戏窗口。'}
                    $event.ReadyAt=$Now+200;$event.FocusUntil=$Now+800
                    $script:gameActions.Focus=$event
                }
                return $false
            }
            if ($script:gameActions.Focus -eq $event -and $Now -lt $event.ReadyAt) {return $false}
        }
        if (-not (Test-GameActionValid $event)) {
            $event.Cancelled=$true;[void]$script:gameActions.Events.Remove($event)
            if ($script:gameActions.Focus -eq $event) {$script:gameActions.Focus=$null}
            return $true
        }
        [void]$script:gameActions.Events.Remove($event)
        if ($script:gameActions.Focus -eq $event) {$script:gameActions.Focus=$null}
        $null = & $event.Execute $event $Now
        [void]$script:gameActions.History.Add([pscustomobject]@{Kind=$event.Kind;Key=$event.Key;Priority=$event.Priority;At=$Now})
        while ($script:gameActions.History.Count -gt 200) {$script:gameActions.History.RemoveAt(0)}
    }
    catch {
        $event.Cancelled=$true;[void]$script:gameActions.Events.Remove($event)
        if ($script:gameActions.Focus -eq $event) {$script:gameActions.Focus=$null}
        $reason='队列动作 '+$event.Kind+' 失败：'+$_.Exception.Message
        if ($event.Domain -eq 'Fish') {
            if ($event.Row.Process.HasExited -or -not (Test-RowProcessIdentity $event.Row)) {
                $event.Row.Validated=$false;Stop-Row $event.Row $reason
            } else {Pause-RowForFocus $event.Row $Now $reason}
        }
        elseif ($event.Domain -eq 'Fight') {$event.Data.Row.CanStart=$false;Stop-AutoFightRow $event.Data.Row $reason}
        elseif ($event.Domain -eq 'Scan') {
            if ($event.Row) {$event.Row.Validated=$false;Set-RowStatusText $event.Row $reason;Set-RowControls $event.Row}
            $script:scanIndex++;$script:scanPhase='Activate';$script:scanDue=$script:scanClock.ElapsedMilliseconds
            if ($script:scanIndex -ge $script:scanQueue.Count) {Finish-RefreshScan}
        }
        elseif ($event.Row) {Stop-Row $event.Row $reason -CancelExit}
        else {Write-Warning $reason}
    }
    finally {$script:gameActions.Current=$previous}
    return $true
}

function Submit-FishingActions([long]$Now) {
    Update-AudioCaptures $Now
    $work=Get-WowAutoWork $script:scheduler $Now
    $candidates=@()
    if ($work) {$candidates+=,$work}
    # Register every due deadline, including other processes; the queue decides their order.
    foreach ($timerEvent in @($script:scheduler.Events)) {
        if ($timerEvent.Kind -in @('Reel','AudioTimeout') -and $timerEvent.Due -le $Now) {
            $candidates+=,[pscustomobject]@{Key=$timerEvent.Key;Kind=$timerEvent.Kind;Due=$timerEvent.Due}
        }
    }
    foreach ($work in $candidates) {
        $row=$script:rows[$work.Key];$state=$script:scheduler.Tasks[$work.Key]
        if (-not $row -or -not $state -or -not $state.Running) {continue}
        $kind=switch ($work.Kind) {
            'Reel' {'Fish.Reel'} 'AudioTimeout' {'Fish.AudioTimeout'} 'Item' {'Fish.Item'} 'FocusRetry' {'Fish.FocusRetry'}
            default {if ($state.PostReelJumpAllowed -and ($state.CycleJumpPending -or $state.CheckReelGreen)) {'Fish.Jump'} else {'Fish.Cast'}}
        }
        Add-GameAction -Id ('fish:'+ $work.Key+':'+$work.Kind) -Kind $kind -Domain Fish -Key $work.Key -Row $row -Owner $state -Due $work.Due -Data $work -Foreground $true -Execute {
            param($event,$now)
            $script:scheduler.ActiveKey=$event.Key
            Invoke-SchedulerTick $now -QueuedWork $event.Data
        }
    }
}
function Submit-CombatAction($Row,$Session,[string]$Action,[long]$Now) {
    $names=@{target='Target';opening='Opening';combat='Combat';recover='Recover';emergency='Emergency';loot='Loot';skin='Skin';jump='Jump';
        'move-forward'='MoveForward';'move-backward'='MoveBackward';'move-left'='MoveLeft';'move-right'='MoveRight'}
    if (-not $names.ContainsKey($Action)) {return}
    $parent=if ($Row.PSObject.Properties['ParentRow']) {$Row.ParentRow} else {$Row}
    $key=$Row.Client.Key
    Add-GameAction -Id ('fight:'+$key) -Kind ('Fight.'+$names[$Action]) -Domain Fight -Key $key -Row $parent -Owner $Session -Due $Now -Foreground $true -Data ([pscustomobject]@{Row=$Row;Action=$Action}) -Execute {
        param($event,$now)
        $script:autoFight.Pending=New-AutoFightPending $event.Data.Row $event.Owner $false $now
        Invoke-AutoFightTick -ExpectedAction $event.Data.Action
    }
}
function Submit-RotationAction([long]$Now) {
    if (-not $script:rotation.Current -and -not $script:rotation.Queue.Count -and $script:rotation.NextAt -and $Now -ge $script:rotation.NextAt) {Begin-RotationBatch $Now}
    $work=$script:rotation.Current
    if (-not $work) {
        if ($script:rotation.Queue.Count) {
            Add-GameAction -Id rotation -Kind Rotation.Activate -Domain Rotation -Due $Now -Execute {param($event,$now) $null=Invoke-RotationTick $now}
        }
        return
    }
    $kind=switch ($work.Phase) {
        'activate' {'Rotation.Activate'} 'inspect' {'Rotation.Logout'} 'menu' {'Rotation.Menu'} 'find' {'Rotation.Select'}
        'login' {'Rotation.Login'} 'validate' {if ($work.MonitorEnabled) {'Rotation.Validate'} else {'Rotation.Enable'}}
    }
    Add-GameAction -Id rotation -Kind $kind -Domain Rotation -Key $work.Row.Key -Row $work.Row -Owner $work -Due $work.Due -Data $work.Phase -Foreground ($work.Phase -ne 'activate') -Execute {param($event,$now) $null=Invoke-RotationTick $now}
}
function Submit-RefreshAction([long]$Now,[long]$ScanNow=-1) {
    if (-not $script:scanning) {return}
    $row=if ($script:scanIndex -lt $script:scanQueue.Count) {$script:scanQueue[$script:scanIndex]} else {$null}
    $kind=switch ($script:scanPhase) {'Activate' {'Scan.Activate'} 'Command' {'Scan.Enable'} default {'Scan.Observe'}}
    $sampleAt=if ($ScanNow -ge 0) {$ScanNow} else {$script:scanClock.ElapsedMilliseconds}
    $due=$Now+[Math]::Max(0,$script:scanDue-$sampleAt)
    Add-GameAction -Id scan -Kind $kind -Domain Scan -Key $row.Key -Row $row -Owner $script:scanGeneration -Due $due -Data ([pscustomobject]@{Index=$script:scanIndex;Phase=$script:scanPhase;ScanNow=$ScanNow}) -Foreground ($null -ne $row -and $script:scanPhase -ne 'Activate') -Execute {
        param($event,$now)
        $sampleAt=if ($event.Data.ScanNow -ge 0) {$event.Data.ScanNow} else {$script:scanClock.ElapsedMilliseconds}
        Invoke-RefreshScan $sampleAt
    }
}
function Submit-GameExitActions([long]$Now) {
    foreach ($key in @($script:pendingGameExits.Keys)) {
        $exit=$script:pendingGameExits[$key]
        $kind=if ($Now -ge $exit.Due) {'Process.Kill'} else {'Process.Observe'}
        Add-GameAction -Id ('exit:'+$key) -Kind $kind -Domain Process -Key $key -Row $exit.Row -Owner $exit -Due ([Math]::Min($exit.NextCheck,$exit.Due)) -Execute {
            param($event,$now) Invoke-GameExitChecks $now -OnlyKey $event.Key
        }
    }
}
function Submit-HoldAction([long]$Now) {
    if (-not $script:autoFight) {return}
    $hold=$script:autoFight.ActiveHold
    if ($hold) {
        Add-GameAction -Id hold -Kind Hold.Pulse -Domain Hold -Owner $hold -Due $Now -Execute {param($event,$now) Invoke-AutoFightHold $now}
    }
    elseif ([WowAutoFight.Native]::IsHolding) {[void](Release-AutoFightHold)}
}
