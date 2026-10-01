using System;
using System.IO;
using System.Windows;
using Apollo.Core;
using Microsoft.Win32;

namespace Apollo.Gui;
public partial class SettingsWindow : Window
{
    private readonly AppPaths paths;
    public EngineConfig? Config { get; private set; }
    public GuiPreferences Preferences { get; private set; }
    public SettingsWindow(AppPaths paths, EngineConfig? config, GuiPreferences preferences, bool welcome = false)
    {
        InitializeComponent(); this.paths = paths; Preferences = preferences;
        AddressBox.Text = config?.Address ?? ""; PortBox.Text = (config?.Port ?? 8080).ToString();
        FolderBox.Text = config?.BackupPath ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "PS4-Saves");
        StartupBox.IsChecked = preferences.StartAutomatically; NotificationsBox.IsChecked = preferences.Notifications; MinimizedBox.IsChecked = preferences.StartMinimized;
        if (welcome) { Heading.Text = "Welcome to PS4 Apollo Auto Backup"; SaveButton.Content = "_Start"; }
        Height = Math.Min(Height, SystemParameters.WorkArea.Height - 32);
        Width = Math.Min(Width, SystemParameters.WorkArea.Width - 32);
    }
    private EngineConfig Read()
    {
        if (!int.TryParse(PortBox.Text, out var port)) throw new InvalidDataException("Enter a whole number for the Apollo port.");
        var config = new EngineConfig(AddressBox.Text.Trim(), port, FolderBox.Text.Trim()).Validate();
        Configuration.ValidateLocation(config, paths); return config;
    }
    private void Save_Click(object sender, RoutedEventArgs e)
    {
        try { Config = Read(); Preferences = new(StartupBox.IsChecked == true, NotificationsBox.IsChecked == true, MinimizedBox.IsChecked == true); DialogResult = true; }
        catch (Exception ex) { Feedback.Text = ex.Message; }
    }
    private async void Test_Click(object sender, RoutedEventArgs e)
    {
        TestButton.IsEnabled = false;
        try { var config = Read(); Feedback.Text = "Checking connection…"; Feedback.Text = await Configuration.TestConnectionAsync(config) ? "Connection successful. The configured port is reachable; the backup will check Apollo's save list." : "Apollo could not be reached. You can continue setup and the application will monitor it later."; }
        catch (Exception ex) { Feedback.Text = ex.Message; }
        finally { TestButton.IsEnabled = true; }
    }
    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        var picker = new OpenFolderDialog { Title = "Choose a backup folder" };
        if (picker.ShowDialog(this) == true) FolderBox.Text = picker.FolderName;
    }
}
