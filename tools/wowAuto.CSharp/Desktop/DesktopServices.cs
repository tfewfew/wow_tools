using System.Media;

namespace WowAuto.Desktop;

internal sealed class DesktopServices(Automation automation, string directory) : IDisposable
{
    private ScreenshotHotkey? hotkey;
    private volatile string hotkeyText = "";
    private SoundPlayer? audio;
    private volatile bool selecting;
    private volatile string? playing;
    public Form? Window { get; set; }
    public string DataDirectory { get; } = directory;
    public bool Restart { get; private set; }
    public object Snapshot() => new { screenshotKey = hotkeyText, screenshotRegistered = hotkey is not null, screenshotSelecting = selecting, audioPreview = playing };

    public void Initialize()
    {
        Settings settings = automation.Config.Effective;
        try { PrepareHotkey(settings)?.Invoke(true); }
        catch
        {
            hotkeyText = settings.ScreenshotKey;
            throw;
        }
    }

    public Action<bool>? PrepareHotkey(Settings settings)
    {
        if (Window is { InvokeRequired: true } form)
            return form.Invoke(() => PrepareHotkey(settings));
        if (settings.ScreenshotKey == hotkeyText)
            return null;
        ScreenshotHotkey? next = null;
        if (settings.ScreenshotKey.Length > 0)
        {
            KeyChord binding = KeyChord.Parse(settings.ScreenshotKey);
            next = new ScreenshotHotkey(binding.Code, binding.Ctrl, binding.Shift, binding.Alt);
            next.Pressed += async (_, _) =>
            {
                try { await Screenshot(); }
                catch (Exception error) { automation.Log(null, "error", error.Message); }
            };
        }
        return committed =>
        {
            void Finish()
            {
                if (!committed)
                {
                    next?.Dispose();
                    return;
                }
                hotkey?.Dispose();
                hotkey = next;
                hotkeyText = settings.ScreenshotKey;
            }
            if (Window is { InvokeRequired: true } owner)
                owner.Invoke(Finish);
            else
                Finish();
        };
    }

    public Task<bool> Screenshot() => OnUi(() =>
    {
        if (selecting)
            throw new InvalidOperationException("截图框选已打开。");
        selecting = true;
        try
        {
            if (!automation.Hub.PauseAndWait(3000))
                throw new InvalidOperationException("当前操作仍在收尾，请稍后再截图。");
            automation.Changed();
            return ScreenshotSelection.CopySelection();
        }
        finally
        {
            selecting = false;
            automation.Hub.Paused = false;
            automation.Hub.Wake.Set();
            automation.Changed();
        }
    });

    public Task<string> AudioPreview(string flavor, int id) => OnUi(() =>
    {
        string name = (flavor, id) switch
        {
            ("titan", 1 or 2) => $"titan-{id:D2}-match.wav",
            ("forerver", 1) => "forerver-01-match.wav",
            _ => throw new ArgumentException("此客户端没有这个片段。")
        };
        string path = Path.Combine(DataDirectory, "audio-samples", name);
        if (!File.Exists(path))
            path = Path.Combine(AppContext.BaseDirectory, "AudioSamples", name);
        if (!File.Exists(path))
            throw new FileNotFoundException($"未找到试听文件 {name}。请放在 {Path.Combine(DataDirectory, "audio-samples")}。");
        audio?.Dispose();
        audio = new SoundPlayer(path);
        audio.Load();
        audio.Play();
        playing = path;
        automation.Changed();
        return path;
    });

    public Task<bool> AudioStop() => OnUi(() =>
    {
        audio?.Stop();
        playing = null;
        automation.Changed();
        return true;
    });

    public void RequestExit(bool restart)
    {
        Form? form = Window;
        if (form is null || form.IsDisposed)
            return;
        form.BeginInvoke(() =>
        {
            Restart = restart;
            form.Close();
        });
    }

    public Task<T> OnUi<T>(Func<T> action)
    {
        Form form = Window ?? throw new InvalidOperationException("桌面窗口尚未就绪。");
        return form.InvokeAsync(action);
    }

    public void Dispose()
    {
        hotkey?.Dispose();
        audio?.Dispose();
    }
}
