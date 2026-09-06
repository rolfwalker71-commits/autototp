using Microsoft.Win32;

namespace Autototp.Services;

public static class ThemeService
{
    public static bool IsDarkTheme()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            var value = key?.GetValue("AppsUseLightTheme");
            return value is int light && light == 0;
        }
        catch
        {
            return false;
        }
    }
}
