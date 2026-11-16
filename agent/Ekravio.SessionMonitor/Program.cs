using System.Diagnostics;
using System.Text.Json;
using Ekravio.SessionMonitor;
using Ekravio.Windows;

if (!OperatingSystem.IsWindows() || Process.GetCurrentProcess().SessionId == 0)
{
    Console.Error.WriteLine("Run Ekravio SessionMonitor from the interactive Windows user session.");
    return 1;
}

if (args.Length != 2 || !int.TryParse(args[0], out int duration) || duration is < 3 or > 600 ||
    !int.TryParse(args[1], out int timeout) || timeout is < 15 or > 900)
{
    Console.Error.WriteLine("Usage: Ekravio.SessionMonitor <duration-seconds:3-600> <idle-seconds:15-900>");
    return 2;
}

Console.Error.WriteLine($"Ekravio SessionMonitor | input activity for {duration}s | idle threshold {timeout}s | Ctrl+C to stop");
var jsonOptions = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower };
var sampler = new ActivitySampler(timeout);
using var stop = new CancellationTokenSource(TimeSpan.FromSeconds(duration));
using var timer = new PeriodicTimer(TimeSpan.FromSeconds(1));
ConsoleCancelEventHandler onCancel = (_, e) => { e.Cancel = true; stop.Cancel(); };
Console.CancelKeyPress += onCancel;
try
{
    do
    {
        var sample = SessionInput.Sample(sampler);
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            sample.ObservedAtUtc,
            sample.State,
            sample.Quality,
            sample.InputSeen,
            SessionTransport = SessionDesktop.Transport
        }, jsonOptions));
    } while (await timer.WaitForNextTickAsync(stop.Token));
}
catch (OperationCanceledException) when (stop.IsCancellationRequested) { }
finally { Console.CancelKeyPress -= onCancel; }
return 0;
