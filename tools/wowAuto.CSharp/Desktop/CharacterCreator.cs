using System.Text.RegularExpressions;
using WowAuto.Protocol;
using Capture = WowAutoCapture.Native;
using Creation = WowAuto.CharacterCreate.Native;
using Rotation = WowAutoRotation.Native;
using Fight = WowAutoFight.Native;

namespace WowAuto.Desktop;

internal sealed record CreationView(bool Active, int? Pid, string Mode, string Message, int Finishes, int Confirmations,
    long? Deadline, long? ConfigRevision, OcrLine[]? Hits = null);
internal sealed record CreationResult(CreationView State, string? Image = null);

internal sealed partial class CharacterCreator(Automation automation)
{
    private readonly object gate = new();
    private CancellationTokenSource? cancellation;
    private Task<CreationResult>? task;
    private CreationView view = new(false, null, "", "等待角色创建任务。", 0, 0, null, null);
    public CreationView View => Volatile.Read(ref view);
    public bool Active => View.Active;
    private long Now => automation.Hub.Now;

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
            var owner = CancellationTokenSource.CreateLinkedTokenSource(automation.Token);
            cancellation = owner;
            Creation.Cancelled.Reset();
            Update(new(true, row?.Client.ProcessId, preview ? "preview" : "run", "正在准备角色创建。", 0, 0, null, null));
            task = Task.Run(() => Run(row, image, preview, output, owner));
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

    private async Task<CreationResult> Run(GameRow? row, string? image, bool preview, string? output, CancellationTokenSource owner)
    {
        CancellationToken token = owner.Token;
        int finished = 0, confirmed = 0, consecutive = 0, activationTries = 0;
        string? artifact = null;
        long lastConfirm = long.MinValue / 2, missingSince = 0, nextActivation = 0;
        long cycleStart = Now, deadline = 0;
        bool dryRun = false;
        string message = "已结束。";
        long version = row?.Endpoint.Advance() ?? 0;
        try
        {
            while (!token.IsCancellationRequested)
            {
                if (Creation.KeyDown(0x78))
                    break;
                Configuration current = automation.Config;
                CreateSettings settings = current.Effective.CharacterCreate;
                dryRun = settings.DryRun;
                long interval = (long)(settings.IntervalSeconds * 1000);
                deadline = cycleStart + interval;
                long now = Now;
                if (row is not null && !Fight.IsAlive(row.Client))
                    throw new InvalidOperationException("游戏进程已退出。");
                if (row is not null && !preview && !dryRun && !Fight.Foreground(row.Client))
                {
                    missingSince = 0;
                    long lead = Math.Min(3000, interval);
                    message = "等待游戏切回前台。";
                    if (now >= deadline - lead && now >= nextActivation)
                    {
                        if (activationTries == 3)
                        {
                            activationTries = 0;
                            cycleStart = now;
                            message = "本轮未能取得前台，等待下一轮。";
                        }
                        else
                        {
                            activationTries++;
                            nextActivation = now + Math.Max(100, lead / 3);
                            await automation.Operator.Submit(row.Endpoint, version, current.Effective, "Character.Activate",
                                _ => !Creation.Cancelled.IsSet && Fight.Activate(row.Client), token, false);
                        }
                    }
                    Update(View with { Message = message, Deadline = deadline, ConfigRevision = current.Revision });
                    await Task.Delay(100, token);
                    continue;
                }
                activationTries = 0;
                Bitmap bitmap;
                int[]? bounds = null;
                try
                {
                    if (image is not null)
                    {
                        using var source = new Bitmap(image);
                        bitmap = new Bitmap(source);
                    }
                    else
                    {
                        var client = row!.Client;
                        bounds = Creation.Bounds(client.ProcessId);
                        bitmap = Rotation.Capture(client.ProcessId, client.StartTicks, client.Path, bounds[2], bounds[3]);
                    }
                }
                catch (WowAutoCapture.PendingException) when (row is not null)
                {
                    foreach (var restore in Capture.PendingRestores().Where(item => item.ProcessId == row.Client.ProcessId && item.StartTicks == row.Client.StartTicks))
                        await automation.Operator.Submit(row.Endpoint, version, current.Effective, "Capture.Restore",
                            _ => { Capture.RestoreMinimized(restore); return true; }, token, false);
                    await Task.Delay(current.Effective.Periods.CaptureRetryMs, token);
                    continue;
                }
                using (bitmap)
                {
                    long stamp = Now;
                    CreationObservation observation = await Read(bitmap, token);
                    now = Now;
                    if (preview)
                    {
                        artifact = output is null ? null : Path.GetFullPath(output);
                        if (artifact is not null)
                            Annotate(bitmap, observation, artifact);
                        message = observation.Balance ? "已识别阵营平衡提示。" : observation.Finish is not null ? "已识别完成按钮。" : "未识别到可点击按钮。";
                        Update(View with { Message = message, Hits = observation.Hits, ConfigRevision = current.Revision });
                        break;
                    }
                    OcrLine? hit = null;
                    bool confirm = false;
                    if (observation.Modal)
                    {
                        missingSince = 0;
                        if (!observation.Balance)
                        {
                            message = "检测到其他确认弹窗，已停止。";
                            break;
                        }
                        if (consecutive >= 3 && now - lastConfirm >= 1800)
                        {
                            message = "连续三次确认后弹窗仍在，已停止。";
                            break;
                        }
                        if (now - lastConfirm >= 1800)
                        {
                            hit = observation.Confirm;
                            confirm = hit is not null;
                        }
                        message = "检测到阵营平衡提示。";
                    }
                    else
                    {
                        consecutive = 0;
                        if (observation.Finish is null)
                        {
                            if (missingSince == 0)
                                missingSince = now;
                            message = "未识别到红色完成按钮。";
                            if (settings.AutoStop && now - missingSince >= 12000)
                                break;
                        }
                        else
                        {
                            missingSince = 0;
                            if (now >= deadline)
                                hit = observation.Finish;
                            message = "等待下一次创建尝试。";
                        }
                    }
                    if (hit is not null && bounds is not null)
                    {
                        int[] geometry = bounds;
                        int x = (int)Math.Round(hit.CenterX * bitmap.Width), y = (int)Math.Round(hit.CenterY * bitmap.Height);
                        bool sent = dryRun;
                        if (!dryRun)
                        {
                            var client = row!.Client;
                            var operation = await automation.Operator.Submit(row.Endpoint, version, current.Effective, "Character.Click",
                                _ => !Creation.Cancelled.IsSet && Now - stamp <= 5000 && Fight.IsAlive(client) &&
                                    Creation.Click(client.ProcessId, client.StartTicks, client.Path, geometry[0], geometry[1], geometry[2], geometry[3], x, y),
                                token, false);
                            sent = operation.Executed;
                        }
                        if (sent)
                        {
                            cycleStart = Now;
                            if (confirm)
                            {
                                confirmed++;
                                consecutive++;
                                lastConfirm = Now;
                            }
                            else
                                finished++;
                            message = dryRun ? "试运行已记录本轮尝试。" : "已提交点击。";
                        }
                    }
                    Update(new(true, row?.Client.ProcessId, View.Mode, message, finished, confirmed, deadline, current.Revision, observation.Hits));
                }
                await Task.Delay(200, token);
            }
            if (token.IsCancellationRequested || Creation.KeyDown(0x78))
                message = "角色创建已停止。";
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { message = "角色创建已停止。"; }
        catch (Exception error)
        {
            message = error.Message;
            automation.Log(row?.Client.ProcessId, "error", message);
            Update(View with { Mode = "failed" });
        }
        finally
        {
            lock (gate)
            {
                Creation.Cancelled.Set();
                cancellation = null;
                owner.Dispose();
                Update(View with { Active = false, Message = message, Deadline = null, Finishes = finished, Confirmations = confirmed });
            }
        }
        return new(View, artifact);
    }

    private void Update(CreationView next)
    {
        Volatile.Write(ref view, next);
        automation.Changed();
    }

    private sealed record CreationObservation(bool Modal, bool Balance, OcrLine? Confirm, OcrLine? Finish, OcrLine[] Hits);

    private static async Task<CreationObservation> Read(Bitmap bitmap, CancellationToken cancellation)
    {
        async Task<OcrLine[]> ReadCrop(double x, double y, double right, double bottom)
        {
            var bounds = Rectangle.FromLTRB((int)(x * bitmap.Width), (int)(y * bitmap.Height),
                (int)(right * bitmap.Width), (int)(bottom * bitmap.Height));
            using var crop = bitmap.Clone(bounds, System.Drawing.Imaging.PixelFormat.Format24bppRgb);
            double scale = Math.Clamp(1050.0 / bitmap.Width, 1, 2.5);
            using var scaled = new Bitmap(crop, (int)(crop.Width * scale), (int)(crop.Height * scale));
            var lines = await ScreenOcr.Read(ScreenOcr.Image(scaled), cancellation);
            return lines.Select(line => line with
            {
                X = (bounds.X + line.X * bounds.Width) / bitmap.Width, Y = (bounds.Y + line.Y * bounds.Height) / bitmap.Height,
                W = line.W * bounds.Width / bitmap.Width, H = line.H * bounds.Height / bitmap.Height
            }).ToArray();
        }
        if (bitmap.Width < 320 || bitmap.Height < 180)
            throw new ArgumentException("截图过小，无法识别角色创建界面。");
        OcrLine[] middle = await ReadCrop(.20, .36, .80, .72);
        OcrLine[] bottom = await ReadCrop(.73, .82, .995, .995);
        string text = Normalize(string.Concat(middle.Select(line => line.Text)));
        bool balance = text.Contains("阵营") && (text.Contains("不平衡") ||
            (text.Contains("目前无法") && (text.Contains("选择") || text.Contains("创建"))));
        OcrLine[] confirmations = middle.Where(line => Normalize(line.Text) == "确定").ToArray();
        OcrLine? confirm = confirmations.FirstOrDefault(line => Red(bitmap, line));
        OcrLine? finish = bottom.FirstOrDefault(line => Normalize(line.Text) == "完成" && Red(bitmap, line));
        return new(balance || confirmations.Length != 0, balance, confirm, finish, [.. middle, .. bottom]);
    }

    private static bool Red(Bitmap bitmap, OcrLine line)
    {
        Rectangle rect = Bounds(bitmap, line);
        rect.Inflate(Math.Max(12, rect.Width / 2), Math.Max(5, rect.Height / 3));
        rect.Intersect(new Rectangle(Point.Empty, bitmap.Size));
        int count = 0;
        for (int y = rect.Top; y < rect.Bottom; y++)
        for (int x = rect.Left; x < rect.Right; x++)
        {
            Color color = bitmap.GetPixel(x, y);
            if (color.R > 60 && color.R > color.G * 1.65 + 15 && color.R > color.B * 1.5 + 15)
                count++;
        }
        return rect.Width * rect.Height > 0 && count >= .16 * rect.Width * rect.Height;
    }

    private static Rectangle Bounds(Bitmap bitmap, OcrLine line) => Rectangle.FromLTRB(
        (int)(line.X * bitmap.Width), (int)(line.Y * bitmap.Height),
        (int)((line.X + line.W) * bitmap.Width), (int)((line.Y + line.H) * bitmap.Height));

    private static void Annotate(Bitmap bitmap, CreationObservation observation, string path)
    {
        using (Graphics graphics = Graphics.FromImage(bitmap))
        using (var valid = new Pen(Color.MediumSpringGreen, 2))
        using (var label = new Pen(Color.Gold, 2))
            foreach (OcrLine hit in observation.Hits)
                graphics.DrawRectangle(hit == observation.Confirm || hit == observation.Finish ? valid : label, Bounds(bitmap, hit));
        using var file = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        bitmap.Save(file, System.Drawing.Imaging.ImageFormat.Png);
    }

    private static string Normalize(string text) => NonWord().Replace(text, "").Replace('陣', '阵').Replace('營', '营')
        .Replace('確', '确').Replace('無', '无').Replace('選', '选').Replace('擇', '择').Replace('創', '创');

    [GeneratedRegex(@"[\W_]+")] private static partial Regex NonWord();
}
