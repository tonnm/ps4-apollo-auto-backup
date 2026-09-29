# PS4 Apollo Auto Backup

Automatic, versioned PS4 save backups from Apollo Save Tool to a Windows PC.
Version **v1.0.0** preserves the working V4 monitoring and content comparison workflow.

## Features

- Automatic backup when the configured Apollo TCP port becomes available.
- Apollo web server integration: discovers `/zip/<position>/<save>.zip` links.
- SHA-256 comparison of extracted file content and relative paths.
- Keeps new and changed saves without retaining redundant ZIPs.
- Per-user Windows Scheduled Task starts monitoring at logon.
- Version history and a V4-compatible state database.
- Configurable PS4 IPv4 address, Apollo port and backup root folder.
- Exclusive file locks, validated downloads and atomic state replacement.
- Native Windows PowerShell; no third-party modules, telemetry or updater.

## Requirements

- Windows with Windows PowerShell, built-in .NET ZIP support, `Get-FileHash` and the built-in
  ScheduledTasks module. Local validation uses **Windows PowerShell 5.1**;
  other PowerShell/Windows versions have not been verified.
- A jailbroken PS4 with Apollo Save Tool and its web server exposing save ZIP links.
  No minimum Apollo version has been established by this project.
- PC and PS4 on the same reachable local network; the configured TCP port must be accessible.
- A writable, dedicated local backup folder with enough space for history, a downloaded ZIP
  and its extracted contents. Use NTFS for atomic state replacement. UNC paths are not supported.
- The installing Windows user must be allowed to create a Scheduled Task. Administrator
  rights are not requested; organizational policy may restrict this capability.

## Installation

1. Download the latest release and extract it.
2. Open **Windows PowerShell** in the extracted directory.
3. Run ` .\install.ps1 `.
4. Enter the PS4 IP address, Apollo port (default `8080`) and backup root folder.
5. Setup starts the monitor and registers it for future user logons.

If execution policy blocks the script, review the files, then run this process-scoped command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

This does not change machine or user execution policy. Managed policy can still prevent execution.
The Scheduled Task also uses a process-scoped bypass to run these unsigned scripts.

Apollo may be offline during installation. A failed TCP check is a warning, not an installation failure.
Setup re-reads the registered task and verifies its action, enabled state, principal, logon trigger and
runtime settings. It then starts the task and requires both `Running` state and a **new** startup record
in `monitor.log` before reporting success. Failure to confirm startup in approximately 15 seconds fails setup.

Application files and `config.json` are installed in `%LOCALAPPDATA%\PS4ApolloAutoBackup`.
The default data root is `PS4-Saves` in the Windows Documents folder. `backupPath` is this
**root**, with a `Backups` subdirectory beneath it, matching V4.
`config.example.json` uses a documentation-only IP; setup creates the real configuration.

Rerun the extracted installer to change settings or reinstall. Existing settings become prompt defaults.
It stops only recognized project tasks, locks the old/new data roots, replaces application files and updates
the task. Fresh installs use `PS4ApolloAutoBackup-<current-user-SID>`; migrated installs keep
`PS4 Apollo Save Backup`. It keeps backups and state. Changing the data root does not move existing backups or state.
An interrupted/failed setup must be rerun; setup is not a transaction across all files and Task Scheduler.

### Migrating from private V4

Close manually started old monitors **before** installing. Setup can migrate the root task named
`PS4 Apollo Save Backup`, including a disabled task, when it belongs to the current user and has one
recognized PowerShell `-File` action pointing to that user's `Documents\Monitor-PS4.ps1` (including the
Windows Documents known folder). The file must exist and contain the V4 monitor header, `Test-Apollo`
function and backup-script invocation. Unknown executables, arguments, owners or scripts cause setup to
fail without modifying any task. The name alone is never proof of ownership.

The recognized task is updated **under the same name**, explicitly enabled and pointed to
`%LOCALAPPDATA%\PS4ApolloAutoBackup\src\Monitor-PS4.ps1`. If the earlier installer also created a SID-named
task, setup removes that duplicate only after verifying its ownership and the replacement configuration.
Old scripts in Documents are not modified or deleted. Other legacy task names are not migrated automatically.
Choose the existing V4 `PS4-Saves` root to reuse `backup-state-v4.json` and `Backups`.
The old scripts do not honor the new locks: never run them concurrently with v1.0.0.
Make an independent copy of important saves before migration.

## Usage

Play and save your game, then open/use Apollo and enable its web server so it exposes the save ZIPs.
Keep Apollo available until `backup.log` reports completion.

The monitor checks the TCP port every 10 seconds, with a one-second connect timeout.
On startup or an unavailable-to-available transition it runs one backup. While the port remains
available, it does not repeat the backup, even after an error. Close/stop Apollo's server until the
monitor logs a disconnect, then reopen it to rearm. A restart of the monitor also triggers a run if
the port is already available. The monitor does **not** detect game closure or watch save changes live.

Only saves exposed in Apollo's page are backed up. HTTP page timeout is 10 seconds;
each ZIP download timeout is 120 seconds. A reachable port alone does not prove the server is Apollo.
HTTP redirects are rejected. No data is written to the PS4.

Run a manual comparison, using the installed configuration:

```powershell
& "$env:LOCALAPPDATA\PS4ApolloAutoBackup\src\Backup-PS4.ps1"
```

Direct execution from the release folder requires `-ConfigPath` pointing to your configuration.
Runtime scripts support this parameter; setup and uninstall manage the fixed per-user installation.

## Backup structure

```text
PS4-Saves/                           # configured backupPath
  Backups/
    CUSA00001/
      SAVE_SLOT_1/
        2026-09-28_21-15-06-123_<guid>.zip
    OUTROS/                         # filenames without a recognized Title ID
      <save-name>/
        <timestamp>_<guid>.zip
  Temp/                             # per-download GUID ZIP and extraction folder
  backup-state-v4.json
  backup.log
  monitor.log
  .backup.lock
  .monitor.lock
```

The ZIP is kept exactly as downloaded after successful extraction and hashing. Timestamp plus GUID
prevents collisions; an existing version is never overwritten. There is no retention pruning.
Lock files remain on disk after exit; their presence alone does not mean the application is running.

## How change detection works

The original V4 algorithm is retained:

1. Identify a save by `Title ID|Save Name` from the ZIP link filename; ignore Apollo's list/export position.
2. Extract the ZIP to a unique temporary directory.
3. Enumerate files recursively with PowerShell's normal `Get-ChildItem -File -Recurse` behavior,
   sort by full path, and compute each file's SHA-256.
4. Join `relative-path|FILE-HASH` entries with a newline; hash the UTF-8 result with SHA-256.
5. Compare the resulting uppercase hash with the state entry: `NEW` and `CHANGED` retain a ZIP;
   `UNCHANGED` discards the temporary download.

ZIP compression, entry ordering and timestamps do not affect the hash. The extraction directory
and `/zip/<position>/` value do not enter it. **Internal relative paths do enter it**: changing a
filename or a directory inside the ZIP changes the signature, just as in V4. No internal file types
are specially excluded; file enumeration does not add `-Force`. Empty archives are rejected.
URL-encoded save names retain their encoded representation, also matching V4.

The state format keeps the existing `Hash`, `Arquivo` and `Data` fields. A validated ZIP is moved into
history before state is atomically committed. A crash between these steps can cause one extra version
on retry, but cannot remove an existing backup. Failed downloads leave previous entries intact.
A missing state file treats all saves as new. A corrupt state file stops the run and is preserved.

## Logs

`backup.log` and `monitor.log` are in the configured data root, with timestamped messages.
Backup logs include `NEW`, `CHANGED`, `UNCHANGED`, counts and failures.
Logs, state and ZIPs may contain personal save names, file paths or account data; do not publish them.
Logs/history are not automatically rotated. Setup errors appear in the console.

## Troubleshooting

See [troubleshooting](docs/troubleshooting.md), including state recovery and safe manual retries.
See [local validation](docs/validation.md) for tested behavior and explicit testing limits.

## Uninstall

Run ` .\uninstall.ps1 ` from the extracted release, or:

```powershell
& "$env:LOCALAPPDATA\PS4ApolloAutoBackup\uninstall.ps1"
```

It checks both supported task names, stops/removes only verified installed v1 actions, and removes only known application files.
Close manually started instances first. **All backups, logs, state and temporary data are preserved.**
There is deliberately no automated backup deletion option. If you want to delete them, inspect and
remove the data folder yourself after keeping another copy. Unknown files in the installation folder
are also preserved.

## Limitations

- Requires Apollo's web server and an awake, reachable PC. Monitoring starts at user **logon**,
  not unattended machine boot; there is no stored password or background service.
- Every save ZIP must be downloaded to determine whether its contents changed.
- V4 identity cannot distinguish two users/accounts exporting the same Title ID and Save Name.
  Use separate data roots/configurations for such collections; no new account-ID logic is introduced.
- Unsafe Windows folder names are rejected rather than silently renamed. Very long paths may fail
  under Windows PowerShell/.NET path limits. Use a short data root if necessary.
- One monitor and one backup per data root are allowed. Legacy V4 instances do not honor these locks.
- No cloud sync, automatic restore, backup pruning or automatic retry while Apollo remains online.
- A removed historical ZIP is not recreated if state still reports unchanged content. See the safe
  state reset instructions to force a fresh copy.
- Local tests do not establish compatibility with every Apollo release or real console export.

## Disclaimer

This project is not affiliated with Sony or Apollo Save Tool. Keep independent copies of important
saves and verify your restore procedure. Software is provided without warranty under the [MIT License](LICENSE).
