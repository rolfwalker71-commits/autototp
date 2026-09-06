using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using Autototp.ViewModels;
using Autototp.Views;

namespace Autototp;

public partial class MainWindow : Window
{
    private readonly DispatcherTimer _timer;

    public MainWindow(MainViewModel viewModel)
    {
        InitializeComponent();
        DataContext = viewModel;
        ViewModel = viewModel;

        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
        _timer.Tick += (_, _) => ViewModel.Tick();
        _timer.Start();

        Loaded += (_, _) =>
        {
            if (System.Windows.Application.Current is App app)
            {
                HotkeyHint.Text = $"Hotkey: {app.Hotkey.DisplayText}";
            }

            SearchBox.Focus();
        };
        Closed += (_, _) => _timer.Stop();
    }

    public MainViewModel ViewModel { get; }

    private void OnAddAccount(object sender, RoutedEventArgs e) => EditAccount(null);

    private void OnImport(object sender, RoutedEventArgs e)
    {
        var dialog = new ImportWindow { Owner = this };
        if (dialog.ShowDialog() == true && dialog.SelectedAccounts.Count > 0)
        {
            ViewModel.AddImported(dialog.SelectedAccounts);
        }
    }

    private void OnSettings(object sender, RoutedEventArgs e)
    {
        var dialog = new SettingsWindow(ViewModel) { Owner = this };
        dialog.ShowDialog();
    }

    private void OnAccountDoubleClick(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (ViewModel.SelectedAccount is { } account)
        {
            EditAccount(account);
        }
    }

    private void OnCodeClick(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: AccountItemViewModel account })
        {
            CopyCode(account);
            e.Handled = true;
        }
    }

    private void OnCopyCode(object sender, RoutedEventArgs e)
    {
        if (GetAccountFromSender(sender) is { } account)
        {
            CopyCode(account);
        }
    }

    private static void CopyCode(AccountItemViewModel account)
    {
        if (account.CurrentCode.All(char.IsDigit))
        {
            Clipboard.SetText(account.CurrentCode);
        }
    }

    private void OnEditAccount(object sender, RoutedEventArgs e)
    {
        if (GetAccountFromSender(sender) is { } account)
        {
            EditAccount(account);
        }
    }

    private void OnDeleteAccount(object sender, RoutedEventArgs e)
    {
        if (GetAccountFromSender(sender) is not { } account)
        {
            return;
        }

        var result = MessageBox.Show(
            this,
            $"Account „{account.Name}“ wirklich löschen?",
            "Account löschen",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);
        if (result == MessageBoxResult.Yes)
        {
            ViewModel.RemoveAccount(account);
        }
    }

    private void EditAccount(AccountItemViewModel? existing)
    {
        var dialog = new AddAccountWindow(existing) { Owner = this };
        if (dialog.ShowDialog() == true && dialog.ResultAccount is { } model && dialog.ResultSecret is { } secret)
        {
            ViewModel.UpsertAccount(model, secret);
        }
    }

    private static AccountItemViewModel? GetAccountFromSender(object sender)
    {
        if (sender is MenuItem { DataContext: AccountItemViewModel fromMenu })
        {
            return fromMenu;
        }

        if (sender is FrameworkElement { DataContext: AccountItemViewModel fromElement })
        {
            return fromElement;
        }

        return null;
    }
}
