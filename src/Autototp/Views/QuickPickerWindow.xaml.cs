using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Autototp.Services;
using Autototp.ViewModels;

namespace Autototp.Views;

public partial class QuickPickerWindow : Window
{
    private readonly IReadOnlyList<AccountItemViewModel> _all;
    private readonly HashSet<Guid> _preferredIds;
    private readonly DispatcherTimer _timer;

    public AccountItemViewModel? SelectedAccount { get; private set; }

    public QuickPickerWindow(
        IReadOnlyList<AccountItemViewModel> accounts,
        IReadOnlyCollection<Guid>? preferredMatchIds = null)
    {
        _all = accounts;
        _preferredIds = preferredMatchIds is { Count: > 0 }
            ? preferredMatchIds.ToHashSet()
            : [];

        InitializeComponent();
        ApplyFilter(FilterBox.Text);

        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(50) };
        _timer.Tick += (_, _) =>
        {
            foreach (var account in _all)
            {
                account.RefreshCode();
            }
        };
        _timer.Start();

        SourceInitialized += (_, _) => NativeWindowService.StealFocus(this, keepTopmost: true);
        Loaded += OnLoaded;
        Closed += (_, _) => _timer.Stop();
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
        NativeWindowService.StealFocus(this, keepTopmost: true);
        FilterBox.Focus();
        Keyboard.Focus(FilterBox);
    }

    private void OnFilterChanged(object sender, TextChangedEventArgs e) => ApplyFilter(FilterBox.Text);

    private void ApplyFilter(string? filter)
    {
        var query = filter ?? string.Empty;
        var matches = new List<AccountItemViewModel>();
        var others = new List<AccountItemViewModel>();
        foreach (var account in _all)
        {
            if (!account.MatchesFilter(query))
            {
                continue;
            }

            if (_preferredIds.Contains(account.Id))
            {
                matches.Add(account);
            }
            else
            {
                others.Add(account);
            }
        }

        var visible = new List<AccountItemViewModel>(matches.Count + others.Count);
        visible.AddRange(matches);
        visible.AddRange(others);

        var view = new ListCollectionView(visible);
        if (string.IsNullOrWhiteSpace(query) && matches.Count > 0 && others.Count > 0)
        {
            view.GroupDescriptions.Add(new PreferredGroupDescription(_preferredIds));
        }

        AccountList.ItemsSource = view;
        if (visible.Count > 0)
        {
            AccountList.SelectedItem = visible[0];
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

    private sealed class PreferredGroupDescription : GroupDescription
    {
        private readonly HashSet<Guid> _preferredIds;

        public PreferredGroupDescription(HashSet<Guid> preferredIds)
        {
            _preferredIds = preferredIds;
        }

        public override object GroupNameFromItem(object item, int level, System.Globalization.CultureInfo culture) =>
            item is AccountItemViewModel account && _preferredIds.Contains(account.Id)
                ? "Fenstertreffer"
                : "Alle Accounts";
    }
}
