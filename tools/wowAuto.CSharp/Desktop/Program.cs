using System.Diagnostics;
using System.Security.Principal;
using WowAuto.Protocol;

namespace WowAuto.Desktop;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        string data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "wowAuto.CSharp");
        if (args is ["--data-root", var supplied])
            data = Path.GetFullPath(supplied);
        else if (args.Length != 0)
            return 2;

        bool restart;
        using (var unique = new Mutex(false, $@"Local\{Wire.PipeName}-{WindowsIdentity.GetCurrent().User?.Value}"))
        {
            bool acquired;
            try { acquired = unique.WaitOne(0); }
            catch (AbandonedMutexException) { acquired = true; }
            if (!acquired)
            {
                MessageBox.Show("当前 Windows 会话已经运行 C# 版 wowAuto。", "wowAuto", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return 1;
            }
            try { restart = Run(data); }
            catch (Exception error)
            {
                MessageBox.Show(error.Message, "wowAuto 启动失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
            finally { unique.ReleaseMutex(); }
        }
        if (restart && Environment.ProcessPath is { } executable)
        {
            var start = new ProcessStartInfo(executable);
            foreach (string arg in args)
                start.ArgumentList.Add(arg);
            Process.Start(start)?.Dispose();
        }
        return 0;
    }

    private static bool Run(string directory)
    {
        var automation = new Automation(directory);
        using var desktop = new DesktopServices(automation, directory);
        var commands = new CommandProcessor(automation, desktop);
        using var form = new MainWindow(automation, commands, desktop);
        desktop.Window = form;
        _ = form.Handle;
        automation.PrepareSettings = desktop.PrepareHotkey;
        automation.DesktopState = desktop.Snapshot;
        try { desktop.Initialize(); }
        catch (Exception error) { automation.Log(null, "error", error.Message); }
        var pipe = new PipeServer(automation, commands, desktop);
        bool closing = false, finished = false;
        form.FormClosing += async (_, args) =>
        {
            if (finished)
                return;
            args.Cancel = true;
            if (closing)
                return;
            closing = true;
            form.Enabled = false;
            try
            {
                await automation.DisposeAsync();
                await pipe.DisposeAsync();
            }
            catch (Exception error)
            {
                MessageBox.Show(form, error.Message, "wowAuto 退出", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally { finished = true; form.Close(); }
        };
        Application.Run(form);
        return desktop.Restart;
    }
}
