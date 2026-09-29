# Dot-sourced by Run-Tests.ps1. Every Scheduler boundary is replaced before setup runs.
# A keyed task collection models coexistence of the legacy and SID names.
$taskState = @{ Tasks = @{}; Fault = ''; Calls = [Collections.Generic.List[string]]::new(); Output = '' }
function New-ScheduledTaskAction {
    param($Execute, $Argument, $WorkingDirectory)
    [pscustomobject]@{ Execute = $Execute; Arguments = $Argument; WorkingDirectory = $WorkingDirectory }
}
function New-ScheduledTaskTrigger {
    param([switch]$AtLogOn, $User)
    if (-not $AtLogOn) { throw 'Expected a logon trigger.' }
    [pscustomobject]@{ CimClass = [pscustomobject]@{ CimClassName = 'MSFT_TaskLogonTrigger' }; UserId = $User; Enabled = $true }
}
function New-ScheduledTaskPrincipal {
    param($UserId, $LogonType, $RunLevel)
    [pscustomobject]@{ UserId = $UserId; LogonType = $LogonType; RunLevel = $RunLevel }
}
function New-ScheduledTaskSettingsSet {
    param($MultipleInstances, $ExecutionTimeLimit, [switch]$StartWhenAvailable, [switch]$AllowStartIfOnBatteries,
        [switch]$DontStopIfGoingOnBatteries, $RestartCount, $RestartInterval)
    [pscustomobject]@{
        Enabled = $true; MultipleInstances = $MultipleInstances
        ExecutionTimeLimit = [Xml.XmlConvert]::ToString([TimeSpan]$ExecutionTimeLimit)
        StartWhenAvailable = [bool]$StartWhenAvailable; DisallowStartIfOnBatteries = -not $AllowStartIfOnBatteries
        StopIfGoingOnBatteries = -not $DontStopIfGoingOnBatteries; AllowDemandStart = $true
        RestartCount = $RestartCount; RestartInterval = [Xml.XmlConvert]::ToString([TimeSpan]$RestartInterval)
    }
}
function Get-ScheduledTask { param($ErrorAction) @($taskState.Tasks.Values) }
function Stop-ScheduledTask {
    param($TaskName, $TaskPath, $ErrorAction)
    $taskState.Calls.Add("stop:$TaskName")
    if ($taskState.Fault -eq 'stop-no-op') { return }
    if ($taskState.Tasks[$TaskName].State -eq 'Running') { $taskState.Tasks[$TaskName].State = 'Ready' }
}
function Enable-ScheduledTask {
    param($TaskName, $TaskPath, $ErrorAction)
    $taskState.Calls.Add("enable:$TaskName")
    if ($taskState.Fault -eq 'enable-denied') { throw 'Fixture: enabling denied.' }
    if ($taskState.Fault -eq 'enable-no-op') { return }
    $taskState.Tasks[$TaskName].Settings.Enabled = $true
    $taskState.Tasks[$TaskName].State = 'Ready'
}
function Start-ScheduledTask {
    param($TaskName, $TaskPath, $ErrorAction)
    $taskState.Calls.Add("start:$TaskName")
    if ($taskState.Fault -eq 'start-denied') { throw 'Fixture: starting denied.' }
    if ($taskState.Fault -eq 'start-no-op') { return }
    $taskState.Tasks[$TaskName].State = 'Running'
    if ($taskState.Fault -eq 'running-no-log') { return }
    # Simulate the monitor's readiness signal, not just successful Start-ScheduledTask.
    $cfg = Read-BackupConfig (Join-Path $installed 'config.json')
    Add-Content -LiteralPath (Join-Path $cfg.backupPath 'monitor.log') -Encoding UTF8 -Value '[2000-01-01 00:00:00] [INFO] Monitor started.'
}
function Register-ScheduledTask {
    param($TaskName, $TaskPath, $Action, $Trigger, $Principal, $Settings, $Description, [switch]$Force, $ErrorAction)
    $taskState.Calls.Add("register:$TaskName")
    if ($taskState.Fault -eq 'register-denied') { throw 'Fixture: registration denied.' }
    if ($taskState.Fault -eq 'register-no-op') { return }
    if ($taskState.Fault -eq 'task-missing') { $taskState.Tasks.Remove($TaskName); return }
    # Explicitly model retention of disabled state: setup must enable and re-read it.
    $disabled = $taskState.Tasks.ContainsKey($TaskName) -and $taskState.Tasks[$TaskName].State -eq 'Disabled'
    $Settings.Enabled = -not $disabled
    $newState = 'Ready'; if ($disabled) { $newState = 'Disabled' }
    $taskState.Tasks[$TaskName] = [pscustomobject]@{
        TaskName = $TaskName; TaskPath = $TaskPath; State = $newState
        Actions = @($Action); Triggers = @($Trigger); Principal = $Principal; Settings = $Settings
    }
    switch ($taskState.Fault) {
        'wrong-action' { $Action.Arguments = '-File "unrelated.ps1"' }
        'wrong-settings' { $Settings.MultipleInstances = 'Parallel' }
        'wrong-trigger' { $Trigger.Enabled = $false }
        'wrong-principal' { $Principal.RunLevel = 'Highest' }
        'wrong-directory' { $Action.WorkingDirectory = $work }
    }
}
function Unregister-ScheduledTask {
    param($TaskName, $TaskPath, [switch]$Confirm, $ErrorAction)
    $taskState.Calls.Add("remove:$TaskName")
    if ($taskState.Fault -eq 'remove-no-op') { return }
    $taskState.Tasks.Remove($TaskName)
}
# Keep failure-timeout tests fast without bypassing the real polling/checking code.
function Start-Sleep { param($Milliseconds, $Seconds) }

function Copy-FixtureObject { param($Value) [Management.Automation.PSSerializer]::Deserialize([Management.Automation.PSSerializer]::Serialize($Value)) }
function Invoke-SetupFixture {
    param([int]$Expected = 0)
    $taskState.Output = @(& (Join-Path $repo 'install.ps1') -Ps4Address '127.0.0.1' -ApolloPort 1 -BackupPath $data 6>&1) -join "`n"
    $code = $LASTEXITCODE
    if ($code -ne $Expected) { Write-Host $taskState.Output }
    Assert ($code -eq $Expected) "setup exits $Expected (fault='$($taskState.Fault)')"
    if ($Expected -eq 0) {
        Assert ($taskState.Output -match '\[OK\] Scheduled Task created/updated and verified:' -and $taskState.Output -match '\[OK\] Monitor started') 'setup reports success only after verification'
    }
    else {
        Assert ($taskState.Output -notmatch '\[OK\] Scheduled Task' -and $taskState.Output -notmatch '\[OK\] Installation completed') 'failed setup never reports task/installation success'
    }
}

$oldLocal = $env:LOCALAPPDATA
$oldProfile = $env:USERPROFILE
try {
    $env:LOCALAPPDATA = Join-Path $work 'local-app-data'
    $env:USERPROFILE = Join-Path $work 'fixture-user'
    $installed = Join-Path $env:LOCALAPPDATA 'PS4ApolloAutoBackup'
    $legacyName = 'PS4 Apollo Save Backup'
    $sidName = Get-AppTaskName
    $stateBefore = Get-StateHash
    Invoke-SetupFixture
    Assert ((Test-Path -LiteralPath (Join-Path $installed 'src\Monitor-PS4.ps1')) -and $taskState.Tasks[$sidName].State -eq 'Running') 'fresh setup deploys and starts the SID task'
    $installedTemplate = Copy-FixtureObject $taskState.Tasks[$sidName]
    $taskState.Tasks[$sidName].State = 'Disabled'; $taskState.Tasks[$sidName].Settings.Enabled = $false
    Invoke-SetupFixture
    Assert ($taskState.Tasks[$sidName].Settings.Enabled -and $taskState.Tasks[$sidName].State -eq 'Running') 'reinstall enables a disabled existing v1 task'

    $legacyPath = Join-Path $env:USERPROFILE 'Documents\Monitor-PS4.ps1'
    New-Item -ItemType Directory -Path (Split-Path $legacyPath -Parent) -Force | Out-Null
    @'
# PS4 APOLLO BACKUP MONITOR V4
function Test-Apollo { return $false }
$BackupScript = Join-Path $env:USERPROFILE 'Documents\Backup-PS4.ps1'
& $BackupScript
'@ | Set-Content -LiteralPath $legacyPath -Encoding UTF8
    $legacyHash = (Get-FileHash -LiteralPath $legacyPath).Hash
    $legacy = Copy-FixtureObject $installedTemplate
    $legacy.TaskName = $legacyName; $legacy.State = 'Disabled'; $legacy.Settings.Enabled = $false
    $legacy.Principal.UserId = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $legacy.Actions[0].Execute = 'powershell.exe'
    $legacy.Actions[0].Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $legacyPath + '"'
    $legacy.Actions[0].WorkingDirectory = Split-Path $legacyPath -Parent
    $taskState.Tasks = @{ $legacyName = (Copy-FixtureObject $legacy) }
    $taskState.Calls.Clear()
    Invoke-SetupFixture
    $migrated = $taskState.Tasks[$legacyName]
    Assert ($migrated.Actions[0].Arguments -eq $installedTemplate.Actions[0].Arguments -and $migrated.Settings.Enabled -and $migrated.State -eq 'Running') 'disabled legacy task updated IN PLACE to installed action, enabled and started'
    Assert ($taskState.Tasks.Count -eq 1 -and $taskState.Calls -contains "enable:$legacyName" -and $taskState.Calls -contains "start:$legacyName") 'migration retains the legacy task name without creating a second task'
    Invoke-SetupFixture
    Assert ($taskState.Tasks.ContainsKey($legacyName) -and $taskState.Tasks.Count -eq 1) 'reinstall recognizes an already migrated task'

    # Reproduce the reported machine: old disabled V4 task plus the earlier installer's SID task.
    $taskState.Tasks = @{ $legacyName = (Copy-FixtureObject $legacy); $sidName = (Copy-FixtureObject $installedTemplate) }
    $taskState.Calls.Clear()
    Invoke-SetupFixture
    Assert ($taskState.Tasks.Count -eq 1 -and $taskState.Tasks[$legacyName].State -eq 'Running' -and $taskState.Calls -contains "remove:$sidName") 'coexisting legacy and SID tasks consolidate into the verified legacy name'
    Assert ((Get-FileHash -LiteralPath $legacyPath).Hash -eq $legacyHash -and (Get-StateHash) -eq $stateBefore -and (Get-ZipCount) -eq 4) 'migration leaves legacy script, backups and state untouched'

    foreach ($case in 'unrelated-exe', 'wrong-owner', 'extra-action', 'wrong-path', 'encoded-command') {
        $candidate = Copy-FixtureObject $legacy
        switch ($case) {
            'unrelated-exe' { $candidate.Actions[0].Execute = 'unrelated.exe' }
            'wrong-owner' { $candidate.Principal.UserId = 'S-1-5-18' }
            'extra-action' { $candidate.Actions += $candidate.Actions[0] }
            'wrong-path' { $candidate.Actions[0].Arguments = '-File "' + (Join-Path $work 'Monitor-PS4.ps1') + '"' }
            'encoded-command' { $candidate.Actions[0].Arguments = '-EncodedCommand ZgA=' }
        }
        $taskState.Tasks = @{ $legacyName = $candidate }
        $taskState.Calls.Clear()
        Invoke-SetupFixture -Expected 1
        Assert ($taskState.Calls.Count -eq 0) "unrecognized legacy task rejected before mutation: $case"
    }
    $legacySource = [IO.File]::ReadAllText($legacyPath)
    [IO.File]::WriteAllText($legacyPath, '# unrelated script with the same filename')
    $taskState.Tasks = @{ $legacyName = (Copy-FixtureObject $legacy) }
    $taskState.Calls.Clear()
    Invoke-SetupFixture -Expected 1
    Assert ($taskState.Calls.Count -eq 0) 'same task/path without V4 source markers is refused'
    [IO.File]::WriteAllText($legacyPath, $legacySource)

    $unrelatedSid = Copy-FixtureObject $installedTemplate
    $unrelatedSid.Actions[0].Arguments = '-File "unrelated.ps1"'
    $taskState.Tasks = @{ $legacyName = (Copy-FixtureObject $legacy); $sidName = $unrelatedSid }
    $taskState.Calls.Clear()
    Invoke-SetupFixture -Expected 1
    Assert ($taskState.Calls.Count -eq 0) 'unrelated SID task prevents all mutation even when the legacy task is recognized'

    # Failures must be detected by re-reading persisted results, not trusting command return values.
    foreach ($fault in 'stop-no-op', 'register-denied', 'register-no-op', 'task-missing', 'enable-denied', 'enable-no-op',
        'wrong-action', 'wrong-settings', 'wrong-trigger', 'wrong-principal', 'wrong-directory',
        'start-denied', 'start-no-op', 'running-no-log', 'remove-no-op') {
        $taskState.Tasks = @{ $legacyName = (Copy-FixtureObject $legacy); $sidName = (Copy-FixtureObject $installedTemplate) }
        $taskState.Fault = $fault
        $taskState.Calls.Clear()
        Invoke-SetupFixture -Expected 1
        if ($fault -notin @('start-denied', 'start-no-op', 'running-no-log')) {
            Assert ($taskState.Calls -notcontains "start:$legacyName") "$fault prevents monitor start"
        }
        Assert ((Get-StateHash) -eq $stateBefore -and (Get-ZipCount) -eq 4) "$fault preserves backups/state"
    }
    $taskState.Fault = ''
    $taskState.Tasks = @{ $legacyName = (Copy-FixtureObject $legacy) }
    Invoke-SetupFixture
    [IO.File]::WriteAllText((Join-Path $installed 'keep-me.txt'), 'unrelated file')
    & (Join-Path $repo 'uninstall.ps1')
    Assert ($LASTEXITCODE -eq 0 -and $taskState.Tasks.Count -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $installed 'src\Monitor-PS4.ps1'))) 'uninstall removes migrated task and installed scripts'
    Assert ((Get-StateHash) -eq $stateBefore -and (Get-ZipCount) -eq 4 -and (Test-Path -LiteralPath $legacyPath)) 'uninstall preserves backups, state and legacy script'
    Assert (Test-Path -LiteralPath (Join-Path $installed 'keep-me.txt')) 'uninstall preserves unknown installation files'
}
finally { $env:LOCALAPPDATA = $oldLocal; $env:USERPROFILE = $oldProfile }
