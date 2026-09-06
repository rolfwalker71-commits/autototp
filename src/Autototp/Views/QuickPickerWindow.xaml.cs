using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Autototp.Services;
using Autototp.ViewModels;

namespace Autototp.Views;

public partial class QuickPickerWindow : Window
{
    private readonly IReadOnlyList<AccountItemViewModel> _all;

    public AccountItemViewModel? SelectedAccount { get; private set; }

    public QuickPickerWindow(IReadOnlyList<AccountItemViewModel> accounts)
    {
        InitializeComponent();
        _all = accounts;
        AccountList.ItemsSource = _all;
        if (_all.Count > 0)
        {
            AccountList.SelectedIndex = 0;
        }

        Loaded += OnLoaded;
        PreviewKeyDown += OnPreviewKey;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        var cursor = NativeWindowService.CursorPosition;
        var dpi = VisualTreeHelper.GetDpi(this);
        var work = SystemParameters.WorkArea;
        var left = cursor.X / dpi.DpiScaleX;
        var top = cursor.Y / dpi.DpiScaleY;
        Left = Math.Clamp(left, work.Left, Math.Max(work.Left, work.Right - ActualWidth));
        Top = Math.Clamp(top, work.Top, Math.Max(work.Top, work.Bottom - ActualHeight));
        FilterBox.Focus();
    }

    private void OnFilterChanged(object sender, TextChangedEventArgs e)
    {
        var filter = FilterBox.Text;
        var filtered = _all.Where(a => a.MatchesFilter(filter)).ToList();
        AccountList.ItemsSource = filtered;
        if (filtered.Count > 0)
        {
            AccountList.SelectedIndex = 0;
        }
    }

    private void OnAccountActivate(object sender, System.Windows.Input.MouseButtonEventArgs e) => AcceptSelection();

    private void OnListKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            AcceptSelection();
            e.Handled = true;
        }
    }

    private void OnPreviewKey(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            DialogResult = false;
            e.Handled = true;
        }
        else if (e.Key == Key.Enter)
        {
            AcceptSelection();
            e.Handled = true;
        }
        else if (e.Key is Key.Down && FilterBox.IsKeyboardFocusWithin)
        {
            AccountList.Focus();
            e.Handled = true;
        }
    }

    private void AcceptSelection()
    {
        if (AccountList.SelectedItem is AccountItemViewModel account)
        {
            SelectedAccount = account;
            DialogResult = true;
        }
    }
}
