using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Apollo.Core;

public sealed record EngineConfig(
    [property: JsonPropertyName("ps4Address")] string Address,
    [property: JsonPropertyName("apolloPort")] int Port,
    [property: JsonPropertyName("backupPath")] string BackupPath)
{
    public EngineConfig Validate()
    {
        if (string.IsNullOrWhiteSpace(Address) || Address.Split('.').Length != 4 ||
            !IPAddress.TryParse(Address, out var ip) || ip.AddressFamily != AddressFamily.InterNetwork)
            throw new InvalidDataException("Enter a valid PS4 IPv4 address, such as the address shown in your console's network settings.");
        if (Port is < 1 or > 65535) throw new InvalidDataException("Apollo port must be between 1 and 65535.");
        var folder = Environment.ExpandEnvironmentVariables(BackupPath ?? "");
        if (folder.Length < 4 || !char.IsAsciiLetter(folder[0]) || folder[1] != ':' || folder[2] != '\\' ||
            folder[2..].IndexOfAny(['<', '>', '"', '|', '?', '*', '%', ':']) >= 0)
            throw new InvalidDataException("Choose a dedicated local backup folder, not a drive root or network share.");
        folder = Path.GetFullPath(folder).TrimEnd('\\');
        if (folder.Length < 4) throw new InvalidDataException("Choose a dedicated backup folder, not a drive root.");
        return this with { Address = ip.ToString(), BackupPath = folder };
    }
}

public sealed record GuiPreferences(bool StartAutomatically = true, bool Notifications = true, bool StartMinimized = false);

public sealed record AppPaths(string Root, string Bundle)
{
    public const string Version = "1.1.0";
    public const string EngineVersion = "1.0.0";
    public string ConfigFile => Path.Combine(Root, "config.json");
    public string PreferencesFile => Path.Combine(Root, "gui-settings.json");
    public string InstalledDirectory => Path.Combine(Root, "gui", Version);
    public string InstalledExe => Path.Combine(InstalledDirectory, "PS4ApolloAutoBackup.exe");
    public string EngineDirectory => Path.Combine(Bundle, "Engine");
    public string TaskScript => Path.Combine(Bundle, "Integration", "Configure-GuiTask.ps1");
    public static AppPaths Default => new(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PS4ApolloAutoBackup"), AppContext.BaseDirectory);
}

public static class Configuration
{
    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true, PropertyNameCaseInsensitive = true };
    public static T Read<T>(string file) => JsonSerializer.Deserialize<T>(File.ReadAllText(file), Options) ?? throw new InvalidDataException("The settings file is empty.");
    public static void Write<T>(string file, T value)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        var temp = file + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temp, JsonSerializer.Serialize(value, Options));
            if (File.Exists(file)) File.Replace(temp, file, null);
            else File.Move(temp, file);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }

    public static void ValidateLocation(EngineConfig config, AppPaths paths)
    {
        var root = Path.GetFullPath(paths.Root).TrimEnd('\\');
        if (config.BackupPath.Equals(root, StringComparison.OrdinalIgnoreCase) ||
            config.BackupPath.StartsWith(root + "\\", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Keep your backups outside the application installation folder.");
    }

    public static async Task<bool> TestConnectionAsync(EngineConfig config)
    {
        using var client = new TcpClient();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(2));
        try { await client.ConnectAsync(config.Address, config.Port, timeout.Token); return true; }
        catch (Exception e) when (e is SocketException or OperationCanceledException) { return false; }
    }
}
