using System.Threading;

namespace Autototp.Services;

public sealed class SingleInstanceService : IDisposable
{
    public const string MutexName = @"Local\Autototp.TOTPManager";
    public const string ShowEventName = @"Local\Autototp.ShowWindow";

    private readonly Mutex _mutex;
    private readonly EventWaitHandle _showEvent;
    private readonly CancellationTokenSource _cts = new();
    private readonly bool _createdNew;

    public SingleInstanceService()
    {
        _mutex = new Mutex(initiallyOwned: true, MutexName, out _createdNew);
        _showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);
    }

    public bool IsPrimary => _createdNew;

    public static void SignalShowMainWindow()
    {
        using var handle = EventWaitHandle.OpenExisting(ShowEventName);
        handle.Set();
    }

    public void ListenForActivation(Action onActivated)
    {
        var token = _cts.Token;
        _ = Task.Run(() =>
        {
            while (!token.IsCancellationRequested)
            {
                if (_showEvent.WaitOne(TimeSpan.FromMilliseconds(400)) && !token.IsCancellationRequested)
                {
                    onActivated();
                }
            }
        }, token);
    }

    public void Dispose()
    {
        _cts.Cancel();
        _showEvent.Dispose();
        if (_createdNew)
        {
            _mutex.ReleaseMutex();
        }

        _mutex.Dispose();
        _cts.Dispose();
    }
}
