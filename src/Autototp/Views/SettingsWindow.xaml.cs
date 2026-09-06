using System.Diagnostics;
using System.Windows;
using Autototp.ViewModels;

namespace Autototp.Views;

public partial class SettingsWindow : Window
{
    private readonly MainViewModel _viewModel;
    private readonly App _app;

    public SettingsWindow(MainViewModel viewModel)
    {
        InitializeComponent();
        _viewModel = viewModel;
        _app = (App)System.Windows.Application.Current;

        AutostartBox.IsChecked = _app.Autostart.IsEnabled();
        StartMinimizedBox.IsChecked = _viewModel.Settings.StartMinimized;
        SendEnterBox.IsChecked = _viewModel.Settings.SendEnterAfterCode;
        HotkeyBox.Text = _app.Hotkey.DisplayText;
        DataPathBox.Text = _app.Store.FilePath;
        HotkeyHint.Text = _app.Hotkey.IsRegistered
            ? $"Aktiv: {_app.Hotkey.DisplayText}. Der Hotkey gilt systemweit, auch wenn Autototp im Tray liegt."
            : $"Hotkey {_app.Hotkey.DisplayText} ist belegt und konnte nicht registriert werden.";
    }

    private void OnAutostartChanged(object sender, RoutedEventArgs e)
    {
        _app.Autostart.SetEnabled(AutostartBox.IsChecked == true);
    }

    private void OnStartMinimizedChanged(object sender, RoutedEventArgs e)
    {
        _viewModel.Settings.StartMinimized = StartMinimizedBox.IsChecked == true;
        _viewModel.Persist();
    }

    private void OnSendEnterChanged(object sender, RoutedEventArgs e)
    {
        _viewModel.Settings.SendEnterAfterCode = SendEnterBox.IsChecked == true;
        _viewModel.Persist();
    }

    private void OnOpenFolder(object sender, RoutedEventArgs e)
    {
        Process.Start(new ProcessStartInfo
        {
            FileName = _app.Store.DataDirectory,
            UseShellExecute = true,
        });
    }

    private void OnClose(object sender, RoutedEventArgs e) => Close();
}
