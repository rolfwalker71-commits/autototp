namespace Autototp.Models;

public sealed class AppSettings
{
    public bool StartMinimized { get; set; }

    public bool SendEnterAfterCode { get; set; } = true;

    public string HotkeyModifiers { get; set; } = "Control,Alt";

    public string HotkeyKey { get; set; } = "T";

    /// <summary>
    /// Prepared for a future optional master password.
    /// Default remains transparent DPAPI (current Windows user).
    /// </summary>
    public MasterPasswordSettings MasterPassword { get; set; } = new();
}

public sealed class MasterPasswordSettings
{
    public bool Enabled { get; set; }

    public string Kdf { get; set; } = "PBKDF2-SHA256";

    public int Iterations { get; set; } = 200_000;

    public string? SaltBase64 { get; set; }

    /// <summary>Reserved verifier so a future password can be checked without storing it.</summary>
    public string? VerifierBase64 { get; set; }
}
