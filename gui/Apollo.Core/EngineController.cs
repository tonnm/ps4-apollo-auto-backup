namespace Apollo.Core;

public sealed class EngineController(AppPaths paths) : IDisposable
{
    private HiddenProcess? monitor;
    private HiddenProcess? backup;
    public string Details { get; private set; } = "";
    public bool Monitoring => monitor?.Running == true;
    public bool ManualBackupRunning => backup?.Running == true;

    public static bool IsLocked(string root, string name)
    {
        var file = Path.Combine(root, $".{name}.lock");
        if (!File.Exists(file)) return false;
        try { using var handle = new FileStream(file, FileMode.Open, FileAccess.ReadWrite, FileShare.None); return false; }
        catch (IOException e) when ((e.HResult & 0xffff) is 32 or 33) { return true; }
    }

    public void Start(EngineConfig config)
    {
        if (Monitoring) return;
        Directory.CreateDirectory(config.BackupPath);
        if (IsLocked(config.BackupPath, "monitor")) throw new InvalidOperationException("Another monitor is running. Close its window or application before starting this one.");
        monitor?.Dispose();
        monitor = new HiddenProcess(HiddenProcess.PowerShell(Path.Combine(paths.EngineDirectory, "Monitor-PS4.ps1"), "-ConfigPath", paths.ConfigFile));
    }

    public async Task<int> BackupAsync(EngineConfig config)
    {
        if (backup != null || IsLocked(config.BackupPath, "backup")) return 12;
        // Called on the UI dispatcher. Assignment occurs before the first await; engine lock is the cross-process guard.
        backup?.Dispose();
        backup = new HiddenProcess(HiddenProcess.PowerShell(Path.Combine(paths.EngineDirectory, "Backup-PS4.ps1"), "-ConfigPath", paths.ConfigFile));
        var current = backup;
        try { var code = await current.WaitAsync(); Details = $"Manual backup exit code: {code}\n{current.Details}"; return code; }
        finally { current.Dispose(); if (backup == current) backup = null; }
    }

    public void Stop(EngineConfig? config)
    {
        if (ManualBackupRunning) throw new InvalidOperationException("A backup is running. Wait for it to finish before exiting or changing settings.");
        FileStream? gate = null;
        try
        {
            if (config != null && Directory.Exists(config.BackupPath))
                gate = new FileStream(Path.Combine(config.BackupPath, ".backup.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            if (monitor != null) { Details = monitor.Details; monitor.Dispose(); monitor = null; }
        }
        catch (IOException e) when ((e.HResult & 0xffff) is 32 or 33)
        { throw new InvalidOperationException("A backup is running. Wait for it to finish before exiting or changing settings.", e); }
        finally { gate?.Dispose(); }
    }
    public void Dispose() { monitor?.Dispose(); backup?.Dispose(); }
}
