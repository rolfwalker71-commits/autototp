namespace Autototp.Models;

public sealed class TotpAccount
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public string Name { get; set; } = string.Empty;

    public string Issuer { get; set; } = string.Empty;

    /// <summary>
    /// Preferred match against the foreground window title (case-insensitive contains;
    /// punctuation and extra spaces are ignored). Name and Issuer are fallbacks.
    /// </summary>
    public string WindowTitleMatch { get; set; } = string.Empty;

    /// <summary>DPAPI-protected Base32 TOTP secret (Base64 payload).</summary>
    public string EncryptedSecret { get; set; } = string.Empty;

    /// <summary>Relative filename under %AppData%\TOTPManager\logos, or an absolute image path.</summary>
    public string? LogoFileName { get; set; }

    public int Digits { get; set; } = 6;

    public int Period { get; set; } = 30;

    public string Algorithm { get; set; } = "SHA1";
}
