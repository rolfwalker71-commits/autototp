using System.Security.Cryptography;
using System.Text;
using Autototp.Models;

namespace Autototp.Services;

/// <summary>
/// Protects TOTP secrets with Windows DPAPI (current user).
/// Master-password fields exist on <see cref="MasterPasswordSettings"/> for a later AES layer.
/// </summary>
public sealed class EncryptionService
{
    private static readonly byte[] AppEntropy = Encoding.UTF8.GetBytes("Autototp.TOTPManager.v1");

    public string ProtectSecret(string plaintext, MasterPasswordSettings? masterPassword = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(plaintext);
        var entropy = BuildEntropy(masterPassword);
        var protectedBytes = ProtectedData.Protect(
            Encoding.UTF8.GetBytes(plaintext.Trim()),
            entropy,
            DataProtectionScope.CurrentUser);
        return Convert.ToBase64String(protectedBytes);
    }

    public string UnprotectSecret(string protectedBase64, MasterPasswordSettings? masterPassword = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(protectedBase64);
        var entropy = BuildEntropy(masterPassword);
        var raw = ProtectedData.Unprotect(
            Convert.FromBase64String(protectedBase64),
            entropy,
            DataProtectionScope.CurrentUser);
        return Encoding.UTF8.GetString(raw);
    }

    public bool TryUnprotectSecret(string protectedBase64, MasterPasswordSettings? masterPassword, out string secret)
    {
        try
        {
            secret = UnprotectSecret(protectedBase64, masterPassword);
            return true;
        }
        catch (CryptographicException)
        {
            secret = string.Empty;
            return false;
        }
        catch (FormatException)
        {
            secret = string.Empty;
            return false;
        }
    }

    private static byte[] BuildEntropy(MasterPasswordSettings? masterPassword)
    {
        if (masterPassword is not { Enabled: true } || string.IsNullOrEmpty(masterPassword.SaltBase64))
        {
            return AppEntropy;
        }

        // Placeholder: when a master password is enabled later, mix its salt into DPAPI entropy.
        var salt = Convert.FromBase64String(masterPassword.SaltBase64);
        var mixed = new byte[AppEntropy.Length + salt.Length];
        Buffer.BlockCopy(AppEntropy, 0, mixed, 0, AppEntropy.Length);
        Buffer.BlockCopy(salt, 0, mixed, AppEntropy.Length, salt.Length);
        return mixed;
    }
}
