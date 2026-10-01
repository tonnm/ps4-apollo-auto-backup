# GUI-only adapter. Common.ps1 retains the V4 engine helpers and shared-log writer.
param([string]$RequestPath, [switch]$VerifyOnly, [switch]$ElevatedRetry)

function Test-GuiPermissionDenied {
    param($ErrorRecord)
    if ([string]$ErrorRecord.CategoryInfo.Category -eq 'PermissionDenied') { return $true }
    $exception = $ErrorRecord.Exception
    while ($exception) {
        if ($exception -is [UnauthorizedAccessException] -or $exception.HResult -eq -2147024891 -or
            ($exception -is [ComponentModel.Win32Exception] -and $exception.NativeErrorCode -eq 5) -or
            ($exception.PSObject.Properties['NativeErrorCode'] -and [string]$exception.NativeErrorCode -eq 'AccessDenied')) { return $true }
        $exception = $exception.InnerException
    }
    return $false
}

function Enter-GuiDataLock {
    param([string]$Root, [string]$Name, [switch]$ElevatedRetry)
    if ($ElevatedRetry) {
        # Elevation is for Scheduler only: never create directories/files in caller-selected data roots.
        return [IO.File]::Open((Join-Path $Root ".$Name.lock"), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    }
    Enter-AppLock $Root $Name
}

function Test-GuiTaskConfiguration {
    param($Entry, $Request)
    if (-not $Entry -or $Entry.Kind -ne 'Gui') { return $false }
    $t = $Entry.Task
    return $t.Settings.Enabled -eq [bool]$Request.StartAutomatically -and
        (-not $Request.StartAutomatically -or [string]$t.State -ne 'Disabled') -and
        [string]$t.Principal.LogonType -eq 'Interactive' -and [string]$t.Principal.RunLevel -eq 'Limited' -and
        @($t.Triggers).Count -eq 1 -and $t.Triggers[0].CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' -and
        (Test-AppTaskUser $t.Triggers[0].UserId) -and $t.Triggers[0].Enabled -eq $true -and
        [string]$t.Settings.MultipleInstances -eq 'IgnoreNew' -and
        [Xml.XmlConvert]::ToTimeSpan($t.Settings.ExecutionTimeLimit) -eq [TimeSpan]::Zero -and
        $t.Settings.DisallowStartIfOnBatteries -eq $false -and $t.Settings.StopIfGoingOnBatteries -eq $false -and
        $t.Settings.StartWhenAvailable -eq $true -and $t.Settings.AllowDemandStart -eq $true -and
        $t.Settings.RestartCount -eq 0
}

function Get-GuiMigrationTasks {
    param($Request)
    $expectedExe = Join-Path $Request.Root 'gui\1.1.0\PS4ApolloAutoBackup.exe'
    if ($Request.GuiExe -ne $expectedExe) { throw 'Unexpected GUI executable location.' }
    foreach ($name in @('PS4 Apollo Save Backup', (Get-AppTaskName))) {
        $task = Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskName -eq $name -and $_.TaskPath -eq '\' }
        if (-not $task) { continue }
        if (@($task.Actions).Count -eq 1 -and (Test-AppTaskUser $task.Principal.UserId) -and
            $task.Actions[0].Execute -eq $expectedExe -and $task.Actions[0].Arguments -eq '--background' -and
            $task.Actions[0].WorkingDirectory -eq (Split-Path $expectedExe -Parent)) {
            [pscustomobject]@{ Task = $task; Kind = 'Gui' }
        }
        else {
            $owned = Get-OwnedAppTask $name $Request.Root
            [pscustomobject]@{ Task = $owned; Kind = 'Engine' }
        }
    }
}

function Update-GuiTask {
    param($Request, [switch]$VerifyOnly, [switch]$ElevatedRetry)
    $tasks = @(Get-GuiMigrationTasks $Request) # Validate every candidate before mutation.
    # A migrated task must not require another privileged rewrite on every normal launch.
    if ($tasks.Count -eq 1 -and (Test-GuiTaskConfiguration $tasks[0] $Request)) { return }
    if ($tasks.Count -eq 0 -and -not $Request.StartAutomatically) { return }
    if ($VerifyOnly) { throw 'Windows startup settings could not be verified.' }
    if ($ElevatedRetry -and $tasks.Count -eq 0) { throw 'The recognized startup task is no longer present. Retry setup normally.' }
    $name = Get-AppTaskName
    if ($tasks.Task.TaskName -contains 'PS4 Apollo Save Backup') { $name = 'PS4 Apollo Save Backup' }
    $roots = @($Request.BackupRoot)
    $configPath = Join-Path $Request.Root 'config.json'
    if (Test-Path -LiteralPath $configPath) { $roots += (Read-BackupConfig $configPath).backupPath }
    $locks = @(); $snapshots = @(); $mutated = $false; $schedulerOperation = $false
    try {
        foreach ($root in ($roots | Select-Object -Unique)) {
            if (-not $ElevatedRetry) {
                New-Item -ItemType Directory -Path $root -Force | Out-Null
                # Prepare the marker with normal permissions, before any Scheduler write can require UAC.
                $monitorMarker = Join-Path $root '.monitor.lock'
                if (-not [IO.File]::Exists($monitorMarker)) {
                    $marker = [IO.File]::Open($monitorMarker, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
                    $marker.Dispose()
                }
            }
            try { $locks += Enter-GuiDataLock $root 'backup' -ElevatedRetry:$ElevatedRetry }
            catch { throw 'A backup is running or the data folder is unavailable. Wait for completion and try again.' }
        }
        $schedulerOperation = $true
        foreach ($entry in $tasks) {
            $snapshots += [pscustomobject]@{
                Name = $entry.Task.TaskName
                Xml = (Export-ScheduledTask -TaskName $entry.Task.TaskName -TaskPath '\' -ErrorAction Stop)
                Restart = ($entry.Kind -eq 'Engine' -and [string]$entry.Task.State -eq 'Running')
            }
        }
        foreach ($entry in $tasks | Where-Object { $_.Kind -eq 'Engine' }) {
            if ([string]$entry.Task.State -in @('Running', 'Queued')) {
                Stop-ScheduledTask -TaskName $entry.Task.TaskName -TaskPath '\' -ErrorAction Stop
                $mutated = $true
                $stopped = $false
                for ($i = 0; $i -lt 60; $i++) {
                    $observed = Get-OwnedAppTask $entry.Task.TaskName $Request.Root
                    if ($observed -and [string]$observed.State -in @('Ready', 'Disabled')) { $stopped = $true; break }
                    Start-Sleep -Milliseconds 250
                }
                if (-not $stopped) { throw 'The previous monitor did not stop. Migration was cancelled.' }
            }
        }
        $schedulerOperation = $false
        foreach ($root in ($roots | Select-Object -Unique)) {
            try { $locks += Enter-GuiDataLock $root 'monitor' -ElevatedRetry:$ElevatedRetry }
            catch { throw 'Another monitor is running. Close manually started instances and retry.' }
        }
        if ($tasks.Count -eq 0 -and -not $Request.StartAutomatically) { return }
        $schedulerOperation = $true
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $action = New-ScheduledTaskAction -Execute $Request.GuiExe -Argument '--background' -WorkingDirectory (Split-Path $Request.GuiExe -Parent)
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity
        $principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
        # No automatic restart: Exit must remain a full exit, not trigger a new GUI instance.
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        $null = Register-ScheduledTask -TaskName $name -TaskPath '\' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'PS4 Apollo Auto Backup GUI v1.1.0' -Force -ErrorAction Stop
        $mutated = $true
        if ($Request.StartAutomatically) { $null = Enable-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop }
        else { $null = Disable-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop }
        $stored = @(Get-GuiMigrationTasks $Request) | Where-Object { $_.Task.TaskName -eq $name }
        if (-not $stored -or $stored.Kind -ne 'Gui') { throw 'Windows did not store the expected GUI startup action.' }
        if (-not (Test-GuiTaskConfiguration $stored $Request)) { throw 'Windows startup settings could not be verified.' }
        foreach ($entry in $tasks | Where-Object { $_.Task.TaskName -ne $name }) {
            Unregister-ScheduledTask -TaskName $entry.Task.TaskName -TaskPath '\' -Confirm:$false -ErrorAction Stop
            if (@(Get-GuiMigrationTasks $Request) | Where-Object { $_.Task.TaskName -eq $entry.Task.TaskName }) {
                throw 'The duplicate project startup task could not be removed.'
            }
        }
    }
    catch {
        $reason = $_.Exception.Message
        foreach ($handle in $locks) { $handle.Dispose() }; $locks = @()
        if (Test-GuiPermissionDenied $_) {
            # Do not attempt the same denied privilege again as an XML "rollback". A denied
            # first write has nothing to restore. If an earlier stop/write succeeded, the
            # dedicated helper re-reads the recognized task and finishes the operation.
            if ($schedulerOperation -and $tasks.Count -gt 0 -and -not $ElevatedRetry) {
                $permission = [UnauthorizedAccessException]::new('Windows needs one-time permission to update automatic startup.')
                $permission.Data['GuiElevationRequired'] = $true
                throw $permission
            }
            throw 'Windows could not authorize the startup update. Retry from Settings after checking your Windows permissions. Your backups were preserved.'
        }
        if ($mutated) {
            try {
                if ($snapshots.Count -eq 0) {
                    $owned = @(Get-GuiMigrationTasks $Request) | Where-Object { $_.Task.TaskName -eq $name -and $_.Kind -eq 'Gui' }
                    if ($owned) { Unregister-ScheduledTask -TaskName $name -TaskPath '\' -Confirm:$false -ErrorAction Stop }
                }
                foreach ($snapshot in $snapshots) {
                    $null = Register-ScheduledTask -TaskName $snapshot.Name -TaskPath '\' -Xml $snapshot.Xml -Force -ErrorAction Stop
                    if ($snapshot.Restart) { Start-ScheduledTask -TaskName $snapshot.Name -TaskPath '\' -ErrorAction Stop }
                }
            }
            catch { $reason += ' Startup recovery is incomplete. Retry the update from Settings. Your backups were preserved.' }
        }
        throw $reason
    }
    finally { foreach ($handle in $locks) { $handle.Dispose() } }
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    try {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'Engine\Common.ps1')
        $request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Update-GuiTask $request -VerifyOnly:$VerifyOnly -ElevatedRetry:$ElevatedRetry
        Write-Output 'GUI_TASK_OK'
        exit 0
    }
    catch {
        if ($_.Exception.Data['GuiElevationRequired']) { Write-Output 'GUI_TASK_ELEVATION_REQUIRED'; exit 740 }
        Write-Output $_.Exception.Message; exit 1
    }
}
