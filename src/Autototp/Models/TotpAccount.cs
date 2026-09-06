namespace Autototp.Models;

public sealed class TotpAccount
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public string Name { get; set; } = string.Empty;

    public string Issuer { get; set; } = string.Empty;

    /// <summary>Case-insensitive substring matched against the foreground window title.</summary>
    public string WindowTitleMatch { get; set; } = string.Empty;

    /// <summary>DPAPI-protected Base32 TOTP secret (Base64 payload).</summary>
    public string EncryptedSecret { get; set; } = string.Empty;

    public int Digits { get; set; } = 6;

    public int Period { get; set; } = 30;

    public string Algorithm { get; set; } = "SHA1";
}
