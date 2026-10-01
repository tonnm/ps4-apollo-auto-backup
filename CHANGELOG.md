# Changelog

## [1.1.0] - Unreleased

### Added

- Compact main-window UX with automatic monitoring, Check saves now, explicit last-backup outcome
  and category badges for unchanged/new/changed/failed checks. Monitor controls and technical
  Apollo lifecycle help are available in Diagnostics. No game-name database is introduced.

- C# / WPF interface on .NET 10: first-run setup, settings, connection test, status,
  backup results, recent activity, diagnostics and Windows tray notifications.
- Manual backup control, single GUI instance and coordinated engine lifetime.
- Verified migration of recognized v1.0.0 startup tasks to the GUI, including disabled tasks,
  rollback on registration failure and preservation of configuration/state/history.
- Self-contained and framework-dependent Windows x64 distribution scripts, integrity manifest,
  service/rendering tests and scheduler migration regressions.

### Fixed

- Windows PowerShell 5.1 log sharing conflict with GUI readers: append logs with explicit
  read/write sharing, preventing a reproduced exit 1 without a final backup summary.
- Show unsuccessful automatic attempts from monitor.log in Recent activity and Diagnostics,
  independently of the last completed backup's counts. See docs/incident-2026-09-29.md.
- Recognized startup-task permission failures now request a one-time UAC authorization for a
  short-lived helper; the main GUI and engine do not restart elevated. Cancellation is explained
  in plain language, stored settings are re-verified, and already-correct tasks are not rewritten.
- Skip privileged XML rollback after access denial; track successful mutations instead of marking
  a task modified before the operation returns. Record the owner's real Windows migration result.

- Launch PowerShell with console creation disabled, instead of relying on WindowStyle Hidden.
  Windows process tests verify a zero console handle and owned-process cleanup.

### Engine

- Backup and monitor log writers use a shared append helper in Common.ps1. No change to hashing,
  save identity, downloads, version publication, state persistence or OFF/ON detection.
- Real PS4/Apollo validation PASS (owner-reported 2026-09-29): GUI-open automatic changed/unchanged,
  tray automatic changed and subsequent manual unchanged checks; zero failures in all four scenarios.

## [1.0.0] - 2026-09-28

Initial public release, based on the working private V4 scripts.

### Fixed

- Migrate a recognized disabled `PS4 Apollo Save Backup` task in place instead of leaving it pointing to Documents.
- Verify ownership of both legacy and SID-named tasks before mutation; remove only a verified duplicate.
- Explicitly enable and re-read task action, principal, trigger and runtime settings after registration.
- Require Running state and a new monitor startup log before reporting installation success.
- Add regressions for disabled legacy actions, coexisting task names, failed registration/enable/start,
  incorrect persisted settings, stale logs and unrelated tasks. Uninstall recognizes migrated tasks.

### Added

- Apollo TCP availability monitoring and automatic save backup workflow.
- V4 SHA-256 content comparison, stable save identity and version history/state.
- Validated JSON configuration, interactive installer and per-user logon Scheduled Task.
- Uninstaller that preserves all backup data.
- Exclusive instance locks, non-overwriting ZIP publication and atomic state commits.
- Corrupt state preservation and archive path validation.
- Installation, migration, troubleshooting and release documentation.
- Native PowerShell local regression tests.

### Changed from private V4

- Removed developer-specific connection settings and script locations.
- Moved runtime scripts to `src`; shared configuration/file helpers live in `Common.ps1`.
- Added milliseconds and GUID to backup filenames to avoid overwriting versions.
- Commit state after each successful save; abort on corrupt state rather than replacing it.
- Restrict temporary cleanup to each run's own files; interrupted leftovers are retained.
- Use built-in .NET ZIP extraction to support bracketed directory names in PowerShell 5.1.
- Preserve the original content hash, filename identity and OFF/ON monitor behavior.
