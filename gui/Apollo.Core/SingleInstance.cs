using System.IO.Pipes;
using System.Security.Cryptography;
using System.Text;

namespace Apollo.Core;

public sealed class SingleInstance : IDisposable
{
    private readonly FileStream lease;
    private readonly CancellationTokenSource stop = new();
    private readonly string pipeName;
    public static string PipeName(string root) => "PS4Apollo-" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(root).ToUpperInvariant())))[..24];
    public SingleInstance(string root, Action activate)
    {
        Directory.CreateDirectory(root);
        lease = new FileStream(Path.Combine(root, ".gui.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        pipeName = PipeName(root);
        _ = Listen(activate);
    }
    private async Task Listen(Action activate)
    {
        while (!stop.IsCancellationRequested)
        {
            try
            {
                using var server = new NamedPipeServerStream(pipeName, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await server.WaitForConnectionAsync(stop.Token);
                activate();
            }
            catch (OperationCanceledException) { break; }
            catch (IOException) { await Task.Delay(250); }
        }
    }
    public static async Task ActivateAsync(string root)
    {
        using var client = new NamedPipeClientStream(".", PipeName(root), PipeDirection.Out, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        await client.ConnectAsync(2000);
    }
    public void Dispose() { stop.Cancel(); lease.Dispose(); }
}
