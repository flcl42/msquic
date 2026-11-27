// Licensed under the MIT License.

using System.Diagnostics.Tracing;
using System.Net.Quic;

using var log = new QuicLog();
bool supported = QuicListener.IsSupported;
string expectedVersion = args[0];
string expectedCommit = args[1];
if (!supported || log.LoadedLibrary?.Contains($" {expectedVersion} ({expectedCommit})", StringComparison.Ordinal) != true)
{
    Console.Error.WriteLine($"Expected MsQuic {expectedVersion} from {expectedCommit}. QUIC supported: {supported}. {log.LoadedLibrary}");
    return 1;
}

Console.WriteLine(log.LoadedLibrary);
return 0;

sealed class QuicLog : EventListener
{
    public string? LoadedLibrary { get; private set; }

    protected override void OnEventSourceCreated(EventSource eventSource)
    {
        if (eventSource.Name == "Private.InternalDiagnostics.System.Net.Quic")
        {
            EnableEvents(eventSource, EventLevel.Informational);
        }
    }

    protected override void OnEventWritten(EventWrittenEventArgs eventData)
    {
        if (eventData.Payload is null)
        {
            return;
        }

        foreach (object? value in eventData.Payload)
        {
            if (value is string message && message.StartsWith("Loaded MsQuic library", StringComparison.Ordinal))
            {
                LoadedLibrary = message;
            }
        }
    }
}
