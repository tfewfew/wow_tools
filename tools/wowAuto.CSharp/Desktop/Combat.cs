using WowAuto.Threading;
using WowAutoFight;

namespace WowAuto.Desktop;

internal sealed partial class GameSession
{
    private async Task<string> Fight()
    {
        long recovery = 0, actionAt = 0, buffAt = Now, jumpAt = long.MaxValue;
        int classId = 0, buffs = 0, buffInterval = -1, jumpInterval = -1;
        while (Current)
        {
            ApplyConfig();
            if (ShouldRotate())
                return "准备切换角色";
            Native.Observation view = Native.Observe(Client);
            if (view.Pending)
            {
                await RepairCapture();
                continue;
            }
            var packet = view.Packet;
            if (packet?.Action == "dead" || await ObserveMode() == "dead")
                return "角色死亡";
            if (packet is null)
            {
                message = "战斗色块暂不可读。";
                Manual(null);
                await Tick(settings.Periods.FightMs);
                continue;
            }
            if (classId != 0 && classId != packet.ClassId)
                throw new InvalidOperationException("战斗职业发生变化，请刷新。");
            classId = packet.ClassId;
            string profileId = $"{Client.Flavor}:{classId}";
            if (!settings.Fight.Profiles.TryGetValue(profileId, out FightProfile? profile))
                throw new InvalidOperationException($"请配置 Fight.Profiles/{profileId}。");
            FightCommon common = settings.Fight.Common;
            long now = Now;
            if (buffInterval != profile.BuffIntervalSeconds)
            {
                buffAt = profile.BuffIntervalSeconds == 0 ? long.MaxValue : buffInterval < 0 ? now : now + 1000L * profile.BuffIntervalSeconds;
                buffInterval = profile.BuffIntervalSeconds;
                buffs = buffInterval == 0 ? 0 : buffs;
            }
            if (jumpInterval != common.JumpIntervalSeconds)
            {
                jumpInterval = common.JumpIntervalSeconds;
                jumpAt = jumpInterval == 0 ? long.MaxValue : now + 1000L * jumpInterval;
            }
            string? action = null;
            string[] keys = [];
            int hold = 0;
            string? movement = null;
            bool safe = !packet.Busy && (now < recovery || packet.Recovery != "unknown");
            if (safe && now >= actionAt && now >= retryAt)
            {
                (string?, string[]) selection = packet switch
                {
                    { Recovery: "recover" } when now >= recovery => ("Fight.Recover", [profile.RecoveryKey]),
                    { Action: "idle" } when now >= buffAt => ("Fight.Buff", [profile.BuffKey]),
                    { Action: "idle" or "combat" } when now >= jumpAt => ("Fight.Jump", ["Space"]),
                    { Action: "opening" } => ("Fight.Opening", [common.TargetKey, profile.OpeningKey]),
                    { Action: "combat" } => ("Fight.Combat", [profile.CombatKey]),
                    { Action: "interact", Combat: false } when common.SkinEnabled => ("Fight.Interact", [common.SkinKey]),
                    _ => (null, [])
                };
                (action, keys) = selection;
            }
            ManualAction? command = null;
            while (manual.Reader.TryRead(out ManualAction? requested))
            {
                if (requested.Kind == action)
                {
                    command = activeManual = requested;
                    break;
                }
                if (action is null && safe && packet.Action == "idle" && now >= retryAt)
                {
                    string? key = requested.Kind switch
                    {
                        "Fight.MoveForward" => common.MoveForwardKey,
                        "Fight.MoveBackward" => common.MoveBackwardKey,
                        "Fight.MoveLeft" => common.MoveLeftKey,
                        "Fight.MoveRight" => common.MoveRightKey,
                        "Fight.Target" => common.TargetKey,
                        _ => null
                    };
                    if (!string.IsNullOrEmpty(key))
                    {
                        action = requested.Kind;
                        movement = action == "Fight.Target" ? null : key;
                        hold = common.MovementHoldMs;
                        keys = [key];
                        command = activeManual = requested;
                        break;
                    }
                }
                requested.Completion.TrySetResult(new(requested.Kind, Client.ProcessId, false, now, "当前战斗状态不允许执行该动作。"));
            }
            if (action is not null)
            {
                string selected = action;
                bool StillAllowed()
                {
                    if (LoginMode() != "fight" || Native.Read(Client) is not { } fresh || fresh.ClassId != classId || fresh.Busy ||
                        (Now >= recovery && fresh.Recovery == "unknown") ||
                        (Now >= recovery && fresh.Recovery == "recover" && selected != "Fight.Recover"))
                        return false;
                    return selected switch
                    {
                        "Fight.Recover" => fresh.Recovery == "recover",
                        "Fight.Jump" => fresh.Action is "idle" or "combat",
                        "Fight.Opening" => fresh.Action == "opening",
                        "Fight.Combat" => fresh.Action == "combat",
                        "Fight.Interact" => fresh.Action == "interact" && !fresh.Combat,
                        _ => fresh.Action == "idle"
                    };
                }
                var result = await Operate(selected, op => StillAllowed() && (movement is null
                    ? Key(op, keys) && (selected != "Fight.Interact" || automation.Operator.Wait(op, op.Timing.InteractionHoldMs))
                    : automation.Operator.Hold(op, Client, movement, hold, StillAllowed)));
                command?.Completion.TrySetResult(result);
                if (result.Error?.Contains("前台保护时间", StringComparison.Ordinal) == true)
                    retryAt = Now + settings.Operations.FocusRetryMs;
                if (result.Executed)
                {
                    long sent = result.SentAt;
                    if (selected == "Fight.Recover")
                        recovery = sent + 1000L * profile.RecoveryCooldownSeconds;
                    else if (selected == "Fight.Buff")
                    {
                        buffs = (buffs == 0 ? profile.BuffCount : buffs) - 1;
                        buffAt = sent + (buffs > 0 ? 1000L : 1000L * profile.BuffIntervalSeconds);
                    }
                    else if (selected == "Fight.Jump")
                        jumpAt = sent + 1000L * common.JumpIntervalSeconds;
                    actionAt = sent + (selected == "Fight.Opening" ? Math.Max(1000, settings.Periods.FightMs) : settings.Periods.FightMs);
                }
                else if (keys.Any(string.IsNullOrEmpty))
                {
                    if (selected == "Fight.Buff")
                    {
                        buffs = 0;
                        buffAt = long.MaxValue;
                    }
                    message = $"请配置 {selected} 按键。";
                }
            }
            metrics = new { packet.Action, packet.Recovery, packet.Combat, packet.Busy, packet.ClassId, packet.EncounterId,
                recovery, buffs, buffAt, jumpAt, retryAt };
            deadline = MinDeadline(now, recovery, buffAt, jumpAt);
            message = $"战斗 {packet.Action}，恢复 {packet.Recovery}。";
            await Tick(Math.Min(settings.Periods.FightMs, settings.Periods.DeathMs));
        }
        return "已停止";
    }

    private static long? MinDeadline(long now, params long[] values) =>
        values.Where(value => value > now && value != long.MaxValue).Select(value => (long?)value).Min();

    private async Task<string> Tame()
    {
        int targetId = -1, finished = -1, stage = 0, interval = -1;
        bool seenCombat = false, sentTame = false, active = false, advancedAfterJump = false;
        long due = 0, jumpAt = long.MaxValue, readyAt = 0;
        while (Current)
        {
            ApplyConfig();
            string login = await ObserveMode();
            if (login == "dead")
                return "角色死亡";
            TamePacket? packet;
            try { packet = Native.ReadTame(Client); }
            catch (WowAutoCapture.PendingException) { await RepairCapture(); continue; }
            if (packet?.State == "dead")
                return "角色死亡";
            TameSettings options = settings.Tame;
            if (options.TameKey.Length == 0)
                throw new InvalidOperationException("捕捉按键已清空。");
            long now = Now;
            if (interval != options.JumpIntervalSeconds)
            {
                interval = options.JumpIntervalSeconds;
                jumpAt = interval > 0 ? now + 1000L * interval : long.MaxValue;
            }
            if (packet?.State == "idle")
                active = false;
            else if (packet?.State == "matched" && packet.TargetId != finished)
            {
                if (!active || targetId != packet.TargetId)
                {
                    active = true;
                    targetId = packet.TargetId;
                    stage = 0;
                    due = now;
                    seenCombat = sentTame = advancedAfterJump = false;
                }
                seenCombat |= packet.Combat;
                if (!packet.Combat && (seenCombat || (sentTame && now >= due)))
                {
                    finished = targetId;
                    active = false;
                }
            }
            string[] keys = [options.TrapKey, options.OpeningKey, options.BackwardKey, options.TameKey];
            int[] waits = [options.TrapWaitMs, options.OpeningWaitMs, options.BackwardWaitMs, options.TameWaitMs];
            while (stage < 3 && keys[stage].Length == 0)
                stage++;
            bool jump = packet is { State: "idle" or "matched" } && options.JumpKey.Length > 0 && now >= Math.Max(jumpAt, readyAt) &&
                (!active || now >= due) && (active || !packet.Combat) && !advancedAfterJump;
            string? action = jump ? "Tame.Jump" : active && packet?.State == "matched" && now >= Math.Max(due, readyAt) ? "Tame.Key" : null;
            ManualAction? command = Manual(now >= retryAt ? action : null);
            if (action is not null && packet is not null && now >= retryAt)
            {
                bool appearedInCombat = false;
                bool Check()
                {
                    if (!LoggedIn() || Native.ReadTame(Client) is not { } fresh || fresh.TargetId != packet.TargetId)
                        return false;
                    appearedInCombat |= fresh.Combat;
                    return jump ? fresh.State == packet.State && fresh.Combat == packet.Combat :
                        fresh.State == "matched" && (!(seenCombat || sentTame || appearedInCombat) || fresh.Combat);
                }
                string key = jump ? options.JumpKey : keys[stage];
                int hold = !jump && stage == 2 ? options.BackwardHoldMs : 0;
                bool began = false;
                var result = await Operate(action, op =>
                {
                    if (!Check())
                        return false;
                    began = true;
                    return hold == 0 ? Key(op, key) : automation.Operator.Hold(op, Client, key, hold, Check);
                });
                command?.Completion.TrySetResult(result);
                seenCombat |= appearedInCombat;
                if (result.Error?.Contains("前台保护时间", StringComparison.Ordinal) == true)
                    retryAt = Now + settings.Operations.FocusRetryMs;
                if (result.Executed && jump)
                {
                    jumpAt = result.SentAt + interval * 1000L;
                    readyAt = result.SentAt + 1000;
                    advancedAfterJump = active;
                }
                else if (result.Executed)
                {
                    due = result.SentAt + waits[stage];
                    advancedAfterJump = false;
                    if (stage == 3)
                        sentTame = true;
                    else
                        stage++;
                }
                else if (hold > 0 && began)
                {
                    finished = targetId;
                    active = false;
                }
            }
            deadline = MinDeadline(now, due, jumpAt, readyAt);
            metrics = new { packet?.State, packet?.TargetId, packet?.Combat, stage, due, jumpAt, readyAt, active, finished, seenCombat, sentTame };
            message = active ? "抓宠流程运行中。" : "等待名单中的当前目标。";
            await Tick(100);
        }
        return "已停止";
    }
}
