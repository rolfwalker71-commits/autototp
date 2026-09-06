using System.Text;
using System.Windows.Forms;
using Autototp.Models;

namespace Autototp.Services;

public enum AutoFillMatchKind
{
    WindowTitle,
    Name,
    Issuer,
}

public sealed class AutoFillMatch
{
    public required TotpAccount Account { get; init; }
    public required string Secret { get; init; }
    public required AutoFillMatchKind Kind { get; init; }

    public string MatchLabel => Kind switch
    {
        AutoFillMatchKind.WindowTitle => string.IsNullOrWhiteSpace(Account.WindowTitleMatch)
            ? "Fenstertitel"
            : $"Match: {Account.WindowTitleMatch.Trim()}",
        AutoFillMatchKind.Name => $"Name: {Account.Name.Trim()}",
        AutoFillMatchKind.Issuer => $"Aussteller: {Account.Issuer.Trim()}",
        _ => "Treffer",
    };
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

        var titleMatches = new List<AutoFillMatch>();
        var fallbacks = new List<AutoFillMatch>();

        foreach (var account in accounts)
        {
            AutoFillMatchKind? kind = null;
            if (!string.IsNullOrWhiteSpace(account.WindowTitleMatch)
                && MatchesWindowTitle(windowTitle, account.WindowTitleMatch))
            {
                kind = AutoFillMatchKind.WindowTitle;
            }
            else if (MatchesWindowTitle(windowTitle, account.Name))
            {
                kind = AutoFillMatchKind.Name;
            }
            else if (MatchesWindowTitle(windowTitle, account.Issuer))
            {
                kind = AutoFillMatchKind.Issuer;
            }

            if (kind is null
                || !_encryption.TryUnprotectSecret(account.EncryptedSecret, masterPassword, out var secret))
            {
                continue;
            }

            var match = new AutoFillMatch
            {
                Account = account,
                Secret = secret,
                Kind = kind.Value,
            };

            if (kind == AutoFillMatchKind.WindowTitle)
            {
                titleMatches.Add(match);
            }
            else
            {
                fallbacks.Add(match);
            }
        }

        return titleMatches.Count > 0 ? titleMatches : fallbacks;
    }

    /// <summary>
    /// Case-insensitive contains after trim; punctuation and extra spaces are ignored.
    /// Also matches compact forms so "ANG CH" hits "ANG-CH" or "ANGCH".
    /// </summary>
    public static bool MatchesWindowTitle(string windowTitle, string candidate)
    {
        if (string.IsNullOrWhiteSpace(windowTitle) || string.IsNullOrWhiteSpace(candidate))
        {
            return false;
        }

        var titleNorm = NormalizeTitle(windowTitle);
        var candidateNorm = NormalizeTitle(candidate);
        if (candidateNorm.Length == 0)
        {
            return false;
        }

        if (ContainsNormalized(titleNorm, candidateNorm))
        {
            return true;
        }

        var titleCompact = CompactTitle(titleNorm);
        var candidateCompact = CompactTitle(candidateNorm);
        return candidateCompact.Length >= 2 && ContainsNormalized(titleCompact, candidateCompact);
    }

    public void TypeCode(string secret, TotpAccount account, bool sendEnter, nint? restoreWindow = null)
    {
        var code = TotpGenerator.ComputeCode(secret, account.Digits, account.Period, account.Algorithm);
        if (restoreWindow is { } hwnd)
        {
            NativeWindowService.ForceForeground(hwnd);
            Thread.Sleep(120);
        }

        SendKeys.SendWait(code);
        if (sendEnter)
        {
            SendKeys.SendWait("{ENTER}");
        }
    }

    private static bool ContainsNormalized(string haystack, string needle)
    {
        if (haystack.Contains(needle, StringComparison.Ordinal))
        {
            return true;
        }

        return haystack.Length >= 3 && needle.Contains(haystack, StringComparison.Ordinal);
    }

    private static string NormalizeTitle(string value)
    {
        var builder = new StringBuilder(value.Length);
        var pendingSpace = false;
        foreach (var ch in value.Trim())
        {
            if (char.IsLetterOrDigit(ch))
            {
                if (pendingSpace && builder.Length > 0)
                {
                    builder.Append(' ');
                }

                builder.Append(char.ToLowerInvariant(ch));
                pendingSpace = false;
            }
            else
            {
                pendingSpace = true;
            }
        }

        return builder.ToString();
    }

    private static string CompactTitle(string normalized) => normalized.Replace(" ", string.Empty);
}
