# Removes only application files. Saves, logs, state and temporary data are retained.
$ErrorActionPreference = 'Stop'
$installRoot = Join-Path $env:LOCALAPPDATA 'PS4ApolloAutoBackup'
$locks = @()
try {
    if (-not (Test-Path -LiteralPath $installRoot)) { Write-Host '[OK] Application is not installed.'; exit 0 }
    . (Join-Path $PSScriptRoot 'src\Common.ps1')
    $marker = Join-Path $installRoot '.installed'
    if (-not (Test-Path -LiteralPath $marker) -or (Get-Content -LiteralPath $marker -Raw).Trim() -ne 'PS4ApolloAutoBackup-v1') {
        throw 'Installation marker is missing or invalid. No files were removed.'
    }
    $config = Read-BackupConfig (Join-Path $installRoot 'config.json')
    $tasks = @()
    foreach ($name in @('PS4 Apollo Save Backup', (Get-AppTaskName))) {
        # Only installed v1 actions are accepted here; never uninstall an unmigrated V4 task.
        $task = Get-OwnedAppTask $name $installRoot
        if ($task) { $tasks += $task }
    }
    foreach ($task in $tasks) { Stop-ScheduledTask -TaskName $task.TaskName -TaskPath '\' }
    if (Test-Path -LiteralPath $config.backupPath) {
        foreach ($name in 'monitor', 'backup') {
            $handle = $null
            for ($attempt = 0; $attempt -lt 20; $attempt++) {
                try { $handle = Enter-AppLock $config.backupPath $name; break }
                catch { Start-Sleep -Milliseconds 250 }
            }
            if (-not $handle) { throw 'Close manual monitor/backup instances and check folder permissions, then retry. Backups were preserved.' }
            $locks += $handle
        }
    }
    foreach ($task in $tasks) { Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath '\' -Confirm:$false }
    # Explicit file allowlist: never recursively remove the installation directory.
    foreach ($relative in @('src\Backup-PS4.ps1', 'src\Monitor-PS4.ps1', 'src\Common.ps1', 'config.json', '.installed', 'uninstall.ps1')) {
        $path = [IO.Path]::GetFullPath((Join-Path $installRoot $relative))
        if (-not $path.StartsWith([IO.Path]::GetFullPath($installRoot).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to remove a file outside the installation folder.'
        }
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
    }
    foreach ($path in @((Join-Path $installRoot 'src'), $installRoot)) {
        if ((Test-Path -LiteralPath $path) -and @(Get-ChildItem -LiteralPath $path -Force).Count -eq 0) {
            [IO.Directory]::Delete($path, $false)
        }
    }
    Write-Host '[OK] Scheduled Task and installed application files removed.'
    Write-Host "[OK] All backups, state and logs preserved in: $($config.backupPath)"
    Write-Host 'Backup deletion is intentionally manual; uninstall never deletes saves.'
}
catch { Write-Host "[ERROR] Uninstall did not complete: $($_.Exception.Message)"; exit 1 }
finally { foreach ($handle in $locks) { $handle.Dispose() } }
exit 0
