# PS4 Apollo Auto Backup v1.0.0

Initial public release.

## Highlights

- Automatic Apollo monitoring and versioned save backups.
- V4 SHA-256 content comparison avoids redundant stored ZIPs.
- Configurable installation with a per-user Windows logon task.
- Backups preserved during uninstall; safe state commits and instance locks.
- English setup, migration and troubleshooting documentation.

## Before publishing

Replace `[COPYRIGHT HOLDER]` in `LICENSE` with the owner's chosen attribution.
Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1`.
Review [validation results](validation.md), especially tests requiring a real PS4 and Windows task execution.
Review staged files for local configuration and personal data before committing.

After reviewing and making the release commit, optionally tag it `v1.0.0` and package committed files:

```powershell
git tag v1.0.0
New-Item -ItemType Directory -Force dist | Out-Null
git archive --format=zip --prefix=ps4-apollo-auto-backup/ --output=dist/ps4-apollo-auto-backup-v1.0.0.zip v1.0.0
```

Only committed source/documentation belongs in the archive. `.gitignore` does not remove files already
tracked, so inspect the commit first. Do not include real `config.json`, state, logs, saves or test outputs.
No remote repository, push, release upload or Git credentials are managed by these scripts.
