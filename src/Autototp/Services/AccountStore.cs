using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using Autototp.Models;

namespace Autototp.Services;

public sealed class AccountStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    private readonly string _filePath;
    private readonly object _sync = new();

    public AccountStore()
        : this(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "TOTPManager",
            "accounts.json"))
    {
    }

    public AccountStore(string filePath)
    {
        _filePath = filePath;
        Directory.CreateDirectory(Path.GetDirectoryName(_filePath)!);
    }

    public string FilePath => _filePath;

    public string DataDirectory => Path.GetDirectoryName(_filePath)!;

    public StoredData Load()
    {
        lock (_sync)
        {
            if (!File.Exists(_filePath))
            {
                var fresh = new StoredData();
                Save(fresh);
                return fresh;
            }

            var json = File.ReadAllText(_filePath);
            return JsonSerializer.Deserialize<StoredData>(json, JsonOptions) ?? new StoredData();
        }
    }

    public void Save(StoredData data)
    {
        lock (_sync)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_filePath)!);
            var json = JsonSerializer.Serialize(data, JsonOptions);
            var temp = _filePath + ".tmp";
            File.WriteAllText(temp, json);
            File.Copy(temp, _filePath, overwrite: true);
            File.Delete(temp);
        }
    }
}
