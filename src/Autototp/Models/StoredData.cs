namespace Autototp.Models;

public sealed class StoredData
{
    public int Version { get; set; } = 1;

    public AppSettings Settings { get; set; } = new();

    public List<TotpAccount> Accounts { get; set; } = [];
}
