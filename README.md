# PS4 Apollo Auto Backup

Automatic, versioned PS4 save backups from Apollo Save Tool to a Windows PC.

**v1.1.0** adds a native Windows interface to the real-world-validated **v1.0.0 backup algorithm**.
Log writes now support concurrent GUI readers; see the [automatic-backup incident investigation](docs/incident-2026-09-29.md).
Configure your PS4, leave the application in the notification area, and enable Apollo's web server when you want a backup.

## Install and start

1. Download the `v1.1.0-win-x64-self-contained.zip` release and **extract the whole ZIP**.
2. Double-click `PS4ApolloAutoBackup.exe`.
3. Confirm the PS4 IP address, Apollo port (usually `8080`) and a dedicated backup folder.
4. Optionally test the connection, then choose **Start**. Apollo may be offline.
5. Enable Apollo's web server and keep it available until the backup finishes.

No Git, Visual Studio, manual JSON editing or PowerShell command is needed.
The app copies its files to `%LOCALAPPDATA%\PS4ApolloAutoBackup\gui\1.1.0`.
Keep the extracted executable as a launcher, or create a Windows shortcut to the installed executable.
Closing the window keeps monitoring in the tray. Choose **Exit** to stop completely.
Settings controls startup at Windows sign-in, notifications and starting minimized.

The smaller `framework-dependent` package requires the **.NET 10 Windows Desktop Runtime x64**.
The self-contained package includes its runtime. Both require Windows PowerShell 5.1 and Windows Task Scheduler.
Use a supported Windows x64 release; organizational policy may restrict scripts or startup registration.
Packages are unsigned. This repository contains build instructions; it does not imply a GitHub release has been published.

## Daily use

- **Check saves now** runs the existing engine and prevents duplicate manual runs. Engine locks also protect against automatic/manual races.
- **Open backup folder** opens your configured data root.
- The last result shows checked/new/changed/unchanged/failed saves and completion time.
- Recent activity shows the latest three checks with distinct outcome labels. View history opens up to ten summaries in Diagnostics.
- **Diagnostics** opens logs and folders and copies version, configuration and status information without save contents.
- Notifications summarize a completed run, not each unchanged save, and can be disabled.

The monitor checks the configured TCP port every ten seconds. Startup or an OFF → ON transition triggers one backup.
It does not watch game closure or detect changes while Apollo stays online. Close Apollo's server until the monitor
detects disconnection, then reopen it, or use **Check saves now**. A reachable TCP port is not proof of an Apollo server.
Progress is indeterminate; the validated comparison and backup-state behavior is unchanged.

## Upgrade from v1.0.0

Finish any backup, close manually launched monitors, then open the extracted GUI.
The welcome screen reuses the existing configuration. Keep the same backup folder to retain its history.
The app safely migrates a recognized v1.0.0 startup task to launch the GUI in the tray.
It verifies the stored action, enabled preference, principal, trigger and runtime settings before accepting success.
Unrelated tasks are refused. Failed registration attempts restore the previous task where Windows permits it.

Some v1.0.0 tasks require administrator permission to update. If Windows refuses the change,
the app explains the one-time authorization and opens a UAC prompt for a short-lived startup helper.
The main app and monitor remain unelevated. Approve with the same Windows account that owns
the installation; cancellation lets you retry in Settings. Already-correct tasks are only read,
so normal launches do not repeat the permission request. A denied operation does not trigger another
equally denied XML rollback. If migration had already stopped the old monitor, finish the update
from Settings before monitoring resumes. Configuration, logs, state and saves are never reset.

**Owner-validated on real Windows:** normal v1.1.0 migration of `PS4 Apollo Save Backup`
was denied; running the same build once with sufficient privilege successfully changed its action to
`%LOCALAPPDATA%\PS4ApolloAutoBackup\gui\1.1.0\PS4ApolloAutoBackup.exe --background`.
The dedicated UAC-helper flow added after that report still needs its own end-to-end Windows check.

Configuration, `backup-state-v4.json`, logs, ZIP history and the old `src` files are preserved.
Changing the data folder creates a separate history; it does not move or delete old backups.
Do not run the old installer/uninstaller after GUI migration: they intentionally reject the GUI-owned task.
Direct migration from private V4/Documents is outside the GUI migration scope; first use the validated v1.0.0 release.

## Data and reliability

Backups live under `<backup folder>\Backups\<Title ID>\<Save Name>`; state and logs live in the backup root.
NEW and CHANGED retain a version; UNCHANGED discards the temporary download. Existing versions are never overwritten.
The V4 algorithm compares SHA-256 signatures of extracted file contents and relative paths.
ZIP timestamps, compression, entry order and Apollo export position do not affect identity.
Every ZIP is downloaded for comparison. State updates remain atomic and corrupt state is preserved.

Use a writable dedicated local NTFS folder with room for downloaded and extracted saves. UNC paths are unsupported.
There is no pruning, cloud synchronization or automatic restore. Identity cannot distinguish accounts with the same
Title ID and Save Name. Keep independent copies and verify your restore procedure.

The owner validated v1.1.0 against a real PS4/Apollo on 2026-09-29: automatic checks with the GUI
open and in tray mode, followed by manual verification, all completed with zero failures.
See [validation results](docs/validation.md) for the four scenarios and counts.

v1.0.0 remains the original CLI release. v1.1.0 is the first GUI/tray release, including the
concurrent-log fix and failed-attempt history. No v1.2.0 functionality is included.
Engine banners retain v1.0.0 as the validated algorithm baseline; V4 identifies the hash/state format.
The shared log writer is a v1.1.0 integration fix, not a new hash algorithm or state format.

## Build and test

Development requires a .NET 10 SDK. The inspected SDK was 10.0.100; the GUI targets `net10.0-windows`.
[.NET 10 is LTS, supported through November 2028](https://dotnet.microsoft.com/en-us/platform/support/policy).

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build\Publish-Gui.ps1 -SelfContained
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Gui-Migration.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build\Test-Gui.ps1
```

Omit `-SelfContained` for the smaller runtime-dependent build. Output is in `dist`.
Runtime downloads need NuGet network access; build caches remain inside the repository.
No external GUI framework or test package is used.

## Documentation

- [GUI architecture, migration, distribution and manual test plan](docs/gui-v1.1.0.md)
- [Validation results and limits](docs/validation.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Archived v1.0.0 engine/CLI guide](docs/engine-v1.0.0.md)
- [Changelog](CHANGELOG.md)

## Removal

In Settings, turn off automatic startup, save, and choose **Exit**.
The disabled project startup entry is harmless; it may be removed in Task Scheduler after verifying its GUI action.
Delete the installed `gui\1.1.0` directory and extracted release if desired.
Keep `config.json`, backup state and your backup folder. No automated save deletion is provided.
There is no MSI, automatic updater or dedicated GUI uninstaller in this release.

## Disclaimer

Not affiliated with Sony or Apollo Save Tool. No Sony artwork is used.
Software is provided without warranty under the [MIT License](LICENSE).
