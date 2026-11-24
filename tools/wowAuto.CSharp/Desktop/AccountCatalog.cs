using System.Text.RegularExpressions;
using WowAutoFight;

namespace WowAuto.Desktop;

internal sealed record CharacterRecord(string Account, string Name, string Realm, string DisplayRealm,
    int? Level, int? FreeBagSlots, int? ClassId, long RecordedAt, string? Professions, string? SecondarySkills, string? BindLocation);

internal static partial class AccountCatalog
{
    public static CharacterRecord[] Read(Client client)
    {
        string directory = Path.GetDirectoryName(client.Path)!;
        return ReadDirectory(directory);
    }

    public static CharacterRecord[] ReadDirectory(string directory)
    {
        var root = new DirectoryInfo(Path.Combine(directory, "WTF", "Account"));
        var records = new List<CharacterRecord>();
        foreach (DirectoryInfo account in Subdirectories(root))
        foreach (DirectoryInfo realm in Subdirectories(account))
        foreach (DirectoryInfo character in Subdirectories(realm))
        {
            string name = character.Name;
            string displayRealm = realm.Name;
            bool connected = long.TryParse(realm.Name, out long realmId) && realmId > 0 && name.Contains('-');
            if (connected)
            {
                int split = name.IndexOf('-');
                displayRealm = name[(split + 1)..];
                name = name[..split];
            }
            if (!RoleName().IsMatch(name))
                continue;
            var saved = new DirectoryInfo(Path.Combine(character.FullName, "SavedVariables"));
            var file = new FileInfo(Path.Combine(saved.FullName, "wow_tools.lua"));
            try
            {
                if (!saved.Exists || !file.Exists || file.Length > 16 * 1024 * 1024 ||
                    (saved.Attributes & FileAttributes.ReparsePoint) != 0 || (file.Attributes & FileAttributes.ReparsePoint) != 0)
                    continue;
                CharacterRecord? record = Parse(File.ReadAllText(file.FullName), account.Name, name, realm.Name, displayRealm, connected);
                if (record is not null)
                    records.Add(record);
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
        return records.ToArray();
    }

    private static DirectoryInfo[] Subdirectories(DirectoryInfo directory)
    {
        try
        {
            if (!directory.Exists || (directory.Attributes & FileAttributes.ReparsePoint) != 0)
                return [];
            return directory.GetDirectories().Where(item => item.Name != "SavedVariables" &&
                (item.Attributes & FileAttributes.ReparsePoint) == 0).OrderBy(item => item.Name, StringComparer.Ordinal).ToArray();
        }
        catch (IOException) { return []; }
        catch (UnauthorizedAccessException) { return []; }
    }

    private static CharacterRecord? Parse(string lua, string account, string name, string realm, string displayRealm, bool connected)
    {
        // The generated snapshot is a flat table. Scan Lua strings/comments as
        // tokens before looking for the top-level assignment.
        int depth = 0;
        int start = -1;
        int end = -1;
        var matches = Tokens().Matches(lua);
        for (int index = 0; index < matches.Count; index++)
        {
            Match token = matches[index];
            if (token.Value == "wowToolsCharacterRecord" && depth == 0 && index + 2 < matches.Count &&
                matches[index + 1].Value == "=" && matches[index + 2].Value == "{")
            {
                if (start >= 0)
                    return null;
                start = matches[index + 2].Index + 1;
            }
            if (token.Value == "{")
                depth++;
            if (token.Value == "}" && --depth == 0 && start >= 0 && end < 0)
                end = token.Index;
        }
        if (start < 0 || end < start || end - start > 65536)
            return null;
        string body = lua[start..end].Trim();
        var fields = new Dictionary<string, string>(StringComparer.Ordinal);
        for (int offset = 0; offset < body.Length;)
        {
            Match member = Fields().Match(body, offset);
            if (!member.Success || member.Index != offset || !fields.TryAdd(member.Groups["key"].Value,
                member.Groups["number"].Success ? member.Groups["number"].Value : Decode(member.Groups["text"].Value)))
                return null;
            offset += member.Length;
        }
        string? Field(string key) => fields.GetValueOrDefault(key);
        if (Field("name") != name || Field("realm") is not { Length: > 0 and <= 128 } storedRealm ||
            (!connected && storedRealm != realm) || !int.TryParse(Field("version"), out int version) || version is < 1 or > 6 ||
            !int.TryParse(Field("level"), out int level) || level is < 0 or > 1000 ||
            !int.TryParse(Field("freeBagSlots"), out int slots) || slots is < -1 or > 11000 ||
            !long.TryParse(Field("recordedAt"), out long recorded) || recorded is < 1 or > 253402300799)
            return null;
        int? classId = int.TryParse(Field("classId"), out int parsed) && SettingsRules.ClassIds.Contains(parsed) ? parsed : null;
        return new(account, name, storedRealm, displayRealm, level > 0 ? level : null, slots >= 0 ? slots : null,
            classId, recorded, Field("professions"), Field("secondarySkills"), Field("bindLocation"));
    }

    private static string Decode(string value) => Escapes().Replace(value, match => match.Value[1] switch
    {
        'n' => "\n", 'r' => "\r", 't' => "\t",
        >= '0' and <= '9' => ((char)int.Parse(match.Value[1..])).ToString(),
        _ => match.Value[1..]
    });

    [GeneratedRegex(@"^[\p{L}\p{M}]{1,24}$")] private static partial Regex RoleName();
    [GeneratedRegex("""--\[(?<comment>=*)\[.*?\]\k<comment>\]|--[^\r\n]*|\[(?<long>=*)\[.*?\]\k<long>\]|"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|[A-Za-z_]\w*|[{}=]""", RegexOptions.Singleline)]
    private static partial Regex Tokens();
    [GeneratedRegex("""\G\s*(?:\["(?<key>[A-Za-z]\w*)"\]|(?<key>[A-Za-z]\w*))\s*=\s*(?:"(?<text>(?:[^"\\\r\n]|\\(?:["\\nrt]|\d{1,3}))*)"|(?<number>-?\d+))\s*(?:,|\z)""")]
    private static partial Regex Fields();
    [GeneratedRegex(@"\\(?:\d{1,3}|.)")] private static partial Regex Escapes();
}
