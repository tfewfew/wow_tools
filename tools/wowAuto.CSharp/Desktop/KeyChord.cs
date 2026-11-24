namespace WowAuto.Desktop;

internal readonly record struct KeyChord(ushort Code, bool Ctrl, bool Shift, bool Alt)
{
    public static KeyChord Parse(string text)
    {
        string[] parts = text.Trim().Split('+', StringSplitOptions.TrimEntries);
        var modifiers = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string part in parts[..^1])
        {
            string name = part.ToLowerInvariant();
            if (name is not ("ctrl" or "shift" or "alt") || !modifiers.Add(name))
                throw new ArgumentException($"无效的组合键 {text}。");
        }
        string key = parts[^1];
        char letter = key.Length == 1 ? char.ToUpperInvariant(key[0]) : '\0';
        Keys code = letter switch
        {
            >= 'A' and <= 'Z' or >= '0' and <= '9' => (Keys)letter,
            '=' => Keys.Oemplus,
            '-' => Keys.OemMinus,
            ',' => Keys.Oemcomma,
            '.' => Keys.OemPeriod,
            '/' => Keys.OemQuestion,
            ';' => Keys.OemSemicolon,
            '\'' => Keys.OemQuotes,
            '[' => Keys.OemOpenBrackets,
            ']' => Keys.OemCloseBrackets,
            '\\' => Keys.OemPipe,
            '`' => Keys.Oemtilde,
            _ => Enum.TryParse(key, true, out Keys candidate) && Enum.IsDefined(candidate) ? candidate : Keys.None
        };
        if ((int)code is <= 0 or > 254 || code is Keys.ControlKey or Keys.ShiftKey or Keys.Menu or Keys.LWin or Keys.RWin)
            throw new ArgumentException($"无效的按键 {text}。");
        return new((ushort)code, modifiers.Contains("ctrl"), modifiers.Contains("shift"), modifiers.Contains("alt"));
    }
}
