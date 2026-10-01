# PS4 Apollo Auto Backup v1.1.0 — first GUI release

v1.0.0 is the original CLI release and its commit/tag remain unchanged. v1.1.0 contains the complete
WPF GUI/tray application and the validated concurrent-log/failed-attempt fix. v1.2.0 is future work.

## Version semantics

Product/GUI/package version is 1.1.0. EngineVersion and `Starting backup v1.0.0 (V4 content comparison)`
identify the validated algorithm baseline, not the GUI product version. The log writer changed for
GUI integration; save identity, hashing, publication and state semantics did not. The GUI's start-line
parser intentionally retains the matching literal. V4 state format, WindowsPowerShell/v1.0 and
XML/runtime/framework versions have unrelated meanings and are not renamed.

## Build privacy

Directory.Build.props applies deterministic compilation and PathMap from the source root to `/_/`
across the projects, including WPF compilation. This uses the standard compiler mechanisms, without
binary rewriting. See [MSBuild properties](https://learn.microsoft.com/en-us/visualstudio/msbuild/common-msbuild-project-properties)
and [folder customization](https://learn.microsoft.com/en-us/visualstudio/msbuild/customize-by-directory).
Validate from a clean source export and empty output directories. Scan DLL/EXE/PDB and all package
entries, including documentation, before distribution. Deterministic compiler output does not promise
identical ZIP bytes: archive timestamps and restore/toolchain inputs are separate concerns.

## Validation and distribution

See [validation](validation.md) for real PS4 results reported by the owner, and [incident analysis](incident-2026-09-29.md)
for deterministic reproduction and historical uncertainty. The public report uses neutral save labels.
No production configuration, logs, state, saves, private reports or build caches belong in source control.

Build with `powershell -NoProfile -ExecutionPolicy Bypass -File build/Publish-Gui.ps1 -SelfContained`.
Extract the whole package and launch PS4ApolloAutoBackup.exe; do not move the executable alone.
Do not install automatically during release verification. Before a manual upgrade, finish active backups
and exit the old tray instance. Existing configuration, history and saves are preserved.

An annotated v1.1.0 tag is a separate approval step after the release commit. No tag, remote or hosted
release is created by these build scripts. Preserve the original CLI v1.0.0 tag.
