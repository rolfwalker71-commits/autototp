using System.Windows.Input;
using System.Windows.Interop;
using Autototp.Models;

namespace Autototp.Services;

public sealed class HotkeyService : IDisposable
{
    public const int HotkeyId = 0xA107;

    private HwndSource? _source;

    public event EventHandler? Pressed;

    public bool IsRegistered { get; private set; }

    public string DisplayText { get; private set; } = "Ctrl + Alt + T";

    public bool Register(AppSettings settings)
    {
        Unregister();

        var modifiers = ParseModifiers(settings.HotkeyModifiers) | NativeWindowService.ModNoRepeat;
        var vk = ParseVirtualKey(settings.HotkeyKey);
        DisplayText = FormatDisplay(settings.HotkeyModifiers, settings.HotkeyKey);

        var parameters = new HwndSourceParameters("AutototpHotkeyWnd")
        {
            Width = 0,
            Height = 0,
            PositionX = -10000,
            PositionY = -10000,
            WindowStyle = 0,
            ExtendedWindowStyle = 0x00000080 | 0x08000000, // WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE
        };

        _source = new HwndSource(parameters);
        _source.AddHook(WndProc);
        IsRegistered = NativeWindowService.TryRegisterHotKey(_source.Handle, HotkeyId, modifiers, vk);
        return IsRegistered;
    }

    public void Unregister()
    {
        if (_source is not null)
        {
            NativeWindowService.TryUnregisterHotKey(_source.Handle, HotkeyId);
            _source.RemoveHook(WndProc);
            _source.Dispose();
            _source = null;
        }

        IsRegistered = false;
    }

    public void Dispose() => Unregister();

    private nint WndProc(nint hwnd, int msg, nint wParam, nint lParam, ref bool handled)
    {
        if (msg == NativeWindowService.WmHotkey && wParam.ToInt32() == HotkeyId)
        {
            Pressed?.Invoke(this, EventArgs.Empty);
            handled = true;
        }

        return nint.Zero;
    }

    public static uint ParseModifiers(string modifiers)
    {
        uint value = 0;
        foreach (var part in modifiers.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
        {
            value |= part.ToLowerInvariant() switch
            {
                "ctrl" or "control" => NativeWindowService.ModControl,
                "alt" => NativeWindowService.ModAlt,
                "shift" => NativeWindowService.ModShift,
                "win" or "windows" => NativeWindowService.ModWin,
                _ => 0,
            };
        }

        return value == 0 ? NativeWindowService.ModControl | NativeWindowService.ModAlt : value;
    }

    public static uint ParseVirtualKey(string key)
    {
        if (Enum.TryParse<Key>(key, ignoreCase: true, out var parsed))
        {
            return (uint)KeyInterop.VirtualKeyFromKey(parsed);
        }

        return (uint)KeyInterop.VirtualKeyFromKey(Key.T);
    }

    public static string FormatDisplay(string modifiers, string key)
    {
        var parts = modifiers
            .Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
            .Select(part => part.ToLowerInvariant() switch
            {
                "ctrl" or "control" => "Ctrl",
                "alt" => "Alt",
                "shift" => "Shift",
                "win" or "windows" => "Win",
                _ => part,
            });
        return string.Join(" + ", parts.Append(key.ToUpperInvariant()));
    }
}
