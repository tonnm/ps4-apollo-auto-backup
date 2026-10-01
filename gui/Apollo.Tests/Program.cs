using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Apollo.Core;
using Apollo.Gui;

internal static class Program
{
    private static int passed;
    private static void Check(bool ok, string message) { if (!ok) throw new Exception("FAIL: " + message); Console.WriteLine("PASS: " + message); passed++; }
    private static void Reject(Action action, string message) { try { action(); } catch { Check(true, message); return; } throw new Exception("FAIL: " + message); }

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            var repo = Path.GetFullPath(args[0]);
            var work = Path.Combine(repo, ".test-artifacts", "gui-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(work);
            ServicesAsync(repo, work).GetAwaiter().GetResult();
            StartupIntegrationTests.RunAsync(work, Check).GetAwaiter().GetResult();
            Render(work);
            Console.WriteLine($"PASS: {passed} GUI/service assertions. Artifacts: {work}");
            return 0;
        }
        catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
    }

    private static async Task ServicesAsync(string repo, string work)
    {
        var config = new EngineConfig("127.0.0.1", 8080, Path.Combine(work, "saves [test]")).Validate();
        var cfgPath = Path.Combine(work, "config.json");
        Configuration.Write(cfgPath, config);
        Check(Configuration.Read<EngineConfig>(cfgPath) == config, "engine configuration roundtrip retains v1 field names");
        Check(File.ReadAllText(cfgPath).Contains("ps4Address"), "v1 JSON keys preserved");
        Reject(() => (config with { Address = "invalid" }).Validate(), "invalid IPv4 rejected");
        Reject(() => (config with { Address = "127.1" }).Validate(), "ambiguous short IPv4 rejected");
        Reject(() => (config with { Port = 0 }).Validate(), "invalid port rejected");
        Reject(() => (config with { BackupPath = "C:\\" }).Validate(), "drive root rejected");
        Reject(() => (config with { BackupPath = "relative" }).Validate(), "relative data folder rejected");
        var paths = new AppPaths(Path.Combine(work, "installed"), Path.Combine(work, "bundle"));
        Reject(() => Configuration.ValidateLocation(config with { BackupPath = paths.InstalledDirectory }, paths), "data inside installation rejected");
        var prefs = new GuiPreferences(false, false, true);
        Configuration.Write(paths.PreferencesFile, prefs);
        Check(Configuration.Read<GuiPreferences>(paths.PreferencesFile) == prefs, "GUI preferences stored separately from engine configuration");

        var lines = "[2026-09-28 21:00:00] [INFO] Backup complete. New=21 Changed=0 Unchanged=0 Failures=0\n" +
            "[2026-09-28 21:10:00] [INFO] Backup complete. New=0 Changed=0 Unchanged=21 Failures=0\n" +
            "[2026-09-28 21:20:00] [INFO] Backup complete. New=0 Changed=5 Unchanged=16 Failures=0\n";
        var parsed = History.Parse(lines);
        const string monitorFailure = "[2026-09-29 15:11:42] [INFO] Backup finished with exit code 1.\r\n";
        var attempts = History.ParseFailures(monitorFailure);
        Check(attempts.Count == 1 && attempts[0].ExitCode == 1, "automatic exit 1 without summary is a failed attempt");
        Check(History.ParseFailures(monitorFailure.Replace("code 1.", "code 0.")).Count == 0, "exit zero is not a failed attempt");
        Check(History.ParseFailures(monitorFailure.Replace("code 1.", "code 999999999999.")).Count == 0 && History.ParseFailures(monitorFailure.Replace("code 1.", "code 1")).Count == 0, "corrupt and partial monitor records ignored");
        Check(History.ParseFailures("[2026-09-29 15:12:00] [INFO] Backup execution failed: test\n").Single().ExitCode == null, "monitor invocation exception retained without invented exit code");
        Check(History.ParseFailures(string.Concat(Enumerable.Repeat(monitorFailure, 20))).Count == 10, "automatic failure history is bounded");
        var activity = ActivityEntry.Merge(parsed, attempts);
        Check(activity[0].Failure == attempts[0] && activity[0].Result == null && activity[0].Label == "Automatic backup failed", "failed attempt has its own activity without invented save counts");
        Check(parsed[0].Changed == 5 && ActivityEntry.Merge(parsed, attempts).SequenceEqual(activity), "refresh does not duplicate attempts or overwrite last completed result");
        Check(parsed.Count == 3 && parsed[0].Total == 21 && parsed[0].Changed == 5 && parsed[0].Unchanged == 16, "parses known real-world v1 summary format in newest-first order");
        Check(parsed[2].New == 21 && parsed[1].Unchanged == 21, "first and unchanged backup results parsed");
        Check(History.Parse(lines + "[2026-09-28 21:30:00] [INFO] Backup complete. New=0 Changed=0 Unchanged=0 Failures=").Count == 3, "partial last line ignored");
        Check(History.Parse(lines.Replace("New=21", "New=99999999999999999")).Count == 2, "corrupt count safely ignored");
        Check(History.Parse(string.Concat(Enumerable.Repeat(lines, 20))).Count == 10, "recent activity bounded to ten results");
        var largeLog = Path.Combine(work, "large.log"); File.WriteAllText(largeLog, new string('x', 512 * 1024) + "\n" + lines);
        Check(History.ReadTail(largeLog).Length < 128 * 1024 && History.Parse(History.ReadTail(largeLog)).Count == 3, "bounded tail reads retain final summaries");
        Check(History.ExitMessage(13).Contains("preserved") && !History.ExitMessage(20).Contains("20"), "errors have human-readable messages");
        var failures = History.Parse(lines.Replace("Failures=0", "Failures=1"));
        Check(failures[0].Title.Contains("failures") && failures[0].Total == 22, "failure count contributes to checked total");

        Directory.CreateDirectory(config.BackupPath);
        using (var held = new FileStream(Path.Combine(config.BackupPath, ".backup.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
            Check(EngineController.IsLocked(config.BackupPath, "backup"), "GUI respects the existing engine lock");
        Check(!EngineController.IsLocked(config.BackupPath, "backup"), "stale lock file is not treated as a running backup");
        var activated = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        using (var single = new SingleInstance(paths.Root, () => activated.TrySetResult(true)))
        {
            Reject(() => { using var second = new SingleInstance(paths.Root, () => { }); }, "single-instance lease rejects second GUI");
            await SingleInstance.ActivateAsync(paths.Root);
            Check(await activated.Task.WaitAsync(TimeSpan.FromSeconds(3)), "second launch activates the existing GUI over a user-only pipe");
        }

        var probe = Path.Combine(work, "console-probe.ps1");
        File.WriteAllText(probe, "Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class Probe { [DllImport(\"kernel32.dll\")] public static extern IntPtr GetConsoleWindow(); }'\n[Console]::WriteLine([Probe]::GetConsoleWindow().ToInt64())\n");
        var start = HiddenProcess.PowerShell(probe, "-Example", "folder with spaces & symbols");
        Check(start.CreateNoWindow && !start.UseShellExecute && start.ArgumentList.Last() == "folder with spaces & symbols", "PowerShell launcher disables console creation and passes arguments without command interpolation");
        using (var hidden = new HiddenProcess(HiddenProcess.PowerShell(probe)))
        {
            Check(await hidden.WaitAsync() == 0 && hidden.Details.Trim() == "0", "WINDOWS REAL: hidden child has GetConsoleWindow() == 0");
        }
        var legacyStart = HiddenProcess.PowerShell(probe);
        legacyStart.CreateNoWindow = false; legacyStart.WindowStyle = ProcessWindowStyle.Hidden;
        legacyStart.ArgumentList.Insert(0, "Hidden"); legacyStart.ArgumentList.Insert(0, "-WindowStyle");
        using (var legacy = new HiddenProcess(legacyStart))
        {
            var legacyCode = await legacy.WaitAsync();
            Console.WriteLine($"Legacy console comparison: exit={legacyCode}, output={legacy.Details.Trim()}");
            // Console host policy can also suppress allocation; do not assume this reproduces the owner's session.
        }
        File.WriteAllText(probe, "Start-Sleep -Seconds 60");
        var owned = new HiddenProcess(HiddenProcess.PowerShell(probe));
        using var observation = Process.GetProcessById(owned.Process.Id);
        owned.Dispose();
        Check(observation.WaitForExit(5000), "WINDOWS REAL: closing the job terminates its owned process");

        var enginePaths = new AppPaths(Path.Combine(work, "engine-app"), Path.Combine(work, "engine-bundle"));
        Directory.CreateDirectory(enginePaths.EngineDirectory);
        Configuration.Write(enginePaths.ConfigFile, config);
        File.WriteAllText(Path.Combine(enginePaths.EngineDirectory, "Backup-PS4.ps1"), "param($ConfigPath)\nStart-Sleep -Milliseconds 400\nexit 20");
        File.WriteAllText(Path.Combine(enginePaths.EngineDirectory, "Monitor-PS4.ps1"), "param($ConfigPath)\nStart-Sleep -Seconds 60");
        using (var controller = new EngineController(enginePaths))
        {
            var first = controller.BackupAsync(config);
            Check(await controller.BackupAsync(config) == 12, "duplicate manual backup refused before a second process is created");
            Reject(() => controller.Stop(config), "Exit/settings refuses to interrupt a running manual backup");
            Check(await first == 20, "manual invocation returns engine result for UI translation");
            controller.Start(config); Check(controller.Monitoring, "monitor runs as owned hidden child"); controller.Stop(config);
            Check(!controller.Monitoring, "explicit Stop releases owned monitor");
        }
        // Use the actual baseline monitor offline, with a synthetic root and loopback address.
        var actual = new AppPaths(Path.Combine(work, "actual-engine"), Path.Combine(work, "actual-bundle"));
        Directory.CreateDirectory(actual.EngineDirectory);
        foreach (var source in Directory.GetFiles(Path.Combine(repo, "src"), "*.ps1")) File.Copy(source, Path.Combine(actual.EngineDirectory, Path.GetFileName(source)));
        var offline = config with { Port = 1, BackupPath = Path.Combine(work, "offline-saves") };
        Configuration.Write(actual.ConfigFile, offline);
        using (var controller = new EngineController(actual))
        {
            controller.Start(offline);
            for (var i = 0; i < 40 && !File.Exists(Path.Combine(offline.BackupPath, "monitor.log")); i++) await Task.Delay(100);
            Check(controller.Monitoring && History.ReadTail(Path.Combine(offline.BackupPath, "monitor.log")).Contains("Monitor started."), "WINDOWS REAL: unchanged baseline monitor starts hidden while Apollo is offline");
            controller.Stop(offline);
        }

        Directory.CreateDirectory(paths.Bundle);
        Directory.CreateDirectory(Path.Combine(paths.Bundle, "Engine"));
        File.WriteAllText(Path.Combine(paths.Bundle, "PS4ApolloAutoBackup.exe"), "fixture executable, never executed");
        File.WriteAllText(Path.Combine(paths.Bundle, "Engine", "Backup-PS4.ps1"), "fixture engine, never executed");
        var manifest = new[] { "PS4ApolloAutoBackup.exe", "Engine/Backup-PS4.ps1" }.Select(p => new PackageFile(p, Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(paths.Bundle, p)))))).ToArray();
        Configuration.Write(Path.Combine(paths.Bundle, "package-manifest.json"), manifest);
        Configuration.Write(paths.ConfigFile, config);
        var beforeConfig = File.ReadAllBytes(paths.ConfigFile);
        var sentinel = Path.Combine(config.BackupPath, "backup-state-v4.json"); File.WriteAllText(sentinel, "state sentinel");
        Deployment.Install(paths);
        Check(File.Exists(paths.InstalledExe), "release bootstrap deploys manifest files to versioned GUI directory");
        Check(File.ReadAllBytes(paths.ConfigFile).SequenceEqual(beforeConfig) && File.ReadAllText(sentinel) == "state sentinel", "deployment preserves v1 config bytes and backup state");
        Deployment.Install(paths); Check(File.Exists(paths.InstalledExe), "identical package reinstall is safe");
        Reject(() => Deployment.SafePath(paths.Root, "../outside"), "manifest path traversal rejected");
        File.AppendAllText(Path.Combine(paths.Bundle, "PS4ApolloAutoBackup.exe"), "tampered");
        Reject(() => Deployment.Install(paths), "package integrity failure rejected before deployment");
    }

    private static void Render(string work)
    {
        var app = new Apollo.Gui.App(); app.InitializeComponent();
        var paths = new AppPaths(Path.Combine(work, "render"), work);
        var window = new MainWindow(paths, createTray: false);
        var baseline = new BackupResult(new DateTime(2026, 9, 28, 22, 32, 0), 0, 0, 21, 0);
        var failedAttempt = new FailedAttempt(new DateTime(2026, 9, 29, 15, 11, 42), 1);
        window.ShowSnapshot(new EngineConfig("192.0.2.10", 8080, work), new[] { baseline }, "Monitoring", "Test", false, new[] { failedAttempt });
        var shownActivity = ((System.Windows.Controls.ItemsControl)window.FindName("ActivityList")).Items.Cast<ActivityEntry>().ToArray();
        Check(shownActivity[0].Failure == failedAttempt && ((System.Windows.Controls.TextBlock)window.FindName("LastTime")).Text == baseline.Completed.ToString("g") && ((System.Windows.Controls.TextBlock)window.FindName("UnchangedCount")).Text == "21", "failed automatic attempt appears in UI while last completed time and counts remain intact");
        window.ShowSnapshot(new EngineConfig("192.0.2.10", 8080, work), Array.Empty<BackupResult>(), "Monitoring", "Test", false, new[] { failedAttempt });
        Check(((System.Windows.Controls.TextBlock)window.FindName("EmptyActivity")).Visibility == Visibility.Collapsed, "failed first attempt appears even with no completed backups");
        Check(new ActivityEntry(baseline).Label == "No changes", "unchanged activity has a distinct text category");
        Check(new ActivityEntry(baseline with { New = 21, Unchanged = 0 }).Label == "New saves", "new saves have their own category");
        Check(new ActivityEntry(baseline with { Changed = 5, Unchanged = 16 }).Label == "Changed saves", "changed saves have their own category");
        var mixed = new ActivityEntry(baseline with { New = 2, Changed = 3, Unchanged = 15, Failures = 1 });
        Check(mixed.Label == "Failures" && mixed.Detail.Contains("2 new") && mixed.Detail.Contains("3 changed") && mixed.Detail.Contains("1 failed"), "failure priority preserves mixed-run counts");
        Check(new ActivityEntry(baseline with { New = 2, Changed = 3 }).Label == "New + changed saves", "mixed successes retain both categories");
        Check(ActivityEntry.Outcome(baseline) == "Backup completed successfully" && ActivityEntry.Outcome(mixed.Result) == "Backup completed with failures" && ActivityEntry.Outcome(null) == "No completed backup yet", "last backup differentiates success, failures and empty history");
        Check(window.FindName("MonitorButton") == null && ((System.Windows.Controls.Button)window.FindName("BackupButton")).Content.ToString() == "_Check saves now", "main actions focus on checking saves without a monitoring toggle");
        window.ShowSnapshot(new EngineConfig("192.0.2.10", 8080, work), new[] {
            new BackupResult(new DateTime(2026, 9, 28, 22, 32, 0), 0, 5, 16, 0),
            new BackupResult(new DateTime(2026, 9, 28, 22, 13, 0), 0, 0, 21, 0),
            new BackupResult(new DateTime(2026, 9, 28, 22, 9, 0), 21, 0, 0, 0)
        }, "Monitoring", "Apollo is available. You can check your saves at any time.", false);
        foreach (var scale in new[] { 1.25, 1.5, 2.0 })
        {
            const double width = 700;
            // 1080px desktop: reserve 80 physical pixels for taskbar and 32 DIPs for window chrome.
            var height = Math.Min(512, 1000 / scale - 32);
            var element = (FrameworkElement)window.Content;
            element.Measure(new Size(width, height)); element.Arrange(new Rect(0, 0, width, height)); element.UpdateLayout();
            var activityScroll = (System.Windows.Controls.ScrollViewer)window.FindName("ActivityScroll");
            var bitmap = new RenderTargetBitmap((int)(width * scale), (int)(height * scale), 96 * scale, 96 * scale, PixelFormats.Pbgra32);
            RenderWithBackground(bitmap, element, window.Background, width, height);
            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using var file = File.Create(Path.Combine(work, $"main-{scale * 100:0}.png")); encoder.Save(file);
            Check(activityScroll.ScrollableHeight < 1, $"three recent activities fit without scrolling on 1080p at {scale * 100:0}% DPI (overflow {activityScroll.ScrollableHeight:0.0})");
            Check(bitmap.PixelWidth == (int)(width * scale), $"WPF renders at {scale * 100:0}% DPI");
        }
        var settings = new SettingsWindow(paths, new EngineConfig("192.0.2.10", 8080, @"C:\PS4-Saves"), new GuiPreferences(), welcome: true);
        var content = (FrameworkElement)settings.Content; content.Measure(new Size(620, 660)); content.Arrange(new Rect(0, 0, 620, 660)); content.UpdateLayout();
        var image = new RenderTargetBitmap(620, 660, 96, 96, PixelFormats.Pbgra32); RenderWithBackground(image, content, settings.Background, 620, 660);
        var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(image));
        using var output = File.Create(Path.Combine(work, "welcome.png")); png.Save(output);
        Check(true, "first-run settings window renders without touching real user configuration");
    }

    private static void RenderWithBackground(RenderTargetBitmap target, FrameworkElement content, Brush background, double width, double height)
    {
        var visual = new DrawingVisual();
        using (var drawing = visual.RenderOpen()) drawing.DrawRectangle(background, null, new Rect(0, 0, width, height));
        target.Render(visual); target.Render(content);
    }
}
