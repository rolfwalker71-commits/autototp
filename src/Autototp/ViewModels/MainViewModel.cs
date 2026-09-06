using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows.Data;
using Autototp.Models;
using Autototp.Services;

namespace Autototp.ViewModels;

public sealed class MainViewModel : ViewModelBase
{
    private readonly AccountStore _store;
    private readonly EncryptionService _encryption;
    private readonly LogoService _logos;
    private string _searchText = string.Empty;
    private AccountItemViewModel? _selectedAccount;
    private StoredData _data;

    public MainViewModel(AccountStore store, EncryptionService encryption, StoredData data)
    {
        _store = store;
        _encryption = encryption;
        _logos = new LogoService(store.DataDirectory);
        _data = data;

        Accounts = [];
        FilteredAccounts = CollectionViewSource.GetDefaultView(Accounts);
        FilteredAccounts.Filter = FilterAccount;

        ReloadFrom(_data);
    }

    public ObservableCollection<AccountItemViewModel> Accounts { get; }

    public ICollectionView FilteredAccounts { get; }

    public StoredData Data => _data;

    public AppSettings Settings => _data.Settings;

    public LogoService Logos => _logos;

    public string SearchText
    {
        get => _searchText;
        set
        {
            if (SetProperty(ref _searchText, value))
            {
                FilteredAccounts.Refresh();
            }
        }
    }

    public AccountItemViewModel? SelectedAccount
    {
        get => _selectedAccount;
        set => SetProperty(ref _selectedAccount, value);
    }

    public bool HasAccounts => Accounts.Count > 0;

    public void ReloadFrom(StoredData data)
    {
        _data = data;
        Accounts.Clear();
        foreach (var account in data.Accounts.OrderBy(a => a.Name, StringComparer.CurrentCultureIgnoreCase))
        {
            _encryption.TryUnprotectSecret(account.EncryptedSecret, data.Settings.MasterPassword, out var secret);
            Accounts.Add(new AccountItemViewModel(
                account,
                string.IsNullOrEmpty(secret) ? null : secret,
                _logos.LoadImage(account.LogoFileName)));
        }

        FilteredAccounts.Refresh();
        OnPropertyChanged(nameof(HasAccounts));
        OnPropertyChanged(nameof(Settings));
    }

    public void Tick()
    {
        foreach (var account in Accounts)
        {
            account.RefreshCode();
        }
    }

    public void AddImported(IEnumerable<ImportedAccount> imported)
    {
        foreach (var item in imported.Where(i => i.IsSelected))
        {
            var account = new TotpAccount
            {
                Name = item.Name.Trim(),
                AccountLogin = item.AccountLogin.Trim(),
                Issuer = item.Issuer.Trim(),
                WindowTitleMatch = item.WindowTitleMatch.Trim(),
                EncryptedSecret = _encryption.ProtectSecret(TotpGenerator.NormalizeSecret(item.Secret), Settings.MasterPassword),
                Digits = item.Digits,
                Period = item.Period,
                Algorithm = item.Algorithm,
            };
            _data.Accounts.Add(account);
            Accounts.Add(new AccountItemViewModel(
                account,
                TotpGenerator.NormalizeSecret(item.Secret),
                _logos.LoadImage(null)));
        }

        Persist();
    }

    public void UpsertAccount(TotpAccount model, string plaintextSecret)
    {
        var existing = _data.Accounts.FirstOrDefault(a => a.Id == model.Id);
        model.EncryptedSecret = _encryption.ProtectSecret(TotpGenerator.NormalizeSecret(plaintextSecret), Settings.MasterPassword);

        if (existing is null)
        {
            _data.Accounts.Add(model);
            Accounts.Add(new AccountItemViewModel(
                model,
                TotpGenerator.NormalizeSecret(plaintextSecret),
                _logos.LoadImage(model.LogoFileName)));
        }
        else
        {
            var oldLogoPath = _logos.ResolvePath(existing.LogoFileName);
            var newLogoPath = _logos.ResolvePath(model.LogoFileName);
            if (oldLogoPath is not null
                && !string.Equals(oldLogoPath, newLogoPath, StringComparison.OrdinalIgnoreCase))
            {
                _logos.Delete(existing.LogoFileName);
            }

            existing.Name = model.Name;
            existing.AccountLogin = model.AccountLogin;
            existing.Issuer = model.Issuer;
            existing.WindowTitleMatch = model.WindowTitleMatch;
            existing.EncryptedSecret = model.EncryptedSecret;
            existing.Digits = model.Digits;
            existing.Period = model.Period;
            existing.Algorithm = model.Algorithm;
            existing.LogoFileName = model.LogoFileName;

            var vm = Accounts.FirstOrDefault(a => a.Id == model.Id);
            if (vm is not null)
            {
                vm.PlaintextSecret = TotpGenerator.NormalizeSecret(plaintextSecret);
                vm.SetLogo(_logos.LoadImage(existing.LogoFileName));
                vm.NotifyLabels();
                vm.RefreshCode();
            }
        }

        Persist();
    }

    public void RemoveAccount(AccountItemViewModel item)
    {
        _logos.Delete(item.Model.LogoFileName);
        _data.Accounts.RemoveAll(a => a.Id == item.Id);
        Accounts.Remove(item);
        if (SelectedAccount == item)
        {
            SelectedAccount = null;
        }

        Persist();
    }

    public void Persist()
    {
        _store.Save(_data);
        FilteredAccounts.Refresh();
        OnPropertyChanged(nameof(HasAccounts));
    }

    private bool FilterAccount(object obj) =>
        obj is AccountItemViewModel item && item.MatchesFilter(_searchText);
}
