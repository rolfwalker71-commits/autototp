using System.Runtime.InteropServices;
using System.Text;

namespace Autototp.Services;

public static class NativeWindowService
{
    private const int MaxTitleLength = 1024;

    [StructLayout(LayoutKind.Sequential)]
    public struct Point
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    private static extern nint GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(nint hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(nint hWnd);

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out Point lpPoint);

    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(nint hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(nint hWnd, int id);

    public const uint ModAlt = 0x0001;
    public const uint ModControl = 0x0002;
    public const uint ModShift = 0x0004;
    public const uint ModWin = 0x0008;
    public const uint ModNoRepeat = 0x4000;
    public const int WmHotkey = 0x0312;

    public static nint ForegroundWindow => GetForegroundWindow();

    public static string GetWindowTitle(nint hwnd)
    {
        if (hwnd == nint.Zero)
        {
            return string.Empty;
        }

        var buffer = new StringBuilder(MaxTitleLength);
        _ = GetWindowText(hwnd, buffer, buffer.Capacity);
        return buffer.ToString();
    }

    public static string ForegroundWindowTitle => GetWindowTitle(ForegroundWindow);

    public static bool TryActivate(nint hwnd) => hwnd != nint.Zero && SetForegroundWindow(hwnd);

    public static Point CursorPosition
    {
        get
        {
            GetCursorPos(out var point);
            return point;
        }
    }

    public static bool TryRegisterHotKey(nint hwnd, int id, uint modifiers, uint virtualKey) =>
        RegisterHotKey(hwnd, id, modifiers, virtualKey);

    public static bool TryUnregisterHotKey(nint hwnd, int id) =>
        UnregisterHotKey(hwnd, id);
}
