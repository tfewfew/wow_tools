using System.Text.RegularExpressions;
using Windows.Globalization;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;
using Rotation = WowAutoRotation.Native;

namespace WowAuto.Desktop;

internal sealed record OcrLine(string Text, double X, double Y, double W, double H)
{
    public double CenterX => X + W / 2;
    public double CenterY => Y + H / 2;
}

internal sealed record MenuTarget(int Row, double X, double Y, string Raw);
internal sealed record MenuFrame(bool Menu, MenuTarget[] Targets, Size Size);

internal static partial class ScreenOcr
{
    public static async Task<OcrLine[]> Read(byte[] image, CancellationToken cancellation)
    {
        var engine = OcrEngine.TryCreateFromLanguage(new Language("zh-Hans-CN"))
            ?? throw new InvalidOperationException("请安装 Windows 简体中文 OCR 语言功能。");
        using var input = new InMemoryRandomAccessStream();
        using (var writer = new DataWriter(input))
        {
            writer.WriteBytes(image);
            await writer.StoreAsync().AsTask(cancellation);
            writer.DetachStream();
        }
        input.Seek(0);
        BitmapDecoder decoder = await BitmapDecoder.CreateAsync(input).AsTask(cancellation);
        using SoftwareBitmap bitmap = await decoder.GetSoftwareBitmapAsync().AsTask(cancellation);
        OcrResult result = await engine.RecognizeAsync(bitmap).AsTask(cancellation);
        double angle = (result.TextAngle ?? 0) * Math.PI / 180;
        double cos = Math.Cos(angle), sin = Math.Sin(angle);
        double halfW = bitmap.PixelWidth / 2.0, halfH = bitmap.PixelHeight / 2.0;
        return result.Lines.Where(line => line.Words.Count != 0).Select(line =>
        {
            double x = line.Words.Min(word => word.BoundingRect.X);
            double y = line.Words.Min(word => word.BoundingRect.Y);
            double right = line.Words.Max(word => word.BoundingRect.Right);
            double bottom = line.Words.Max(word => word.BoundingRect.Bottom);
            double cx = (x + right) / 2 - halfW, cy = (y + bottom) / 2 - halfH;
            double width = Math.Abs((right - x) * cos) + Math.Abs((bottom - y) * sin);
            double height = Math.Abs((right - x) * sin) + Math.Abs((bottom - y) * cos);
            return new OcrLine(Whitespace().Replace(line.Text, ""), (halfW + cx * cos - cy * sin - width / 2) / bitmap.PixelWidth,
                (halfH + cx * sin + cy * cos - height / 2) / bitmap.PixelHeight, width / bitmap.PixelWidth, height / bitmap.PixelHeight);
        }).ToArray();
    }

    public static byte[] Image(Bitmap bitmap) => Rotation.OcrPng(bitmap, (int)OcrEngine.MaxImageDimension);

    public static async Task<MenuFrame> Menu(Bitmap bitmap, Size clientSize, string flavor,
        CharacterRecord[] catalog, CancellationToken cancellation)
    {
        Rectangle names = Rotation.NamesRegion(bitmap);
        int maximumDimension = (int)OcrEngine.MaxImageDimension;
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        timeout.CancelAfter(Rotation.OcrTimeoutMs(flavor));
        var fullTask = Read(Rotation.OcrPng(bitmap, maximumDimension), timeout.Token);
        var anchorsTask = Read(Rotation.AnchorsPng(bitmap, maximumDimension), timeout.Token);
        var namesTask = Read(Rotation.NamesPng(bitmap, maximumDimension), timeout.Token);
        await Task.WhenAll(fullTask, anchorsTask, namesTask);
        OcrLine[] full = fullTask.Result.Concat(anchorsTask.Result).ToArray();
        double bx = (double)names.X / bitmap.Width, by = (double)names.Y / bitmap.Height;
        double bw = (double)names.Width / bitmap.Width, bh = (double)names.Height / bitmap.Height;
        OcrLine[] labels = namesTask.Result.Select(line => line with
        {
            X = bx + line.X * bw, Y = by + line.Y * bh, W = line.W * bw, H = line.H * bh
        }).ToArray();
        bool menu = full.Concat(labels).Any(line =>
            (line.X > .65 && line.Y < .15 && Anchor().Replace(line.Text, "") == "选择服务器") ||
            (line.X is > .25 and < .70 && line.Y > .85 && Anchor().Replace(line.Text, "") == "进入魔兽世界"));
        if (!menu)
            return new(false, [], clientSize);

        var known = catalog.SelectMany(role => new[] { role.Name, $"{role.Name}-{role.DisplayRealm}" }).ToHashSet();
        double expectedFirst = flavor == "forerver" ? .1432 : .119;
        double expectedStep = flavor == "forerver" ? .082 : .0743;
        (double first, double step) = Geometry(labels, expectedFirst, expectedStep);
        var targets = new List<MenuTarget>();
        foreach (OcrLine line in labels.Concat(full.Where(line => line.X > bx && known.Contains(line.Text))))
        {
            double y = line.CenterY;
            if (y is < .08 or > .80 || line.Text == "选择服务器" || (!Letters().IsMatch(line.Text) && !known.Contains(line.Text)))
                continue;
            int row = (int)Math.Round((y - first) / step, MidpointRounding.AwayFromZero);
            double middle = first + row * step;
            if (row is >= 0 and < 10 && Math.Abs(y - middle) <= (known.Contains(line.Text) ? .034 : .02))
                targets.Add(new(row + 1, bx + bw / 2, middle, line.Text));
        }
        return new(true, targets.Distinct().ToArray(), clientSize);
    }

    private static (double First, double Step) Geometry(OcrLine[] lines, double first, double step)
    {
        var distinct = new List<double>();
        foreach (double y in lines.Where(line => Letters().IsMatch(line.Text) && line.Text != "选择服务器")
                     .Select(line => line.CenterY).Where(y => y is >= .08 and <= .80).Order())
            if (distinct.Count == 0 || y - distinct[^1] > .025)
                distinct.Add(y);
        var gaps = distinct.Zip(distinct.Skip(1), (a, b) => b - a).Where(gap => gap is >= .05 and <= .11).Order().ToArray();
        if (distinct.Count < 3 || gaps.Length < 2)
            return (first, step);
        double spacing = gaps[gaps.Length / 2];
        int firstIndex = (int)Math.Round((distinct[0] - first) / spacing, MidpointRounding.AwayFromZero);
        if (firstIndex is < 0 or > 3 || gaps.Count(gap => Math.Abs(gap - spacing) > .012) > gaps.Length / 3)
            return (first, step);
        var offsets = distinct.Select(y => y - (firstIndex + Math.Round((y - distinct[0]) / spacing)) * spacing).Order().ToArray();
        double origin = offsets[offsets.Length / 2];
        return origin is >= .08 and <= .17 && distinct.Count(y => Math.Abs((y - origin) / spacing -
            Math.Round((y - origin) / spacing)) > .20) <= 1 ? (origin, spacing) : (first, step);
    }

    [GeneratedRegex(@"\s+")] private static partial Regex Whitespace();
    [GeneratedRegex(@"^[\p{L}\p{M}]+$")] private static partial Regex Letters();
    [GeneratedRegex(@"^[0一_—\-口□]+|[一_—\-口□]+$")] private static partial Regex Anchor();
}
