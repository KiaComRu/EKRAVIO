using System.Runtime.InteropServices;

namespace Ekravio.Windows;

internal enum SessionDesktopState
{
    Unavailable,
    Disconnected,
    Active
}

internal static class SessionDesktop
{
    private const int CurrentSession = -1;
    private const int ConnectState = 8;
    private const int ClientProtocolType = 16;
    private const int DesktopName = 2;

    public static string Transport => ReadSessionValue(ClientProtocolType, sizeof(short)) switch
    {
        0 => "console",
        2 => "rdp",
        _ => "unknown"
    };

    public static SessionDesktopState State => ReadSessionValue(ConnectState, sizeof(int)) switch
    {
        4 => SessionDesktopState.Disconnected,
        0 when IsDefaultInputDesktop() => SessionDesktopState.Active,
        _ => SessionDesktopState.Unavailable
    };

    public static bool AllowsDesktopCapture(int sessionId) => sessionId > 0 &&
        WTSGetActiveConsoleSessionId() == (uint)sessionId && Transport == "console" &&
        State == SessionDesktopState.Active;

    private static int? ReadSessionValue(int infoClass, int size)
    {
        if (!WTSQuerySessionInformationW(IntPtr.Zero, CurrentSession, infoClass, out var buffer, out int bytes))
            return null;
        try
        {
            if (buffer == IntPtr.Zero || bytes < size) return null;
            return size == sizeof(short) ? Marshal.ReadInt16(buffer) : Marshal.ReadInt32(buffer);
        }
        finally { WTSFreeMemory(buffer); }
    }

    private static bool IsDefaultInputDesktop()
    {
        const uint desktopReadObjects = 0x0001;
        var desktop = OpenInputDesktop(0, false, desktopReadObjects);
        if (desktop == IntPtr.Zero) return false;

        var name = Marshal.AllocHGlobal(512);
        try
        {
            return GetUserObjectInformationW(desktop, DesktopName, name, 512, out _) &&
                string.Equals(Marshal.PtrToStringUni(name), "Default", StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            Marshal.FreeHGlobal(name);
            CloseDesktop(desktop);
        }
    }

    [DllImport("kernel32.dll")]
    private static extern uint WTSGetActiveConsoleSessionId();

    [DllImport("wtsapi32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool WTSQuerySessionInformationW(IntPtr server, int sessionId, int infoClass,
        out IntPtr buffer, out int bytes);

    [DllImport("wtsapi32.dll")]
    private static extern void WTSFreeMemory(IntPtr buffer);

    [DllImport("user32.dll")]
    private static extern IntPtr OpenInputDesktop(uint flags, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint access);

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetUserObjectInformationW(IntPtr handle, int index, IntPtr buffer, int length,
        out int bytesNeeded);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseDesktop(IntPtr desktop);
}
