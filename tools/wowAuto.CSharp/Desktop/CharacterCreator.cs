using System.Text.Json;
using WowAuto.Protocol;
using Creation = WowAuto.CharacterCreate.Native;
using Rotation = WowAutoRotation.Native;
using Fight = WowAutoFight.Native;

namespace WowAuto.Desktop;

internal sealed record CreationHit(string Text, double Score, double X, double Y, double W, double H);
internal sealed record CreationView(bool Active, int? Pid, string Mode, string Message, int Finishes, int Confirmations,
    long? Deadline, long? ConfigRevision, CreationHit[]? Hits = null, double? OcrSeconds = null);
internal sealed record CreationResult(CreationView State, string? Image = null);

internal sealed class CharacterCreator(Automation automation)
{
    private readonly object gate = new();
    private CancellationTokenSource? cancellation;
    private Task<CreationResult>? task;
    private CreationView view = new(false, null, "", "等待角色创建任务。", 0, 0, null, null);
    public CreationView View => Volatile.Read(ref view);
    public bool Active => View.Active;

    public Task<CreationResult> Start(GameRow? row, string? image, bool preview, string? output)
    {
        lock (gate)
        {
            if (Active || automation.Rows.Any(item => item.Session?.Active == true) || automation.Snapshot().ShutdownAt is not null)
                throw new InvalidOperationException("角色创建需要独占，请先停止其他任务和退出倒计时。");
            if ((row is null) == (image is null) || (image is not null && !preview))
                throw new ArgumentException("指定一个游戏进程，或使用 --image 预览图片。");
            if (output is not null && !preview)
                throw new ArgumentException("--output 仅用于预览。");
            if (image is not null)
                image = Path.GetFullPath(image);
            if (output is not null)
                output = Path.GetFullPath(output);

            CharacterOcrProgram program = CharacterOcrProgram.Find();
            var owner = CancellationTokenSource.CreateLinkedTokenSource(automation.Token);
            cancellation = owner;
            Creation.Cancelled.Reset();
            Update(new(true, row?.Client.ProcessId, preview ? "preview" : "run", "正在准备角色创建。", 0, 0, null, null));
            task = Task.Run(() => Run(program, row, image, preview, output, owner));
            return task;
        }
    }

    public async Task Stop()
    {
        Task<CreationResult>? pending;
        lock (gate)
        {
            Creation.Cancelled.Set();
            cancellation?.Cancel();
            pending = task;
        }
        if (pending is not null)
            await pending;
    }

    private async Task<CreationResult> Run(CharacterOcrProgram program, GameRow? row, string? image, bool preview, string? output,
        CancellationTokenSource owner)
    {
        CancellationToken token = owner.Token;
        using var keyLifetime = CancellationTokenSource.CreateLinkedTokenSource(token);
        Task monitor = WatchStopKey(owner, keyLifetime.Token);
        var host = row is null ? null : new OperationHost(automation, row, row.Endpoint.Advance(), preview, token);
        string? artifact = null;
        CreationView completed;
        try
        {
            token.ThrowIfCancellationRequested();
            await using var worker = new CharacterOcrWorker(program);
            Configuration initial = automation.Config;
            CreateSettings settings = initial.Effective.CharacterCreate;
            await worker.Send(new
            {
                mode = preview ? "preview" : "run", image, interval = settings.IntervalSeconds,
                auto_stop = settings.AutoStop, dry_run = settings.DryRun
            }, token);
            bool finished = false;
            bool previewed = false;
            while (!finished && await worker.Read(token) is { } line)
            {
                using var document = JsonDocument.Parse(line);
                JsonElement message = document.RootElement;
                switch (message.GetProperty("kind").GetString())
                {
                    case "operation":
                        await Reply(worker, host, message, token);
                        break;
                    case "status":
                        Update(View with { Message = Text(message) });
                        break;
                    case "log":
                        automation.Log(row?.Client.ProcessId, "character-create", Text(message));
                        break;
                    case "counts":
                        Update(View with { Finishes = message.GetProperty("finish").GetInt32(), Confirmations = message.GetProperty("confirm").GetInt32() });
                        break;
                    case "timing":
                        Update(View with
                        {
                            Deadline = automation.Hub.Now + message.GetProperty("remaining_ms").GetInt64(),
                            ConfigRevision = message.GetProperty("revision").GetInt64()
                        });
                        break;
                    case "preview" when preview:
                        if (output is not null)
                        {
                            byte[] bytes = message.GetProperty("png").GetBytesFromBase64();
                            await SavePreview(output, bytes, token);
                            artifact = output;
                        }
                        previewed = true;
                        Update(View with
                        {
                            Message = message.GetProperty("description").GetString()!,
                            Hits = message.GetProperty("hits").Deserialize<CreationHit[]>(Wire.Json),
                            OcrSeconds = message.GetProperty("seconds").GetDouble(),
                            ConfigRevision = initial.Revision
                        });
                        break;
                    case "error":
                        throw new InvalidOperationException(Text(message));
                    case "finished":
                        finished = true;
                        break;
                    default:
                        throw new InvalidDataException("RapidOCR 后台返回了未知消息。");
                }
            }
            token.ThrowIfCancellationRequested();
            if (!finished)
                throw new InvalidOperationException(await worker.ExplainExit(token));
            if (preview && !previewed)
                throw new InvalidOperationException("RapidOCR 后台未返回预览。");
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
            Update(View with { Message = "角色创建已停止。" });
        }
        catch (Exception error) when (token.IsCancellationRequested && error is IOException or InvalidOperationException)
        {
            Update(View with { Message = "角色创建已停止。" });
        }
        catch (Exception error)
        {
            automation.Log(row?.Client.ProcessId, "error", error.Message);
            Update(View with { Mode = "failed", Message = error.Message });
        }
        finally
        {
            keyLifetime.Cancel();
            await monitor;
            lock (gate)
            {
                Creation.Cancelled.Set();
                host?.Invalidate();
                cancellation = null;
                owner.Dispose();
                completed = View with { Active = false, Deadline = null };
                Update(completed);
            }
        }
        return new(completed, artifact);
    }

    private static async Task SavePreview(string path, byte[] png, CancellationToken cancellation)
    {
        string temporary = $"{path}.{Guid.NewGuid():N}.tmp";
        try
        {
            await using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                await file.WriteAsync(png, cancellation);
            cancellation.ThrowIfCancellationRequested();
            File.Move(temporary, path);
        }
        finally
        {
            if (File.Exists(temporary))
                File.Delete(temporary);
        }
    }

    private static async Task Reply(CharacterOcrWorker worker, OperationHost? host, JsonElement message, CancellationToken token)
    {
        long id = message.GetProperty("id").GetInt64();
        object result;
        try
        {
            if (host is null)
                throw new InvalidOperationException("图片预览没有游戏操作目标。");
            var data = await host.Execute(message.GetProperty("action").GetString()!, message.GetProperty("data"));
            result = new { id, data };
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            result = new { id, error = error.Message };
        }
        await worker.Send(result, token);
    }

    private static async Task WatchStopKey(CancellationTokenSource owner, CancellationToken token)
    {
        try
        {
            using var timer = new PeriodicTimer(TimeSpan.FromMilliseconds(25));
            while (await timer.WaitForNextTickAsync(token))
            {
                if (!Creation.KeyDown(0x78))
                    continue;
                Creation.Cancelled.Set();
                owner.Cancel();
                return;
            }
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
    }

    private static string Text(JsonElement message) => message.GetProperty("text").GetString() ?? "";

    private void Update(CreationView next)
    {
        Volatile.Write(ref view, next);
        automation.Changed();
    }

    private sealed class OperationHost(Automation automation, GameRow row, long version, bool preview, CancellationToken token)
    {
        private sealed record Frame(int Left, int Top, int Width, int Height, long Stamp)
        {
            public bool Matches(int[] bounds) => Left == bounds[0] && Top == bounds[1] && Width == bounds[2] && Height == bounds[3];
        }

        private Frame? lastFrame;
        private bool Current => !token.IsCancellationRequested && !Creation.Cancelled.IsSet && row.Endpoint.Current(version);
        private bool Foreground => Current && !automation.Hub.Paused && Fight.Foreground(row.Client);

        public void Invalidate()
        {
            if (row.Endpoint.Current(version))
                row.Endpoint.Advance();
            automation.Hub.Wake.Set();
        }

        public async Task<object> Execute(string action, JsonElement data)
        {
            token.ThrowIfCancellationRequested();
            if (!Current || !Fight.IsAlive(row.Client))
                throw new InvalidOperationException("游戏进程已退出或角色创建会话已失效。");
            Configuration config = automation.Config;
            if (action == "State")
            {
                CreateSettings settings = config.Effective.CharacterCreate;
                return new
                {
                    Foreground,
                    Settings = new { revision = config.Revision, interval = settings.IntervalSeconds, auto_stop = settings.AutoStop, dry_run = settings.DryRun }
                };
            }
            if (action == "Capture")
            {
                object result = new { Foreground = false };
                ActionResult capture = await automation.Operator.Submit(row.Endpoint, version, config.Effective, "Character.Capture",
                    _ => Capture(frame => result = frame), token, foreground: false);
                if (capture.Error is not null)
                    throw new InvalidOperationException(capture.Error);
                return result;
            }
            if (action == "Activate")
            {
                ActionResult activate = await automation.Operator.Submit(row.Endpoint, version, config.Effective, "Character.Activate",
                    _ => Current && !automation.Hub.Paused && Fight.Activate(row.Client), token, foreground: false);
                if (activate.Error is not null)
                    throw new InvalidOperationException(activate.Error);
                return new { Executed = activate.Executed };
            }
            if (action != "Click" || preview)
                throw new InvalidOperationException("RapidOCR 后台请求了当前模式不可用的操作。");

            var frame = new Frame(data.GetProperty("Left").GetInt32(), data.GetProperty("Top").GetInt32(),
                data.GetProperty("Width").GetInt32(), data.GetProperty("Height").GetInt32(), data.GetProperty("Stamp").GetInt64());
            int x = data.GetProperty("X").GetInt32(), y = data.GetProperty("Y").GetInt32();
            ActionResult click = await automation.Operator.Submit(row.Endpoint, version, config.Effective, "Character.Click", _ =>
            {
                if (!Foreground || automation.Config.Effective.CharacterCreate.DryRun || frame != lastFrame ||
                    frame.Stamp < 0 || automation.Hub.Now - frame.Stamp is < 0 or > 5000)
                    return false;
                lastFrame = null;
                return Creation.Click(row.Client.ProcessId, row.Client.StartTicks, row.Client.Path,
                    frame.Left, frame.Top, frame.Width, frame.Height, x, y);
            }, token, foreground: false);
            if (click.Error is not null)
                throw new InvalidOperationException(click.Error);
            return new { Executed = click.Executed };
        }

        private bool Capture(Action<object> reply)
        {
            lastFrame = null;
            if (!Foreground)
                return false;
            var client = row.Client;
            int[] bounds = Creation.Bounds(client.ProcessId);
            try
            {
                using Bitmap image = Rotation.Capture(client.ProcessId, client.StartTicks, client.Path, bounds[2], bounds[3]);
                if (image.Width != bounds[2] || image.Height != bounds[3])
                    return false;
                long stamp = automation.Hub.Now;
                byte[] png = Rotation.Png(image);
                var frame = new Frame(bounds[0], bounds[1], bounds[2], bounds[3], stamp);
                if (!Foreground || !frame.Matches(Creation.Bounds(client.ProcessId)))
                    return false;
                lastFrame = frame;
                reply(new { Foreground = true, Png = png, frame.Left, frame.Top, frame.Width, frame.Height, frame.Stamp });
                return true;
            }
            catch (WowAutoCapture.PendingException)
            {
                reply(new { Foreground = Foreground, Pending = true });
                return false;
            }
        }
    }
}
