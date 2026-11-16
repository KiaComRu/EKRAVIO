using System.ComponentModel;
using System.Diagnostics;
using Ekravio.Capture;
using Ekravio.Windows;

if (!OperatingSystem.IsWindows() || args.Length < 4 || args[0] is not ("publish" or "probe") ||
    !int.TryParse(args[1], out int timeoutSeconds) || timeoutSeconds is < 3 or > 190 ||
    !Path.IsPathFullyQualified(args[2]) ||
    !string.Equals(Path.GetFileName(args[2]), "gst-launch-1.0.exe", StringComparison.OrdinalIgnoreCase))
{
    Console.Error.WriteLine("Start Ekravio Capture with Start-Prototype.ps1 in the Windows user session.");
    return 2;
}

const string secretName = "EKRAVIO_CAPTURE_PUBLISHER_PASSWORD";
string? password = Environment.GetEnvironmentVariable(secretName);
Environment.SetEnvironmentVariable(secretName, null);
var startInfo = new ProcessStartInfo(args[2]) { UseShellExecute = false };
foreach (var argument in args.AsSpan(3)) startInfo.ArgumentList.Add(argument);
if (args[0] == "publish")
{
    if (string.IsNullOrEmpty(password))
    {
        Console.Error.WriteLine("The capture launcher did not supply a publisher password.");
        return 2;
    }
    startInfo.ArgumentList.Add($"signaller::auth-token=publisher:{password}");
}

using var process = Process.GetCurrentProcess();
int sessionId = process.SessionId;
using var stop = new CancellationTokenSource();
ConsoleCancelEventHandler onCancel = (_, e) => { e.Cancel = true; stop.Cancel(); };
Console.CancelKeyPress += onCancel;
try
{
    WindowsChildJob.ArmForProcessLifetime();
    return CaptureWatch.Run(startInfo, () => SessionDesktop.AllowsDesktopCapture(sessionId),
        TimeSpan.FromSeconds(timeoutSeconds), stop.Token);
}
catch (Win32Exception error)
{
    Console.Error.WriteLine($"Could not supervise capture: {error.Message}");
    return 5;
}
finally { Console.CancelKeyPress -= onCancel; }
