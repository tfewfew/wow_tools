using WowAuto.Threading;

namespace WowAuto.Desktop;

internal sealed partial class GameSession
{
    private async Task<string> Rest()
    {
        long accumulated = 0, observed = Now, lastJump = 0;
        bool wasRest = false, startedRest = false;
        while (Current)
        {
            ApplyConfig();
            if (!direct && !ConfiguredRoles().Any(item => item.Name == role && item.Mode == "rest"))
                return "角色任务已变更";
            string login;
            try { login = LoginMode(); }
            catch (WowAutoCapture.PendingException) { wasRest = false; await RepairCapture(); continue; }
            if (login == "dead")
                return "角色死亡";
            long now = Now;
            bool inRest = login == "rest";
            if (startedRest && inRest && wasRest)
                accumulated += now - observed;
            observed = now;
            wasRest = inRest;
            long remaining = Math.Max(0, 1000L * settings.Rest.DurationSeconds - accumulated);
            if (startedRest && remaining == 0 && inRest)
                return "放号完成";
            long next = lastJump + 1000L * settings.Rest.JumpIntervalSeconds;
            deadline = startedRest && inRest ? now + remaining : null;
            bool canJump = inRest && now >= retryAt && (!startedRest || next <= now);
            ManualAction? command = Manual(canJump ? "Rest.Jump" : null);
            if (canJump)
            {
                long? expires = deadline;
                var result = await Operate("Rest.Jump", op => (expires is null || Now < expires) && LoginMode() == "rest" && Key(op, "Space"));
                command?.Completion.TrySetResult(result);
                if (result.Executed)
                {
                    lastJump = result.SentAt;
                    if (!startedRest)
                        observed = lastJump;
                    startedRest = true;
                }
                else
                {
                    wasRest = false;
                    if (result.Error?.Contains("前台保护时间", StringComparison.Ordinal) == true)
                        retryAt = Now + settings.Operations.FocusRetryMs;
                }
            }
            metrics = new { inRest, accumulated, remaining, nextJumpAt = next, round = restVisits.GetValueOrDefault(role ?? "") + 1,
                rounds = direct ? 1 : settings.Rest.Rounds, startedRest };
            message = inRest ? "放号计时中。" : "放号色块暂不可读，计时暂停。";
            await Tick(settings.Periods.LoginMs);
        }
        return "已停止";
    }

    private async Task<string> Shop()
    {
        long startedShop = Now, stateAt = startedShop, stateDue = 0, lastJump = startedShop, finishedAt = 0;
        string lastState = "";
        int visits = 0;
        long rollingDelay = 0, rollingJitter = -1;
        while (Current)
        {
            ApplyConfig();
            if (!direct && !ConfiguredRoles().Any(item => item.Name == role && item.Mode == "shop"))
            {
                await CancelShop();
                return "角色任务已变更";
            }
            string state;
            try { state = ShopState(); }
            catch (WowAutoCapture.PendingException) { await RepairCapture(); continue; }
            if (state == "dead")
                return "角色死亡";
            ShopSettings options = settings.Shop;
            long now = Now;
            long end = startedShop + 1000L * options.DurationSeconds;
            if (state == "bought")
            {
                var receipt = await Operate("Shop.Logout", op => LoginMode() == "shop" && ShopState() == "bought" &&
                    NativeInput.SendRotationCommand(Client.ProcessId, Client.StartTicks, Client.Path, "logout", 0, op.Timing.ChatKeyPressMs));
                if (receipt.Executed)
                {
                    shopPrepared = false;
                    await automation.CloseClient(row, version, settings, Token);
                    return "买到商品，已请求退出";
                }
            }
            if (finishedAt != 0 && now - finishedAt >= 3000)
                return "购物结束";
            if (finishedAt == 0 && now >= end)
            {
                var finish = await Operate("Shop.Stop", op => LoginMode() == "shop" && Chat(op, "finish"));
                if (!finish.Executed && finish.Error is not null)
                    message = finish.Error;
                shopPrepared = !finish.Executed;
                finishedAt = Now;
                continue;
            }
            string? action = null;
            long baseDelay = state == "open" ? options.CloseDelayMs : options.ReopenDelayMs;
            if (state != lastState || baseDelay != rollingDelay || options.JitterMs != rollingJitter)
            {
                if (lastState != state)
                    stateAt = now;
                stateDue = stateAt + Math.Max(1, baseDelay + Random.Shared.NextInt64(-options.JitterMs, options.JitterMs + 1));
                lastState = state;
                rollingDelay = baseDelay;
                rollingJitter = options.JitterMs;
            }
            long nextJump = options.JumpIntervalSeconds > 0 ? lastJump + 1000L * options.JumpIntervalSeconds : long.MaxValue;
            if (finishedAt == 0 && now >= retryAt)
                action = state switch
                {
                    "open" when now >= stateDue => "Shop.Close",
                    "closed" when now >= stateDue => "Shop.Visit",
                    "closed" when now >= nextJump => "Shop.Jump",
                    _ => null
                };
            ManualAction? command = Manual(action);
            if (action is not null)
            {
                string selected = action;
                bool jumped = false;
                bool Ready(Operation op) => op.Current && Now < end && LoginMode() == "shop" && ShopState() == state;
                var result = await Operate(selected, op =>
                {
                    if (!Ready(op))
                        return false;
                    if (selected == "Shop.Close")
                        return Chat(op, "close");
                    if (selected == "Shop.Jump")
                        return Key(op, "Space");
                    if (!Key(op, options.InteractKey))
                        return false;
                    if (options.JumpOnVisit)
                    {
                        if (!op.Current || Now >= end || !(jumped = Key(op, "Space")))
                            return false;
                    }
                    return op.Current && Now < end && LoginMode() == "shop" && Chat(op, "buy");
                });
                command?.Completion.TrySetResult(result);
                if (result.Error?.Contains("前台保护时间", StringComparison.Ordinal) == true)
                    retryAt = Now + settings.Operations.FocusRetryMs;
                if (jumped || (result.Executed && selected == "Shop.Jump"))
                    lastJump = Now;
                if (result.Executed && selected == "Shop.Visit")
                    visits++;
                if (selected != "Shop.Jump")
                    stateDue = Now + Math.Max(100, baseDelay);
            }
            deadline = finishedAt == 0 ? end : finishedAt + 3000;
            metrics = new { state, stateDue, nextJump, visits, startedShop, finishedAt };
            message = $"购物 {state}，已访问 {visits} 次。";
            await Tick(Math.Min(100, settings.Periods.LoginMs));
        }
        return "已停止";
    }

    private async Task CancelShop()
    {
        shopPrepared = false;
        if (automation.Hub.Closing || !WowAutoFight.Native.IsAlive(Client))
            return;
        using var timeout = new CancellationTokenSource(5000);
        try
        {
            await automation.Operator.Submit(Endpoint, Endpoint.Version, settings, "Shop.Stop",
                op => LoginMode() == "shop" && Chat(op, "cancel"), timeout.Token);
        }
        catch (OperationCanceledException) { }
    }
}
