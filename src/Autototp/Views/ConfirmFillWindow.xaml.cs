using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;
using Autototp.Services;
using Autototp.ViewModels;

namespace Autototp.Views;

public partial class ConfirmFillWindow : Window
{
    private readonly DispatcherTimer _timer;

    public ConfirmFillWindow(AccountItemViewModel account, AutoFillMatch match, string foregroundTitle, bool sendEnter)
    {
        InitializeComponent();
        DataContext = account;
        Account = account;

        IssuerText.Text = string.IsNullOrWhiteSpace(account.Issuer)
            ? "Kein Aussteller"
            : account.Issuer;
        MatchText.Text = match.MatchLabel;
        ForegroundHint.Text = string.IsNullOrWhiteSpace(foregroundTitle)
            ? "Aktives Fenster ohne Titel"
            : $"Fenster: {foregroundTitle.Trim()}";
        ConfirmButton.Content = sendEnter ? "Einfügen + Enter" : "Einfügen";

        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(50) };
        _timer.Tick += (_, _) => account.RefreshCode();
        _timer.Start();

        SourceInitialized += (_, _) => NativeWindowService.StealFocus(this, keepTopmost: true);
        Loaded += OnLoaded;
        Closed += (_, _) => _timer.Stop();
        PreviewKeyDown += OnPreviewKey;
    }

    public AccountItemViewModel Account { get; }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        NativeWindowService.StealFocus(this, keepTopmost: true);
        ConfirmButton.Focus();
        Keyboard.Focus(ConfirmButton);
    }

    private void OnConfirm(object sender, RoutedEventArgs e)
    {
        DialogResult = true;
    }

    private void OnCancel(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
    }

    private void OnPreviewKey(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            DialogResult = false;
            e.Handled = true;
        }
    }
}
