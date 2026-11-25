using WowAuto.Threading;
using Capture = WowAutoCapture.Native;
using Rotation = WowAutoRotation.Native;

namespace WowAuto.Desktop;

internal sealed partial class GameSession
{
    private async Task<bool> Rotate(RotationBatch currentBatch)
    {
        phase = "switching";
        message = "正在返回角色选择界面。";
        metrics = null;
        deadline = Now + 180000;
        CharacterRecord[] catalog = AccountCatalog.Read(Client);
        if (catalog.Length == 0)
            throw new InvalidOperationException("此客户端没有可校验的插件角色记录。");
        CharacterRecord[]? beforeLogout = directRest && account is null ? catalog : null;
        if (account is not null && !catalog.Any(item => item.Account == account))
            throw new InvalidOperationException("已识别子战网的插件角色记录不可用。");
        if (account is not null && !ChooseRole(catalog))
            return false;

        long lastLogout = Now;
        if (await ObserveMode() != "unknown")
            await Logout();
        await Barrier(currentBatch, 1);

        int menus = 0, repeats = 0, retries = 0;
        long nextOcr = 0;
        MenuTarget? prior = null;
        Size priorSize = Size.Empty;
        while (Current)
        {
            if (Now >= deadline)
                throw new InvalidOperationException("选角超过 180 秒，已停止本进程任务。");
            ApplyConfig();
            string login = await ObserveMode();
            if (login != "unknown")
            {
                menus = repeats = 0;
                prior = null;
                if (Now >= lastLogout + 30000)
                {
                    await Logout();
                    lastLogout = Now;
                }
                await Tick(settings.Periods.MenuMs);
                continue;
            }
            if (Now < nextOcr)
            {
                await WaitUntil(nextOcr);
                continue;
            }
            nextOcr = Now + settings.Periods.OcrMs;
            if (Client.Flavor == "forerver")
            {
                var park = await Operate("Rotation.ParkCursor", _ =>
                {
                    if (LoginMode() != "unknown")
                        return false;
                    Rotation.ParkCursor(Client.ProcessId, Client.StartTicks, Client.Path);
                    return true;
                });
                if (!park.Executed)
                {
                    message = park.Error ?? "等待选角界面。";
                    continue;
                }
            }
            MenuFrame frame;
            try
            {
                Size size = Capture.ReadClientSize(Client.ProcessId, Client.StartTicks, Client.Path);
                using Bitmap bitmap = Rotation.Capture(Client.ProcessId, Client.StartTicks, Client.Path, size.Width, size.Height);
                frame = await ScreenOcr.Menu(bitmap, size, Client.Flavor, catalog, Token);
            }
            catch (WowAutoCapture.PendingException) { await RepairCapture(); continue; }
            catch (OperationCanceledException) when (Current) { message = "OCR 超时，等待重试。"; continue; }
            if (!frame.Menu)
            {
                menus = repeats = 0;
                prior = null;
                message = "等待角色选择界面。";
                continue;
            }
            if (!directRest)
                deadline = Now + 180000;
            menus++;
            metrics = new { menus, retries, targets = frame.Targets };
            if (menus < 3)
                continue;
            string? confirmedAccount = directRest ? ResolveAccount(frame.Targets, catalog, exactOnly: true) : null;
            if (directRest && confirmedAccount is not null && account is not null && confirmedAccount != account)
                throw new InvalidOperationException("选角界面的子战网已变化，已停止放号轮转。");
            if (account is null)
            {
                account = directRest ? confirmedAccount : ResolveAccount(frame.Targets, catalog);
                if (account is not null)
                {
                    message = $"OCR 已识别子战网 {account}。";
                    if (beforeLogout is not null)
                    {
                        catalog = AccountCatalog.Read(Client);
                        CreditStartingRest(beforeLogout, catalog);
                        beforeLogout = null;
                    }
                    if (!ChooseRole(catalog))
                        return false;
                }
            }
            var matches = account is null || role is null || (directRest && confirmedAccount != account) ? [] : frame.Targets
                .Where(item => ResolveName(item.Raw, catalog.Where(record => record.Account == account).ToArray())?.Name == role)
                .DistinctBy(item => item.Row).ToArray();
            if (matches.Length > 1)
                throw new InvalidOperationException("选角界面存在多个同名角色。");
            if (matches.Length == 0)
            {
                if (retries >= 30)
                {
                    if (directRest)
                        throw new InvalidOperationException("重识别 30 次仍无法确认当前子战网和放号角色，已停止轮转。");
                    message = "重识别 30 次仍无法唯一定位，准备退出客户端。";
                    currentBatch.Drop(Endpoint.Key);
                    await automation.CloseClient(row, version, settings, Token);
                    return false;
                }
                var up = await Operate("Rotation.Up", op => LoginMode() == "unknown" &&
                    NativeInput.PressChord(Client.ProcessId, Client.StartTicks, Client.Path, 38, false, false, false, op.Timing.ChatKeyPressMs));
                if (up.Executed)
                    retries++;
                repeats = 0;
                prior = null;
                await Tick(settings.Periods.MenuMs);
                continue;
            }
            MenuTarget selected = matches[0];
            bool stable = prior is not null && prior.Row == selected.Row && Math.Abs(prior.X - selected.X) < .005 &&
                Math.Abs(prior.Y - selected.Y) < .005 &&
                Rotation.ClientSizeWithinTolerance(priorSize.Width, priorSize.Height, frame.Size.Width, frame.Size.Height);
            if (!stable)
                priorSize = frame.Size;
            repeats = stable ? repeats + 1 : 1;
            prior = selected;
            if (repeats < 2)
                continue;
            message = $"已定位第 {selected.Row} 个槽位 {role}，等待其他进程。";
            await Barrier(currentBatch, 2);
            if (!(directRest ? Eligible() : ConfiguredRoles()).Any(item => item.Name == role && item.Mode == mode))
            {
                currentBatch.Clear(Endpoint.Key, 2);
                role = null;
                if (!ChooseRole(catalog))
                    return false;
                repeats = 0;
                continue;
            }
            int min = settings.Operations.ClickMinMs, max = settings.Operations.ClickMaxMs;
            int first = Random.Shared.Next(min, max + 1), second = Random.Shared.Next(min, max + 1);
            Size baseline = priorSize;
            var click = await Operate("Rotation.Click", op => LoginMode() == "unknown" && Rotation.ClickCharacter(
                Client.ProcessId, Client.StartTicks, Client.Path, selected.X, selected.Y, baseline.Width, baseline.Height,
                first, second, min, max));
            if (click.Executed)
                break;
            currentBatch.Clear(Endpoint.Key, 2);
            repeats = 0;
            prior = null;
        }

        message = $"等待角色 {role} 登录。";
        await Barrier(currentBatch, 4);
        int confirmations = 0;
        while (Current && confirmations < 3)
        {
            if (Now >= deadline)
                throw new InvalidOperationException("登录确认超过 180 秒。");
            string login = await ObserveMode();
            if (login == "dead")
            {
                excluded.Add(role!);
                message = $"角色 {role} 已死亡。";
                currentBatch.Drop(Endpoint.Key);
                if (Eligible().Length == 0)
                    return false;
                batch = await automation.JoinRotation(Endpoint, Token);
                return await Rotate(batch);
            }
            confirmations = login == "unknown" ? 0 : confirmations + 1;
            if (confirmations < 3)
                await Tick(settings.Periods.LoginMs);
        }
        await Enable("Rotation.Enable");
        await Barrier(currentBatch, 8);
        deadline = null;
        return Current;
    }

    private bool ChooseRole(CharacterRecord[] catalog)
    {
        var eligible = Eligible();
        var candidates = eligible.Where(item => catalog.Any(record => record.Account == account &&
            record.Name == item.Name && record.Realm == item.Realm)).ToArray();
        RoleSettings? pick = null;
        if (target is not null)
        {
            pick = candidates.FirstOrDefault(item => item.Name == target);
            if (pick is null)
                throw new InvalidOperationException($"角色 {target} 不在当前子战网的可运行列表中。");
            target = null;
        }
        if (candidates.Length == 0)
        {
            role = null;
            message = directRest && ConfiguredRoles().Length > 0 && eligible.Length == 0
                ? "本次放号轮转已完成。"
                : "当前子战网没有启用且可校验的角色任务。";
            return false;
        }
        if (directRest)
        {
            var configured = ConfiguredRoles();
            int start = Array.FindIndex(configured, candidate => candidate.Name == role) + 1;
            pick = configured.Skip(start).Concat(configured.Take(start)).First(candidates.Contains);
        }
        else
        {
            int previous = Array.FindIndex(candidates, candidate => candidate.Name == role);
            pick ??= candidates[(previous + 1) % candidates.Length];
        }
        role = pick.Name;
        mode = pick.Mode;
        roleUseItem = pick.UseItem;
        return true;
    }

    private void CreditStartingRest(CharacterRecord[] beforeLogout, CharacterRecord[] afterLogout)
    {
        // The client saves the logged-in character's plugin record on logout.
        var previous = beforeLogout.Where(item => item.Account == account).ToLookup(item => (item.Name, item.Realm));
        var changed = afterLogout.Where(item => item.Account == account &&
            previous[(item.Name, item.Realm)].All(old => old.RecordedAt < item.RecordedAt)).Take(2).ToArray();
        if (changed.Length != 1)
        {
            automation.Log(Client.ProcessId, "status", "未通过下线记录确认起始角色，按当前子战网的放号名单继续。");
            return;
        }
        var startingRole = changed[0];
        if (ConfiguredRoles().Any(item => item.Name == startingRole.Name && item.Realm == startingRole.Realm))
        {
            role = startingRole.Name;
            restVisits[role] = initialRestVisits;
        }
    }

    private async Task Barrier(RotationBatch currentBatch, int flag)
    {
        Token.ThrowIfCancellationRequested();
        currentBatch.Mark(Endpoint.Key, flag);
        automation.Hub.Wake.Set();
        while (!currentBatch.All(flag))
        {
            await Tick(Math.Max(10, settings.Operations.CommandReceiveMs));
            if (deadline is not null && Now >= deadline.Value)
                throw new InvalidOperationException("等待换角批次超时。");
        }
    }

    private Task<ActionResult> Logout() => Operate("Rotation.Logout", op => LoginMode() != "unknown" &&
        NativeInput.SendRotationCommand(Client.ProcessId, Client.StartTicks, Client.Path, "logout", 0, op.Timing.ChatKeyPressMs));

    private static string? ResolveAccount(MenuTarget[] targets, CharacterRecord[] catalog, bool exactOnly = false)
    {
        var hits = targets.Select(item => ResolveName(item.Raw, catalog)).OfType<NameMatch>().ToArray();
        var exact = hits.Where(match => match.Exact).ToArray();
        if (hits.Length == 0 || (exactOnly && exact.Length == 0))
            return null;
        var evidence = exact.Length == 0 ? hits : exact;
        var possible = evidence[0].Accounts.ToHashSet(StringComparer.Ordinal);
        foreach (var match in evidence.Skip(1))
            possible.IntersectWith(match.Accounts);
        if (!exactOnly && possible.Count > 1)
            foreach (var match in hits.Where(match => !match.Exact))
                possible.IntersectWith(match.Accounts);
        return possible.Count == 1 ? possible.Single() : null;
    }

    private sealed record NameMatch(string Name, bool Exact, string[] Accounts);

    private static NameMatch? ResolveName(string text, CharacterRecord[] catalog)
    {
        var matches = catalog.Where(role => text == role.Name || text == $"{role.Name}-{role.DisplayRealm}").ToArray();
        bool exact = matches.Length > 0;
        if (!exact)
            matches = catalog.Where(role => Near(text, role.Name) || Near(text, $"{role.Name}-{role.DisplayRealm}")).ToArray();
        string[] names = matches.Select(role => role.Name).Distinct().ToArray();
        return names.Length == 1 ? new(names[0], exact, matches.Select(role => role.Account).Distinct().ToArray()) : null;
    }

    private static bool Near(string text, string name) => text.Length == name.Length && name.Length >= 2 &&
        text.Zip(name, (left, right) => left != right).Count(different => different) <= 1;
}
