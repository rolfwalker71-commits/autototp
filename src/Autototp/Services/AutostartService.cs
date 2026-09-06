using System.IO;
using Microsoft.Win32;

namespace Autototp.Services;

public sealed class AutostartService
{
    public const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    public const string ValueName = "Autototp";

    public bool IsEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
        var value = key?.GetValue(ValueName) as string;
        return !string.IsNullOrWhiteSpace(value);
    }

    public void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true)
            ?? Registry.CurrentUser.CreateSubKey(RunKeyPath);

        if (enabled)
        {
            key.SetValue(ValueName, BuildCommand());
        }
        else
        {
            key.DeleteValue(ValueName, throwOnMissingValue: false);
        }
    }

    public void Toggle() => SetEnabled(!IsEnabled());

    private static string BuildCommand()
    {
        var exe = Environment.ProcessPath
            ?? Path.Combine(AppContext.BaseDirectory, "Autototp.exe");
        return $"\"{exe}\" --minimized";
    }
}
