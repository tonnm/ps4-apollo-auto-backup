using System.ComponentModel;
using System.Diagnostics;
using System.Security.Principal;
using System.Text.Json;

namespace Apollo.Core;

public sealed record StartupRequest(string Root, string GuiExe, string BackupRoot, bool StartAutomatically, string UserSid);
public sealed record StartupCommandResult(int ExitCode, string Details);

public interface IStartupTaskRunner
{
    Task<StartupCommandResult> RunAsync(AppPaths paths, string request, bool verifyOnly = false);
    Task<int> ElevateAsync(AppPaths paths, string request);
}

public sealed class StartupTaskRunner : IStartupTaskRunner
{
    public async Task<StartupCommandResult> RunAsync(AppPaths paths, string request, bool verifyOnly = false)
    {
        var args = new List<string> { "-RequestPath", request };
        if (verifyOnly) args.Add("-VerifyOnly");
        using var process = new HiddenProcess(HiddenProcess.PowerShell(paths.TaskScript, args.ToArray()));
        return new(await process.WaitAsync(), process.Details);
    }

    public static ProcessStartInfo ElevatedStart(AppPaths paths, string request)
    {
        // A short-lived WinExe helper mode, never the normal GUI/monitor lifecycle.
        var start = new ProcessStartInfo(paths.InstalledExe) { UseShellExecute = true, Verb = "runas", WorkingDirectory = paths.InstalledDirectory };
        start.ArgumentList.Add("--startup-helper"); start.ArgumentList.Add(request);
        return start;
    }

    public async Task<int> ElevateAsync(AppPaths paths, string request)
    {
        using var helper = Process.Start(ElevatedStart(paths, request)) ?? throw new InvalidOperationException("The startup authorization helper could not start.");
        await helper.WaitForExitAsync();
        return helper.ExitCode;
    }
}

public sealed class TaskIntegration(AppPaths paths, IStartupTaskRunner? runner = null)
{
    public const int ElevationRequired = 740;
    public const int WrongUser = 741;
    private readonly IStartupTaskRunner runner = runner ?? new StartupTaskRunner();
    private const string Cancelled = "Startup authorization was cancelled. You can retry in Settings. Complete the startup update to resume monitoring. Your backups were preserved.";

    public async Task ApplyAsync(EngineConfig config, bool automatically, Func<Task<bool>>? authorize = null)
    {
        var request = Path.Combine(paths.Root, ".startup-" + Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            Configuration.Write(request, new StartupRequest(paths.Root, paths.InstalledExe, config.BackupPath, automatically, WindowsIdentity.GetCurrent().User!.Value));
            var result = await runner.RunAsync(paths, request);
            if (result.ExitCode == ElevationRequired && result.Details.Trim() == "GUI_TASK_ELEVATION_REQUIRED")
            {
                if (authorize == null || !await authorize()) throw new InvalidOperationException(Cancelled);
                int code;
                try { code = await runner.ElevateAsync(paths, request); }
                catch (Win32Exception ex) when (ex.NativeErrorCode == 1223) { throw new InvalidOperationException(Cancelled, ex); }
                catch (Win32Exception ex) { throw new InvalidOperationException("Windows could not open the startup authorization prompt. Retry from Settings. Your backups were preserved.", ex); }
                if (code == WrongUser) throw new InvalidOperationException("Authorize this update with the same Windows account that owns the application. Another administrator account cannot migrate this user's startup settings.");
                if (code != 0) throw Failure(new(code, "The dedicated startup helper did not complete."));
                // A successful elevated exit alone is not proof. Re-read without changing anything.
                result = await runner.RunAsync(paths, request, verifyOnly: true);
            }
            if (result.ExitCode != 0 || result.Details.Trim() != "GUI_TASK_OK") throw Failure(result);
        }
        finally { if (File.Exists(request)) File.Delete(request); }
    }

    private static Exception Failure(StartupCommandResult result) => new InvalidOperationException(
        "Windows could not finish updating automatic startup. Retry from Settings. Your backups were preserved. See Diagnostics for details.",
        new InvalidOperationException($"Startup operation exit code: {result.ExitCode}\n{result.Details}"));

    public static void ValidateHelperRequest(AppPaths expected, string requestPath, StartupRequest request, string currentSid, string executableDirectory)
    {
        static bool Same(string a, string b) => Path.GetFullPath(a).TrimEnd('\\').Equals(Path.GetFullPath(b).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
        if (request.UserSid != currentSid) throw new UnauthorizedAccessException("The startup request belongs to another Windows user.");
        var name = Path.GetFileName(requestPath);
        if (!Same(Path.GetDirectoryName(Path.GetFullPath(requestPath))!, expected.Root) ||
            !name.StartsWith(".startup-", StringComparison.Ordinal) || !name.EndsWith(".tmp", StringComparison.Ordinal) ||
            !Guid.TryParseExact(name[9..^4], "N", out _) || !Same(request.Root, expected.Root) ||
            !Same(request.GuiExe, expected.InstalledExe) || !Same(executableDirectory, expected.InstalledDirectory))
            throw new InvalidDataException("The startup request is not for this installed application.");
        var config = new EngineConfig("127.0.0.1", 1, request.BackupRoot).Validate();
        Configuration.ValidateLocation(config, expected);
    }

    // Called before GUI creation/single-instance handling. Never starts a monitor or edits config/state.
    public static async Task<int> RunElevatedHelperAsync(string requestPath)
    {
        try
        {
            using var identity = WindowsIdentity.GetCurrent();
            if (!new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator)) return 1;
            var paths = AppPaths.Default;
            // Keep the validated request immutable until the adapter has finished reading it.
            using var requestLease = new FileStream(requestPath, FileMode.Open, FileAccess.Read, FileShare.Read);
            var request = JsonSerializer.Deserialize<StartupRequest>(requestLease) ?? throw new InvalidDataException("Empty startup request.");
            if (request.UserSid != identity.User!.Value) return WrongUser;
            ValidateHelperRequest(paths, requestPath, request, identity.User.Value, AppContext.BaseDirectory);
            using var process = new HiddenProcess(HiddenProcess.PowerShell(paths.TaskScript, "-RequestPath", requestPath, "-ElevatedRetry"));
            var code = await process.WaitAsync();
            return code == 0 && process.Details.Trim() == "GUI_TASK_OK" ? 0 : 1;
        }
        catch { return 1; }
    }
}
