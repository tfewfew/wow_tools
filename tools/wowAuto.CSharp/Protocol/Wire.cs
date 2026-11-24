using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace WowAuto.Protocol;

public sealed record Request(int Version, Guid Id, string[] Args);
public sealed record Response(Guid Id, string State, JsonElement? Data = null, string? Error = null, string? Code = null);

public static class Wire
{
    public const int Version = 1;
    public const int MaxLineBytes = 1024 * 1024;
    public static string PipeName => $"wowauto-csharp-v{Version}-{Process.GetCurrentProcess().SessionId}";
    public static readonly Encoding Utf8 = new UTF8Encoding(false, true);
    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        MaxDepth = 32
    };

    public static Response Reply(Guid id, string state, object? data = null) =>
        new(id, state, data is null ? null : JsonSerializer.SerializeToElement(data, Json));

    public static async Task<T?> Read<T>(Stream stream, CancellationToken cancellation) where T : class
    {
        // Each connection sends one request. Line framing also works for subscriptions.
        using var buffer = new MemoryStream();
        byte[] chunk = new byte[4096];
        while (buffer.Length <= MaxLineBytes)
        {
            int read = await stream.ReadAsync(chunk, cancellation);
            if (read == 0)
                return buffer.Length == 0 ? null : throw new InvalidDataException("Incomplete JSON message.");
            int end = Array.IndexOf(chunk, (byte)'\n', 0, read);
            if (end >= 0 && end != read - 1)
                throw new InvalidDataException("Send one request per pipe connection.");
            buffer.Write(chunk, 0, end < 0 ? read : end);
            if (end >= 0 && buffer.Length <= MaxLineBytes)
                return JsonSerializer.Deserialize<T>(buffer.GetBuffer().AsSpan(0, (int)buffer.Length), Json);
        }
        throw new InvalidDataException("JSON message exceeds 1 MiB.");
    }

    public static async Task Write<T>(Stream stream, T message, CancellationToken cancellation)
    {
        byte[] json = JsonSerializer.SerializeToUtf8Bytes(message, Json);
        if (json.Length > MaxLineBytes)
            throw new InvalidDataException("JSON message exceeds 1 MiB.");
        await stream.WriteAsync(json, cancellation);
        await stream.WriteAsync("\n"u8.ToArray(), cancellation);
        await stream.FlushAsync(cancellation);
    }
}
