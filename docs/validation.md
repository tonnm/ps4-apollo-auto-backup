# Local validation

## Clean source release preparation — 2026-09-30

PASS: 165 engine assertions, 78 GUI/service assertions, 53 migration assertions in an isolated source
copy with no pre-existing build output, production files or optional local V4 reference. Counts vary
because the engine suite also counts syntax checks of scripts present in the checkout. No tests were
weakened to match older counts. The same source is used for the self-contained release build.

An initial excessively nested clean copy failed at ZIP publication (a generated path was 262
characters) and GUI File.Replace. The unchanged tests passed after using a shorter clean source root.
Use a short workspace and backup root on Windows PowerShell 5.1; long paths are not newly supported.
These environment failures are retained in private validation logs, not counted as successful runs.

## Real PS4/Apollo validation — v1.1.0 — PASS

Owner-reported results completed on 2026-09-29, separate from automated fixture tests:

| Scenario | Checked | New | Changed | Unchanged | Failures | Outcome |
| --- | --- | --- | --- | --- | --- | --- |
| Automatic, GUI open and polling history | 22 | 0 | 4 | 18 | 0 | Successful automatic completion |
| Automatic, GUI open, no further modifications | 22 | 0 | 0 | 22 | 0 | Successful; changed content recognized without duplication |
| Automatic, main window closed, tray running; one deliberately modified save | 22 | 0 | 1 | 21 | 0 | Successful; reopening GUI recovered the result |
| Check saves now, no modifications after tray backup | 22 | 0 | 0 | 22 | 0 | Successful; no duplicate version |

The four initial changes were legitimate changes from normal gameplay during development/testing.
The GUI stayed open and polling during the first two scenarios; no log-sharing failure occurred.
The tray/manual sequence confirms the automatic changed-save run committed state correctly.
No game, account or save identifiers are required to reproduce this validation record.

The PowerShell 5.1 sharing defect was deterministically reproduced. The fix is now validated in real
GUI-open and tray/background use. The exception from the original failed attempt was not persisted:
historical causation remains strongly supported, not conclusively recovered.
This does not certify every UAC/logon, restore or physical failure scenario listed below.

## v1.1.0 — 2026-09-29

Windows PowerShell 5.1, .NET SDK 10.0.100, Windows x64. No production installation,
task, backup or Git credential was changed. Fixture data lives under `.test-artifacts`.

| Status | Validation | Result |
| --- | --- | --- |
| PASS — automated | Complete original regression suite | 186 assertions, including shared-log regression and syntax checks for generated package copies; original assertions retained |
| PASS — automated | GUI/core services and WPF rendering | 78 assertions including failed automatic history and startup authorization flow |
| PASS — automated | GUI task migration adapter | 53 assertions; all Scheduler commands mocked |
| PASS — Windows real environment | PowerShell process creation | New launcher reports GetConsoleWindow() = 0 |
| PASS — Windows real environment | Process lifetime | Closing the job terminates its owned test child |
| PASS — Windows real environment | Baseline monitor | Actual unchanged monitor starts hidden with loopback/offline synthetic configuration |
| PASS — Windows real environment | Helper entry point | Invalid arguments exit before GUI/deployment/startup access; actual UAC is not invoked by automated tests |
| PASS — automated | WPF layout rendering | Compact main window fits three activity rows without scrolling in simulated 1080p work area at 125%, 150%, 200%; first-run dialog; synthetic content |
| PASS — build | Framework-dependent and self-contained x64 | .NET 10; runtime 10.0.12 included in self-contained package |
| PASS — baseline algorithm | Engine | Only shared log appending differs from v1.0.0; hashing/state/downloads/OFF-ON unchanged; tag retained. See incident-2026-09-29.md |
| PASS — Windows real environment (owner report) | v1.0.0 task → GUI migration with sufficient privilege | Same build failed unelevated, succeeded once elevated; stored action is installed PS4ApolloAutoBackup.exe with --background |
| NOT TESTED | New dedicated UAC helper, cancellation through actual Windows UAC, real logon/full tray interaction | Requires end-to-end test; automated runs do not modify real tasks or trigger UAC |
| PASS — owner-reported | GUI + real PS4/Apollo | Four scenarios above; future repeat plan in gui-v1.1.0.md |

Repeat with `tests/Run-Tests.ps1`, `tests/Gui-Migration.Tests.ps1`, and `build/Test-Gui.ps1` in
separate Windows PowerShell processes. Build with `build/Publish-Gui.ps1` (optionally `-SelfContained`).
The initial runtime download was blocked by sandbox networking; the authorized network-enabled
build succeeded. This was an environment restore failure, not an engine test failure.

During the authorization revision, restricted runs of the original suite also failed in the synthetic
v1.0.0 installer at `File.Replace` (unable to remove the replaced file). The unchanged complete suite
passed when rerun outside that filesystem restriction, still using only workspace fixtures and mocked
Scheduler operations. This does not establish the exact external cause of the restricted-file failure;
no engine or installer change was made to bypass it. Logs are retained under `.test-artifacts`.

GUI tests cover configuration/validation, old field compatibility, bounded result parsing,
single-instance activation, engine locks, invocation, process creation and deployment preservation.
Migration regressions use a keyed persisted task collection, independent reads and fault injection:
disabled old action, no-op registration, no-op enable, incorrect settings, thrown registration,
rollback/restart, duplicate tasks, unrelated action/user, active backup/monitor and startup preference.
Unlike a mock that merely returns the requested task, these tests do not equate a successful cmdlet
return with stored state. They exercise the production adapter's post-registration verification.
They still cannot prove real Task Scheduler behavior; that limitation is explicit.

Permission regressions cover denied export/stop/register/enable, localized messages/HRESULT,
no denied XML rollback, helper retry, read-only post-verification, no repeated registration for an
already-correct task and ownership revalidation. GUI orchestration tests cover ordinary startup without
UAC, explanation/consent, cancellation (including Windows error 1223), failed helper, wrong Windows
identity, false-success rejection, request validation/cleanup and configuration preservation.

Real Windows migration was subsequently reported by the owner: `PS4 Apollo Save Backup`, previously
running `Monitor-PS4.ps1`, was successfully changed with sufficient privilege to
`%LOCALAPPDATA%\PS4ApolloAutoBackup\gui\1.1.0\PS4ApolloAutoBackup.exe --background`.
The same build without elevation returned Access denied and a failed-rollback message. The helper and
rollback changes address that confirmed permission boundary. Do not label the newly added UAC flow
as real-Windows validated until the manual authorization tests are performed.

The legacy Hidden comparison returned exit 0 and console handle 0 in this hosted environment too.
An initial assertion expecting a nonzero old-style handle failed; it was corrected to a diagnostic
comparison because host policy controls allocation. The new no-console assertion remains mandatory.
The user's visible-window symptom was not reproduced here, and its historical process origin is unknown.

Owner-reported PS4 validation applies to **v1.0.0 only**: 21 NEW, 21 UNCHANGED,
then 5 CHANGED + 16 UNCHANGED following the game-save modification, all with zero failures.

## Archived v1.0.0 validation

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
