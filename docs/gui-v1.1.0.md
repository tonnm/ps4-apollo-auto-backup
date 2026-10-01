# GUI v1.1.0

## Main-window UX revision

Monitoring remains automatic on launch and after setup. The main action is **Check saves now**;
the tray uses the same label. Advanced Stop/Resume monitoring controls and the Apollo OFF/ON
explanation live in Diagnostics. No engine or background lifecycle behavior changed.

The default window is 700 × 550 DIPs and adapts to the available desktop work area. Last backup
retains all five counts and explicitly states success, failures or absence of a completed backup.
Recent activity shows three outcome badges, with text as well as color, and retains mixed-result
counts. View history opens the bounded ten-result history in Diagnostics. No game-name database
or new persistence is used. Only the activity region scrolls if space is constrained; the primary
actions and backup result remain visible. Rendered tests cover 1080p desktop space at 125%, 150%
and 200% with three activities and no scrollbar; physical display transitions remain a manual check.

## Architecture and lifecycle

`Apollo.Gui` is a .NET 10 WPF WinExe, with a built-in Windows Forms NotifyIcon for the tray.
`Apollo.Core` provides configuration, bounded history reading, deployment, startup integration,
single-instance coordination and process ownership. There are no third-party GUI frameworks.

The GUI starts `Monitor-PS4.ps1` as an owned background child with an explicit
`-ConfigPath`. The monitor invokes `Backup-PS4.ps1`. Check saves now invokes that same
backup script. The original `.monitor.lock` and `.backup.lock` remain the final cross-process guards.
The GUI also disables backup controls while a run is active and rejects duplicate manual requests.

Both engine scripts now append logs through `Add-AppLogLine` to permit concurrent GUI readers.
Only logging differs from the baseline engine; see [incident investigation](incident-2026-09-29.md).
Recent activity combines completed summaries with unsuccessful attempts from the bounded monitor
log tail. Failed attempts do not invent save counts or replace the last completed result. Diagnostics
also shows their exit codes. A partial run with a final summary and a nonzero monitor exit has two
distinct records: its measured result and its automatic execution failure.

One per-installation file lease owns the GUI; subsequent launches activate it through a current-user-only
named pipe. Startup registration launches the installed GUI with `--background`, never a second monitor.
Closing/minimizing the window hides it in the tray. Exit refuses while a backup is active, takes the backup
lock to prevent a start/stop race, and terminates only its owned monitor. A Windows Job Object with
KILL_ON_JOB_CLOSE contains owned processes if the GUI crashes. A crash can interrupt a download;
the existing engine's atomic state/publication behavior provides the same recovery guarantees as v1.0.0.
The startup task intentionally has no restart policy so explicit Exit remains an exit.

## No-console investigation

The v1.0.0 task executes a console application (`powershell.exe`) with `-WindowStyle Hidden`.
That requests a visibility change; it does not prevent console allocation. The new boundary uses
`ProcessStartInfo.UseShellExecute=false`, `CreateNoWindow=true`, redirected output and separate arguments.
The GUI itself is a WinExe. No window is moved off-screen and no desktop-global process is killed.

The process regression measures `GetConsoleWindow()` in a real PowerShell child. The new launcher
must return zero; a comparison launch using Hidden without CreateNoWindow is recorded as diagnostic
evidence only, because console allocation also depends on the host environment. The exact origin of the owner's previously visible
window cannot be established retrospectively without that session's process tree; GUI startup through
the real logon task remains in the manual test plan.

Microsoft documents the dependency on UseShellExecute in
[CreateNoWindow](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processstartinfo.createnowindow?view=net-10.0).

## Status and results

No engine changes were needed. The engine's JSON state contains per-save state, not run totals.
The GUI therefore parses the existing persisted summary contract in `backup.log`:

```text
[2000-01-01 12:00:00] [INFO] Backup complete. New=0 Changed=5 Unchanged=16 Failures=0
```

This is log parsing, not console decoration parsing. Tests pin the exact v1.0.0 format, bad/partial
records, overflow and ordering. Read at most the last 128 KiB and retain at most ten summaries (three on the main screen, ten in Diagnostics);
very large runs may push older summaries out of that window. No percentage is invented.
Missing summaries are not reported as successful backups. Technical exit codes remain in diagnostics.
Notifications are generated once per new observed summary after the initial history snapshot.
TCP tests only establish reachability; only the engine checks Apollo's save listing.

## Migration and task verification

Bootstrap verifies the complete package hash manifest before copying files to
`%LOCALAPPDATA%\PS4ApolloAutoBackup\gui\1.1.0`. This is corruption detection, not a digital signature.
It does not replace the v1.0.0 `src` directory or delete unknown files.
The existing root `config.json` remains the engine configuration; GUI preferences use `gui-settings.json`.
If values are unchanged, saving first-run setup retains existing configuration bytes.
No state, ZIP or log is reset. Changing the backup folder does not migrate its contents.

The adapter recognizes the root tasks `PS4 Apollo Save Backup` and the current-user SID task.
It requires the current user and the exact v1.0.0 installed monitor action, or the exact installed
GUI action. It validates every candidate before mutation. Tasks with unknown owners/actions are refused.
The legacy name is retained when present; only a recognized duplicate is removed after verification.

Migration locks both old/new backup roots, snapshots task XML, stops recognized scheduled monitors,
checks monitor locks, and registers the GUI action. Enabled/disabled follows the startup preference.
After registration it re-reads action, working directory, owner, interactive/limited principal,
enabled state, enabled user logon trigger, IgnoreNew, infinite time limit, battery settings,
StartWhenAvailable, AllowDemandStart and absence of automatic restart.
Cmdlet success alone is insufficient. Non-permission failures after a successful change attempt to
restore task XML and restart a previously running engine task. Permission denial does not trigger
the same privileged XML write as rollback. This is not a transaction spanning the scheduler
and configuration files. If writing configuration/preferences later fails, correct the folder problem
and retry Settings. Existing backup data is unaffected.

Manually started monitors must be closed by the user; the GUI never kills an arbitrary process by name.
Direct private-V4 migration belongs to the v1.0.0 installer, not this adapter.

### One-time startup authorization

The owner reproduced migration on real Windows: the v1.0.0 `PS4 Apollo Save Backup` task pointed
to `Monitor-PS4.ps1`; an ordinary v1.1.0 launch received Access denied and the former rollback
also failed. Running that exact build once with sufficient privilege correctly changed the task to
`%LOCALAPPDATA%\PS4ApolloAutoBackup\gui\1.1.0\PS4ApolloAutoBackup.exe` with `--background`.
This validates the real migration/action with sufficient permission, not the new helper flow below.

The normal adapter now identifies permission failures by exception/category/HRESULT, not English
error text. Only after validating existing project task ownership does it return its dedicated
authorization-required code/marker. The GUI explains the one-time startup update before invoking UAC.
Other failures and unrelated tasks never trigger automatic elevation.

ShellExecute `runas` starts the installed WinExe in `--startup-helper <request>` mode. This is a separate,
short-lived process of the same binary; its entry point bypasses deployment, single-instance activation,
the main window, tray and engine. It executes only the fixed startup adapter as a console-free child
and exits. The original GUI remains running unelevated, and the task still uses Interactive/Limited.
This follows Microsoft's [guidance to keep the main app asInvoker and elevate a separate process only
for required operations](https://learn.microsoft.com/en-us/windows/win32/secbp/running-with-administrator-privileges).

The helper checks its installed location, request filename/root, executable, backup-folder constraints
and owning Windows SID. It holds the request open against modification while the adapter reads it.
Data directories and lock markers are prepared before elevation. The elevated adapter opens existing
lock files read-only for exclusion; it cannot create data directories/lock files or write backup contents.
The adapter rechecks task ownership after consent, so replacing/removing a task during UAC cannot
turn this into an arbitrary task overwrite. The GUI verifies stored settings again without mutation
after helper exit; zero exit alone is insufficient. Cancellation and helper failures have friendly
messages, never a UAC retry loop. Raw initial errors are available only as diagnostic details.

An already-correct task is only read on subsequent launches; it is not repeatedly rewritten or elevated.
Changing a protected task's startup preference later may require another authorization for that change.
Different-account administrator credentials are deliberately rejected: authorize as the same Windows
account that owns this per-user installation. No credentials are stored.

The mutation flag is set only after a mutating call succeeds. If the first write is denied, there is
nothing to roll back. If a stop or earlier write succeeded before permission denial, the helper re-reads
that recognized state and completes migration. If consent is cancelled or migration cannot finish,
the old monitor may remain stopped until the user retries Settings; no state, log or backup is reset.
No unprivileged retry of the denied XML rollback is attempted, and no manual Task Scheduler editing is
requested. Ordinary non-permission rollback uses snapshots from that attempt, not caller-supplied XML.

## Distribution and development

The inspected SDK is 10.0.100. Target `net10.0-windows` uses
[.NET 10 LTS](https://dotnet.microsoft.com/en-us/platform/support/policy).
Build scripts isolate CLI caches and NuGet settings in the repository, without modifying Git credentials.
The self-contained build pins runtime 10.0.12 and requires network access for its initial restore.
Review this pin for security maintenance before future releases.

`build/Publish-Gui.ps1 -SelfContained` builds a Windows x64 folder and ZIP with the runtime included.
Omitting the switch creates the smaller package requiring the .NET 10 Windows Desktop Runtime x64.
Users extract the whole package and run the executable. No Visual Studio/Git is required.
Single-file distribution was not selected: keeping engine scripts and the scheduler adapter as
auditable package files avoids extraction lifecycle complexity. The runtime makes the self-contained
package larger. No installer service, MSI, updater or code-signing certificate is included.
UAC is scoped to a recognized startup-task update that Windows refuses without elevation.
To open it again, use the extracted launcher or a Windows shortcut to the installed executable.

## Known limitations

- Real migration with sufficient privilege was owner-validated. The new UAC-helper flow, real logon
  behavior and GUI/PS4 backup workflow still require their respective end-to-end checks.
- UAC must elevate the same account; a standard account entering another administrator's credentials
  is not supported by this per-user helper.
- UI text is currently English. Windows can suppress tray balloons according to notification settings.
- WPF was rendered at 125%, 150% and 200%; multi-monitor DPI transitions, screen readers and a complete
  keyboard walkthrough still need manual verification. Scrollable windows support smaller work areas.
- Recent history is intentionally bounded; the complete logs remain accessible in Diagnostics.
- No GUI uninstaller: disable startup in Settings, Exit, then remove GUI files if desired. Do not run
  the v1.0.0 uninstall script against the GUI task. It refuses that action rather than deleting it.
- All engine limitations from the archived v1.0.0 guide remain, including full downloads for comparison,
  account identity limitations and no pruning/restore/cloud sync.

## Exact manual validation plan

For the new UAC flow, use a disposable Windows user/VM with a recognized v1.0.0 task whose permissions
reproduce the owner's denial. Keep Apollo offline and hash config/state/logs/ZIPs before testing.
Exit any previously running GUI, then launch v1.1.0 normally, keep automatic startup enabled and confirm the friendly one-time explanation.
First cancel the explanation, then retry and cancel UAC: neither path may claim success, show a raw
Access denied/failed-restore message or ask for Task Scheduler editing. Retry in Settings and approve
UAC as the same account. Confirm the short-lived helper exits, the existing GUI process is still
unelevated, and the stored task has the installed executable, `--background`, enabled state and Limited
principal. Reopen normally: no new UAC prompt should appear for an unchanged task. Confirm no state/ZIP
changes (normal monitor startup may append its own log entries). Repeat with an unrelated task to
confirm refusal without elevation, then complete the original PS4 validation below.

1. Keep an independent copy of important backups. Finish active backups. Record hashes/counts of the
   existing state and historical ZIPs, plus the current task action and enabled state.
2. With Apollo OFF, extract the self-contained ZIP and run `PS4ApolloAutoBackup.exe` as the ordinary
   Windows user. Confirm that v1.0.0 address, port and backup root are prefilled. Keep the same root.
3. Test connection: an offline result must allow Start. Choose automatic startup and Start. Expect
   Waiting for Apollo and no PowerShell console. Confirm historical ZIPs/state bytes remain unchanged
   before Apollo becomes reachable. New monitor log entries are expected.
4. Inspect the task: one project startup task, enabled, action pointing to the installed GUI executable
   with `--background`, current-user logon trigger. Sign out/in with no backup active. Confirm one tray
   app, one monitor and no console. Launch the executable again: the existing window should open.
5. For a separate fresh test data folder, enable Apollo with the same 21 saves. Expect 21 NEW, 0 failures.
   In the existing production folder, unchanged saves should remain UNCHANGED, not reset to NEW.
6. Choose Check saves now without changing saves. Expect 21 UNCHANGED, 0 failures, no redundant ZIPs.
   During a backup verify that another click/start is refused and Exit/Settings does not interrupt it.
7. Modify a save by playing and saving normally. Reopen Apollo after an OFF period
   of at least 12 seconds. Expect outcomes matching the content actually changed, with zero failures.
   Confirm result counts, history and one summary notification; inspect the new ZIP versions.
8. Turn Apollo OFF for at least 12 seconds and ON again. Verify one automatic comparison per transition.
   In Diagnostics, use Stop monitoring and Resume monitoring; confirm only one engine instance resumes.
9. Test a controlled unreachable address in a separate configuration. Check saves now must show a useful
   unreachable message. Restore settings. Do not corrupt or alter real state for error testing.
10. Test tray Open/Check saves now/Settings/Open backup folder/Exit, disabled notifications, startup off/on,
    missing backup folder handling, diagnostic log/folder actions and copied information.
11. Review the main/settings/diagnostics windows at 125%, 150%, 200%, keyboard-only operation and
    movement between monitors. Confirm all controls remain reachable via scrolling if necessary.
12. Exit with no backup running. Confirm the GUI-owned monitor ends and the app stays closed. Reopen
    and verify retained settings/history. Repeat migration from a disabled recognized v1.0.0 task in
    a disposable Windows user/VM, including denied scheduler permissions and an unrelated same-name task.

Do not label the new GUI PS4 validation PASS until these steps have actually been performed.
