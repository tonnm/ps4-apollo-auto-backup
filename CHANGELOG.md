# Changelog

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
