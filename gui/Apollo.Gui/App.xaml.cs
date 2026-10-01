using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using Apollo.Core;

namespace Apollo.Gui;

public partial class App : Application
{
    private SingleInstance? instance;
    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        if (e.Args.Length > 0 && e.Args[0] == "--startup-helper")
        {
            Shutdown(e.Args.Length == 2 ? await TaskIntegration.RunElevatedHelperAsync(e.Args[1]) : 1);
            return; // No main window, tray, bootstrap, GUI lease or engine in the elevated process.
        }
        var paths = AppPaths.Default;
        try
        {
            // All instances, including the release bootstrap, coordinate on the stable per-user root.
            try { instance = new SingleInstance(paths.Root, () => Dispatcher.BeginInvoke(() => (MainWindow as MainWindow)?.Reveal())); }
            catch (IOException ex) when ((ex.HResult & 0xffff) is 32 or 33)
            {
                try { await SingleInstance.ActivateAsync(paths.Root); } catch (TimeoutException) { }
                Shutdown(); return;
            }
            if (!Path.GetFullPath(AppContext.BaseDirectory).TrimEnd('\\').Equals(paths.InstalledDirectory, StringComparison.OrdinalIgnoreCase))
            {
                Deployment.Install(paths);
                instance.Dispose(); instance = null;
                var start = new ProcessStartInfo(paths.InstalledExe) { UseShellExecute = false, CreateNoWindow = true };
                if (e.Args.Contains("--background")) start.ArgumentList.Add("--background");
                Process.Start(start);
                Shutdown(); return;
            }
            var window = new MainWindow(paths);
            MainWindow = window;
            await window.InitializeAsync(e.Args.Contains("--background"));
        }
        catch (Exception ex)
        {
            MessageBox.Show("The application could not start. Your backups were preserved.\n\n" + ex.Message,
                "PS4 Apollo Auto Backup", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
        }
    }
    protected override void OnExit(ExitEventArgs e) { instance?.Dispose(); base.OnExit(e); }
}
