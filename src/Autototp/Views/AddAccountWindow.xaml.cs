using System.Windows;
using System.Windows.Threading;
using Autototp.Models;
using Autototp.Services;
using Autototp.ViewModels;

namespace Autototp.Views;

public partial class AddAccountWindow : Window
{
    private readonly AccountItemViewModel? _existing;
    private readonly DispatcherTimer _previewTimer;

    public TotpAccount? ResultAccount { get; private set; }
    public string? ResultSecret { get; private set; }

    public AddAccountWindow(AccountItemViewModel? existing = null)
    {
        InitializeComponent();
        _existing = existing;
        _previewTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
        _previewTimer.Tick += (_, _) => UpdatePreview();
        _previewTimer.Start();

        if (existing is not null)
        {
            Title = "Account bearbeiten";
            TitleText.Text = "Account bearbeiten";
            NameBox.Text = existing.Model.Name;
            IssuerBox.Text = existing.Model.Issuer;
            MatchBox.Text = existing.Model.WindowTitleMatch;
            if (existing.PlaintextSecret is not null)
            {
                SecretBox.Password = existing.PlaintextSecret;
                SecretPlainBox.Text = existing.PlaintextSecret;
            }
        }

        Closed += (_, _) => _previewTimer.Stop();
        SecretBox.PasswordChanged += (_, _) => UpdatePreview();
        SecretPlainBox.TextChanged += (_, _) => UpdatePreview();
    }

    private string CurrentSecret =>
        ShowSecretBox.IsChecked == true ? SecretPlainBox.Text : SecretBox.Password;

    private void OnIssuerLostFocus(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(MatchBox.Text) && !string.IsNullOrWhiteSpace(IssuerBox.Text))
        {
            MatchBox.Text = IssuerBox.Text.Trim();
        }
    }

    private void OnToggleSecret(object sender, RoutedEventArgs e)
    {
        if (ShowSecretBox.IsChecked == true)
        {
            SecretPlainBox.Text = SecretBox.Password;
            SecretPlainBox.Visibility = Visibility.Visible;
            SecretBox.Visibility = Visibility.Collapsed;
        }
        else
        {
            SecretBox.Password = SecretPlainBox.Text;
            SecretPlainBox.Visibility = Visibility.Collapsed;
            SecretBox.Visibility = Visibility.Visible;
        }

        UpdatePreview();
    }

    private void OnSave(object sender, RoutedEventArgs e)
    {
        var name = NameBox.Text.Trim();
        var secret = TotpGenerator.NormalizeSecret(CurrentSecret);
        if (string.IsNullOrWhiteSpace(name))
        {
            MessageBox.Show(this, "Bitte einen Namen angeben.", "Account", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        if (!TotpGenerator.TryValidateSecret(secret, out var error))
        {
            MessageBox.Show(this, error, "Account", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        ResultAccount = new TotpAccount
        {
            Id = _existing?.Id ?? Guid.NewGuid(),
            Name = name,
            Issuer = IssuerBox.Text.Trim(),
            WindowTitleMatch = MatchBox.Text.Trim(),
            Digits = _existing?.Model.Digits ?? 6,
            Period = _existing?.Model.Period ?? 30,
            Algorithm = _existing?.Model.Algorithm ?? "SHA1",
        };
        ResultSecret = secret;
        DialogResult = true;
    }

    private void UpdatePreview()
    {
        var secret = TotpGenerator.NormalizeSecret(CurrentSecret);
        if (!TotpGenerator.TryValidateSecret(secret, out var error))
        {
            PreviewCode.Text = "--- ---";
            PreviewHint.Text = string.IsNullOrWhiteSpace(secret) ? "Secret eingeben, um den aktuellen Code zu sehen." : error;
            return;
        }

        try
        {
            var code = TotpGenerator.ComputeCode(secret);
            PreviewCode.Text = code.Length == 6 ? $"{code[..3]} {code[3..]}" : code;
            PreviewHint.Text = $"Noch {TotpGenerator.RemainingSeconds()}s gültig.";
        }
        catch
        {
            PreviewCode.Text = "--- ---";
            PreviewHint.Text = "Code konnte nicht berechnet werden.";
        }
    }
}
