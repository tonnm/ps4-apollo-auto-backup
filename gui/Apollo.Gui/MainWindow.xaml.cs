using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using Apollo.Core;
using Forms = System.Windows.Forms;

namespace Apollo.Gui;

public partial class MainWindow : Window
{
    private readonly AppPaths paths;
    private readonly EngineController engine;
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(2) };
    private readonly Forms.NotifyIcon? tray;
    private readonly Forms.ToolStripMenuItem? trayBackup;
    private EngineConfig? config;
    private GuiPreferences preferences = new();
    private BackupResult? last;
    private IReadOnlyList<ActivityEntry> recentActivity = Array.Empty<ActivityEntry>();
    private string? lastSeen;
    private bool seeded, refreshing, applying, exiting;
    private bool? reachable;
    private DateTime lastConnectionCheck = DateTime.MinValue;
    private string? manualMessage;
    private DateTime manualMessageUntil;
    private int? lastExit;
    private string diagnosticError = "";
    private (string Title, string Message)? persistentError;

    // createTray=false is used only by the rendering harness; it does not initialize/migrate a session.
    public MainWindow(AppPaths paths, bool createTray = true)
    {
        InitializeComponent(); this.paths = paths; engine = new(paths);
        Height = Math.Min(Height, SystemParameters.WorkArea.Height - 32);
        Width = Math.Min(Width, SystemParameters.WorkArea.Width - 32);
        timer.Tick += async (_, _) => await RefreshAsync();
        if (createTray)
        {
            var menu = new Forms.ContextMenuStrip();
            menu.Items.Add("Open", null, (_, _) => Reveal());
            trayBackup = new Forms.ToolStripMenuItem("Check saves now", null, async (_, _) => await BackupNowAsync());
            menu.Items.Add(trayBackup);
            menu.Items.Add("Open backup folder", null, (_, _) => OpenFolder());
            menu.Items.Add("Settings", null, async (_, _) => await SettingsAsync());
            menu.Items.Add(new Forms.ToolStripSeparator());
            menu.Items.Add("Exit", null, (_, _) => Exit());
            tray = new Forms.NotifyIcon { Icon = System.Drawing.SystemIcons.Application, Text = "PS4 Apollo Auto Backup", ContextMenuStrip = menu, Visible = true };
            tray.DoubleClick += (_, _) => Reveal();
        }
    }

    public async Task InitializeAsync(bool background)
    {
        try
        {
            if (File.Exists(paths.ConfigFile)) config = Configuration.Read<EngineConfig>(paths.ConfigFile).Validate();
            if (File.Exists(paths.PreferencesFile)) preferences = Configuration.Read<GuiPreferences>(paths.PreferencesFile);
            if (config == null || !File.Exists(paths.PreferencesFile))
            {
                Reveal(); await SettingsAsync(welcome: true);
            }
            else
            {
                await RefreshAsync(); // Seed history before starting; don't notify about old runs.
                applying = true;
                await new TaskIntegration(paths).ApplyAsync(config, preferences.StartAutomatically, AuthorizeStartupAsync);
                engine.Start(config);
                applying = false;
                await RefreshAsync(); // Present the automatic monitoring state on the first visible frame.
                if (!background && !preferences.StartMinimized) Reveal();
            }
        }
        catch (Exception ex) { ShowError(ex, "Configuration error"); Reveal(); }
        finally { applying = false; timer.Start(); }
    }

    public void Reveal() { Show(); WindowState = WindowState.Normal; Activate(); }

    public void ShowSnapshot(EngineConfig? value, IReadOnlyList<BackupResult> results, string heading, string detail, bool busy, IReadOnlyList<FailedAttempt>? failures = null)
    {
        StatusHeading.Text = heading; StatusDetail.Text = detail;
        BusyBar.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
        ConnectionLabel.Text = value == null ? "PS4 not configured" : $"PS4 · {value.Address}";
        recentActivity = ActivityEntry.Merge(results, failures ?? Array.Empty<FailedAttempt>());
        last = results.FirstOrDefault();
        LastTime.Text = last?.Completed.ToString("g") ?? "";
        LastOutcome.Text = ActivityEntry.Outcome(last);
        TotalCount.Text = last?.Total.ToString() ?? "—"; NewCount.Text = last?.New.ToString() ?? "—";
        ChangedCount.Text = last?.Changed.ToString() ?? "—"; UnchangedCount.Text = last?.Unchanged.ToString() ?? "—";
        FailureCount.Text = last?.Failures.ToString() ?? "—";
        ActivityList.ItemsSource = recentActivity.Take(3).ToArray();
        BackupButton.IsEnabled = value != null && !busy && !applying;
        EmptyActivity.Visibility = recentActivity.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        if (tray != null) { var tooltip = "PS4 Apollo Auto Backup\n" + heading; tray.Text = tooltip[..Math.Min(63, tooltip.Length)]; }
    }

    private async Task RefreshAsync()
    {
        if (refreshing || applying || config == null) return;
        refreshing = true;
        try
        {
            var current = config;
            var busy = engine.ManualBackupRunning || EngineController.IsLocked(current.BackupPath, "backup");
            if (busy || DateTime.UtcNow > manualMessageUntil) manualMessage = null;
            var log = await Task.Run(() => History.ReadTail(Path.Combine(current.BackupPath, "backup.log")));
            var results = History.Parse(log);
            var monitorLog = await Task.Run(() => History.ReadTail(Path.Combine(current.BackupPath, "monitor.log")));
            var failures = History.ParseFailures(monitorLog);
            if ((DateTime.UtcNow - lastConnectionCheck).TotalSeconds >= 10)
            { lastConnectionCheck = DateTime.UtcNow; reachable = await Configuration.TestConnectionAsync(current); }
            var heading = "Monitoring";
            var detail = "Waiting for Apollo. We'll check your saves when it's available.";
            if (!engine.Monitoring) { heading = "Monitor stopped"; detail = "Monitoring is stopped. Open Diagnostics to resume."; }
            else if (reachable == false) { detail = "Waiting for Apollo. Your PS4 may be offline."; }
            else if (reachable == true) { detail = "Apollo is available. You can check your saves at any time."; }
            if (busy) { heading = "Backup in progress"; detail = "Checking saves… Keep Apollo available until the backup finishes."; }
            else if (manualMessage != null) { heading = manualMessage.StartsWith("Backup completed", StringComparison.Ordinal) ? manualMessage : "Backup needs attention"; detail = manualMessage; }
            else if (results.FirstOrDefault() is { } recent && DateTime.Now - recent.Completed < TimeSpan.FromSeconds(15)) { heading = recent.Title; detail = recent.Summary; }
            // A failed automatic attempt may have no final summary. Show its persisted error, not an old success.
            var lastStart = log.LastIndexOf("Starting backup v1.0.0", StringComparison.Ordinal);
            var lastError = log.LastIndexOf("[ERROR]", StringComparison.Ordinal);
            var lastComplete = log.LastIndexOf("Backup complete.", StringComparison.Ordinal);
            if (!busy && lastError > lastStart && lastError > lastComplete && engine.Monitoring)
            { heading = "Backup needs attention"; detail = "The last check could not finish. Open Diagnostics for details."; }
            if (applying || config != current) return;
            if (!busy && failures.FirstOrDefault() is { } failed &&
                (results.FirstOrDefault() == null || failed.Completed > results[0].Completed))
            { heading = "Backup needs attention"; detail = "The last automatic check failed. Open Diagnostics for details."; }
            if (!busy && persistentError is { } error) { heading = error.Title; detail = error.Message; }
            ShowSnapshot(current, results, heading, detail, busy, failures);
            BackupButton.IsEnabled = !busy;
            if (trayBackup != null) trayBackup.Enabled = !busy;
            var identity = results.FirstOrDefault()?.ToString();
            if (seeded && identity != null && identity != lastSeen && preferences.Notifications && tray != null && results.FirstOrDefault() is { } completed)
                tray.ShowBalloonTip(5000, completed.Title, $"{completed.New} new, {completed.Changed} changed. {completed.Failures} failures.", completed.Failures == 0 ? Forms.ToolTipIcon.Info : Forms.ToolTipIcon.Warning);
            lastSeen = identity; seeded = true;
        }
        catch (Exception ex) { ShowError(ex, "Configuration error"); }
        finally { refreshing = false; }
    }

    private async Task SettingsAsync(bool welcome = false)
    {
        if (applying) return;
        try {
            if (engine.ManualBackupRunning || (config != null && EngineController.IsLocked(config.BackupPath, "backup")))
            { MessageBox.Show(this, "A backup is running. Wait for it to finish before changing settings.", "Backup in progress"); return; }
        }
        catch (Exception ex) { ShowError(ex, "Backup folder unavailable"); }
        Reveal();
        var dialog = new SettingsWindow(paths, config, preferences, welcome) { Owner = this };
        if (dialog.ShowDialog() != true || dialog.Config == null) return;
        applying = true; BackupButton.IsEnabled = false;
        try
        {
            engine.Stop(config);
            StatusHeading.Text = "Applying settings"; StatusDetail.Text = "Preparing background monitoring…";
            await new TaskIntegration(paths).ApplyAsync(dialog.Config, dialog.Preferences.StartAutomatically, AuthorizeStartupAsync);
            Directory.CreateDirectory(dialog.Config.BackupPath);
            // Retain original v1.0 config bytes during migration if the user did not change values.
            if (config != dialog.Config || !File.Exists(paths.ConfigFile)) Configuration.Write(paths.ConfigFile, dialog.Config);
            Configuration.Write(paths.PreferencesFile, dialog.Preferences);
            var changedRoot = config?.BackupPath != dialog.Config.BackupPath;
            config = dialog.Config; preferences = dialog.Preferences; manualMessage = null; persistentError = null;
            if (changedRoot) { seeded = false; lastSeen = null; }
            engine.Start(config);
            if (preferences.StartMinimized && welcome) Hide();
        }
        catch (Exception ex) { ShowError(ex, "Settings could not be applied"); }
        finally { applying = false; await RefreshAsync(); }
    }

    private async Task BackupNowAsync()
    {
        if (config == null || applying) return;
        BackupButton.IsEnabled = false; if (trayBackup != null) trayBackup.Enabled = false;
        manualMessage = null; persistentError = null;
        try { var task = engine.BackupAsync(config); await RefreshAsync(); lastExit = await task; manualMessage = History.ExitMessage(lastExit.Value); manualMessageUntil = DateTime.UtcNow.AddSeconds(15); }
        catch (Exception ex) { ShowError(ex, "Backup needs attention"); }
        finally { await RefreshAsync(); }
    }
    private Task<bool> AuthorizeStartupAsync()
    {
        Reveal();
        return Task.FromResult(MessageBox.Show(this,
            "Windows needs your permission to update the automatic startup left by the previous installation.\n\n" +
            "This is a one-time authorization for this update. Only a small startup helper will run as administrator and then close. The app and monitoring will keep running normally.\n\n" +
            "Your settings and backups will be kept. Continue to the Windows authorization prompt?",
            "Update automatic startup", MessageBoxButton.OKCancel, MessageBoxImage.Information) == MessageBoxResult.OK);
    }
    private void ShowError(Exception ex, string title)
    {
        diagnosticError = ex.ToString(); persistentError = (title, ex.Message); StatusHeading.Text = title; StatusDetail.Text = ex.Message;
        if (!IsVisible) Reveal();
    }
    private void OpenFolder()
    {
        if (config == null) { MessageBox.Show(this, "Choose your backup folder in Settings first.", "Backup folder"); return; }
        OpenPath(config.BackupPath);
    }
    private void OpenPath(string path)
    {
        try
        {
            if (!File.Exists(path) && !Directory.Exists(path)) { MessageBox.Show(this, "This location is not available yet. Check the drive or wait for the first backup.", "Location unavailable"); return; }
            Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
        }
        catch (Exception ex) { ShowError(ex, "Could not open this location"); }
    }
    private void Diagnostics_Click(object sender, RoutedEventArgs e)
    {
        string Info() => $"Application: {AppPaths.Version}\nEngine: {AppPaths.EngineVersion}\nPS4: {config?.Address ?? "not configured"}\nApollo port: {config?.Port}\nMonitor: {(engine.Monitoring ? "Running" : "Stopped")}\nBackup folder: {config?.BackupPath}\nLast backup: {last?.Completed.ToString("g") ?? "none"}\nLast result: {last?.Summary ?? "none"}\nLast manual exit code: {lastExit?.ToString() ?? "none"}";
        var panel = new StackPanel { Margin = new Thickness(22) };
        panel.Children.Add(new TextBlock { Text = "Diagnostics", FontSize = 24, Margin = new Thickness(0, 0, 0, 14) });
        var information = new TextBox { Text = Info(), IsReadOnly = true, TextWrapping = TextWrapping.Wrap, AcceptsReturn = true };
        panel.Children.Add(information);
        panel.Children.Add(new TextBlock { Text = "Copied information includes your network address and folder path, but no save contents.", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 14) });
        var buttons = new WrapPanel();
        void Add(string title, Action action) { var b = new Button { Content = title }; b.Click += (_, _) => action(); buttons.Children.Add(b); }
        Add("Copy information", () => { try { Clipboard.SetText(Info()); } catch (Exception ex) { MessageBox.Show(ex.Message); } });
        Add("Open installation folder", () => OpenPath(paths.Root));
        Add("Open backup folder", OpenFolder);
        Add("Open monitor log", () => { if (config != null) OpenPath(Path.Combine(config.BackupPath, "monitor.log")); });
        Add("Open backup log", () => { if (config != null) OpenPath(Path.Combine(config.BackupPath, "backup.log")); });
        panel.Children.Add(buttons);
        panel.Children.Add(new TextBlock { Text = "Monitoring starts automatically when the app opens. The engine checks when Apollo becomes available. To trigger another automatic check, leave Apollo off for at least 12 seconds and reopen it, or use Check saves now. A reachable port alone does not prove the server is Apollo.", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 8) });
        var monitorControl = new Button { Content = engine.Monitoring ? "Stop monitoring" : "Resume monitoring", HorizontalAlignment = HorizontalAlignment.Left, IsEnabled = config != null && !applying };
        monitorControl.Click += async (_, _) =>
        {
            monitorControl.IsEnabled = false;
            await ToggleMonitoringAsync();
            monitorControl.Content = engine.Monitoring ? "Stop monitoring" : "Resume monitoring";
            monitorControl.IsEnabled = config != null && !applying;
            information.Text = Info();
        };
        panel.Children.Add(monitorControl);
        panel.Children.Add(new TextBlock { Text = "Recent history (up to 10 checks)", FontSize = 16, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 12, 0, 8) });
        foreach (var entry in recentActivity)
        {
            panel.Children.Add(new TextBlock { Text = $"{entry.Timestamp} · {entry.Label}\n{entry.Detail}", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 8) });
            if (entry.Failure is { } failure)
                panel.Children.Add(new TextBlock { Text = $"Automatic attempt exit code: {failure.ExitCode?.ToString() ?? "execution exception"}", TextWrapping = TextWrapping.Wrap });
        }
        if (diagnosticError.Length > 0) panel.Children.Add(new TextBox { Text = diagnosticError, IsReadOnly = true, TextWrapping = TextWrapping.Wrap, MaxHeight = 140, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        new Window { Title = "Diagnostics", Owner = this, Width = 640, Height = Math.Min(640, SystemParameters.WorkArea.Height - 32), Content = new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }, WindowStartupLocation = WindowStartupLocation.CenterOwner }.ShowDialog();
    }
    private async void Backup_Click(object sender, RoutedEventArgs e) => await BackupNowAsync();
    private void Folder_Click(object sender, RoutedEventArgs e) => OpenFolder();
    private async void Settings_Click(object sender, RoutedEventArgs e) => await SettingsAsync();
    private async Task ToggleMonitoringAsync()
    {
        if (applying || config == null) return;
        try { if (config == null) { await SettingsAsync(true); return; } if (engine.Monitoring) engine.Stop(config); else engine.Start(config); manualMessage = null; persistentError = null; await RefreshAsync(); }
        catch (Exception ex) { ShowError(ex, "Monitor needs attention"); }
    }
    private void Window_Closing(object? sender, CancelEventArgs e) { if (!exiting) { e.Cancel = true; Hide(); } }
    private void Window_StateChanged(object? sender, EventArgs e) { if (WindowState == WindowState.Minimized) Hide(); }
    private void Exit_Click(object sender, RoutedEventArgs e) => Exit();
    private void Exit()
    {
        if (applying) { MessageBox.Show(this, "Wait for settings to finish applying before exiting.", "Please wait"); return; }
        try { engine.Stop(config); }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "Backup in progress"); return; }
        exiting = true; timer.Stop(); tray?.Dispose(); engine.Dispose(); Close(); Application.Current.Shutdown();
    }
}
