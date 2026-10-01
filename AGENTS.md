# PS4 Apollo Auto Backup — GUI v1.1.0

## Context

Version v1.0.0 has been validated against a real Windows + PS4 + Apollo Save Tool environment.

Real-world validation successfully covered:

- Windows Scheduled Task migration
- monitor startup
- Apollo OFF → ON detection
- 21 saves discovered
- initial backup: 21 NEW, 0 failures
- second backup: 21 UNCHANGED, 0 failures
- real game-save save modification: 5 CHANGED, 16 UNCHANGED, 0 failures
- monitor OFF/ON rearming

The v1.0.0 Git tag is the known-good engine baseline.

The goal of v1.1.0 is to add a friendly Windows graphical interface without destabilizing the validated backup engine.

---

# 1. Primary rule: protect the engine

Treat these files and their behavior as validated:

- `src/Backup-PS4.ps1`
- `src/Monitor-PS4.ps1`
- V4 SHA-256 comparison algorithm
- NEW / CHANGED / UNCHANGED semantics
- Apollo communication
- backup state persistence
- backup version creation
- OFF/ON monitor behavior

Do NOT rewrite the backup algorithm.

Do NOT port the backup engine to C# in v1.1.0.

Do NOT change save identity semantics.

Do NOT optimize save downloading in this release.

If integration requires a change to the PowerShell engine, keep it minimal and explain why it is necessary.

Existing regression tests must continue to pass.

---

# 2. Goal

Turn PS4 Apollo Auto Backup from a PowerShell-oriented tool into a user-friendly Windows application.

Normal users should not need to understand:

- PowerShell
- Scheduled Tasks
- JSON
- command-line arguments
- exit codes
- SHA-256

The application should feel like a small native Windows utility.

---

# 3. Technology

Preferred GUI:

C# + WPF.

Use a current supported .NET version available in the development environment.

Before choosing the target framework:

1. inspect installed .NET SDKs;
2. select an appropriate supported target;
3. document the requirement.

Avoid:

- Electron
- Node.js runtime
- Python runtime
- browser-based UI
- unnecessary third-party frameworks.

Prefer built-in .NET/WPF functionality.

The final release should preferably support self-contained or otherwise simple distribution if practical.

Do not introduce a large runtime requirement without documenting the tradeoff.

---

# 4. Architecture

Keep responsibilities separated.

Conceptual architecture:

GUI application
|
+-- configuration
+-- status
+-- tray icon
+-- notifications
+-- backup history
+-- diagnostics
|
+---- controls validated PowerShell engine
|
+-- Monitor-PS4.ps1
|
+-- Backup-PS4.ps1
|
+-- Apollo Save Tool

The GUI is the presentation/control layer.

PowerShell remains the backup engine for v1.1.0.

---

# 5. Main window

Create a clean, simple main window.

Conceptual layout:

PS4 Apollo Auto Backup

[status indicator] Monitoring
Waiting for Apollo

PS4
Address: 192.168.x.x
Apollo port: 8080

Last backup
Date/time

21 saves checked
5 changed
16 unchanged
0 failures

[ Backup now ]
[ Open backup folder ]

Recent activity

22:32 Backup completed — 5 changed
22:13 Backup completed — no changes

[ Settings ]

Do not copy this layout mechanically if a better native WPF layout is appropriate.

Prioritize clarity.

---

# 6. Status states

The GUI must clearly represent at least:

Monitoring

Waiting for Apollo

Apollo detected

Backup in progress

Backup completed

Backup completed with failures

Monitor stopped

Configuration error

PS4/Apollo unreachable

Use human-readable messages.

Do not expose raw exit codes as the primary user-facing status.

Diagnostics may show technical details.

---

# 7. Backup progress

When a backup is running, show useful progress if this can be implemented without invasive changes to the validated engine.

Example:

Backing up saves...

16 / 21

If reliable progress requires major changes to Backup-PS4.ps1, do NOT modify the engine just for progress.

In that case show:

Backup in progress...

and derive the final result from the existing logs/state.

Engine stability is more important than a progress bar.

---

# 8. Backup results

After a backup, display:

total saves checked
new
changed
unchanged
failures
time completed

Example:

Backup completed

21 saves checked
0 new
5 changed
16 unchanged
0 failures

The GUI should obtain these values from a stable integration mechanism.

Prefer parsing a structured result/state if one already exists.

Avoid fragile parsing of console formatting when possible.

If structured status output requires a very small additive engine change, propose and document it before changing validated behavior.

---

# 9. Backup Now

Provide:

Backup now

This should invoke the existing backup engine manually.

Prevent concurrent backups.

While a backup is already running:

- disable the button;
- show that backup is in progress.

Do not permit two Backup-PS4 processes to race.

Existing engine locking remains the final safety mechanism.

---

# 10. Open Backup Folder

Provide:

Open backup folder

Open the configured backup root using Windows Explorer.

Handle missing directories gracefully.

---

# 11. Settings

Create a Settings screen/dialog.

Fields:

PS4 IP address
Apollo port
Backup folder
Start automatically with Windows
Show notifications

Optional:

Start minimized
Minimize to tray

Validate values before saving.

Configuration should remain compatible with the existing engine.

Do not store secrets because none are required.

---

# 12. Connection test

Settings should provide:

Test connection

Possible results:

Apollo detected
Connection successful

or:

Apollo not detected

The second result should not be treated as a fatal configuration error because the PS4 or Apollo may simply be offline.

---

# 13. First-run experience

A new user should not have to execute install.ps1 manually if the GUI can reasonably handle initial configuration.

On first launch:

Welcome to PS4 Apollo Auto Backup

PS4 IP address
Apollo port
Backup folder

[ Test connection ]

[ Start ]

If Apollo is offline:

Apollo could not be reached.
You can continue setup and the application will monitor it later.

Do not block setup solely because Apollo is unavailable.

---

# 14. System tray

The application should support the Windows notification area/system tray.

Normal background operation should not require an open PowerShell console.

Tray behavior:

PS4 Apollo Auto Backup
Monitoring

Menu:

Open
Backup now
Open backup folder
Settings
Exit

Closing the main window should preferably minimize to tray when monitoring is enabled.

Provide a clear way to fully exit.

---

# 15. No visible monitor console

Normal v1.1.0 operation must not leave the Monitor-PS4 PowerShell console visible.

This is a specific issue observed during real v1.0.0 validation.

The existing Scheduled Task used `-WindowStyle Hidden`, but a console window was still visible.

Investigate the actual cause.

Fix it without destabilizing monitor behavior.

Do not merely move the window off-screen.

The normal user experience must be console-free.

A diagnostics/developer mode may intentionally expose logs or a console if useful.

---

# 16. Notifications

Use Windows notifications where practical.

Examples:

Backup completed
5 saves changed. 0 failures.

Backup warning
1 save could not be backed up.

Avoid notifications for every UNCHANGED save.

Do not spam the user.

Allow notifications to be disabled.

---

# 17. Recent activity

Display a small recent history.

Examples:

22:32 Backup completed — 5 changed
22:13 Backup completed — no changes
22:09 Initial backup — 21 saves

Do not scan unlimited log history on every UI refresh.

Use a reasonable bounded amount of data.

---

# 18. Diagnostics

Provide a Diagnostics section.

Useful actions:

Open monitor log
Open backup log
Open installation folder
Open backup folder
Copy diagnostic information

Display:

application version
engine version
configured PS4 address
Apollo port
monitor state
last backup time
last backup result

Do not include private save contents in copied diagnostics.

---

# 19. Tray/application lifecycle

Define lifecycle carefully.

There should be one authoritative background monitoring instance.

Avoid:

GUI monitor

- Scheduled Task monitor
- manual monitor

running simultaneously.

Determine a clean ownership model.

Preferred direction:

The GUI/tray application owns user-facing lifecycle.

The existing monitor engine may run hidden as a child/background process or through a clearly coordinated mechanism.

Existing locking protections must remain.

Document the final lifecycle architecture.

---

# 20. Windows startup

Users should be able to enable:

Start automatically with Windows

The GUI should manage this safely.

If the existing Scheduled Task remains the best mechanism, adapt it to launch the GUI/tray application rather than presenting a PowerShell console.

Migration from v1.0.0 must be supported.

Existing users must not need to manually delete their v1.0.0 task.

---

# 21. Migration from v1.0.0

This is mandatory.

Existing v1.0.0 users may already have:

%LOCALAPPDATA%\PS4ApolloAutoBackup

config.json

backup-state-v4.json

existing backups

Scheduled Task:
PS4 Apollo Save Backup

v1.1.0 must preserve:

configuration
backup state
backup history
all existing backups

Never reset the user's save history merely because the GUI was installed.

Migration must be tested.

---

# 22. Installation/distribution

Investigate the simplest safe distribution.

Preferred user experience:

Download release
→ run setup/application
→ configure PS4
→ done

Users should not need Git.

Users should not need Visual Studio.

Users should not need to manually create Scheduled Tasks.

Users should not need to manually edit JSON.

If producing a single executable is practical, evaluate it.

Do not sacrifice maintainability merely to achieve one file.

---

# 23. Visual design

Use a restrained Windows-native visual style.

Avoid:

- gamer neon overload;
- giant gradients;
- excessive animations;
- PlayStation/Sony copyrighted artwork;
- unofficial use of Sony logos.

A simple controller/save/cloud-style generic icon may be used if legally appropriate and original.

Support normal Windows DPI scaling.

The application must remain usable at 125%, 150% and 200% scaling.

---

# 24. Accessibility

Use readable font sizes.

Provide clear labels.

Do not communicate status using color alone.

Controls should work with keyboard navigation.

Use appropriate accessible names/tooltips where necessary.

---

# 25. Error handling

Translate technical failures into useful messages.

Instead of:

Exit code 20

show:

Backup failed while downloading one or more saves.

Then provide:

View details

Diagnostics can contain the technical exit code.

---

# 26. Existing tests

All existing v1.0.0 tests must continue passing.

Currently the suite contains 158 assertions.

Do not delete tests merely because the GUI architecture changes.

Add tests for GUI-supporting services where practical, especially:

configuration
migration
status parsing
single-instance behavior
startup registration
backup invocation
history/result parsing

UI rendering itself does not need excessive automated testing.

---

# 27. Real-world validation

Do not claim real PS4 validation for new GUI functionality until manually tested.

Clearly separate:

PASS — automated
PASS — Windows real environment
NOT TESTED — requires PS4/Apollo

---

# 28. Versioning

Target:

v1.1.0

Do NOT move or recreate the existing v1.0.0 Git tag.

Update:

CHANGELOG.md
README.md
documentation

Do not create the v1.1.0 Git tag automatically.

---

# 29. Git safety

Work on the current feature branch.

Do not:

push
force push
rewrite v1.0.0 history
delete tags
modify Git credentials

The existing v1.0.0 commit/tag is the stable baseline.

---

# 30. Final report

At completion provide:

## Architecture

Explain how GUI, monitor and backup engine interact.

## Changes made

Files added/modified.

## Engine changes

Explicitly state whether Backup-PS4.ps1 or Monitor-PS4.ps1 changed and why.

## Tests

PASS / FAIL / NOT TESTED.

## Migration

Explain v1.0.0 → v1.1.0 behavior.

## Distribution

Explain how a normal user installs/runs the application.

## Known limitations

List remaining limitations.

## Manual test plan

Provide exact steps for testing against a real PS4/Apollo environment.

Do not create a Git tag or push.

---

# Core principle

v1.0.0 proved that the backup engine works.

v1.1.0 should make it pleasant to use.

Do not trade proven backup reliability for visual improvements.
