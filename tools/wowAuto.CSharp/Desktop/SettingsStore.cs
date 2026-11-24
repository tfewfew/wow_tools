using System.Text.Json;
using System.Text.Json.Nodes;

namespace WowAuto.Desktop;

internal sealed record SettingChange(string Path, string Text);
internal sealed record Configuration(long Revision, Settings Saved, Settings Effective);

internal sealed class SettingsStore
{
    private readonly object gate = new();
    private readonly string path;
    private Configuration current;

    public SettingsStore(string directory)
    {
        Directory.CreateDirectory(directory);
        path = Path.Combine(directory, "settings.json");
        Settings settings = File.Exists(path) ? SettingsJson.Read(JsonNode.Parse(File.ReadAllText(path))) : new();
        current = new(0, settings, settings);
    }

    public Configuration Current => Volatile.Read(ref current);

    public Configuration Update(IReadOnlyList<SettingChange> changes, bool runtime, long? expected, Func<Settings, Action<bool>?>? prepare = null)
    {
        lock (gate)
        {
            if (expected is not null && expected != current.Revision)
                throw new InvalidOperationException("配置已被修改，请读取最新版本后重试。");
            Settings saved = runtime ? current.Saved : Patch(current.Saved, changes);
            Settings effective = Patch(current.Effective, changes);
            Action<bool>? finish = prepare?.Invoke(effective);
            bool committed = false;
            try
            {
                if (!runtime)
                    Write(saved);
                var next = new Configuration(current.Revision + 1, saved, effective);
                Volatile.Write(ref current, next);
                committed = true;
                return next;
            }
            finally { finish?.Invoke(committed); }
        }
    }

    public static Settings Patch(Settings basis, IEnumerable<SettingChange> changes)
    {
        JsonObject root = SettingsJson.Tree(basis);
        foreach (SettingChange change in changes)
        {
            JsonNode? next = SettingsJson.ParseValue(change.Text);
            // Key bindings such as 0 and 1 are strings in this schema.
            try
            {
                if (SettingsJson.Get(root, change.Path) is JsonValue old && old.TryGetValue(out string? _) &&
                    (next is not JsonValue value || !value.TryGetValue(out string? _)))
                    next = JsonValue.Create(change.Text);
            }
            catch (ArgumentException) { }
            SettingsJson.Set(root, change.Path, next);
        }
        return SettingsJson.Read(root);
    }

    private void Write(Settings settings)
    {
        string temporary = $"{path}.{Guid.NewGuid():N}.tmp";
        try
        {
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                JsonSerializer.Serialize(file, settings, SettingsJson.Options);
                file.Flush(flushToDisk: true);
            }
            if (File.Exists(path))
                File.Replace(temporary, path, null);
            else
                File.Move(temporary, path);
        }
        finally
        {
            if (File.Exists(temporary))
                File.Delete(temporary);
        }
    }
}
