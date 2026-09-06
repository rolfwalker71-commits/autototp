using System.Windows;
using Autototp.Models;
using Autototp.Services;
using Autototp.ViewModels;
using Autototp.Views;
using Hardcodet.Wpf.TaskbarNotification;

namespace Autototp;

public partial class App : Application
{
    private readonly AccountStore _store = new();
    private readonly EncryptionService _encryption = new();
    private readonly AutostartService _autostart = new();
    private readonly HotkeyService _hotkey = new();
    private readonly AutoFillService _autoFill;
    private MainViewModel _viewModel = null!;
    private MainWindow? _mainWindow;
    private TaskbarIcon? _tray;
    private Stream? _trayIconStream;
    private bool _isExiting;

    public App()
    {
        _autoFill = new AutoFillService(_encryption);
    }

    public AccountStore Store => _store;
    public EncryptionService Encryption => _encryption;
    public AutostartService Autostart => _autostart;
    public HotkeyService Hotkey => _hotkey;
    public AutoFillService AutoFill => _autoFill;
    public MainViewModel ViewModel => _viewModel;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        ApplyTheme();

        var data = _store.Load();
        _viewModel = new MainViewModel(_store, _encryption, data);

        _hotkey.Pressed += OnHotkeyPressed;
        if (!_hotkey.Register(data.Settings))
        {
            // Registration can fail if another app owns Ctrl+Alt+T.
        }

        _tray = CreateTrayIcon();
        _mainWindow = new MainWindow(_viewModel);
        _mainWindow.Closing += OnMainWindowClosing;

        var startMinimized = data.Settings.StartMinimized
            || e.Args.Any(a => a.Equals("--minimized", StringComparison.OrdinalIgnoreCase));

        if (startMinimized)
        {
            _mainWindow.Hide();
        }
        else
        {
            _mainWindow.Show();
        }
    }

    public void ShowMainWindow()
    {
        if (_mainWindow is null)
        {
            return;
        }

        _mainWindow.Show();
        _mainWindow.WindowState = WindowState.Normal;
        _mainWindow.Activate();
        _mainWindow.Focus();
    }

    public void ExitApplication()
    {
        _isExiting = true;
        _hotkey.Dispose();
        _tray?.Dispose();
        Shutdown();
    }

    public void RefreshHotkey()
    {
        if (!_hotkey.Register(_viewModel.Settings) && _tray is not null)
        {
            _tray.ShowBalloonTip(
                "Autototp",
                $"Hotkey {_hotkey.DisplayText} konnte nicht registriert werden.",
                BalloonIcon.Warning);
        }
    }

    private void OnMainWindowClosing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        if (_isExiting)
        {
            return;
        }

        e.Cancel = true;
        _mainWindow?.Hide();
    }

    private void OnHotkeyPressed(object? sender, EventArgs e)
    {
        Dispatcher.Invoke(HandleAutoFill);
    }

    private void HandleAutoFill()
    {
        var hwnd = NativeWindowService.ForegroundWindow;
        var title = NativeWindowService.GetWindowTitle(hwnd);
        var matches = _autoFill.FindMatches(_viewModel.Data.Accounts, title, _viewModel.Settings.MasterPassword);

        if (matches.Count == 1)
        {
            _autoFill.TypeCode(matches[0].Secret, matches[0].Account, _viewModel.Settings.SendEnterAfterCode);
            return;
        }

        var candidates = matches.Count > 1
            ? _viewModel.Accounts.Where(a => matches.Any(m => m.Account.Id == a.Id)).ToList()
            : _viewModel.Accounts.ToList();

        var picker = new QuickPickerWindow(candidates);
        if (picker.ShowDialog() == true && picker.SelectedAccount is { } selected && selected.PlaintextSecret is not null)
        {
            _autoFill.TypeCode(
                selected.PlaintextSecret,
                selected.Model,
                _viewModel.Settings.SendEnterAfterCode,
                hwnd);
        }
    }

    private TaskbarIcon CreateTrayIcon()
    {
        var open = new System.Windows.Controls.MenuItem { Header = "Öffnen" };
        open.Click += (_, _) => ShowMainWindow();

        var autostart = new System.Windows.Controls.MenuItem
        {
            Header = AutostartHeader(),
        };
        autostart.Click += (_, _) =>
        {
            _autostart.Toggle();
            autostart.Header = AutostartHeader();
        };

        var exit = new System.Windows.Controls.MenuItem { Header = "Beenden" };
        exit.Click += (_, _) => ExitApplication();

        var menu = new System.Windows.Controls.ContextMenu();
        menu.Items.Add(open);
        menu.Items.Add(autostart);
        menu.Items.Add(new System.Windows.Controls.Separator());
        menu.Items.Add(exit);
        menu.Opened += (_, _) => autostart.Header = AutostartHeader();

        var icon = new TaskbarIcon
        {
            ToolTipText = "Autototp",
            ContextMenu = menu,
        };

        _trayIconStream = GetResourceStream(new Uri("pack://application:,,,/Assets/app.ico"))?.Stream;
        if (_trayIconStream is not null)
        {
            icon.Icon = new System.Drawing.Icon(_trayIconStream);
        }
        icon.TrayMouseDoubleClick += (_, _) => ShowMainWindow();
        return icon;
    }

    private string AutostartHeader() =>
        _autostart.IsEnabled() ? "Autostart deaktivieren" : "Autostart aktivieren";

    private void ApplyTheme()
    {
        if (!ThemeService.IsDarkTheme())
        {
            return;
        }

        var dark = new ResourceDictionary
        {
            Source = new Uri("Themes/FluentTheme.Dark.xaml", UriKind.Relative),
        };
        Resources.MergedDictionaries.Add(dark);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _hotkey.Dispose();
        _tray?.Dispose();
        base.OnExit(e);
    }
}
