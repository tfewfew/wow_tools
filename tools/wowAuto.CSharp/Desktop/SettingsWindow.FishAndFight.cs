using System.Text.Json;
using System.Text.Json.Nodes;

namespace WowAuto.Desktop;

internal sealed partial class SettingsWindow
{
    private void BuildFishPage()
    {
        var draft = Draft();
        TabPage page = fishPage = Ui.Page(tabs, "自动钓鱼");
        page.AutoScrollMinSize = Ui.Size(960, 874);
        Ui.Label(page, "版本", 18, 18, 95, 25);
        Ui.Label(page, "收杆延迟区间配置（ms）", 130, 18, 375, 25);
        Ui.Label(page, "音频门槛（%）", 530, 18, 185, 25);
        Ui.Label(page, "无咬钩保护（ms）", 730, 18, 215, 25);
        GroupBox recordings = Ui.Group(page, "咬钩匹配片段（按版本选择）", 18, 238, 912, 151);
        audioPreviewStatus = Ui.Label(recordings, "", 16, 118, 876, 28);
        Label feedback = Ui.Label(page, "", 18, 752, 912, 52);
        for (int index = 0; index < Ui.Clients.Length; index++)
        {
            var (id, label) = Ui.Clients[index];
            string prefix = index == 0 ? "Fish.Titan." : "Fish.Forerver.";
            int y = 54 + index * 46;
            Ui.Label(page, label, 18, y + 4, 95, 30);
            draft.Number(page, prefix + "MinimumMs", 130, y, 175, 1, 3600000, 100);
            Ui.Label(page, "-", 306, y + 2, 24, 28).TextAlign = ContentAlignment.MiddleCenter;
            draft.Number(page, prefix + "MaximumMs", 330, y, 175, 1, 3600000, 100);
            draft.Number(page, prefix + "AudioThresholdPercent", 530, y, 175, 1, 100);
            draft.Number(page, prefix + "AudioTimeoutMs", 730, y, 200, 1000, 3600000, 1000);

            int recordingY = 30 + index * 46;
            Ui.Label(recordings, label, 16, recordingY + 5, 95, 30);
            ComboBox samples = Ui.Choice(recordings, 112, recordingY, 528);
            samples.Items.AddRange(index == 0
                ? ["片段 1 · 2026-10-11 · 右侧窗口 · 1秒", "片段 2 · 2026-10-12 · 左上窗口 · 1秒"]
                : ["片段 1 · 2026-10-11 · 1秒"]);
            draft.Bind(prefix + "AudioRecordingId", () => JsonValue.Create(samples.SelectedIndex + 1),
                value => samples.SelectedIndex = value!.GetValue<int>() - 1);
            samples.SelectedIndexChanged += (_, _) => StopAudioPreview();
            Ui.Button(recordings, "试听", 652, recordingY, 110, 36, () =>
            {
                try
                {
                    desktop.PlayAudioPreview(id, samples.SelectedIndex + 1);
                    previewing = true;
                    feedback.Text = "";
                    audioPreviewStatus.Text = $"试听片段：{label} · {samples.Text}";
                    previewTimer.Stop();
                    previewTimer.Start();
                }
                catch (Exception error) { feedback.Text = error.Message; }
            });
        }
        Ui.Button(recordings, "停止试听", 780, 30, 110, 36, StopAudioPreview);
        Ui.Label(page, "日志保留条数", 530, 150, 185, 30);
        draft.Number(page, "StatusLogLimit", 730, 146, 200, 1, 1000);
        Ui.Label(page, "跳跃间隔（循环，0关闭）", 530, 196, 200, 30);
        draft.Number(page, "Fish.JumpEveryCycles", 730, 192, 200, 0, int.MaxValue);

        GroupBox keys = Ui.Group(page, "快捷键（所有进程）", 18, 400, 745, 131);
        (string Id, string Label)[] keyFields = [("CastKey", "抛竿"), ("ReelKey", "收竿"), ("ItemKey", "钓鱼道具"), ("EquipRodKey", "装备鱼竿")];
        for (int i = 0; i < keyFields.Length; i++)
        {
            int x = 16 + i * 182;
            Ui.Label(keys, keyFields[i].Label, x, 28, 150, 28);
            KeyBox input = draft.Key(keys, "Fish." + keyFields[i].Id, x, 58, 162, "未配置");
            if (keyFields[i].Id == "EquipRodKey")
                Ui.Button(keys, "清空", 674, 25, 52, 28, () => input.Binding = "");
        }
        Ui.Label(keys, "点击输入框后直接按键，支持 Ctrl / Shift / Alt 组合键。", 16, 98, 715, 28);
        CheckBox audio = draft.Check(page, "Fish.AudioDetectionEnabled", "音频咬钩检测", 780, 414, 160);
        if (automation.DesktopSnapshot().Processes.Any(process => process.Mode == "fish" && process.Phase is "starting" or "running" or "switching"))
            audio.Enabled = false;
        Ui.Label(page, "停止钓鱼后可修改", 780, 460, 160, 65);

        GroupBox direct = Ui.Group(page, "直接开始（所有进程）", 18, 544, 912, 90);
        draft.Check(direct, "Fish.DirectStartUseItem", "使用钓鱼道具", 16, 30, 250);
        Ui.Label(direct, "直接开始钓鱼时检查并补充鱼竿附魔。保存后从下次直接开始生效。", 282, 27, 610, 52);

        Ui.Label(page, "音频模式：匹配成功后随机等待；定时模式：变绿后随机等待。\r\n" +
            "无咬钩保护从确认绿色开始计时，仅用于音频模式。\r\n" +
            "无咬钩保护与片段选择从下轮生效；试听播放1秒匹配片段。",
            18, 650, 912, 100);
        Ui.Button(page, "保存钓鱼设置", 540, 819, 150, 36,
            () => draft.SaveWithFeedback(feedback, "钓鱼设置已保存。", StopAudioPreview), true);
        Ui.Button(page, "取消", 700, 819, 95, 36, Close);
    }

    private void StopAudioPreview()
    {
        if (!previewing)
            return;
        previewing = false;
        previewTimer.Stop();
        desktop.StopAudioPreview();
        audioPreviewStatus.Text = "";
    }

    private void BuildFightPage()
    {
        var draft = Draft();
        TabPage page = Ui.Page(tabs, "自动战斗", false);
        page.BackColor = Ui.Surface;
        var body = new Panel { Dock = DockStyle.Fill, AutoScroll = true, AutoScrollMinSize = Ui.Size(840, 780) };
        var footer = new Panel { Dock = DockStyle.Bottom, Size = Ui.Size(DesignWidth, 100) };
        GrayTabs clients = Ui.Place(body, Ui.Tabs(140), 16, 12, 808, 260);
        foreach (var (id, label) in Ui.Clients)
            BuildFightClient(Ui.Page(clients, label), draft, id);

        Ui.Label(body, "通用设置：全部服务器与职业", 16, 278, 810, 26);
        (string Id, string Label)[] common =
        [
            ("MoveForwardKey", "向前移动键"), ("MoveBackwardKey", "向后移动键"),
            ("MoveLeftKey", "向左移动键"), ("MoveRightKey", "向右移动键"),
            ("SkinKey", "拾取 / 剥皮交互键"), ("TargetKey", "选中目标键")
        ];
        for (int i = 0; i < common.Length; i++)
        {
            int x = 16 + i % 2 * 420, y = 306 + i / 2 * 44;
            Ui.Label(body, common[i].Label, x, y + 4, 220, 32);
            draft.Key(body, "Fight.Common." + common[i].Id, x + 224, y, 168);
        }
        Ui.Label(body, "移动按住时长 (ms)", 16, 446, 220, 32);
        draft.Number(body, "Fight.Common.MovementHoldMs", 240, 442, 168, 1, 60000, 100);
        draft.Check(body, "Fight.Common.SkinEnabled", "启用自动拾取 / 剥皮交互", 16, 488, 600);
        Ui.Label(body, "自动跳跃间隔 (秒，0 关闭)", 16, 574, 340, 32);
        draft.Number(body, "Fight.Common.JumpIntervalSeconds", 360, 570, 168, 0, 3600);
        Ui.Label(body, "选目标键须与游戏内选目标按键一致。\r\n每次采样最多执行一个逻辑动作。\r\n" +
            "恢复键成功发送后按职业冷却；冷却期间忽略副色块恢复提示，主状态继续运行。\r\n" +
            "补 Buff 间隔为 0 时关闭；进入游戏和到期后各执行一轮，轮内成功按键相隔至少 1 秒。\r\n" +
            "检测 / 攻击距离在插件面板设置；等待接近期间不发攻击键。",
            16, 616, 812, 144);
        Label status = Ui.Label(footer, "", 16, 4, DesignWidth - 32, 30);
        status.AutoEllipsis = true;
        status.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        var save = Ui.Button(footer, "保存战斗设置", DesignWidth - 266, 50, 130, 32,
            () => draft.SaveWithFeedback(status, "战斗设置已保存。"), true);
        var cancel = Ui.Button(footer, "取消", DesignWidth - 116, 50, 100, 32, Close);
        save.Anchor = cancel.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        page.Controls.AddRange([body, footer]);
    }

    private static void BuildFightClient(TabPage page, SettingsDraft draft, string flavor)
    {
        page.BackColor = Ui.Surface;
        page.AutoScrollMinSize = Ui.Size(790, 216);
        Ui.Label(page, "职业", 8, 10, 216, 28);
        var classes = Ui.Choice(page, 232, 6, 168, item => Ui.Class(((ClassChoice)item).Id).Color);
        int[] ids = SettingsRules.ClassIds.Where(id => flavor != "forerver" || id != 6).ToArray();
        classes.Items.AddRange(ids.Select(id => new ClassChoice(id)).ToArray());
        var (collect, load) = BuildFightProfile(page);
        var profiles = new FightProfile[ids.Length];
        int shown = -1;
        for (int i = 0; i < ids.Length; i++)
        {
            int index = i;
            draft.Bind($"Fight.Profiles.{flavor}:{ids[index]}",
                () => JsonSerializer.SerializeToNode(shown == index ? collect() : profiles[index], SettingsJson.Options),
                value =>
                {
                    profiles[index] = value?.Deserialize<FightProfile>(SettingsJson.Options) ?? new();
                    if (shown == index)
                        load(profiles[index]);
                });
        }
        classes.SelectedIndexChanged += (_, _) =>
        {
            if (shown >= 0)
                profiles[shown] = collect();
            shown = classes.SelectedIndex;
            if (shown >= 0)
                load(profiles[shown]);
        };
        classes.SelectedIndex = 0;
    }

    private static (Func<FightProfile> Collect, Action<FightProfile> Load) BuildFightProfile(TabPage page)
    {
        var profile = Ui.Place(page, new Panel(), 0, 42, 790, 174);
        Ui.Label(profile, "开怪战斗键", 8, 6, 212, 32);
        Ui.Label(profile, "正常战斗键", 408, 6, 212, 32);
        Ui.Label(profile, "恢复键", 8, 48, 212, 32);
        Ui.Label(profile, "补 Buff 快捷键", 408, 48, 212, 32);
        KeyBox opening = Ui.Key(profile, "", 220, 2, 168);
        KeyBox combat = Ui.Key(profile, "", 620, 2, 168);
        KeyBox recovery = Ui.Key(profile, "", 220, 44, 168);
        KeyBox buff = Ui.Key(profile, "", 620, 44, 168);
        Ui.Label(profile, "恢复键冷却 (秒)", 408, 90, 212, 32);
        var cooldown = Ui.Number(profile, 0, 0, 3600, 620, 86, 168);
        Ui.Label(profile, "补 Buff 间隔 (秒，0关闭)", 8, 136, 212, 32);
        var interval = Ui.Number(profile, 0, 0, 86400, 220, 132, 168);
        Ui.Label(profile, "每轮补 Buff 次数", 408, 136, 212, 32);
        var count = Ui.Number(profile, 1, 1, 100, 620, 132, 168);

        FightProfile Collect() => new()
        {
            OpeningKey = opening.Binding, CombatKey = combat.Binding, RecoveryKey = recovery.Binding, BuffKey = buff.Binding,
            RecoveryCooldownSeconds = (int)cooldown.Value, BuffIntervalSeconds = (int)interval.Value, BuffCount = (int)count.Value
        };
        void Load(FightProfile settings)
        {
            opening.Binding = settings.OpeningKey;
            combat.Binding = settings.CombatKey;
            recovery.Binding = settings.RecoveryKey;
            buff.Binding = settings.BuffKey;
            cooldown.Value = settings.RecoveryCooldownSeconds;
            interval.Value = settings.BuffIntervalSeconds;
            count.Value = settings.BuffCount;
        }
        return (Collect, Load);
    }

    private sealed record ClassChoice(int Id)
    {
        public override string ToString() => Ui.Class(Id).Label;
    }
}
