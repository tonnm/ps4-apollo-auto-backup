using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Apollo.Core;

internal static class StartupIntegrationTests
{
    private sealed class Runner(params StartupCommandResult[] results) : IStartupTaskRunner
    {
        private readonly Queue<StartupCommandResult> pending = new(results);
        public readonly List<bool> Verification = new();
        public int Elevations;
        public int HelperExit;
        public Exception? HelperException;
        public Task<StartupCommandResult> RunAsync(AppPaths paths, string request, bool verifyOnly = false)
        {
            if (!File.Exists(request)) throw new Exception("Request must exist until the helper/verification finishes.");
            Verification.Add(verifyOnly);
            return Task.FromResult(pending.Dequeue());
        }
        public Task<int> ElevateAsync(AppPaths paths, string request)
        {
            Elevations++;
            return HelperException != null ? Task.FromException<int>(HelperException) : Task.FromResult(HelperExit);
        }
    }

    private static async Task<Exception> Failure(Func<Task> action)
    {
        try { await action(); } catch (Exception ex) { return ex; }
        throw new Exception("Expected startup authorization failure.");
    }

    public static async Task RunAsync(string work, Action<bool, string> check)
    {
        var paths = new AppPaths(Path.Combine(work, "startup-app"), work);
        var config = new EngineConfig("127.0.0.1", 1, Path.Combine(work, "startup-saves"));
        Configuration.Write(paths.ConfigFile, config);
        var configBytes = File.ReadAllBytes(paths.ConfigFile);
        var ok = new StartupCommandResult(0, "GUI_TASK_OK");
        var denied = new StartupCommandResult(740, "GUI_TASK_ELEVATION_REQUIRED");
        var consent = 0;
        Task<bool> Authorize() { consent++; return Task.FromResult(true); }

        var normal = new Runner(ok);
        await new TaskIntegration(paths, normal).ApplyAsync(config, true, Authorize);
        check(normal.Elevations == 0 && consent == 0, "ordinary startup never requests UAC");
        var migrated = new Runner(denied, ok);
        await new TaskIntegration(paths, migrated).ApplyAsync(config, true, Authorize);
        check(consent == 1 && migrated.Elevations == 1 && migrated.Verification.SequenceEqual(new[] { false, true }), "recognized permission denial authorizes one helper then verifies without elevation");

        var declined = new Runner(denied);
        var error = await Failure(() => new TaskIntegration(paths, declined).ApplyAsync(config, true, () => Task.FromResult(false)));
        check(declined.Elevations == 0 && error.Message.Contains("cancelled"), "declining explanation performs no elevation");
        var cancelled = new Runner(denied) { HelperException = new Win32Exception(1223) };
        error = await Failure(() => new TaskIntegration(paths, cancelled).ApplyAsync(config, true, Authorize));
        check(cancelled.Elevations == 1 && cancelled.Verification.Count == 1 && error.Message.Contains("cancelled") && !error.Message.Contains("Access denied"), "UAC cancellation is friendly and never retries or claims success");
        var blocked = new Runner(denied) { HelperException = new Win32Exception(5) };
        error = await Failure(() => new TaskIntegration(paths, blocked).ApplyAsync(config, true, Authorize));
        check(error.Message.Contains("could not open") && !error.Message.Contains("Access denied"), "policy refusal to open UAC also has a friendly message");

        var broken = new Runner(denied) { HelperExit = 1 };
        error = await Failure(() => new TaskIntegration(paths, broken).ApplyAsync(config, true, Authorize));
        check(broken.Elevations == 1 && error.Message.Contains("Retry from Settings") && !error.Message.Contains("Task Scheduler"), "failed elevated helper returns useful recovery guidance without an elevation loop");
        var wrongUser = new Runner(denied) { HelperExit = TaskIntegration.WrongUser };
        error = await Failure(() => new TaskIntegration(paths, wrongUser).ApplyAsync(config, true, Authorize));
        check(error.Message.Contains("same Windows account"), "alternate administrator identity is rejected rather than migrating the wrong user's task");
        var falseSuccess = new Runner(denied, new(1, "Stored action was not updated"));
        error = await Failure(() => new TaskIntegration(paths, falseSuccess).ApplyAsync(config, true, Authorize));
        check(falseSuccess.Elevations == 1 && falseSuccess.Verification.Last() && error.InnerException != null, "helper exit zero cannot bypass stored-task verification");
        var unauthorized = new Runner(new StartupCommandResult(1, "Access denied: unrelated task"));
        error = await Failure(() => new TaskIntegration(paths, unauthorized).ApplyAsync(config, true, Authorize));
        check(unauthorized.Elevations == 0 && !error.Message.Contains("Access denied") && error.InnerException!.Message.Contains("Access denied"), "ordinary errors stay unelevated and raw details are restricted to diagnostics");
        var badMarker = new Runner(new StartupCommandResult(740, "unexpected response"));
        await Failure(() => new TaskIntegration(paths, badMarker).ApplyAsync(config, true, Authorize));
        check(badMarker.Elevations == 0, "elevation requires both the dedicated code and adapter marker");
        check(!Directory.EnumerateFiles(paths.Root, ".startup-*.tmp").Any() && File.ReadAllBytes(paths.ConfigFile).SequenceEqual(configBytes), "success and cancellation clean requests while preserving configuration bytes");

        var requestPath = Path.Combine(paths.Root, ".startup-" + Guid.NewGuid().ToString("N") + ".tmp");
        var request = new StartupRequest(paths.Root, paths.InstalledExe, config.BackupPath, true, "test-user");
        TaskIntegration.ValidateHelperRequest(paths, requestPath, request, "test-user", paths.InstalledDirectory);
        check(true, "helper accepts only its installed application request");
        foreach (var invalid in new[] { request with { UserSid = "another-user" }, request with { Root = work }, request with { GuiExe = "C:\\unrelated.exe" }, request with { BackupRoot = paths.Root } })
        {
            error = await Failure(() => { TaskIntegration.ValidateHelperRequest(paths, requestPath, invalid, "test-user", paths.InstalledDirectory); return Task.CompletedTask; });
            check(error is InvalidDataException or UnauthorizedAccessException, "helper rejects mismatched identity, installation, action or data location");
        }
        await Failure(() => { TaskIntegration.ValidateHelperRequest(paths, Path.Combine(work, Path.GetFileName(requestPath)), request, "test-user", paths.InstalledDirectory); return Task.CompletedTask; });
        check(true, "helper rejects requests outside its installation root");
        await Failure(() => { TaskIntegration.ValidateHelperRequest(paths, requestPath, request, "test-user", work); return Task.CompletedTask; });
        check(true, "helper cannot run from an arbitrary extracted executable location");
        var start = StartupTaskRunner.ElevatedStart(paths, requestPath);
        check(start.UseShellExecute && start.Verb == "runas" && start.FileName == paths.InstalledExe &&
            start.ArgumentList.SequenceEqual(new[] { "--startup-helper", requestPath }), "UAC launches only dedicated WinExe helper mode, never background GUI or engine");

        // Missing arguments must exit before deployment, tray, GUI lease or scheduler access.
        var probe = new ProcessStartInfo(Path.Combine(AppContext.BaseDirectory, "PS4ApolloAutoBackup.exe"))
        { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        probe.ArgumentList.Add("--startup-helper");
        using var helper = new HiddenProcess(probe);
        check(await helper.WaitAsync().WaitAsync(TimeSpan.FromSeconds(10)) == 1,
            "WINDOWS REAL: helper-only entry point exits on invalid arguments without opening the GUI or touching startup");
    }
}
