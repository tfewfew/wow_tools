using System.Text.Json.Nodes;

namespace WowAuto.Desktop;

internal static class LegacyImport
{
    public static SettingChange[] Read(string directory, Settings saved)
    {
        string root = Path.GetFullPath(directory);
        if (!Directory.Exists(root))
            throw new DirectoryNotFoundException(root);
        var changes = new List<SettingChange>();
        void Add(string key, JsonNode? value)
        {
            if (value is not null)
                changes.Add(new(key, value.ToJsonString()));
        }
        JsonNode? ReadFile(string name)
        {
            string path = Path.Combine(root, name);
            return File.Exists(path) ? JsonNode.Parse(File.ReadAllText(path)) : null;
        }
        JsonNode? account = ReadFile("account-tasks.config.json");
        if (account is not null)
        {
            foreach (string group in new[] { "Accounts", "Operations", "Periods", "Rest" })
                Add(group, account[group]);
            if (account["Shop"] is JsonObject legacyShop)
            {
                JsonObject shop = legacyShop.DeepClone().AsObject();
                foreach ((string old, string current) in new[] { ("VisitIntervalSeconds", "ReopenDelayMs"), ("CloseDelaySeconds", "CloseDelayMs") })
                    if (shop.Remove(old, out JsonNode? value) && !shop.ContainsKey(current))
                        shop[current] = value!.GetValue<long>() * 1000;
                Add("Shop", shop);
            }
        }
        if (ReadFile("autoTame.config.json") is JsonObject tame)
        {
            tame.Remove("Version");
            Add("Tame", tame);
        }
        if (ReadFile("autoFight.config.json") is JsonObject legacyFight)
        {
            if (legacyFight["Common"] is JsonObject common)
            {
                var shared = common.DeepClone().AsObject();
                if (shared.Remove("InteractionHoldMs", out JsonNode? hold) && account?["Operations"] is null)
                    Add("Operations.InteractionHoldMs", hold);
                Add("Fight.Common", shared);
            }
            if (legacyFight["Profiles"] is JsonArray profiles)
            {
                JsonObject mapped = new();
                foreach (JsonNode? profile in profiles)
                {
                    var data = profile!.DeepClone().AsObject();
                    string flavor = data["Flavor"]!.GetValue<string>();
                    int classId = data["ClassId"]!.GetValue<int>();
                    data.Remove("Flavor");
                    data.Remove("ClassId");
                    mapped[$"{flavor}:{classId}"] = data;
                }
                Add("Fight.Profiles", mapped);
            }
            if (account?["Operations"] is null)
                Add("Operations.CommandIntervalMs", legacyFight["CommandIntervalMs"]);
        }
        if (ReadFile("rotation.config.json") is JsonObject rotation)
        {
            Add("Rotation.IntervalSeconds", rotation["IntervalSeconds"]);
            Add("Rotation.NameHistory", rotation["NameHistory"]);
            Add("Rotation.TitanDirectory", rotation["GameDirectories"]?["titan"]);
            Add("Rotation.ForerverDirectory", rotation["GameDirectories"]?["forerver"]);
            if (account?["Periods"] is null)
                Add("Periods.OcrMs", rotation["OcrIntervalMs"]);
        }
        if (ReadFile("action-priorities.json")?["Events"] is JsonObject events)
        {
            var priorities = SettingsJson.Tree(saved)["Priorities"]!.AsObject();
            foreach (var (key, value) in events)
                if (ActionDefaults.Priorities.ContainsKey(key))
                    priorities[key] = value?.DeepClone();
            Add("Priorities", priorities);
        }
        if (ReadFile("character-create/data/settings.json") is JsonObject character)
        {
            JsonNode? interval = character["interval"];
            if (interval is JsonValue raw && raw.TryGetValue(out string? text) &&
                double.TryParse(text, System.Globalization.CultureInfo.InvariantCulture, out double seconds))
                interval = JsonValue.Create(seconds);
            Add("CharacterCreate.IntervalSeconds", interval);
            Add("CharacterCreate.AutoStop", character["auto_stop"]);
            Add("CharacterCreate.TitleFilter", character["title_filter"]);
        }
        string ini = Path.Combine(root, "config.ini");
        if (File.Exists(ini))
        {
            var direct = new JsonObject();
            foreach (string line in File.ReadLines(ini))
            {
                int separator = line.IndexOf('=');
                if (separator <= 0 || line.TrimStart().StartsWith(';'))
                    continue;
                string key = line[..separator].Trim();
                string value = line[(separator + 1)..].Trim();
                if (key.StartsWith("Mode_", StringComparison.Ordinal))
                {
                    direct[key[5..].Replace('_', ':')] = value;
                    continue;
                }
                if (key is "AudioDetectionEnabled" or "DirectStartUseItem")
                    Add($"Fish.{key}", JsonValue.Create(value == "1"));
                else if (key is "CastKey" or "ReelKey" or "ItemKey" or "EquipRodKey")
                    Add($"Fish.{key}", JsonValue.Create(value));
                else if (key == "ScreenshotKey")
                    Add(key, JsonValue.Create(value));
                else if (int.TryParse(value, out int number))
                {
                    if (key is "StatusLogLimit" or "LogMaxSizeMB")
                        Add(key, JsonValue.Create(number));
                    else if (key == "JumpEveryCycles")
                        Add("Fish.JumpEveryCycles", JsonValue.Create(number));
                    else if ((key is "FocusRetryIntervalMs" or "ReelHoldMs") && account?["Operations"] is null)
                        Add(key == "ReelHoldMs" ? "Operations.ReelHoldMs" : "Operations.FocusRetryMs", JsonValue.Create(number));
                    else
                        foreach (string flavor in new[] { "Titan", "Forerver" })
                        {
                            if (key.StartsWith(flavor, StringComparison.Ordinal) &&
                                key[flavor.Length..] is "MinimumMs" or "MaximumMs" or "AudioTimeoutMs" or "AudioThresholdPercent" or "AudioRecordingId")
                                Add($"Fish.{flavor}.{key[flavor.Length..]}", JsonValue.Create(number));
                        }
                }
            }
            if (direct.Count != 0)
                Add("DirectModes", direct);
        }
        return changes.Count == 0 ? throw new ArgumentException("目录下没有可导入的旧脚本配置。") : changes.ToArray();
    }
}
