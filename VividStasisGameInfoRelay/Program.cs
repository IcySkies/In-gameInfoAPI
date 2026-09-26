using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        const int gamePort = 28745;
        var gamePath = GetArgument("--game-path") ?? Environment.CurrentDirectory;
        var subscriberPort = int.TryParse(GetArgument("--subscriber-port"), out var configuredPort) ? configuredPort : 0;
        var discoveryDirectory = Path.Combine(gamePath, "AutoChartSwitchV2");
        Directory.CreateDirectory(discoveryDirectory);
        var discoveryPath = Path.Combine(discoveryDirectory, "bridge-relay.json");
        var logPath = Path.Combine(discoveryDirectory, "bridge-relay.log");
        using var instance = new Mutex(false, "Local\\VividStasisGameInfoRelay");
        try { if (!instance.WaitOne(0)) return; } catch (AbandonedMutexException) { }

        using var stop = new CancellationTokenSource();
        using var relay = new Relay(gamePort, subscriberPort, discoveryPath, logPath, stop.Token);
        ApplicationConfiguration.Initialize();
        using var form = new RelayForm(relay, stop);
        form.Shown += (_, _) => _ = RunRelayAsync(relay, form);
        Application.Run(form);
        stop.Cancel();
        relay.Dispose();
    }

    private static async Task RunRelayAsync(Relay relay, RelayForm form)
    {
        try { await relay.RunAsync(); }
        catch (Exception ex)
        {
            relay.SetStatus($"Relay failed: {ex.Message}");
            form.ShowRelayError(ex.Message);
        }
    }

    private static string? GetArgument(string name)
    {
        var args = Environment.GetCommandLineArgs();
        var index = Array.IndexOf(args, name);
        return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
    }
}

sealed class Relay : IDisposable
{
    private const int MaxFrameBytes = 1024 * 1024;
    private const int JournalLimit = 32;
    private const int QueueLimit = 64;
    private readonly int _gamePort;
    private readonly int _requestedSubscriberPort;
    private readonly string _discoveryPath;
    private readonly string _logPath;
    private readonly CancellationToken _cancellationToken;
    private readonly List<byte[]> _journal = [];
    private readonly object _gate = new();
    private readonly List<Subscriber> _subscribers = [];
    private TcpListener? _gameListener;
    private TcpListener? _subscriberListener;
    private int _subscriberPort;
    private bool _gameConnected;
    private string _status = "Starting relay...";

    public int GamePort => _gamePort;
    public int SubscriberPort => _subscriberPort;
    public bool GameConnected { get { lock (_gate) return _gameConnected; } }
    public int SubscriberCount { get { lock (_gate) return _subscribers.Count; } }
    public string Status { get { lock (_gate) return _status; } }

    public Relay(int gamePort, int requestedSubscriberPort, string discoveryPath, string logPath, CancellationToken cancellationToken)
    {
        _gamePort = gamePort;
        _requestedSubscriberPort = requestedSubscriberPort;
        _discoveryPath = discoveryPath;
        _logPath = logPath;
        _cancellationToken = cancellationToken;
    }

    public async Task RunAsync()
    {
        _gameListener = new TcpListener(IPAddress.Loopback, _gamePort);
        _gameListener.Start();
        _subscriberListener = new TcpListener(IPAddress.Loopback, _requestedSubscriberPort);
        _subscriberListener.Start();
        _subscriberPort = ((IPEndPoint)_subscriberListener.LocalEndpoint).Port;
        await WriteDiscoveryAsync();
        SetStatus($"Listening on game port {_gamePort}; subscriber port {_subscriberPort}.");
        Log($"Relay listening for game on 127.0.0.1:{_gamePort}; subscribers on 127.0.0.1:{_subscriberPort}.");
        var acceptSubscribers = AcceptSubscribersAsync();
        try
        {
            while (!_cancellationToken.IsCancellationRequested)
            {
                TcpClient game;
                try { game = await _gameListener.AcceptTcpClientAsync(_cancellationToken); }
                catch (OperationCanceledException) { break; }
                catch (ObjectDisposedException) when (_cancellationToken.IsCancellationRequested) { break; }
                _ = HandleGameAsync(game);
            }
            await acceptSubscribers;
        }
        finally { DeleteDiscovery(); }
    }

    private async Task AcceptSubscribersAsync()
    {
        try
        {
            while (!_cancellationToken.IsCancellationRequested)
            {
                var client = await _subscriberListener!.AcceptTcpClientAsync(_cancellationToken);
                Log($"Subscriber connected from {client.Client.RemoteEndPoint}.");
                var subscriber = new Subscriber(client, QueueLimit, _cancellationToken);
                lock (_gate)
                {
                    _subscribers.Add(subscriber);
                    foreach (var frame in _journal) subscriber.Enqueue(frame);
                }
                _ = RunSubscriberAsync(subscriber);
            }
        }
        catch (OperationCanceledException) { }
        catch (ObjectDisposedException) when (_cancellationToken.IsCancellationRequested) { }
        catch (Exception ex) { Log($"Subscriber accept loop failed: {ex.Message}"); }
    }

    private async Task HandleGameAsync(TcpClient client)
    {
        lock (_gate) _gameConnected = true;
        SetStatus("Game connected; forwarding events to subscribers.");
        using (client)
        {
            await using var stream = client.GetStream();
            try
            {
                while (!_cancellationToken.IsCancellationRequested)
                {
                    var header = new byte[4];
                    if (!await ReadExactlyAsync(stream, header)) break;
                    var length = BinaryPrimitives.ReadInt32LittleEndian(header);
                    if (length is <= 0 or > MaxFrameBytes) break;
                    var payload = new byte[length];
                    if (!await ReadExactlyAsync(stream, payload)) break;
                    var frame = new byte[4 + length];
                    header.CopyTo(frame, 0);
                    payload.CopyTo(frame, 4);
                    lock (_gate)
                    {
                        _journal.Add(frame);
                        while (_journal.Count > JournalLimit) _journal.RemoveAt(0);
                        foreach (var subscriber in _subscribers.ToArray()) subscriber.Enqueue(frame);
                    }
                }
            }
        catch (IOException) { }
        catch (SocketException) { }
        finally
        {
            lock (_gate) _gameConnected = false;
            Log("Game connection ended; waiting for reconnect.");
            SetStatus("Waiting for game connection.");
        }
        }
    }

    private async Task RunSubscriberAsync(Subscriber subscriber)
    {
        try { await subscriber.RunAsync(); }
        finally
        {
            lock (_gate) _subscribers.Remove(subscriber);
            subscriber.Dispose();
        }
    }

    private async Task WriteDiscoveryAsync()
    {
        var data = new
        {
            schemaVersion = 1,
            protocolVersion = 1,
            host = "127.0.0.1",
            gamePort = _gamePort,
            subscriberPort = _subscriberPort,
            processId = Environment.ProcessId,
            startedAtUtc = DateTimeOffset.UtcNow
        };
        var temporary = _discoveryPath + ".tmp";
        await File.WriteAllTextAsync(temporary, JsonSerializer.Serialize(data));
        File.Move(temporary, _discoveryPath, true);
        Log($"Discovery written to {_discoveryPath}.");
    }

    private void Log(string message)
    {
        try { File.AppendAllText(_logPath, $"[{DateTimeOffset.Now:O}] {message}\r\n"); } catch { }
    }

    public void SetStatus(string status)
    {
        lock (_gate) _status = status;
        Log(status);
    }

    private void DeleteDiscovery()
    {
        try { if (File.Exists(_discoveryPath)) File.Delete(_discoveryPath); } catch { }
    }

    public void Dispose()
    {
        try { _gameListener?.Stop(); } catch { }
        try { _subscriberListener?.Stop(); } catch { }
        lock (_gate) foreach (var subscriber in _subscribers.ToArray()) subscriber.Dispose();
        DeleteDiscovery();
    }

    private static async Task<bool> ReadExactlyAsync(NetworkStream stream, byte[] buffer)
    {
        var offset = 0;
        while (offset < buffer.Length)
        {
            var count = await stream.ReadAsync(buffer.AsMemory(offset));
            if (count == 0) return false;
            offset += count;
        }
        return true;
    }
}

sealed class Subscriber : IDisposable
{
    private readonly TcpClient _client;
    private readonly NetworkStream _stream;
    private readonly int _limit;
    private readonly CancellationToken _cancellationToken;
    private readonly CancellationTokenSource _connectionStop;
    private readonly Queue<byte[]> _queue = new();
    private readonly SemaphoreSlim _signal = new(0);
    private readonly object _gate = new();
    private bool _closed;

    public Subscriber(TcpClient client, int limit, CancellationToken cancellationToken)
    {
        _client = client;
        _stream = client.GetStream();
        _limit = limit;
        _cancellationToken = cancellationToken;
        _connectionStop = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
    }

    public void Enqueue(byte[] frame)
    {
        lock (_gate)
        {
            if (_closed) return;
            while (_queue.Count >= _limit) _queue.Dequeue();
            _queue.Enqueue(frame.ToArray());
            _signal.Release();
        }
    }

    public async Task RunAsync()
    {
        var writer = WriteLoopAsync(_connectionStop.Token);
        var monitor = MonitorAsync(_connectionStop.Token);
        await Task.WhenAny(writer, monitor);
        _connectionStop.Cancel();
        try { await Task.WhenAll(writer, monitor); } catch (OperationCanceledException) { }
    }

    private async Task WriteLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            await _signal.WaitAsync(cancellationToken);
            byte[]? frame;
            lock (_gate) frame = _queue.Count == 0 ? null : _queue.Dequeue();
            if (frame is null) continue;
            await _stream.WriteAsync(frame, cancellationToken);
            await _stream.FlushAsync(cancellationToken);
        }
    }

    private async Task MonitorAsync(CancellationToken cancellationToken)
    {
        var buffer = new byte[1];
        while (!cancellationToken.IsCancellationRequested)
        {
            var count = await _stream.ReadAsync(buffer.AsMemory(), cancellationToken);
            if (count == 0) return;
        }
    }

    public void Dispose()
    {
        lock (_gate) _closed = true;
        try { _connectionStop.Cancel(); } catch { }
        try { _client.Close(); } catch { }
        _signal.Dispose();
        _connectionStop.Dispose();
    }
}
