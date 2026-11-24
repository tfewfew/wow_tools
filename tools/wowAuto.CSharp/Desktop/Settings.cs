using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace WowAuto.Desktop;

internal sealed record Settings
{
    public FishSettings Fish { get; init; } = new();
    public FightSettings Fight { get; init; } = new();
    public TameSettings Tame { get; init; } = new();
    public RestSettings Rest { get; init; } = new();
    public ShopSettings Shop { get; init; } = new();
    public CreateSettings CharacterCreate { get; init; } = new();
    public PeriodSettings Periods { get; init; } = new();
    public OperationSettings Operations { get; init; } = new();
    public RotationSettings Rotation { get; init; } = new();
    public Dictionary<string, RoleSettings[]> Accounts { get; init; } = new();
    public Dictionary<string, string> DirectModes { get; init; } = new();
    public Dictionary<string, int> Priorities { get; init; } = new(ActionDefaults.Priorities);
    public string ScreenshotKey { get; init; } = "Ctrl+Alt+A";
    [Range(1, 1000)] public int StatusLogLimit { get; init; } = 50;
    [Range(1, 1024)] public int LogMaxSizeMB { get; init; } = 50;
}

internal sealed record FishSettings
{
    public FishFlavor Titan { get; init; } = new() { MinimumMs = 500, MaximumMs = 2500, AudioTimeoutMs = 17000, AudioThresholdPercent = 80 };
    public FishFlavor Forerver { get; init; } = new() { AudioTimeoutMs = 35000, AudioThresholdPercent = 86 };
    public bool AudioDetectionEnabled { get; init; } = true;
    public bool DirectStartUseItem { get; init; }
    [Range(0, int.MaxValue)] public int JumpEveryCycles { get; init; }
    public string CastKey { get; init; } = "0";
    public string ReelKey { get; init; } = "=";
    public string ItemKey { get; init; } = "-";
    public string EquipRodKey { get; init; } = "F11";

    public FishFlavor For(string flavor) => flavor == "titan" ? Titan : Forerver;
}

internal sealed record FishFlavor
{
    [Range(1, 3600000)] public int MinimumMs { get; init; } = 300;
    [Range(1, 3600000)] public int MaximumMs { get; init; } = 2000;
    [Range(1000, 3600000)] public int AudioTimeoutMs { get; init; } = 30000;
    [Range(1, 100)] public int AudioThresholdPercent { get; init; } = 90;
    [Range(1, 2)] public int AudioRecordingId { get; init; } = 1;
}

internal sealed record FightSettings
{
    public FightCommon Common { get; init; } = new();
    public Dictionary<string, FightProfile> Profiles { get; init; } = DefaultProfiles();

    private static Dictionary<string, FightProfile> DefaultProfiles()
    {
        var profiles = new Dictionary<string, FightProfile>();
        foreach (string flavor in new[] { "titan", "forerver" })
        foreach (int id in SettingsRules.ClassIds)
        {
            if (flavor == "forerver" && id == 6)
                continue;
            profiles[$"{flavor}:{id}"] = new() { OpeningKey = "F5", CombatKey = "F6", RecoveryKey = "F8", BuffKey = "F11" };
        }
        return profiles;
    }
}

internal sealed record FightCommon
{
    public string MoveForwardKey { get; init; } = "W";
    public string MoveBackwardKey { get; init; } = "S";
    public string MoveLeftKey { get; init; } = "A";
    public string MoveRightKey { get; init; } = "D";
    public string SkinKey { get; init; } = "=";
    public string TargetKey { get; init; } = "F10";
    public bool SkinEnabled { get; init; } = true;
    [Range(1, 60000)] public int MovementHoldMs { get; init; } = 400;
    [Range(0, 3600)] public int JumpIntervalSeconds { get; init; }
}

internal sealed record FightProfile
{
    public string OpeningKey { get; init; } = "";
    public string CombatKey { get; init; } = "";
    public string RecoveryKey { get; init; } = "";
    public string BuffKey { get; init; } = "";
    [Range(0, 3600)] public int RecoveryCooldownSeconds { get; init; } = 30;
    [Range(0, 86400)] public int BuffIntervalSeconds { get; init; }
    [Range(1, 100)] public int BuffCount { get; init; } = 1;
}

internal sealed record TameSettings
{
    public string TrapKey { get; init; } = "";
    public string OpeningKey { get; init; } = "";
    public string BackwardKey { get; init; } = "";
    public string TameKey { get; init; } = "";
    public string JumpKey { get; init; } = "Space";
    [Range(0, 600000)] public int TrapWaitMs { get; init; } = 1000;
    [Range(0, 600000)] public int OpeningWaitMs { get; init; } = 1000;
    [Range(0, 600000)] public int BackwardWaitMs { get; init; } = 1000;
    [Range(0, 60000)] public int BackwardHoldMs { get; init; }
    [Range(100, 600000)] public int TameWaitMs { get; init; } = 10000;
    [Range(0, 3600)] public int JumpIntervalSeconds { get; init; }
}

internal sealed record RestSettings
{
    [Range(1, int.MaxValue)] public int DurationSeconds { get; init; } = 600;
    [Range(1, int.MaxValue)] public int Rounds { get; init; } = 5;
    [Range(1, int.MaxValue)] public int JumpIntervalSeconds { get; init; } = 60;
}

internal sealed record ShopSettings
{
    [Range(typeof(long), "1", "2147483647000")] public long ReopenDelayMs { get; init; } = 1000;
    [Range(typeof(long), "1", "2147483647000")] public long CloseDelayMs { get; init; } = 1000;
    [Range(typeof(long), "0", "2147483647000")] public long JitterMs { get; init; }
    [Range(0, int.MaxValue)] public int JumpIntervalSeconds { get; init; } = 60;
    [Range(1, int.MaxValue)] public int DurationSeconds { get; init; } = 600;
    public bool JumpOnVisit { get; init; } = true;
    public string InteractKey { get; init; } = "F";
}

internal sealed record CreateSettings
{
    [Range(1, 86400)] public double IntervalSeconds { get; init; } = 30;
    public bool AutoStop { get; init; } = true;
    public bool DryRun { get; init; }
    public string TitleFilter { get; init; } = "";
}

internal sealed record RoleSettings
{
    public string Name { get; init; } = "";
    public string Realm { get; init; } = "";
    public string Mode { get; init; } = "fish";
    public bool Enabled { get; init; }
    public bool UseItem { get; init; }
}

internal sealed record RotationSettings
{
    [Range(0, int.MaxValue)] public int IntervalSeconds { get; init; }
    public string TitanDirectory { get; init; } = @"C:\Program Files (x86)\World of Warcraft\_classic_titan_";
    public string ForerverDirectory { get; init; } = @"C:\Program Files (x86)\World of Warcraft\_forever_";
    public string[] NameHistory { get; init; } = [];
}

internal sealed record PeriodSettings
{
    [Range(25, 60000)] public int FishMs { get; init; } = 100;
    [Range(25, 60000)] public int FightMs { get; init; } = 1000;
    [Range(25, 60000)] public int MenuMs { get; init; } = 300;
    [Range(25, 60000)] public int LoginMs { get; init; } = 300;
    [Range(25, 60000)] public int BaitMs { get; init; } = 300;
    [Range(25, 60000)] public int DeathMs { get; init; } = 1000;
    [Range(25, 60000)] public int AudioMs { get; init; } = 50;
    [Range(25, 60000)] public int PositionMs { get; init; } = 1000;
    [Range(25, 60000)] public int CaptureRetryMs { get; init; } = 100;
    [Range(25, 60000)] public int OcrMs { get; init; } = 1000;
}

internal sealed record OperationSettings
{
    [Range(1, 1000)] public int OperatorIdleMs { get; init; } = 25;
    [Range(1, 1000)] public int CommandReceiveMs { get; init; } = 10;
    [Range(1, 1000)] public int ReplyCheckMs { get; init; } = 25;
    [Range(1, 1000)] public int WaitCheckMs { get; init; } = 25;
    [Range(1, 1000)] public int DetectorWaitMs { get; init; } = 20;
    [Range(10, 1000)] public int UiRefreshMs { get; init; } = 25;
    [Range(0, 5000)] public int ForegroundSettleMs { get; init; } = 200;
    [Range(1, 60000)] public int ForegroundRetryMs { get; init; } = 100;
    [Range(1, 60000)] public int ForegroundTimeoutMs { get; init; } = 800;
    [Range(1, 60000)] public int RotationFocusRetryMs { get; init; } = 500;
    [Range(1, 60000)] public int RotationFocusTimeoutMs { get; init; } = 5000;
    [Range(1000, 3600000)] public int FocusRetryMs { get; init; } = 30000;
    [Range(1, 5000)] public int KeyPressMs { get; init; } = 30;
    [Range(1, 5000)] public int ChatKeyPressMs { get; init; } = 50;
    [Range(100, 60000)] public int CommandIntervalMs { get; init; } = 500;
    [Range(0, 60000)] public int ReelHoldMs { get; init; } = 100;
    [Range(0, 4000)] public int ItemHoldMs { get; init; } = 3000;
    [Range(1000, 60000)] public int InteractionHoldMs { get; init; } = 3500;
    [Range(1, 2000)] public int ClickMinMs { get; init; } = 100;
    [Range(1, 2000)] public int ClickMaxMs { get; init; } = 250;
    [Range(0, 60000)] public int ClickGuardMs { get; init; } = 1000;
    [Range(1, 60000)] public int CaptureRetryMs { get; init; } = 100;
    [Range(1000, 60000)] public int FishColorRetryMs { get; init; } = 3000;
}

internal static class SettingsRules
{
    public static readonly HashSet<string> Modes = new(StringComparer.OrdinalIgnoreCase) { "fish", "fight", "rest", "shop", "tame" };
    public static readonly int[] ClassIds = [1, 2, 3, 4, 5, 6, 7, 8, 9, 11];

    public static void Validate(Settings value)
    {
        ValidateProperties(value, "");
        if (value.Fish.Titan.MinimumMs > value.Fish.Titan.MaximumMs || value.Fish.Forerver.MinimumMs > value.Fish.Forerver.MaximumMs)
            throw new ArgumentException("收竿延迟下限不能超过上限。");
        if (value.Fish.Forerver.AudioRecordingId != 1)
            throw new ArgumentException("无限服音频片段编号只支持 1。");
        if (value.Operations.ClickMinMs > value.Operations.ClickMaxMs)
            throw new ArgumentException("点击间隔下限不能超过上限。");
        if (value.Shop.InteractKey.Length == 0 || KeyChord.Parse(value.Shop.InteractKey).Code is 13 or 32)
            throw new ArgumentException("购物交互键须与回车和空格分开。");
        if (value.ScreenshotKey.Length != 0 && KeyChord.Parse(value.ScreenshotKey) is { Ctrl: false, Alt: false })
            throw new ArgumentException("截图热键需要 Ctrl 或 Alt。");
        foreach (var (id, mode) in value.DirectModes)
            if (!Regex.IsMatch(id, @"^[1-9]\d*:[1-9]\d*$") || !Modes.Contains(mode))
                throw new ArgumentException($"无效的进程直接开始设置 {id}。");
        foreach (var (name, priority) in value.Priorities)
            if (!ActionDefaults.Priorities.TryGetValue(name, out int fixedPriority) ||
                (fixedPriority < 10 ? priority != fixedPriority : priority is < 10 or > 999))
                throw new ArgumentException($"无效的动作优先级 {name}。");
        foreach (var (id, profile) in value.Fight.Profiles)
        {
            string[] parts = id.Split(':');
            if (parts.Length != 2 || parts[0] is not ("titan" or "forerver") || !int.TryParse(parts[1], out int classId) ||
                !ClassIds.Contains(classId) || (parts[0] == "forerver" && classId == 6))
                throw new ArgumentException($"无效的职业战斗配置 {id}。");
            if (value.Fight.Common.TargetKey.Length != 0 && profile.OpeningKey.Length != 0 &&
                KeyChord.Parse(value.Fight.Common.TargetKey) == KeyChord.Parse(profile.OpeningKey))
                throw new ArgumentException($"选中目标和开怪键冲突 {id}。");
        }
        foreach (var (id, roles) in value.Accounts)
        {
            if (!Regex.IsMatch(id, @"^(titan|forerver):[^\\/\p{C}]+$"))
                throw new ArgumentException($"无效的子战网 {id}。");
            var identities = new HashSet<(string, string)>();
            var enabled = new HashSet<string>(StringComparer.Ordinal);
            foreach (RoleSettings role in roles)
            {
                if (!Regex.IsMatch(role.Name, @"^[\p{L}\p{M}]{1,24}$") || string.IsNullOrWhiteSpace(role.Realm) ||
                    Regex.IsMatch(role.Realm, @"[\\/\p{C}]") || role.Mode is not ("fish" or "fight" or "rest" or "shop") ||
                    (role.UseItem && role.Mode != "fish") || (role.Mode == "rest" && !id.StartsWith("forerver:", StringComparison.Ordinal)) ||
                    !identities.Add((role.Realm, role.Name)) || (role.Enabled && !enabled.Add(role.Name)))
                    throw new ArgumentException($"无效或重复的角色配置 {id}/{role.Name}。");
            }
        }
        foreach (string directory in new[] { value.Rotation.TitanDirectory, value.Rotation.ForerverDirectory })
            if (!Path.IsPathFullyQualified(directory))
                throw new ArgumentException("游戏安装目录必须使用绝对路径。");
    }

    private static void ValidateProperties(object value, string path)
    {
        if (value is string || value.GetType().IsValueType)
            return;
        if (value is System.Collections.IDictionary map)
        {
            foreach (System.Collections.DictionaryEntry entry in map)
                ValidateValue(entry.Value, $"{path}/{entry.Key}");
            return;
        }
        if (value is System.Collections.IEnumerable list)
        {
            int index = 0;
            foreach (object? item in list)
                ValidateValue(item, $"{path}/{index++}");
            return;
        }
        foreach (var property in value.GetType().GetProperties())
        {
            string name = path.Length == 0 ? property.Name : $"{path}.{property.Name}";
            object? member = property.GetValue(value);
            foreach (ValidationAttribute rule in property.GetCustomAttributes(typeof(ValidationAttribute), false))
                if (!rule.IsValid(member))
                    throw new ArgumentException($"{name} 超出范围。{rule.FormatErrorMessage(name)}");
            ValidateValue(member, name);
            if (property.Name.EndsWith("Key", StringComparison.Ordinal) && member is string { Length: > 0 } key)
                _ = KeyChord.Parse(key);
        }
    }

    private static void ValidateValue(object? value, string path) =>
        ValidateProperties(value ?? throw new ArgumentException($"{path} 需要值。"), path);
}

internal static class SettingsJson
{
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNameCaseInsensitive = true,
        UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow,
        WriteIndented = true
    };

    public static JsonObject Tree(Settings settings) => JsonSerializer.SerializeToNode(settings, Options)!.AsObject();

    public static Settings Read(JsonNode? node)
    {
        Settings value = node?.Deserialize<Settings>(Options) ?? throw new ArgumentException("配置需要 JSON 对象。");
        SettingsRules.Validate(value);
        return value;
    }

    public static JsonNode? Get(JsonNode root, string path)
    {
        JsonNode? node = root;
        foreach (string segment in Segments(path))
        {
            node = node switch
            {
                JsonObject obj when obj.TryGetPropertyValue(Find(obj, segment), out JsonNode? found) => found,
                JsonArray array when int.TryParse(segment, out int index) && index >= 0 && index < array.Count => array[index],
                _ => throw new ArgumentException($"配置路径不存在 {path}。")
            };
        }
        return node;
    }

    public static void Set(JsonObject root, string path, JsonNode? value)
    {
        string[] segments = Segments(path);
        if (segments.Length == 0)
            throw new ArgumentException("需要配置路径。");
        string member = segments[^1];
        JsonNode? parent = segments.Length == 1 ? root : Get(root, "/" + string.Join('/', segments[..^1].Select(Escape)));
        if (parent is JsonObject obj)
            obj[Find(obj, member)] = value?.DeepClone();
        else if (parent is JsonArray array && int.TryParse(member, out int index) && index >= 0 && index < array.Count)
            array[index] = value?.DeepClone();
        else
            throw new ArgumentException($"配置路径不存在 {path}。");
    }

    public static JsonNode? ParseValue(string value)
    {
        try { return JsonNode.Parse(value); }
        catch (JsonException) { return JsonValue.Create(value); }
    }

    private static string Find(JsonObject obj, string name) =>
        obj.ContainsKey(name) ? name : obj.Select(item => item.Key).FirstOrDefault(key => key.Equals(name, StringComparison.OrdinalIgnoreCase)) ?? name;

    private static string Escape(string value) => value.Replace("~", "~0").Replace("/", "~1");

    private static string[] Segments(string path) => path.Length == 0 ? [] : path.StartsWith('/')
        ? path[1..].Split('/').Select(value => value.Replace("~1", "/").Replace("~0", "~")).ToArray()
        : path.Split('.');
}
