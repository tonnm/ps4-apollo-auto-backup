# Troubleshooting

## GUI v1.1.0

Use **Diagnostics** to open logs and **Settings** to change the address, port or backup folder.
Closing the window hides it in the notification area; choose **Exit** for a complete stop.
Exit and Settings refuse to interrupt an active backup. Windows can suppress tray notifications.
If the GUI says another monitor is running, close manually launched old monitors before retrying;
do not delete lock files to bypass a running process.

For a startup/migration error, inspect the detail in Diagnostics. The GUI only replaces recognized
current-user project tasks and verifies the stored result. Permission failures on recognized tasks
show a one-time authorization explanation followed by Windows UAC. Only the startup helper is elevated;
do not run the whole app as administrator. Cancelling is safe for your saved data; retry from Settings.
If the old monitor had already stopped, complete the update to resume monitoring. Use the same Windows
account that owns this installation; entering a different administrator account is not supported.
An already-correct migrated task is read without being rewritten on subsequent launches.
For non-permission failures after a successful change, the adapter attempts rollback. Permission denial
does not trigger another denied XML write or instructions to manually edit Task Scheduler.
Managed Windows policy may deny task registration or PowerShell execution. Do not run the old
installer/uninstaller to repair a GUI task; use GUI Settings after resolving the policy/folder issue.
The engine copies in the versioned GUI package retain the v1.0.0 backup algorithm with the shared-log fix; the old installed `src` folder
is retained for recovery, not used as a second background monitor.

The framework-dependent package needs the .NET 10 **Windows Desktop Runtime x64**. Alternatively,
extract the whole self-contained package. Moving only its executable is insufficient.
See the [GUI guide](gui-v1.1.0.md) for lifecycle, rollback limits and manual validation.

For an automatic exit 1 without a final summary, see the [2026-09-29 investigation](incident-2026-09-29.md).
The GUI now records failed automatic attempts separately in Recent activity. A reproduced Windows
PowerShell log-sharing conflict was fixed without changing the backup algorithm. Exit 1 never means
"no changes"; a successful all-UNCHANGED check exits 0.

The remaining sections describe the backup engine. CLI setup/uninstall commands apply to v1.0.0,
not to a GUI-owned startup task.

Start with `monitor.log` and `backup.log` in the data root recorded in
`%LOCALAPPDATA%\PS4ApolloAutoBackup\config.json`. Never share these files without reviewing
save names, local paths and other personal data.

## Apollo not detected / port unreachable / firewall

Keep the PS4 awake and Apollo's web server enabled. Opening Apollo alone may not enable its server.
Check that its page exposes `/zip/<position>/<save>.zip` links. Both machines need local network access;
guest Wi-Fi isolation, VPN routing and firewall rules can prevent it.

```powershell
$app = Join-Path $env:LOCALAPPDATA 'PS4ApolloAutoBackup'
$config = Get-Content -LiteralPath (Join-Path $app 'config.json') -Raw | ConvertFrom-Json
Test-NetConnection -ComputerName $config.ps4Address -Port $config.apolloPort
```

Check the configured HTTP page in a browser. A successful port check does not verify Apollo or its saves.
Allow the necessary local outbound connection in the applicable firewall policy; do not disable your
firewall or expose Apollo through an Internet-facing router port.

## PS4 IP changed

Rerun the installer from the extracted release and enter the new address. Keep the existing data root
to preserve change detection. The monitor loads configuration only at startup. An address reservation
on your local router can avoid repeated changes.

## Scheduled Task not running

Open Windows Task Scheduler and find `PS4ApolloAutoBackup-<current-user-SID>` in the root task folder.
After migrating the legacy task, its name remains `PS4 Apollo Save Backup` instead.
It runs as the installing user, with limited privileges and an interactive logon. Sign in as that user,
check the task's last result/history, and check whether `monitor.log` receives a startup message.
The task is intended to remain Running. Its action uses Windows PowerShell, not `pwsh`.

Rerun setup if files are missing. If policy denies task registration, consult your Windows administrator;
the installer reports an error, and the scripts can still be run manually using `-ConfigPath`.
Setup verifies the persisted action/settings and enables the task explicitly. It reports success only after
observing `Running` and a newly appended `Monitor started.` record. A start request that returns without
launching the monitor, or a task that stays disabled, now fails setup clearly. Review the error and Task
Scheduler history before retrying; registration permissions can differ from execution permissions.
An existing unrelated action or another user's task under either supported name causes setup/uninstall
to stop without replacing it.

## Legacy task still disabled or pointing to Documents

The initial v1 installer used a different SID-based name, so its success message did not mean that
`PS4 Apollo Save Backup` was updated. Rerun the corrected installer. It recognizes the original V4
monitor by owner, executable, allowed `-File` arguments, expected Documents path and source structure.
It updates that task in place and safely removes a verified duplicate SID task, if present.
The Action must then reference `%LOCALAPPDATA%\PS4ApolloAutoBackup\src\Monitor-PS4.ps1`, with an enabled
logon trigger and task. Unknown/missing legacy scripts are refused; inspect them manually rather than
deleting a task based solely on its name. The installer never executes the legacy script to identify it.

## Monitor running but backup does not start

This is an edge-triggered TCP monitor. It waits for a disconnect after each attempt, even a failed attempt.
Close the Apollo server until `Monitor rearmed` appears (allow more than 10 seconds), then reopen it.
It does not watch game exit or save modification events. If no ZIP links exist, backup exits with code 11.
Check for another instance or a manually launched legacy V4 monitor. Close manual instances before migration;
the corrected installer handles the recognized legacy Scheduled Task.

## Backup folder unavailable / permissions / storage

Reconnect the drive and verify that the configured root is writable by the installing user and has free
space. Use a dedicated local NTFS directory; UNC paths are rejected. Keep `Temp` and `Backups` on the
same volume and do not replace them with junctions to another volume. A storage or state-write failure
stops processing; previous ZIP versions remain. Check the console for manually run scripts and the
monitor log for exit status. A read-only or disconnected log directory can prevent logging itself.

No versions are pruned automatically. After stopping all instances, leftover GUID files/directories
inside `Temp` from an interrupted run may be removed manually. Do not clear `Backups`.

## Corrupt state file / complete state reset without deleting backups

A parse error or invalid state entry exits with code 13 and leaves the file untouched. Stop the Scheduled
Task and close manual monitor/backup instances first. Keep a copy of the state for diagnosis. Then rename
the state, without touching the `Backups` directory:

```powershell
$app = Join-Path $env:LOCALAPPDATA 'PS4ApolloAutoBackup'
$config = Get-Content -LiteralPath (Join-Path $app 'config.json') -Raw | ConvertFrom-Json
$root = [Environment]::ExpandEnvironmentVariables($config.backupPath)
$state = Join-Path $root 'backup-state-v4.json'
if (Test-Path -LiteralPath $state) {
    Rename-Item -LiteralPath $state -NewName ("backup-state-v4.json.saved-" + [guid]::NewGuid().ToString('N'))
}
```

This completely resets save comparison state. Monitor edge state is in memory and resets when the monitor
is restarted. Lock files do not contain save state and need not be removed. Run a manual backup with Apollo
online, then restart the task. All currently exposed saves become `NEW`; previous ZIPs remain in history.
To recover instead, restore a known-good V4-format state copy while all instances are stopped.

## Force a backup safely

Run the installed `src\Backup-PS4.ps1` to force an immediate **comparison**; unchanged content still does
not create a new version. To force fresh ZIPs even for unchanged saves (for example after manually deleting
a ZIP), follow the state rename procedure above. There is no destructive force switch.

## Reinstall or uninstall fails

Close manual instances and retry; setup/uninstall wait briefly for the stopped Scheduled Task to release
its locks. They never kill unrelated PowerShell processes. A failed setup can leave the task stopped or
application files partially updated; rerun setup from the complete release before restarting it.
If installed `config.json` is damaged, repair it using the three fields in `config.example.json` before
retrying. Never substitute the example IP for your real address. If the `.installed` marker is missing,
inspect the directory manually rather than deleting it blindly. Backups are never removed by uninstall.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Backup completed, or setup/uninstall succeeded |
| 1 | Configuration, storage, setup or other fatal error |
| 10 | Apollo HTTP page unavailable |
| 11 | Page contains no save links |
| 12 | Instance lock unavailable or its directory not writable |
| 13 | State unreadable or invalid; preserved |
| 20 | One or more saves could not be downloaded/processed; successful saves retained |
