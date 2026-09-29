# PS4 Apollo Auto Backup v1.0.0 - per-user setup; no administrator required.
param([string]$Ps4Address, [int]$ApolloPort, [string]$BackupPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'src\Common.ps1')
$installRoot = Join-Path $env:LOCALAPPDATA 'PS4ApolloAutoBackup'
$taskName = Get-AppTaskName
$locks = @()
$probe = $null
$taskStopped = $false
try {
    Write-Host '========================================'
    Write-Host 'PS4 Apollo Auto Backup - Setup v1.0.0'
    Write-Host '========================================'
    foreach ($command in 'Register-ScheduledTask', 'Get-FileHash') {
        $null = Get-Command $command -ErrorAction Stop
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $sourceFiles = @('src\Common.ps1', 'src\Backup-PS4.ps1', 'src\Monitor-PS4.ps1', 'uninstall.ps1')
    foreach ($relative in $sourceFiles) {
        $file = Join-Path $PSScriptRoot $relative
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing release file: $relative" }
        $tokens = $null; $errors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
        if ($errors.Count) { throw "PowerShell syntax error in $relative" }
    }
    $oldConfig = $null
    if (Test-Path -LiteralPath $installRoot) {
        if (-not (Test-Path -LiteralPath (Join-Path $installRoot '.installed'))) {
            throw 'Installation directory already exists without the application marker. Choose another directory for those files before setup.'
        }
        if ((Get-Content -LiteralPath (Join-Path $installRoot '.installed') -Raw).Trim() -ne 'PS4ApolloAutoBackup-v1') {
            throw 'Unknown installation marker; setup stopped.'
        }
        $oldConfig = Read-BackupConfig (Join-Path $installRoot 'config.json')
    }
    if (-not $Ps4Address) {
        $prompt = 'PS4 IP address'
        if ($oldConfig) { $prompt += " [$($oldConfig.ps4Address)]" }
        $Ps4Address = Read-Host $prompt
        if (-not $Ps4Address -and $oldConfig) { $Ps4Address = $oldConfig.ps4Address }
    }
    if (-not $PSBoundParameters.ContainsKey('ApolloPort')) {
        $defaultPort = 8080
        if ($oldConfig) { $defaultPort = $oldConfig.apolloPort }
        $answer = Read-Host "Apollo port [$defaultPort]"
        if ($answer) {
            if (-not [int]::TryParse($answer, [ref]$ApolloPort)) { throw 'Port must be an integer.' }
        }
        else { $ApolloPort = $defaultPort }
    }
    if (-not $BackupPath) {
        $defaultPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PS4-Saves'
        if ($oldConfig) { $defaultPath = $oldConfig.backupPath }
        $BackupPath = Read-Host "Backup root folder [$defaultPath]"
        if (-not $BackupPath) { $BackupPath = $defaultPath }
    }
    # Validate before stopping or modifying an existing installation.
    $probe = Join-Path ([IO.Path]::GetTempPath()) ("ps4-setup-" + [guid]::NewGuid() + '.json')
    Write-AtomicJson @{ ps4Address = $Ps4Address; apolloPort = $ApolloPort; backupPath = $BackupPath } $probe
    $config = Read-BackupConfig $probe
    $appPrefix = [IO.Path]::GetFullPath($installRoot).TrimEnd('\')
    if ($config.backupPath -eq $appPrefix -or $config.backupPath.StartsWith($appPrefix + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Backups must be outside the application installation directory.'
    }
    # Validate both names before any mutation. Keep the legacy name when migrating.
    $tasks = @()
    foreach ($name in @('PS4 Apollo Save Backup', (Get-AppTaskName))) {
        $existing = Get-OwnedAppTask $name $installRoot -AllowLegacy
        if ($existing) { $tasks += $existing }
    }
    if ($tasks.TaskName -contains 'PS4 Apollo Save Backup') { $taskName = 'PS4 Apollo Save Backup' }
    foreach ($task in $tasks) {
        if ([string]$task.State -in @('Ready', 'Disabled')) { continue }
        Stop-ScheduledTask -TaskName $task.TaskName -TaskPath '\' -ErrorAction Stop
        $taskStopped = $true
        # Legacy V4 has no instance locks. Confirm it stopped before touching application data.
        $stopped = $false
        for ($attempt = 0; $attempt -lt 60; $attempt++) {
            $observed = Get-OwnedAppTask $task.TaskName $installRoot -AllowLegacy
            if ($observed -and [string]$observed.State -in @('Ready', 'Disabled')) { $stopped = $true; break }
            Start-Sleep -Milliseconds 250
        }
        if (-not $stopped) { throw "Task '$($task.TaskName)' did not stop. No application files have been replaced." }
    }
    $roots = @($config.backupPath)
    if ($oldConfig) { $roots += $oldConfig.backupPath }
    foreach ($root in ($roots | Select-Object -Unique)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        # A manual monitor/backup is never killed. Wait briefly for the stopped task to release handles.
        foreach ($name in 'monitor', 'backup') {
            $handle = $null
            for ($attempt = 0; $attempt -lt 20; $attempt++) {
                try { $handle = Enter-AppLock $root $name; break }
                catch { Start-Sleep -Milliseconds 250 }
            }
            if (-not $handle) { throw 'An instance is still running, or the data folder is not writable. Close manual instances and retry.' }
            $locks += $handle
        }
    }
    foreach ($folder in 'Backups', 'Temp') {
        New-Item -ItemType Directory -Path (Join-Path $config.backupPath $folder) -Force | Out-Null
    }
    Write-Host '[OK] Backup directory created and writable'
    New-Item -ItemType Directory -Path (Join-Path $installRoot 'src') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $installRoot '.installed') -Value 'PS4ApolloAutoBackup-v1' -Encoding ASCII
    foreach ($relative in $sourceFiles) {
        $destination = Join-Path $installRoot $relative
        $tempFile = "$destination.$([guid]::NewGuid().ToString('N')).tmp"
        try {
            [IO.File]::Copy((Join-Path $PSScriptRoot $relative), $tempFile, $false)
            if ([IO.File]::Exists($destination)) { [IO.File]::Replace($tempFile, $destination, [NullString]::Value) }
            else { [IO.File]::Move($tempFile, $destination) }
        }
        finally { if ([IO.File]::Exists($tempFile)) { [IO.File]::Delete($tempFile) } }
    }
    Write-AtomicJson $config (Join-Path $installRoot 'config.json')
    Write-Host '[OK] Configuration created'
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $installRoot 'src\Monitor-PS4.ps1') + '"'
    $action = New-ScheduledTaskAction -Execute $exe -Argument $arguments -WorkingDirectory $installRoot
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity
    $principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    $null = Register-ScheduledTask -TaskName $taskName -TaskPath '\' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'PS4 Apollo Auto Backup v1.0.0 - monitor for the current user' -Force -ErrorAction Stop
    # Re-read before enabling: registration may fail to replace an existing action.
    $registered = Get-OwnedAppTask $taskName $installRoot
    if (-not $registered) { throw "Task '$taskName' was not found after registration." }
    $null = Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    $null = Assert-AppTaskConfiguration $taskName $installRoot
    # Remove only a previously verified duplicate from the earlier v1 installer.
    foreach ($task in $tasks | Where-Object { $_.TaskName -ne $taskName }) {
        $null = Get-OwnedAppTask $task.TaskName $installRoot
        Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath '\' -Confirm:$false -ErrorAction Stop
        if (Get-OwnedAppTask $task.TaskName $installRoot) { throw 'The duplicate project task could not be removed.' }
    }
    foreach ($handle in $locks) { $handle.Dispose() }; $locks = @()
    $logPath = Join-Path $config.backupPath 'monitor.log'
    $logOffset = 0
    if (Test-Path -LiteralPath $logPath) { $logOffset = (Get-Item -LiteralPath $logPath).Length }
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    Wait-AppMonitorStarted $taskName $installRoot $logPath $logOffset
    $taskStopped = $false
    Write-Host "[OK] Scheduled Task created/updated and verified: $taskName"
    Write-Host '[OK] Monitor started (Running task and new startup log confirmed)'
    if (Test-ApolloPort $config.ps4Address $config.apolloPort) {
        Write-Host '[OK] Configured TCP port is reachable (save export is tested by the backup)'
    }
    else { Write-Host '[WARN] Apollo could not be reached. Installation completed, but connection could not be tested.' }
    Write-Host "[OK] Installation completed: $installRoot"
    Write-Host 'The monitor starts now and at user logon. Logs are in the configured backup root.'
}
catch {
    Write-Host "[ERROR] Installation did not complete: $($_.Exception.Message)"
    if ($taskStopped) { Write-Host '[WARN] Project tasks were stopped during setup. Installation is incomplete; inspect Task Scheduler and rerun setup after fixing the error.' }
    exit 1
}
finally {
    foreach ($handle in $locks) { $handle.Dispose() }
    if ($probe -and [IO.File]::Exists($probe)) { [IO.File]::Delete($probe) }
}
exit 0

