# PS4 Apollo Auto Backup v1.0.0

Original CLI release; preserved historical baseline. For the first GUI release, see release-v1.1.0.md.

## Highlights

- Automatic Apollo monitoring and versioned save backups.
- V4 SHA-256 content comparison avoids redundant stored ZIPs.
- Configurable installation with a per-user Windows logon task.
- Backups preserved during uninstall; safe state commits and instance locks.
- English setup, migration and troubleshooting documentation.

## Before publishing

The owner's chosen attribution is recorded in `LICENSE`.
Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1`.
Review [validation results](validation.md), especially tests requiring a real PS4 and Windows task execution.
Review staged files for local configuration and personal data before committing.

The v1.0.0 tag already exists and must not be moved or recreated. To archive that historical source:

```powershell
New-Item -ItemType Directory -Force dist | Out-Null
git archive --format=zip --prefix=ps4-apollo-auto-backup/ --output=dist/ps4-apollo-auto-backup-v1.0.0.zip v1.0.0
```

Only committed source/documentation belongs in the archive. `.gitignore` does not remove files already
tracked, so inspect the commit first. Do not include real `config.json`, state, logs, saves or test outputs.
No remote repository, push, release upload or Git credentials are managed by these scripts.
