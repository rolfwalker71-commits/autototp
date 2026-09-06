using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Interop;

namespace Autototp.Services;

public static class NativeWindowService
{
    private const int MaxTitleLength = 1024;
    private const int SwRestore = 9;
    private const uint AsfwAny = 0xFFFFFFFF;

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
    private static extern bool AllowSetForegroundWindow(uint dwProcessId);

    [DllImport("user32.dll")]
    private static extern bool BringWindowToTop(nint hWnd);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(nint hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint hWnd, out uint processId);

    [DllImport("user32.dll")]
    private static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

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

    public static bool IsOwnedByCurrentProcess(nint hwnd)
    {
        if (hwnd == nint.Zero)
        {
            return false;
        }

        _ = GetWindowThreadProcessId(hwnd, out var processId);
        return processId == (uint)Environment.ProcessId;
    }

    public static bool TryActivate(nint hwnd) => ForceForeground(hwnd);

    public static bool ForceForeground(nint hwnd)
    {
        if (hwnd == nint.Zero)
        {
            return false;
        }

        AllowSetForegroundWindow(AsfwAny);

        var foreground = GetForegroundWindow();
        var currentThread = GetCurrentThreadId();
        var foregroundThread = foreground == nint.Zero ? 0 : GetWindowThreadProcessId(foreground, out _);
        var targetThread = GetWindowThreadProcessId(hwnd, out _);

        var attachedForeground = false;
        var attachedTarget = false;
        try
        {
            if (foregroundThread != 0 && foregroundThread != currentThread)
            {
                attachedForeground = AttachThreadInput(currentThread, foregroundThread, true);
            }

            if (targetThread != 0 && targetThread != currentThread && targetThread != foregroundThread)
            {
                attachedTarget = AttachThreadInput(currentThread, targetThread, true);
            }

            ShowWindow(hwnd, SwRestore);
            BringWindowToTop(hwnd);
            SetForegroundWindow(hwnd);
        }
        finally
        {
            if (attachedTarget)
            {
                AttachThreadInput(currentThread, targetThread, false);
            }

            if (attachedForeground)
            {
                AttachThreadInput(currentThread, foregroundThread, false);
            }
        }

        return GetForegroundWindow() == hwnd;
    }

    /// <summary>
    /// Brings a WPF window to the foreground even when another app currently owns focus
    /// (needed after a global hotkey such as Ctrl+Alt+T).
    /// </summary>
    public static void StealFocus(Window window, bool keepTopmost)
    {
        if (window.WindowState == WindowState.Minimized)
        {
            window.WindowState = WindowState.Normal;
        }

        window.Topmost = true;
        var hwnd = new WindowInteropHelper(window).EnsureHandle();
        ForceForeground(hwnd);
        window.Activate();
        window.Focus();

        if (!keepTopmost)
        {
            window.Topmost = false;
        }
    }

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
