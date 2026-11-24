using System.Text.Json;
using System.Text.Json.Nodes;

namespace WowAuto.Desktop;

// Each editor commits its changed fields against the values it displayed.
// Unrelated saves and CLI changes are merged by the existing configuration store.
internal sealed class SettingsDraft(Automation automation)
{
    private readonly List<Field> fields = [];
    private long revision = -1;
    private JsonObject? source;

    public JsonNode? Saved(string path)
    {
        Configuration current = automation.Config;
        if (source is null || revision != current.Revision)
        {
            source = SettingsJson.Tree(current.Saved);
            revision = current.Revision;
        }
        return Read(source, path);
    }

    public void Bind(string path, Func<JsonNode?> collect, Action<JsonNode?> load, Func<JsonNode?, JsonNode?>? normalize = null)
    {
        JsonNode? raw = Saved(path);
        load(raw);
        fields.Add(new(path, collect, load, normalize) { Raw = raw, Initial = collect() });
    }

    public NumericUpDown Number(Control parent, string path, int x, int y, int width, decimal min, decimal max,
        decimal step = 1, int places = 0, decimal factor = 1)
    {
        var input = Ui.Number(parent, min, min, max, x, y, width, step, places);
        Bind(path, () => places == 0 || factor != 1 ? JsonValue.Create(decimal.ToInt64(input.Value * factor)) : JsonValue.Create(input.Value),
            value => input.Value = value!.Deserialize<decimal>() / factor);
        return input;
    }

    public CheckBox Check(Control parent, string path, string label, int x, int y, int width)
    {
        var input = Ui.Check(parent, label, false, x, y, width);
        Bind(path, () => JsonValue.Create(input.Checked), value => input.Checked = value!.GetValue<bool>());
        return input;
    }

    public TextBox Text(Control parent, string path, int x, int y, int width, Func<string, string>? normalize = null)
    {
        var input = Ui.InputBox(parent, "", x, y, width);
        Bind(path, () => JsonValue.Create(input.Text), value => input.Text = value!.GetValue<string>(),
            normalize is null ? null : value => JsonValue.Create(normalize(value!.GetValue<string>())));
        return input;
    }

    public KeyBox Key(Control parent, string path, int x, int y, int width, string empty = "")
    {
        var input = Ui.Key(parent, "", x, y, width, empty);
        Bind(path, () => JsonValue.Create(input.Binding), value => input.Binding = value!.GetValue<string>());
        return input;
    }

    public void Refresh(Configuration current)
    {
        if (current.Revision == revision)
            return;
        source = SettingsJson.Tree(current.Saved);
        revision = current.Revision;
        foreach (Field field in fields)
        {
            JsonNode? latest = Read(source, field.Path);
            if (!JsonNode.DeepEquals(latest, field.Raw) && JsonNode.DeepEquals(field.Collect(), field.Initial))
                field.Reset(latest);
        }
    }

    public bool Save()
    {
        Configuration current = automation.Config;
        Refresh(current);
        var edits = new List<SettingChange>();
        var updated = new List<Field>();
        foreach (Field field in fields)
        {
            JsonNode? value = field.Collect();
            if (JsonNode.DeepEquals(value, field.Initial))
                continue;
            JsonNode? latest = Read(source!, field.Path);
            value = field.Normalize is null ? value : field.Normalize(value);
            if (!JsonNode.DeepEquals(latest, field.Raw) && !JsonNode.DeepEquals(latest, value))
                throw new InvalidOperationException($"{field.Path} 已通过其他入口修改，请重新打开界面后再保存。");
            if (!JsonNode.DeepEquals(latest, value))
                edits.Add(new(field.Path, value?.ToJsonString() ?? "null"));
            updated.Add(field);
        }

        bool changed = edits.Count > 0;
        if (changed)
            current = automation.Configure(edits, false, current.Revision);
        source = SettingsJson.Tree(current.Saved);
        revision = current.Revision;
        foreach (Field field in updated)
            field.Reset(Read(source, field.Path));
        return changed;
    }

    public void SaveWithFeedback(Label feedback, string success, Action? after = null)
    {
        try { Save(); after?.Invoke(); feedback.Text = success; }
        catch (Exception error) { feedback.Text = error.Message; }
    }

    private static JsonNode? Read(JsonObject root, string path)
    {
        try { return SettingsJson.Get(root, path); }
        catch (ArgumentException) { return null; }
    }

    private sealed record Field(string Path, Func<JsonNode?> Collect, Action<JsonNode?> Load,
        Func<JsonNode?, JsonNode?>? Normalize)
    {
        public JsonNode? Raw { get; set; }
        public JsonNode? Initial { get; set; }

        public void Reset(JsonNode? raw)
        {
            Raw = raw;
            Load(raw);
            Initial = Collect();
        }
    }
}
