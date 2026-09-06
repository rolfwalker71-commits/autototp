using System.Windows.Media;
using Autototp.Models;
using Autototp.Services;

namespace Autototp.ViewModels;

public sealed class AccountItemViewModel : ViewModelBase
{
    private string _currentCode = "------";
    private string _formattedCode = "--- ---";
    private int _remainingSeconds = 30;
    private double _progress = 1;
    private bool _isExpiringSoon;
    private bool _secretAvailable = true;
    private ImageSource? _logoImage;

    public AccountItemViewModel(TotpAccount model, string? plaintextSecret, ImageSource? logo = null)
    {
        Model = model;
        PlaintextSecret = plaintextSecret;
        _secretAvailable = !string.IsNullOrEmpty(plaintextSecret);
        _logoImage = logo ?? LogoService.LoadDefault();
        RefreshCode();
    }

    public TotpAccount Model { get; }

    public string? PlaintextSecret { get; set; }

    public Guid Id => Model.Id;

    public string Name => string.IsNullOrWhiteSpace(Model.Name) ? "Account" : Model.Name;

    public string AccountLogin => Model.AccountLogin?.Trim() ?? string.Empty;

    public string Issuer => Model.Issuer;

    public string WindowTitleMatch => Model.WindowTitleMatch;

    public ImageSource? LogoImage
    {
        get => _logoImage;
        private set
        {
            if (SetProperty(ref _logoImage, value))
            {
                OnPropertyChanged(nameof(HasLogo));
                OnPropertyChanged(nameof(HasCustomLogo));
            }
        }
    }

    public bool HasLogo => LogoImage is not null;

    public bool HasCustomLogo => !string.IsNullOrWhiteSpace(Model.LogoFileName);

    public string LogoInitial
    {
        get
        {
            var name = Name.Trim();
            return name.Length == 0 ? "?" : char.ToUpperInvariant(name[0]).ToString();
        }
    }

    public string Subtitle
    {
        get
        {
            var parts = new List<string>();
            if (!string.IsNullOrWhiteSpace(Issuer) && !Issuer.Equals(Name, StringComparison.OrdinalIgnoreCase))
            {
                parts.Add(Issuer);
            }

            if (!string.IsNullOrWhiteSpace(WindowTitleMatch))
            {
                parts.Add($"Match: {WindowTitleMatch}");
            }

            return parts.Count == 0 ? "Kein Fenstertitel-Match" : string.Join("  ·  ", parts);
        }
    }

    public string CurrentCode
    {
        get => _currentCode;
        private set => SetProperty(ref _currentCode, value);
    }

    public string FormattedCode
    {
        get => _formattedCode;
        private set => SetProperty(ref _formattedCode, value);
    }

    public int RemainingSeconds
    {
        get => _remainingSeconds;
        private set => SetProperty(ref _remainingSeconds, value);
    }

    public double Progress
    {
        get => _progress;
        private set => SetProperty(ref _progress, value);
    }

    public bool IsExpiringSoon
    {
        get => _isExpiringSoon;
        private set => SetProperty(ref _isExpiringSoon, value);
    }

    public bool SecretAvailable
    {
        get => _secretAvailable;
        private set => SetProperty(ref _secretAvailable, value);
    }

    public void SetLogo(ImageSource? logo) => LogoImage = logo;

    public void NotifyLabels()
    {
        OnPropertyChanged(nameof(Name));
        OnPropertyChanged(nameof(AccountLogin));
        OnPropertyChanged(nameof(Issuer));
        OnPropertyChanged(nameof(WindowTitleMatch));
        OnPropertyChanged(nameof(Subtitle));
        OnPropertyChanged(nameof(LogoInitial));
        OnPropertyChanged(nameof(HasCustomLogo));
    }

    public void RefreshCode()
    {
        RemainingSeconds = TotpGenerator.RemainingSeconds(Model.Period);
        Progress = TotpGenerator.Progress(Model.Period);
        IsExpiringSoon = RemainingSeconds <= 10;

        if (string.IsNullOrEmpty(PlaintextSecret))
        {
            CurrentCode = "------";
            FormattedCode = "--- ---";
            SecretAvailable = false;
            return;
        }

        try
        {
            var code = TotpGenerator.ComputeCode(PlaintextSecret, Model.Digits, Model.Period, Model.Algorithm);
            CurrentCode = code;
            FormattedCode = FormatCode(code);
            SecretAvailable = true;
        }
        catch
        {
            CurrentCode = "------";
            FormattedCode = "--- ---";
            SecretAvailable = false;
        }
    }

    public bool MatchesFilter(string filter)
    {
        if (string.IsNullOrWhiteSpace(filter))
        {
            return true;
        }

        return Name.Contains(filter, StringComparison.OrdinalIgnoreCase)
            || AccountLogin.Contains(filter, StringComparison.OrdinalIgnoreCase)
            || Issuer.Contains(filter, StringComparison.OrdinalIgnoreCase)
            || WindowTitleMatch.Contains(filter, StringComparison.OrdinalIgnoreCase);
    }

    private static string FormatCode(string code) =>
        code.Length == 6 ? $"{code[..3]} {code[3..]}" : code;
}
