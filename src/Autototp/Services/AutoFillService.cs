using System.Windows.Forms;
using Autototp.Models;

namespace Autototp.Services;

public sealed class AutoFillMatch
{
    public required TotpAccount Account { get; init; }
    public required string Secret { get; init; }
}

public sealed class AutoFillService
{
    private readonly EncryptionService _encryption;

    public AutoFillService(EncryptionService encryption)
    {
        _encryption = encryption;
    }

    public IReadOnlyList<AutoFillMatch> FindMatches(IEnumerable<TotpAccount> accounts, string windowTitle, MasterPasswordSettings? masterPassword)
    {
        if (string.IsNullOrWhiteSpace(windowTitle))
        {
            return [];
        }

        var matches = new List<AutoFillMatch>();
        foreach (var account in accounts)
        {
            if (string.IsNullOrWhiteSpace(account.WindowTitleMatch))
            {
                continue;
            }

            if (windowTitle.Contains(account.WindowTitleMatch.Trim(), StringComparison.OrdinalIgnoreCase)
                && _encryption.TryUnprotectSecret(account.EncryptedSecret, masterPassword, out var secret))
            {
                matches.Add(new AutoFillMatch { Account = account, Secret = secret });
            }
        }

        return matches;
    }

    public void TypeCode(string secret, TotpAccount account, bool sendEnter, nint? restoreWindow = null)
    {
        var code = TotpGenerator.ComputeCode(secret, account.Digits, account.Period, account.Algorithm);
        if (restoreWindow is { } hwnd)
        {
            NativeWindowService.TryActivate(hwnd);
            Thread.Sleep(80);
        }

        SendKeys.SendWait(code);
        if (sendEnter)
        {
            SendKeys.SendWait("{ENTER}");
        }
    }
}
