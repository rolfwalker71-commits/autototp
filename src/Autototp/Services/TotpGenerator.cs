using System.Text;
using OtpNet;

namespace Autototp.Services;

public static class TotpGenerator
{
    public static string NormalizeSecret(string secret)
    {
        if (string.IsNullOrWhiteSpace(secret))
        {
            return string.Empty;
        }

        var builder = new StringBuilder(secret.Length);
        foreach (var ch in secret)
        {
            if (char.IsWhiteSpace(ch) || ch == '-')
            {
                continue;
            }

            builder.Append(char.ToUpperInvariant(ch));
        }

        return builder.ToString();
    }

    public static bool TryValidateSecret(string secret, out string error)
    {
        var normalized = NormalizeSecret(secret);
        if (normalized.Length < 8)
        {
            error = "Das Secret ist zu kurz.";
            return false;
        }

        try
        {
            _ = Base32Encoding.ToBytes(normalized);
            error = string.Empty;
            return true;
        }
        catch (Exception)
        {
            error = "Das Secret ist kein gültiges Base32.";
            return false;
        }
    }

    public static string ComputeCode(string secret, int digits = 6, int period = 30, string algorithm = "SHA1")
    {
        var totp = CreateTotp(secret, digits, period, algorithm);
        return totp.ComputeTotp();
    }

    public static int RemainingSeconds(int period = 30)
    {
        var step = period <= 0 ? 30 : period;
        var unix = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var elapsed = (int)(unix % step);
        return step - elapsed;
    }

    public static double Progress(int period = 30)
    {
        var step = period <= 0 ? 30 : period;
        return RemainingSeconds(step) / (double)step;
    }

    public static Totp CreateTotp(string secret, int digits = 6, int period = 30, string algorithm = "SHA1")
    {
        var key = Base32Encoding.ToBytes(NormalizeSecret(secret));
        var mode = ParseMode(algorithm);
        var size = digits is >= 6 and <= 8 ? digits : 6;
        var step = period <= 0 ? 30 : period;
        return new Totp(key, step, mode, size);
    }

    private static OtpHashMode ParseMode(string algorithm) =>
        algorithm.ToUpperInvariant() switch
        {
            "SHA256" => OtpHashMode.Sha256,
            "SHA512" => OtpHashMode.Sha512,
            _ => OtpHashMode.Sha1,
        };
}
