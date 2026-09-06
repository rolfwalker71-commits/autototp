using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using Autototp.Models;
using Autototp.Services;
using Autototp.ViewModels;
using Microsoft.Win32;

namespace Autototp.Views;

public partial class AddAccountWindow : Window
{
    private readonly AccountItemViewModel? _existing;
    private readonly LogoService _logos;
    private readonly DispatcherTimer _previewTimer;
    private string? _pendingLogoPath;
    private bool _clearLogo;

    public TotpAccount? ResultAccount { get; private set; }
    public string? ResultSecret { get; private set; }

    public AddAccountWindow(AccountItemViewModel? existing, LogoService logos)
    {
        InitializeComponent();
        _existing = existing;
        _logos = logos;
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

            if (existing.LogoImage is not null)
            {
                ShowLogoPreview(existing.LogoImage);
            }
        }

        UpdateLogoInitial();
        Closed += (_, _) => _previewTimer.Stop();
        SecretBox.PasswordChanged += (_, _) => UpdatePreview();
        SecretPlainBox.TextChanged += (_, _) => UpdatePreview();
    }

    private string CurrentSecret =>
        ShowSecretBox.IsChecked == true ? SecretPlainBox.Text : SecretBox.Password;

    private void OnNameChanged(object sender, System.Windows.Controls.TextChangedEventArgs e) =>
        UpdateLogoInitial();

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

    private void OnChooseLogo(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "Logo wählen",
            Filter = "Bilder (*.png;*.jpg;*.jpeg;*.ico;*.bmp;*.gif)|*.png;*.jpg;*.jpeg;*.ico;*.bmp;*.gif|" +
                     "PNG (*.png)|*.png|JPEG (*.jpg;*.jpeg)|*.jpg;*.jpeg|Icon (*.ico)|*.ico|Alle Dateien (*.*)|*.*",
        };

        if (dialog.ShowDialog(this) != true)
        {
            return;
        }

        if (!LogoService.TryCreatePreview(dialog.FileName, out var image, out var error) || image is null)
        {
            MessageBox.Show(this, error, "Logo", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        _pendingLogoPath = dialog.FileName;
        _clearLogo = false;
        ShowLogoPreview(image);
    }

    private void OnRemoveLogo(object sender, RoutedEventArgs e)
    {
        _pendingLogoPath = null;
        _clearLogo = true;
        ClearLogoPreview();
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

        var id = _existing?.Id ?? Guid.NewGuid();
        string? logoFileName = _existing?.Model.LogoFileName;

        try
        {
            if (_clearLogo)
            {
                logoFileName = null;
            }
            else if (!string.IsNullOrWhiteSpace(_pendingLogoPath))
            {
                logoFileName = _logos.SaveFromFile(id, _pendingLogoPath);
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Logo", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        ResultAccount = new TotpAccount
        {
            Id = id,
            Name = name,
            Issuer = IssuerBox.Text.Trim(),
            WindowTitleMatch = MatchBox.Text.Trim(),
            Digits = _existing?.Model.Digits ?? 6,
            Period = _existing?.Model.Period ?? 30,
            Algorithm = _existing?.Model.Algorithm ?? "SHA1",
            LogoFileName = logoFileName,
        };
        ResultSecret = secret;
        DialogResult = true;
    }

    private void ShowLogoPreview(ImageSource image)
    {
        LogoPreviewBrush.ImageSource = image;
        LogoImageTile.Visibility = Visibility.Visible;
        LogoInitialTile.Visibility = Visibility.Collapsed;
        RemoveLogoButton.IsEnabled = true;
    }

    private void ClearLogoPreview()
    {
        LogoPreviewBrush.ImageSource = null;
        LogoImageTile.Visibility = Visibility.Collapsed;
        LogoInitialTile.Visibility = Visibility.Visible;
        RemoveLogoButton.IsEnabled = false;
        UpdateLogoInitial();
    }

    private void UpdateLogoInitial()
    {
        var name = NameBox.Text.Trim();
        LogoInitialText.Text = name.Length == 0 ? "?" : char.ToUpperInvariant(name[0]).ToString();
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
