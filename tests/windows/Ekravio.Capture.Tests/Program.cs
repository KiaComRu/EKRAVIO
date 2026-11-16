using System.Diagnostics;
using Ekravio.Capture;

if (!OperatingSystem.IsWindows()) return 1;

if (args is ["child", var pidFile])
{
    File.WriteAllText(pidFile, Environment.ProcessId.ToString());
    Thread.Sleep(TimeSpan.FromSeconds(15));
    return 0;
}
if (args is ["job-owner", var childPidFile])
{
    WindowsChildJob.ArmForProcessLifetime();
    using var child = Process.Start(OwnProcess("child", childPidFile))!;
    child.WaitForExit();
    return child.ExitCode;
}

string marker = Path.GetTempFileName();
try
{
    var childInfo = OwnProcess("child", marker);
    var limit = TimeSpan.FromSeconds(5);
    int denied = CaptureWatch.Run(childInfo, () => false, limit, CancellationToken.None);
    if (denied != 3 || new FileInfo(marker).Length != 0)
        throw new InvalidOperationException("A closed session allowed capture to start.");

    using var stop = new CancellationTokenSource();
    stop.Cancel();
    int cancelled = CaptureWatch.Run(childInfo, () => true, limit, stop.Token);
    if (cancelled != 130 || new FileInfo(marker).Length != 0)
        throw new InvalidOperationException("A cancelled run allowed capture to start.");

    int sessionLost = CaptureWatch.Run(childInfo, () => ReadPid(marker) is null, limit, CancellationToken.None);
    if (sessionLost != 3 || ReadPid(marker) is not int stoppedPid || IsRunning(stoppedPid))
        throw new InvalidOperationException("Capture survived the loss of the permitted session.");

    File.WriteAllText(marker, "");
    int timedOut = CaptureWatch.Run(childInfo, () => true, TimeSpan.FromSeconds(2), CancellationToken.None);
    if (timedOut != 4 || ReadPid(marker) is not int timedOutPid || IsRunning(timedOutPid))
        throw new InvalidOperationException("Capture survived the run deadline.");

    File.WriteAllText(marker, "");
    using var owner = Process.Start(OwnProcess("job-owner", marker))!;
    try
    {
        var wait = Stopwatch.StartNew();
        while (ReadPid(marker) is null && !owner.HasExited && wait.Elapsed < limit)
            Thread.Sleep(50);
        if (ReadPid(marker) is not int childPid || !IsRunning(childPid))
            throw new InvalidOperationException("The job owner did not start its child.");

        using var worker = Process.GetProcessById(childPid);
        owner.Kill();
        if (!owner.WaitForExit(5000) || !worker.WaitForExit(5000))
            throw new InvalidOperationException("The capture child survived the loss of its guard.");
    }
    finally
    {
        if (!owner.HasExited) owner.Kill();
    }
    Console.WriteLine("Capture session, timeout and process lifetime regressions passed.");
}
finally { File.Delete(marker); }
return 0;

static ProcessStartInfo OwnProcess(params string[] arguments)
{
    var executable = Environment.ProcessPath ?? throw new InvalidOperationException("Missing test executable path.");
    var info = new ProcessStartInfo(executable) { UseShellExecute = false };
    if (string.Equals(Path.GetFileNameWithoutExtension(executable), "dotnet", StringComparison.OrdinalIgnoreCase))
        info.ArgumentList.Add(System.Reflection.Assembly.GetExecutingAssembly().Location);
    foreach (var argument in arguments) info.ArgumentList.Add(argument);
    return info;
}

static int? ReadPid(string path)
{
    try { return int.TryParse(File.ReadAllText(path), out int pid) ? pid : null; }
    catch (IOException) { return null; }
}

static bool IsRunning(int pid)
{
    try
    {
        using var process = Process.GetProcessById(pid);
        return !process.HasExited;
    }
    catch (ArgumentException) { return false; }
}
