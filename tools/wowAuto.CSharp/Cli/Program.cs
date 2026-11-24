using System.IO.Pipes;
using System.Text.Json;
using WowAuto.Protocol;

bool json = args.Contains("--json", StringComparer.Ordinal);
string[] command = args.Where(value => value != "--json").ToArray();
if (command.Length == 0 || command is ["--help"] or ["-h"])
{
    Console.WriteLine("wowauto-cli [--json] <命令>\n使用 wowauto-cli help 查询运行中的 wowAuto 支持的命令。");
    return 0;
}

Console.OutputEncoding = Wire.Utf8;
using var cancel = new CancellationTokenSource();
Console.CancelKeyPress += (_, ev) => { ev.Cancel = true; cancel.Cancel(); };
Guid id = Guid.NewGuid();
try
{
    using var pipe = new NamedPipeClientStream(".", Wire.PipeName, PipeDirection.InOut,
        PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
    await pipe.ConnectAsync(3000, cancel.Token);
    await Wire.Write(pipe, new Request(Wire.Version, id, command), cancel.Token);
    using var reader = new StreamReader(pipe, Wire.Utf8, detectEncodingFromByteOrderMarks: false);
    bool subscribed = command is ["status", "watch", ..];
    bool received = false;
    while (await reader.ReadLineAsync(cancel.Token) is { } line)
    {
        var response = JsonSerializer.Deserialize<Response>(line, Wire.Json) ?? throw new InvalidDataException("响应格式无效。");
        if (response.Id != id)
            throw new InvalidDataException("响应 ID 与请求不符。");
        received = true;
        if (json || subscribed)
            Console.WriteLine(line);
        else if (response.Data is { } data)
        {
            if (command is ["help"] && data.ValueKind == JsonValueKind.Array)
                foreach (JsonElement item in data.EnumerateArray()) Console.WriteLine(item.GetString());
            else
                Console.WriteLine(JsonSerializer.Serialize(data, new JsonSerializerOptions(Wire.Json) { WriteIndented = true,
                    Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping }));
        }
        if (response.State is "failed" or "cancelled")
        {
            if (!json) Console.Error.WriteLine(response.Error);
            return response.State == "cancelled" ? 130 : 1;
        }
        if (!subscribed)
        {
            if (response.State == "accepted" && !json)
                Console.WriteLine($"请求已受理 {id}");
            return 0;
        }
    }
    if (!received)
        throw new IOException("连接已关闭，未收到回执。");
    return 0;
}
catch (OperationCanceledException) { return 130; }
catch (Exception error) when (error is TimeoutException or IOException or UnauthorizedAccessException or JsonException)
{
    string message = error is TimeoutException ? "连接超时。请在同一 Windows 用户会话启动 C# 版 WowAuto.exe。" : error.Message;
    if (json)
        Console.WriteLine(JsonSerializer.Serialize(new Response(id, "failed", Error: message, Code: "connection_failed"), Wire.Json));
    else
        Console.Error.WriteLine(message);
    return 2;
}
