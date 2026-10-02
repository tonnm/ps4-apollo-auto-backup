# PS4 Apollo Auto Backup

Automatic, versioned PS4 save backups from Apollo Save Tool to Windows.

## ⬇️ Download

**[Download PS4 Apollo Auto Backup v1.1.0](https://github.com/tonnm/ps4-apollo-auto-backup/releases/download/v1.1.0/v1.1.0-win-x64-self-contained.zip)**

Windows x64 · Self-contained · No separate .NET installation required

[View the latest release](https://github.com/tonnm/ps4-apollo-auto-backup/releases/latest)

## What it does

- Automatically backs up saves when Apollo becomes available.
- Creates new versions only when save contents actually change.
- Runs in the Windows tray and in the background.
- Lets you run **Check saves now** manually.
- Provides backup history and diagnostics.
- Never overwrites existing backup versions.

## Quick start

1. Download and extract the whole ZIP.
2. Run `PS4ApolloAutoBackup.exe`.
3. Configure your PS4 IP address, Apollo port (normally `8080`), and backup folder.
4. Start monitoring.
5. Open Apollo Save Tool on your PS4 and enable its web server.

Closing the window keeps monitoring in the Windows tray; choose **Exit** from the tray menu to stop the application completely.

## Requirements

- Windows x64
- PS4 with Apollo Save Tool
- PC and PS4 reachable on the same network
- Windows PowerShell 5.1

The self-contained download includes the required .NET runtime.

## How backups work

- **NEW:** the first version of a save is stored.
- **CHANGED:** changed save contents are stored as a new version.
- **UNCHANGED:** no additional version is stored.

Existing backup versions are never overwritten.

**Restore from the GUI is not available yet. Keep independent copies of important saves.**

## Documentation

- [Troubleshooting](docs/troubleshooting.md)
- [Validation](docs/validation.md)
- [GUI / technical documentation](docs/gui-v1.1.0.md)
- [Changelog](CHANGELOG.md)

## ☕ Support the project

PS4 Apollo Auto Backup is free and open source.

If this project has been useful to you, you can support its continued development by buying me a coffee.

☕ Donation link coming soon.

Support is completely optional and does not unlock features.

## Development

Created and maintained by [tonnm](https://github.com/tonnm).

Developed with assistance from OpenAI Codex for implementation, testing, debugging and code review. Final design decisions and real-device validation are performed by the project maintainer.

## License and disclaimer

Released under the [MIT License](LICENSE).

This project is not affiliated with Sony Interactive Entertainment or Apollo Save Tool.
