using WowAuto.Audio;

namespace WowAuto.Desktop;

internal sealed partial class GameSession
{
    private async Task<string> Fish()
    {
        ProcessCapture? audio = null;
        int audioTemplate = 0, audioThreshold = 0;
        long currentArm = 0, bite = 0, matchAt = 0, waiting = 0, protection = 0, reel = 0, cooldown = 0;
        long nextCast = 0, nextBait = 0, itemConfirm = 0, colorRetry = 0;
        int jumpIntervalAtReel = 0;
        bool periodicJump = false;
        bool forceCast = false, requireRed = false, afterReel = false, skipItem = false;
        string color = "unknown", lure = "unknown";

        void ResetWait(bool recast)
        {
            waiting = protection = reel = 0;
            forceCast = requireRed = recast;
            afterReel = false;
            periodicJump = false;
            audio?.Arm(0);
        }

        try
        {
            while (Current)
            {
                ApplyConfig();
                if (ShouldRotate())
                    return "准备切换角色";
                string login;
                try
                {
                    login = LoginMode();
                    color = login is "fish" or "dead" ? FishColor() : "unknown";
                }
                catch (WowAutoCapture.PendingException) { await RepairCapture(); continue; }
                if (login == "dead" || color == "dead")
                    return "角色死亡";
                if (color == "yellow")
                    return "背包已满";

                FishSettings fish = settings.Fish;
                if (fish.JumpEveryCycles != jumpIntervalAtReel)
                    periodicJump = false;
                FishFlavor local = fish.For(Client.Flavor);
                long now = Now;
                if (fish.AudioDetectionEnabled && (audio is null || audioTemplate != local.AudioRecordingId))
                {
                    var template = AudioTemplate.LoadFeatures(Automation.AudioPath(Client.Flavor, local.AudioRecordingId));
                    if (audio is null)
                        audio = new ProcessCapture(Client.ProcessId, Client.StartTicks, Client.Path, template,
                            local.AudioThresholdPercent / 100.0, arm => {
                                Interlocked.Exchange(ref matchAt, Now);
                                Interlocked.Exchange(ref bite, arm);
                                Wake();
                            });
                    else
                        audio.SetTemplate(template, local.AudioThresholdPercent / 100.0);
                    if (waiting > 0 && reel == 0)
                    {
                        Interlocked.Exchange(ref bite, 0);
                        audio.Arm(++currentArm);
                    }
                    audioTemplate = local.AudioRecordingId;
                    audioThreshold = local.AudioThresholdPercent;
                    if (waiting > 0 && protection == 0 && reel > 0)
                    {
                        reel = 0;
                        protection = now + local.AudioTimeoutMs;
                        Interlocked.Exchange(ref bite, 0);
                        audio.Arm(++currentArm);
                    }
                }
                else if (!fish.AudioDetectionEnabled && audio is not null)
                {
                    audio.Dispose();
                    audio = null;
                    if (waiting > 0 && reel == 0)
                        reel = now + Random.Shared.Next(local.MinimumMs, local.MaximumMs + 1);
                    protection = 0;
                }
                else if (audio is not null && audioThreshold != local.AudioThresholdPercent)
                {
                    audio.SetMinimumSimilarity(local.AudioThresholdPercent / 100.0);
                    audioThreshold = local.AudioThresholdPercent;
                }
                if (audio?.Status is "Failed" or "Error")
                    throw new InvalidOperationException(audio.Error);
                if (audio is not null && login == "fish" && color is not ("red" or "green") && now >= colorRetry)
                {
                    ResetWait(false);
                    colorRetry = now + settings.Operations.FishColorRetryMs;
                }

                bool useItem = Volatile.Read(ref overrides).UseItem ??
                    (direct ? fish.DirectStartUseItem : ConfiguredRoles().FirstOrDefault(item => item.Name == role)?.UseItem ?? roleUseItem);
                bool usable = now >= colorRetry && now >= retryAt && color is "red" or "green";
                if (waiting > 0 && reel == 0 && audio is not null && Interlocked.Read(ref bite) == currentArm)
                {
                    long matched = Interlocked.Read(ref matchAt);
                    if (matched >= waiting + 1000)
                    {
                        reel = matched + Random.Shared.Next(local.MinimumMs, local.MaximumMs + 1);
                        if (reel > protection)
                        {
                            row.BiteTimeouts++;
                            automation.Log(Client.ProcessId, "audio-timeout", "匹配后的收竿延迟超过本轮保护截止。");
                        }
                    }
                }

                string? action = null;
                if (usable && waiting > 0 && reel > 0 && now >= reel)
                    action = "Fish.Reel";
                else if (waiting > 0 && reel == 0 && protection > 0 && now >= protection)
                {
                    row.BiteTimeouts++;
                    automation.Log(Client.ProcessId, "audio-timeout", $"无咬钩。峰值 {audio?.MaximumPeak:P2}，最高相似度 {audio?.BestSimilarity:P2}，候选 {audio?.ComparedCandidates}。");
                    ResetWait(true);
                }
                else if (usable && waiting == 0 && now >= cooldown && (audio is null || audio.Status == "Listening"))
                {
                    if (color == "red")
                        requireRed = false;
                    if (afterReel && (periodicJump || color == "green"))
                        action = "Fish.Jump";
                    else if (color == "red" && useItem && !skipItem && now >= nextBait)
                    {
                        nextBait = now + settings.Periods.BaitMs;
                        try { lure = LureColor(); }
                        catch (WowAutoCapture.PendingException) { await RepairCapture(); continue; }
                        if (lure == "present")
                            itemConfirm = 0;
                        else if (itemConfirm > 0 && now >= itemConfirm)
                        {
                            skipItem = true;
                            itemConfirm = 0;
                        }
                        else if (lure == "missing" && itemConfirm == 0)
                            action = "Fish.Item";
                    }
                    if (action is null && (!useItem || itemConfirm == 0))
                    {
                        if (color == "green" && !forceCast && !requireRed)
                        {
                            waiting = now;
                            if (audio is null)
                                reel = now + Random.Shared.Next(local.MinimumMs, local.MaximumMs + 1);
                            else
                            {
                                protection = now + local.AudioTimeoutMs;
                                Interlocked.Exchange(ref bite, 0);
                                audio.Arm(++currentArm);
                            }
                        }
                        else if (now >= nextCast && (color == "red" || forceCast))
                            action = "Fish.Cast";
                    }
                }
                ManualAction? command = Manual(action);
                if (action == "Fish.Reel")
                {
                    bool success = await Execute(action, op => LoginMode() == "fish" &&
                        (audio is not null ? FishColor() == "green" : FishColor() is "red" or "green") &&
                        Key(op, fish.ReelKey) && automation.Operator.Wait(op, op.Timing.ReelHoldMs), command);
                    ResetWait(true);
                    if (success)
                    {
                        row.Cycles++;
                        row.CyclesSinceJump++;
                        afterReel = true;
                        jumpIntervalAtReel = fish.JumpEveryCycles;
                        periodicJump = jumpIntervalAtReel > 0 && row.CyclesSinceJump >= jumpIntervalAtReel;
                        cooldown = Now + Math.Max(0, 1000 - settings.Operations.ReelHoldMs);
                    }
                }
                else if (action == "Fish.Jump")
                {
                    if (await Execute(action, op => LoginMode() == "fish" && FishColor() is "red" or "green" && Key(op, "Space"), command))
                    {
                        row.CyclesSinceJump = 0;
                        afterReel = false;
                        periodicJump = false;
                    }
                }
                else if (action == "Fish.Item")
                {
                    if (await Execute(action, op => LoginMode() == "fish" && FishColor() == "red" && LureColor() == "missing" &&
                        Key(op, fish.ItemKey) && automation.Operator.Wait(op, op.Timing.ItemHoldMs), command))
                        itemConfirm = Now + Math.Max(1, 5000 - settings.Operations.ItemHoldMs);
                }
                else if (action == "Fish.Cast")
                {
                    bool forced = forceCast;
                    if (await Execute(action, op => LoginMode() == "fish" && (FishColor() == "red" || (forced && FishColor() == "green")) &&
                        Key(op, fish.CastKey), command))
                    {
                        forceCast = afterReel = false;
                        nextCast = Now + Random.Shared.Next(400, 651);
                    }
                }

                deadline = reel > 0 ? reel : protection > 0 ? protection : cooldown > now ? cooldown : null;
                metrics = new
                {
                    color, lure, useItem, audio = audio?.Status, audio?.Peak, audio?.Similarity, audio?.CandidatePeakThreshold,
                    audio?.ComparedCandidates, audio?.BestSimilarity, audio?.MaximumPeak, waiting, protection, reel, cooldown,
                    row.CyclesSinceJump, colorRetry, postReel = afterReel
                };
                message = now < colorRetry ? "钓鱼色块暂不可读，等待重试。" : reel > 0 ? "等待收竿。" :
                    waiting > 0 ? "监听咬钩。" : cooldown > now ? "收竿冷却。" : "等待钓鱼状态。";
                int poll = Math.Min(settings.Periods.FishMs, settings.Periods.DeathMs);
                if (audio is not null)
                    poll = Math.Min(poll, settings.Periods.AudioMs);
                long due = deadline is > 0 ? deadline.Value - Now : poll;
                await Tick((int)Math.Clamp(due, 1, poll));
            }
            return "已停止";
        }
        finally { audio?.Dispose(); }
    }
}
