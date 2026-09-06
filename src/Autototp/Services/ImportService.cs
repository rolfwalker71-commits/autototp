using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Autototp.Models;

namespace Autototp.Services;

public sealed class ImportedAccount : System.ComponentModel.INotifyPropertyChanged
{
    private bool _isSelected = true;
    private string _windowTitleMatch = string.Empty;

    public string Name { get; init; } = string.Empty;
    public string Issuer { get; init; } = string.Empty;
    public string Secret { get; init; } = string.Empty;
    public int Digits { get; init; } = 6;
    public int Period { get; init; } = 30;
    public string Algorithm { get; init; } = "SHA1";

    public string WindowTitleMatch
    {
        get => _windowTitleMatch;
        set
        {
            if (_windowTitleMatch == value)
            {
                return;
            }

            _windowTitleMatch = value;
            PropertyChanged?.Invoke(this, new System.ComponentModel.PropertyChangedEventArgs(nameof(WindowTitleMatch)));
        }
    }

    public bool IsSelected
    {
        get => _isSelected;
        set
        {
            if (_isSelected == value)
            {
                return;
            }

            _isSelected = value;
            PropertyChanged?.Invoke(this, new System.ComponentModel.PropertyChangedEventArgs(nameof(IsSelected)));
        }
    }

    public event System.ComponentModel.PropertyChangedEventHandler? PropertyChanged;
}

public sealed class ImportResult
{
    public List<ImportedAccount> Accounts { get; init; } = [];
    public List<string> Warnings { get; init; } = [];
}

public sealed class ImportService
{
    public ImportResult ParseOtpAuthText(string text)
    {
        var result = new ImportResult();
        if (string.IsNullOrWhiteSpace(text))
        {
            result.Warnings.Add("Keine otpauth:// URIs gefunden.");
            return result;
        }

        foreach (var rawLine in text.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries))
        {
            var line = rawLine.Trim();
            if (line.Length == 0 || line.StartsWith('#'))
            {
                continue;
            }

            if (!line.StartsWith("otpauth://", StringComparison.OrdinalIgnoreCase))
            {
                result.Warnings.Add($"Übersprungen (kein otpauth://): {TrimForDisplay(line)}");
                continue;
            }

            if (TryParseOtpAuthUri(line, out var account, out var warning))
            {
                result.Accounts.Add(account);
            }
            else if (!string.IsNullOrEmpty(warning))
            {
                result.Warnings.Add(warning);
            }
        }

        if (result.Accounts.Count == 0 && result.Warnings.Count == 0)
        {
            result.Warnings.Add("Keine importierbaren TOTP-Einträge gefunden.");
        }

        return result;
    }

    public ImportResult Parse2FasFile(string path, string? password = null)
    {
        var json = File.ReadAllText(path);
        return Parse2FasJson(json, password);
    }

    public ImportResult Parse2FasJson(string json, string? password = null)
    {
        var result = new ImportResult();
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;

        JsonElement services = default;
        var hasServices = root.TryGetProperty("services", out services)
            && services.ValueKind == JsonValueKind.Array
            && services.GetArrayLength() > 0;

        if (!hasServices
            && root.TryGetProperty("servicesEncrypted", out var encrypted)
            && encrypted.ValueKind == JsonValueKind.String
            && !string.IsNullOrWhiteSpace(encrypted.GetString()))
        {
            if (string.IsNullOrWhiteSpace(password))
            {
                throw new InvalidOperationException(
                    "Diese 2FAS-Sicherung ist passwortgeschützt. Bitte das Backup-Passwort eingeben.");
            }

            var decrypted = Decrypt2FasServices(encrypted.GetString()!, password);
            using var inner = JsonDocument.Parse(decrypted);
            if (inner.RootElement.ValueKind != JsonValueKind.Array)
            {
                throw new InvalidOperationException("Das entschlüsselte 2FAS-Backup hat ein unerwartetes Format.");
            }

            services = inner.RootElement.Clone();
            hasServices = true;
        }

        if (!hasServices)
        {
            result.Warnings.Add("Die 2FAS-Datei enthält keine Services.");
            return result;
        }

        foreach (var service in services.EnumerateArray())
        {
            if (TryMap2FasService(service, out var account, out var warning))
            {
                result.Accounts.Add(account);
            }
            else if (!string.IsNullOrEmpty(warning))
            {
                result.Warnings.Add(warning);
            }
        }

        return result;
    }

    public bool TryParseOtpAuthUri(string uri, out ImportedAccount account, out string warning)
    {
        account = new ImportedAccount();
        warning = string.Empty;

        if (!Uri.TryCreate(uri, UriKind.Absolute, out var parsed)
            || !parsed.Scheme.Equals("otpauth", StringComparison.OrdinalIgnoreCase))
        {
            warning = "Ungültige otpauth:// URI.";
            return false;
        }

        var type = parsed.Host;
        if (!type.Equals("totp", StringComparison.OrdinalIgnoreCase))
        {
            warning = $"Übersprungen ({type}, nur TOTP wird unterstützt): {TrimForDisplay(uri)}";
            return false;
        }

        var query = ParseQuery(parsed.Query);
        if (!query.TryGetValue("secret", out var secret) || string.IsNullOrWhiteSpace(secret))
        {
            warning = "otpauth:// URI ohne Secret.";
            return false;
        }

        secret = TotpGenerator.NormalizeSecret(secret);
        if (!TotpGenerator.TryValidateSecret(secret, out _))
        {
            warning = $"Ungültiges Secret in URI: {TrimForDisplay(uri)}";
            return false;
        }

        var label = Uri.UnescapeDataString(parsed.AbsolutePath.Trim('/'));
        var issuerFromQuery = query.GetValueOrDefault("issuer");
        SplitLabel(label, out var labelIssuer, out var labelAccount);

        var issuer = FirstNonEmpty(issuerFromQuery, labelIssuer);
        var name = FirstNonEmpty(labelAccount, label, issuer, "Account");

        account = new ImportedAccount
        {
            Name = name,
            Issuer = issuer,
            Secret = secret,
            WindowTitleMatch = issuer,
            Digits = ParseInt(query.GetValueOrDefault("digits"), 6),
            Period = ParseInt(query.GetValueOrDefault("period"), 30),
            Algorithm = (query.GetValueOrDefault("algorithm") ?? "SHA1").ToUpperInvariant(),
        };
        return true;
    }

    private static bool TryMap2FasService(JsonElement service, out ImportedAccount account, out string warning)
    {
        account = new ImportedAccount();
        warning = string.Empty;

        var otp = service.TryGetProperty("otp", out var otpEl) ? otpEl : default;
        var tokenType = ReadString(otp, "tokenType");
        if (!string.IsNullOrEmpty(tokenType) && !tokenType.Equals("TOTP", StringComparison.OrdinalIgnoreCase))
        {
            warning = $"Übersprungen ({tokenType}): {ReadString(service, "name")}";
            return false;
        }

        var secret = TotpGenerator.NormalizeSecret(ReadString(service, "secret"));
        if (!TotpGenerator.TryValidateSecret(secret, out _))
        {
            warning = $"Ungültiges Secret: {ReadString(service, "name")}";
            return false;
        }

        var name = FirstNonEmpty(
            ReadString(service, "name"),
            ReadString(otp, "account"),
            ReadString(otp, "issuer"),
            "Account");
        var issuer = FirstNonEmpty(ReadString(otp, "issuer"), name);

        account = new ImportedAccount
        {
            Name = name,
            Issuer = issuer,
            Secret = secret,
            WindowTitleMatch = issuer,
            Digits = ReadInt(otp, "digits", 6),
            Period = ReadInt(otp, "period", 30),
            Algorithm = FirstNonEmpty(ReadString(otp, "algorithm"), "SHA1").ToUpperInvariant(),
        };
        return true;
    }

    private static string Decrypt2FasServices(string servicesEncrypted, string password)
    {
        var parts = servicesEncrypted.Split(':');
        if (parts.Length < 3)
        {
            throw new InvalidOperationException("Das verschlüsselte 2FAS-Format wird nicht erkannt.");
        }

        var cipher = Convert.FromBase64String(parts[0]);
        var salt = Convert.FromBase64String(parts[1]);
        var iv = Convert.FromBase64String(parts[2]);

        using var kdf = new Rfc2898DeriveBytes(password, salt, 10_000, HashAlgorithmName.SHA256);
        var key = kdf.GetBytes(32);

        using var aes = Aes.Create();
        aes.Key = key;
        aes.IV = iv;
        aes.Mode = CipherMode.CBC;
        aes.Padding = PaddingMode.PKCS7;

        using var decryptor = aes.CreateDecryptor();
        var plain = decryptor.TransformFinalBlock(cipher, 0, cipher.Length);
        return Encoding.UTF8.GetString(plain);
    }

    private static Dictionary<string, string> ParseQuery(string query)
    {
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (string.IsNullOrEmpty(query))
        {
            return map;
        }

        var trimmed = query.StartsWith('?') ? query[1..] : query;
        foreach (var pair in trimmed.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var idx = pair.IndexOf('=');
            if (idx < 0)
            {
                continue;
            }

            var key = Uri.UnescapeDataString(pair[..idx]);
            var value = Uri.UnescapeDataString(pair[(idx + 1)..]);
            map[key] = value;
        }

        return map;
    }

    private static void SplitLabel(string label, out string issuer, out string account)
    {
        issuer = string.Empty;
        account = label;
        var idx = label.IndexOf(':');
        if (idx > 0)
        {
            issuer = label[..idx];
            account = label[(idx + 1)..];
        }
    }

    private static string ReadString(JsonElement element, string name)
    {
        if (element.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null)
        {
            return string.Empty;
        }

        return element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString() ?? string.Empty
            : string.Empty;
    }

    private static int ReadInt(JsonElement element, string name, int fallback)
    {
        if (element.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null)
        {
            return fallback;
        }

        if (!element.TryGetProperty(name, out var value))
        {
            return fallback;
        }

        return value.ValueKind switch
        {
            JsonValueKind.Number when value.TryGetInt32(out var n) => n,
            JsonValueKind.String when int.TryParse(value.GetString(), out var n) => n,
            _ => fallback,
        };
    }

    private static int ParseInt(string? text, int fallback) =>
        int.TryParse(text, out var n) ? n : fallback;

    private static string FirstNonEmpty(params string?[] values) =>
        values.FirstOrDefault(v => !string.IsNullOrWhiteSpace(v))?.Trim() ?? string.Empty;

    private static string TrimForDisplay(string text) =>
        text.Length <= 48 ? text : text[..45] + "...";
}
