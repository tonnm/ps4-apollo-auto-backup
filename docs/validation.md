# Local validation - v1.0.0

Validated on 2026-09-28 using Windows PowerShell 5.1 (Desktop) and built-in .NET libraries.
Run the repeatable tests from the extracted repository:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Tests create synthetic data only in the ignored `.test-artifacts` directory. HTTP requests are replaced
with fixture responses. Task Scheduler commands are replaced with test functions; the installer still
copies real files, validates configuration, acquires locks and updates state on disk in that directory.
Git, if present, is used only in a disposable fixture repository to check ignore rules. It is not a runtime
dependency. No production task, installed application, PS4 save, repository credentials or remote is changed.

## Results

Latest complete local run after the legacy-task fix: **158 assertions passed**, including the optional
local V4 reference and Git ignore checks. There are no real Scheduler writes in this suite.

| Status | Check | Scope / evidence |
| --- | --- | --- |
| PASS | PowerShell syntax | Every shipped `.ps1` parsed by Windows PowerShell 5.1 |
| PASS | Configuration | Example JSON accepted; invalid address, ports and relative/root paths rejected |
| PASS | Original V4 hash equivalence | Original function and released function produce the same hash on a synthetic ZIP; fixed expected hash retained in public tests |
| PASS | Content comparison | ZIP timestamp/order and extraction root changes leave hash unchanged; file content and internal filename changes change it |
| PASS | Save identity | A changed Apollo export/list position produces no redundant ZIP |
| PASS | NEW / CHANGED / UNCHANGED | Full backup script exercised with two synthetic saves and exact version counts |
| PASS | Special characters | Backup root and save name containing brackets work |
| PASS | Archive validation | Invalid ZIPs and traversal paths rejected; unsafe save names skipped |
| PASS | Network failure handling | Injected page/download failures preserve state bytes and all existing ZIPs |
| PASS | Partial success | Successful save committed; failed save retains previous entry |
| PASS | Missing/corrupt state | Missing state creates new entries; corrupt state remains unchanged and exits 13 |
| PASS | Atomic write failure | Locked destination forces replacement failure; previous state remains intact |
| PASS | Concurrent execution | A separate PowerShell backup/monitor process is refused while its file lock is held |
| PASS | Monitor transitions | Real loop with injected OFF/ON sequence runs twice, waits while online, rearms after disconnect even after backup failure |
| PASS | Installation and reinstallation | Isolated filesystem deployment, disabled-task update, explicit enable and startup confirmation; Scheduler API mocked |
| PASS | Legacy task migration | Disabled Documents action replaced under the same legacy name; verified SID duplicate removed; legacy files and backups preserved |
| PASS | Task settings and ownership | Re-read persisted action, enabled flags, current user, interactive/limited, logon trigger, working directory, battery/restart/runtime settings; unknown owner/action/source refused before mutation |
| PASS | Registration and startup failures | Missing/no-op/denied registration, enable failures, wrong persisted settings, no-op/denied start and Running without a new startup log all fail without success messages |
| PASS | Uninstall preservation | Known application files/task removed in fixture; backups, state and unknown files preserved |
| PASS | `.gitignore` | Git check-ignore verifies runtime exclusions and retention of public source/example configuration |
| PASS | Documentation/reference review | Relative documentation links and installed script paths reviewed against final layout |
| PASS | Privacy review | Public source scanned for private IPs, original personal identifiers, user paths, MACs and credential patterns |
| NOT TESTED | Actual Task Scheduler registration/logon | Local CIM constructor access returned Access denied. Mock tests do not prove task registration or launch on the target Windows installation |
| NOT TESTED | Console exports and end-to-end backup | NOT TESTED — requires real PS4/Apollo environment |
| NOT TESTED | Physical power loss, disk removal/full disk | File locking/write-failure tests cover selected failure boundaries, not hardware behavior |
| NOT TESTED | Restore on PS4 | No restore automation is supplied; requires real PS4/Apollo environment |

The original V4 function was kept temporarily under ignored test artifacts for direct comparison; the
published fixed regression vector makes the core comparison repeatable without shipping private scripts.
The suite reports one additional assertion if that local reference is present.

No unresolved local test failures remain. Actual console compatibility and Windows startup behavior
must be checked before describing this release as verified in production.

## Why the original task tests missed the migration bug

The initial installer and mock both used only `PS4ApolloAutoBackup-<SID>`. The mock stored one task and
replaced it on registration; it never represented the separately named `PS4 Apollo Save Backup` task,
its disabled state or its Documents action. Post-registration checks examined the action only, and the
startup test merely counted `Start-ScheduledTask` calls. Consequently those tests could pass while the
legacy task remained untouched and startup was unconfirmed.

`tests/TaskSetup-Tests.ps1` now models tasks by name, retains disabled state across registration, exposes
the persisted settings, and simulates startup evidence separately from the start request. It exercises
both names together, unrelated tasks and failed/no-op Scheduler operations. No real Scheduler API is
called by these automated tests; the new code still needs a real installation check on the target PC.

## Privacy findings

The original hardcoded console IP and developer-specific script placement were removed from runtime code.
No real account ID, PSN ID, MAC, credential or token is included in runtime code.
`config.example.json` uses a documentation-only address. The unchanged `AGENTS.md` includes generic
private-IP and user-path examples as instructions; these are not the original developer's settings.
Generated fixture configurations, logs, absolute paths and ZIPs are ignored and must not be packaged.
The owner's attribution in `LICENSE` is intentional and was not modified by the task migration fix.
