using System.Collections.Concurrent;
using System.IO.Pipes;
using WowAuto.Protocol;

namespace WowAuto.Desktop;

internal sealed class PipeServer : IAsyncDisposable
{
    private readonly Automation automation;
    private readonly CommandProcessor commands;
    private readonly DesktopServices desktop;
    private readonly CancellationTokenSource closing = new();
    private readonly SemaphoreSlim slots = new(24, 24);
    private readonly ConcurrentDictionary<int, Task> connections = new();
    private readonly Task listener;
    private int nextConnection;

    public PipeServer(Automation automation, CommandProcessor commands, DesktopServices desktop)
    {
        this.automation = automation;
        this.commands = commands;
        this.desktop = desktop;
        listener = Task.Run(Listen);
    }

    private async Task Listen()
    {
        CancellationToken token = closing.Token;
        while (!token.IsCancellationRequested)
        {
            NamedPipeServerStream? pipe = null;
            bool reserved = false;
            try
            {
                await slots.WaitAsync(token);
                reserved = true;
                pipe = new NamedPipeServerStream(Wire.PipeName, PipeDirection.InOut, 24, PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await pipe.WaitForConnectionAsync(token);
                int id = Interlocked.Increment(ref nextConnection);
                Task task = Serve(pipe, token);
                connections[id] = task;
                _ = task.ContinueWith(_ =>
                {
                    connections.TryRemove(id, out Task? removed);
                    slots.Release();
                }, CancellationToken.None, TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
                pipe = null;
                reserved = false;
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested) { }
            catch (IOException error)
            {
                automation.Log(null, "error", $"命名管道监听失败。{error.Message}");
                try { await Task.Delay(250, token); }
                catch (OperationCanceledException) when (token.IsCancellationRequested) { }
            }
            finally
            {
                pipe?.Dispose();
                if (reserved)
                    slots.Release();
            }
        }
    }

    private async Task Serve(NamedPipeServerStream pipe, CancellationToken token)
    {
        using (pipe)
        {
            Guid id = Guid.Empty;
            try
            {
                Request? request;
                using (var timeout = CancellationTokenSource.CreateLinkedTokenSource(token))
                {
                    timeout.CancelAfter(TimeSpan.FromSeconds(10));
                    request = await Wire.Read<Request>(pipe, timeout.Token);
                }
                if (request is null)
                    return;
                id = request.Id;
                if (request.Version == Wire.Version && request.Id != Guid.Empty && request.Args is not null)
                {
                    (bool watch, int? pid) = CommandProcessor.Subscription(request.Args);
                    if (watch)
                    {
                        // Watch consumes a single connection and streams complete snapshots.
                        await foreach (RuntimeView state in automation.Watch(pid, token))
                            await Send(Wire.Reply(request.Id, "snapshot", state));
                        return;
                    }
                }
                Response response = await commands.Execute(request);
                await Send(response);
                if (response.State == "accepted" && request.Args is ["runtime", "close" or "restart"])
                    desktop.RequestExit(request.Args[1] == "restart");
            }
            catch (IOException) { }
            catch (OperationCanceledException) { }
            catch (Exception error)
            {
                try { await Send(CommandProcessor.Failure(id, error)); }
                catch (IOException) { }
                catch (OperationCanceledException) { }
            }

            async Task Send(Response response)
            {
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
                timeout.CancelAfter(TimeSpan.FromSeconds(5));
                await Wire.Write(pipe, response, timeout.Token);
            }
        }
    }

    public async ValueTask DisposeAsync()
    {
        closing.Cancel();
        await listener;
        await Task.WhenAll(connections.Values);
        closing.Dispose();
    }
}
