using System.ComponentModel;
using System.Diagnostics;

namespace Ekravio.Capture;

internal static class CaptureWatch
{
    public static int Run(ProcessStartInfo startInfo, Func<bool> allowsCapture, TimeSpan limit,
        CancellationToken cancellationToken)
    {
        if (cancellationToken.IsCancellationRequested) return 130;
        if (!allowsCapture())
        {
            Console.Error.WriteLine("Capture requires an unlocked, active Windows console session.");
            return 3;
        }

        var elapsed = Stopwatch.StartNew();
        using var child = Process.Start(startInfo) ?? throw new InvalidOperationException("GStreamer did not start.");
        try
        {
            // Check immediately after launch as well as while waiting for the live pipeline to finish.
            do
            {
                if (cancellationToken.IsCancellationRequested) return 130;
                if (!allowsCapture())
                {
                    Console.Error.WriteLine("Capture stopped because the Windows console desktop changed or became unavailable.");
                    return 3;
                }
                if (elapsed.Elapsed >= limit)
                {
                    Console.Error.WriteLine("Capture stopped because the run exceeded its time limit.");
                    return 4;
                }
            } while (!child.WaitForExit(200));

            return child.ExitCode;
        }
        finally
        {
            if (!child.HasExited)
            {
                try { child.Kill(); }
                catch (InvalidOperationException) when (child.HasExited) { }
                catch (Win32Exception) when (child.HasExited) { }
                child.WaitForExit();
            }
        }
    }
}
