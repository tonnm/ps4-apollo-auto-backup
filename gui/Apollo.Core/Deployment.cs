using System.Security.Cryptography;

namespace Apollo.Core;

public sealed record PackageFile(string Path, string Sha256);
public static class Deployment
{
    public static string SafePath(string root, string relative)
    {
        if (Path.IsPathRooted(relative)) throw new InvalidDataException("Invalid package path.");
        var full = Path.GetFullPath(Path.Combine(root, relative));
        if (!full.StartsWith(Path.GetFullPath(root).TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Package path escapes its directory.");
        return full;
    }

    public static void Install(AppPaths paths)
    {
        var files = Configuration.Read<PackageFile[]>(Path.Combine(paths.Bundle, "package-manifest.json"));
        if (!files.Any(f => f.Path == "PS4ApolloAutoBackup.exe") || !files.Any(f => f.Path == "Engine/Backup-PS4.ps1"))
            throw new InvalidDataException("The release package is incomplete. Extract the full ZIP before opening the application.");
        // Check every source BEFORE copying. Never enumerate or copy runtime/user data.
        foreach (var item in files)
        {
            var source = SafePath(paths.Bundle, item.Path);
            _ = SafePath(paths.InstalledDirectory, item.Path);
            using var stream = File.OpenRead(source);
            if (!Convert.ToHexString(SHA256.HashData(stream)).Equals(item.Sha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("The release package failed its integrity check. Extract a fresh copy.");
        }
        foreach (var item in files)
        {
            var destination = SafePath(paths.InstalledDirectory, item.Path);
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            if (File.Exists(destination))
            {
                using var current = File.OpenRead(destination);
                if (Convert.ToHexString(SHA256.HashData(current)).Equals(item.Sha256, StringComparison.OrdinalIgnoreCase)) continue;
            }
            var temp = destination + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                File.Copy(SafePath(paths.Bundle, item.Path), temp);
                if (File.Exists(destination)) File.Replace(temp, destination, null); else File.Move(temp, destination);
            }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
        Configuration.Write(Path.Combine(paths.InstalledDirectory, "package-manifest.json"), files);
        // No writes to config.json, state, backup directories or the existing v1.0 src folder.
    }
}
