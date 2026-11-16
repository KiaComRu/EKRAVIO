using System.Runtime.InteropServices;
using Ekravio.Windows;

namespace Ekravio.SessionMonitor;

internal static class SessionInput
{
    public static ActivitySample Sample(ActivitySampler sampler)
    {
        var state = SessionDesktop.State;
        if (state != SessionDesktopState.Active)
        {
            return sampler.MarkUnavailable(DateTimeOffset.UtcNow,
                state == SessionDesktopState.Disconnected ? "disconnected" : "unknown");
        }

        var info = new LastInputInfo { Size = (uint)Marshal.SizeOf<LastInputInfo>() };
        if (!GetLastInputInfo(ref info)) return sampler.MarkUnavailable(DateTimeOffset.UtcNow, "unknown");
        return sampler.Observe(new(DateTimeOffset.UtcNow, GetTickCount64(), info.Tick));
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct LastInputInfo
    {
        public uint Size;
        public uint Tick;
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetLastInputInfo(ref LastInputInfo info);

    [DllImport("kernel32.dll")]
    private static extern ulong GetTickCount64();
}
