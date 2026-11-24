using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace WowAuto.Desktop;

internal sealed record CharacterOcrProgram(string Python, string Bridge)
{
    public static CharacterOcrProgram Find()
    {
        string worker = Path.Combine(AppContext.BaseDirectory, "CharacterOcr");
        string bridge = Path.Combine(worker, "bridge.py");
        if (!File.Exists(bridge))
            throw new FileNotFoundException("角色创建后台文件缺失，请重新发布 WowAuto。", bridge);

        string? python = Environment.GetEnvironmentVariable("WOWAUTO_CHARACTER_PYTHON");
        if (!string.IsNullOrWhiteSpace(python))
        {
            if (!File.Exists(python))
                throw new FileNotFoundException("WOWAUTO_CHARACTER_PYTHON 指定的解释器不存在。", python);
            return new(Path.GetFullPath(python), bridge);
        }

        string local = Path.Combine(worker, ".runtime", "Scripts", "python.exe");
        if (File.Exists(local))
            return new(local, bridge);

        // In the repository, the existing virtual environment can supply the
        // pinned wheels and bundled models for both applications.
        for (var directory = new DirectoryInfo(worker); directory != null; directory = directory.Parent)
        {
            if (!directory.Name.Equals("wowAuto.CSharp", StringComparison.OrdinalIgnoreCase) || directory.Parent is null)
                continue;
            string existing = Path.Combine(directory.Parent.FullName, "wowAuto", "character-create", ".runtime", "Scripts", "python.exe");
            if (File.Exists(existing))
                return new(existing, bridge);
            break;
        }
        throw new InvalidOperationException($"角色创建需要 RapidOCR。请运行 {Path.Combine(worker, "install-runtime.ps1")} 安装运行环境。");
    }
}

internal sealed class CharacterOcrWorker : IAsyncDisposable
{
    private static readonly UTF8Encoding Utf8 = new(false);
    private readonly Process process;
    private readonly Task<string> errors;

    public CharacterOcrWorker(CharacterOcrProgram program)
    {
        var start = new ProcessStartInfo(program.Python)
        {
            WorkingDirectory = Path.GetDirectoryName(program.Bridge)!,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardInputEncoding = Utf8,
            StandardOutputEncoding = Utf8,
            StandardErrorEncoding = Utf8
        };
        start.ArgumentList.Add("-B");
        start.ArgumentList.Add("-u");
        start.ArgumentList.Add(program.Bridge);
        start.Environment["PYTHONIOENCODING"] = "utf-8";
        process = Process.Start(start) ?? throw new InvalidOperationException("无法启动 RapidOCR 后台。");
        errors = process.StandardError.ReadToEndAsync();
    }

    public async Task Send(object data, CancellationToken cancellation)
    {
        string json = JsonSerializer.Serialize(data);
        await process.StandardInput.WriteLineAsync(json.AsMemory(), cancellation);
        await process.StandardInput.FlushAsync(cancellation);
    }

    public ValueTask<string?> Read(CancellationToken cancellation) => process.StandardOutput.ReadLineAsync(cancellation);

    public async Task<string> ExplainExit(CancellationToken cancellation)
    {
        await process.WaitForExitAsync(cancellation);
        string detail = (await errors.WaitAsync(cancellation)).Trim();
        if (detail.Length > 2000)
            detail = detail[^2000..];
        return $"RapidOCR 后台提前退出（{process.ExitCode}）。{detail}";
    }

    public async ValueTask DisposeAsync()
    {
        try
        {
            using var grace = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            try
            {
                if (!process.HasExited)
                    await Send(new { stop = true }, grace.Token);
            }
            catch (IOException) { }
            await process.WaitForExitAsync(grace.Token);
        }
        catch (OperationCanceledException)
        {
            if (!process.HasExited)
            {
                try { process.Kill(); }
                catch (InvalidOperationException) when (process.HasExited) { }
                await process.WaitForExitAsync();
            }
        }
        finally { process.Dispose(); }
    }
}
