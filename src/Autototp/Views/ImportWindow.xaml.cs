using System.Collections.ObjectModel;
using System.Windows;
using Autototp.Services;
using Microsoft.Win32;

namespace Autototp.Views;

public partial class ImportWindow : Window
{
    private readonly ImportService _import = new();
    private readonly ObservableCollection<ImportedAccount> _preview = [];

    public ImportWindow()
    {
        InitializeComponent();
        PreviewList.ItemsSource = _preview;
    }

    public IReadOnlyList<ImportedAccount> SelectedAccounts =>
        _preview.Where(a => a.IsSelected).ToList();

    private void OnOpen2Fas(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Filter = "2FAS Backup (*.2fas)|*.2fas|JSON (*.json)|*.json|Alle Dateien (*.*)|*.*",
            Title = "2FAS-Backup wählen",
        };

        if (dialog.ShowDialog(this) != true)
        {
            return;
        }

        try
        {
            var password = string.IsNullOrWhiteSpace(BackupPasswordBox.Password)
                ? null
                : BackupPasswordBox.Password;
            ApplyResult(_import.Parse2FasFile(dialog.FileName, password));
        }
        catch (Exception ex)
        {
            StatusText.Text = ex.Message;
            _preview.Clear();
        }
    }

    private void OnParseUris(object sender, RoutedEventArgs e)
    {
        ApplyResult(_import.ParseOtpAuthText(UriBox.Text));
    }

    private void OnImportSelected(object sender, RoutedEventArgs e)
    {
        if (SelectedAccounts.Count == 0)
        {
            MessageBox.Show(this, "Bitte mindestens einen Account auswählen.", "Import", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        DialogResult = true;
    }

    private void ApplyResult(ImportResult result)
    {
        _preview.Clear();
        foreach (var account in result.Accounts)
        {
            _preview.Add(account);
        }

        var parts = new List<string> { $"{result.Accounts.Count} Account(s) erkannt." };
        parts.AddRange(result.Warnings);
        StatusText.Text = string.Join(" ", parts);
    }
}
