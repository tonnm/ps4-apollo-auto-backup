# Scheduler calls are entirely simulated. File locks/configuration use a fresh workspace fixture.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'src\Common.ps1')
. (Join-Path $repo 'gui\Integration\Configure-GuiTask.ps1')
$work = Join-Path $repo ('.test-artifacts\migration-' + [guid]::NewGuid().ToString('N'))
$root = Join-Path $work 'app'; $data = Join-Path $work 'data'
New-Item -ItemType Directory -Path $root, $data -Force | Out-Null
Write-AtomicJson @{ ps4Address = '127.0.0.1'; apolloPort = 1; backupPath = $data } (Join-Path $root 'config.json')
Set-Content (Join-Path $data 'backup-state-v4.json') 'state sentinel'
Set-Content (Join-Path $data 'save.zip') 'backup sentinel'
Set-Content (Join-Path $data 'backup.log') 'history sentinel'
Set-Content (Join-Path $data 'monitor.log') 'monitor history sentinel'
$sentinels = @(Get-ChildItem $root, $data -File | Get-FileHash)
$request = [pscustomobject]@{ Root = $root; BackupRoot = $data; GuiExe = (Join-Path $root 'gui\1.1.0\PS4ApolloAutoBackup.exe'); StartAutomatically = $true }
$script:tasks = @{}; $script:fault = ''; $script:writes = 0; $script:restores = 0; $passed = 0
function Assert([bool]$Value, [string]$Name) { if (-not $Value) { throw "FAIL: $Name" }; $script:passed++; Write-Host "PASS: $Name" }
function Reject([scriptblock]$Action, [string]$Name) { try { & $Action } catch { Assert $true $Name; return }; throw "FAIL: $Name" }
function Get-ScheduledTask { [CmdletBinding()]param(); @($script:tasks.Values) }
function New-Item {
    [CmdletBinding()]param($ItemType, $Path, [switch]$Force)
    if ($script:fault -eq 'denied-folder') { throw [UnauthorizedAccessException]::new('Folder permission denied') }
    Microsoft.PowerShell.Management\New-Item -ItemType $ItemType -Path $Path -Force:$Force
}
function New-ScheduledTaskAction { param($Execute, $Argument, $WorkingDirectory); [pscustomobject]@{ Execute=$Execute; Arguments=$Argument; WorkingDirectory=$WorkingDirectory } }
function New-ScheduledTaskTrigger { param([switch]$AtLogOn, $User); [pscustomobject]@{ UserId=$User; Enabled=$true; CimClass=[pscustomobject]@{ CimClassName='MSFT_TaskLogonTrigger' } } }
function New-ScheduledTaskPrincipal { param($UserId, $LogonType, $RunLevel); [pscustomobject]@{ UserId=$UserId; LogonType=$LogonType; RunLevel=$RunLevel } }
function New-ScheduledTaskSettingsSet {
    param($MultipleInstances, $ExecutionTimeLimit, [switch]$StartWhenAvailable, [switch]$AllowStartIfOnBatteries, [switch]$DontStopIfGoingOnBatteries)
    [pscustomobject]@{ MultipleInstances=$MultipleInstances; ExecutionTimeLimit='PT0S'; StartWhenAvailable=[bool]$StartWhenAvailable; DisallowStartIfOnBatteries=(-not $AllowStartIfOnBatteries); StopIfGoingOnBatteries=(-not $DontStopIfGoingOnBatteries); AllowDemandStart=$true; RestartCount=0; Enabled=$true }
}
function Register-ScheduledTask {
    [CmdletBinding()]param($TaskName, $TaskPath, $Action, $Trigger, $Principal, $Settings, $Description, [switch]$Force, $Xml)
    $script:writes++
    if ($Xml) { $script:restores++; $script:tasks[$TaskName] = $Xml | ConvertFrom-Json; return }
    if ($script:fault -eq 'denied-register') { throw [UnauthorizedAccessException]::new('Acesso negado') }
    if ($script:fault -eq 'throw') { throw 'Simulated scheduler failure' }
    if ($script:fault -eq 'no-op') { return } # Cmdlet returns success but stored task is still the old one.
    if ($script:fault -eq 'settings') { $Settings.StartWhenAvailable = $false }
    $script:tasks[$TaskName] = [pscustomobject]@{ TaskName=$TaskName; TaskPath=$TaskPath; Actions=@($Action); Triggers=@($Trigger); Principal=$Principal; Settings=$Settings; State='Ready' }
}
function Enable-ScheduledTask { [CmdletBinding()]param($TaskName, $TaskPath); if ($script:fault -eq 'denied-enable') { throw [UnauthorizedAccessException]::new('Zugriff verweigert') }; if ($script:fault -eq 'disabled') { $script:tasks[$TaskName].State='Disabled'; $script:tasks[$TaskName].Settings.Enabled=$false; return }; $script:tasks[$TaskName].State='Ready'; $script:tasks[$TaskName].Settings.Enabled=$true }
function Disable-ScheduledTask { [CmdletBinding()]param($TaskName, $TaskPath); $script:tasks[$TaskName].State='Disabled'; $script:tasks[$TaskName].Settings.Enabled=$false }
function Stop-ScheduledTask { [CmdletBinding()]param($TaskName, $TaskPath); if ($script:fault -eq 'denied-stop') { throw [Runtime.InteropServices.COMException]::new('Localized permission failure', -2147024891) }; $script:tasks[$TaskName].State='Ready' }
function Start-ScheduledTask { [CmdletBinding()]param($TaskName, $TaskPath); $script:tasks[$TaskName].State='Running' }
function Export-ScheduledTask { [CmdletBinding()]param($TaskName, $TaskPath); if ($script:fault -eq 'denied-export') { throw [UnauthorizedAccessException]::new('Acesso negado') }; $script:tasks[$TaskName] | ConvertTo-Json -Depth 12 }
function Unregister-ScheduledTask { [CmdletBinding(SupportsShouldProcess)]param($TaskName, $TaskPath); $script:tasks.Remove($TaskName) }
function Reset-Legacy([string]$State = 'Disabled') {
    $script:tasks=@{}; $script:fault=''; $script:writes=0; $script:restores=0
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $script:tasks['PS4 Apollo Save Backup'] = [pscustomobject]@{
        TaskName='PS4 Apollo Save Backup'; TaskPath='\'; State=$State
        Actions=@([pscustomobject]@{ Execute=(Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'); Arguments=('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $root 'src\Monitor-PS4.ps1') + '"'); WorkingDirectory=$root })
        Principal=(New-ScheduledTaskPrincipal $identity Interactive Limited)
        Triggers=@((New-ScheduledTaskTrigger -AtLogOn -User $identity))
        Settings=(New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries)
    }
    $script:tasks['PS4 Apollo Save Backup'].Settings.Enabled=($State -ne 'Disabled')
}
Reset-Legacy
Update-GuiTask $request
$migrated=$script:tasks['PS4 Apollo Save Backup']
Assert ($migrated.Actions[0].Execute -eq $request.GuiExe -and $migrated.Actions[0].Arguments -eq '--background') 'disabled v1 task now starts installed GUI, never legacy monitor'
Assert ($migrated.State -eq 'Ready' -and $migrated.Settings.Enabled) 'migration explicitly enables previously disabled task'
Assert ($migrated.Settings.RestartCount -eq 0 -and $migrated.Settings.MultipleInstances -eq 'IgnoreNew') 'GUI lifecycle settings verified'
Update-GuiTask $request
Assert ($script:tasks.Count -eq 1) 'GUI reinstallation retains one authoritative startup task'
Assert ($script:writes -eq 1) 'already migrated task is verified without another registration or UAC'
$request.StartAutomatically=$false; Update-GuiTask $request
Assert ($script:tasks['PS4 Apollo Save Backup'].State -eq 'Disabled') 'startup preference disables GUI task without restoring old monitor'
$request.StartAutomatically=$true
foreach ($mode in @('no-op', 'disabled', 'settings', 'throw')) {
    Reset-Legacy; $before=Export-ScheduledTask 'PS4 Apollo Save Backup'; $script:fault=$mode
    Reject { Update-GuiTask $request } "registration $mode is reported as failure"
    Assert ((Export-ScheduledTask 'PS4 Apollo Save Backup') -eq $before) "registration $mode restores previous task"
}
Reset-Legacy 'Running'; $script:fault='no-op'
Reject { Update-GuiTask $request } 'failed migration of running engine is rejected'
Assert ($script:tasks['PS4 Apollo Save Backup'].State -eq 'Running') 'rollback restarts previously running engine task'
Reset-Legacy
$script:tasks['PS4 Apollo Save Backup'].Actions[0].Execute='unrelated.exe'
Reject { Update-GuiTask $request } 'unrelated task action rejected'
Assert ($script:writes -eq 0) 'unrelated task is not overwritten'
Reset-Legacy
$script:tasks['PS4 Apollo Save Backup'].Principal.UserId='S-1-0-0'
Reject { Update-GuiTask $request } 'other user task rejected'
Assert ($script:writes -eq 0) 'other user task is not overwritten'
Reset-Legacy
$lease=Enter-AppLock $data 'backup'
try { Reject { Update-GuiTask $request } 'migration refuses active backup'; Assert ($script:writes -eq 0) 'active backup prevents scheduler mutation' } finally { $lease.Dispose() }
$lease=Enter-AppLock $data 'monitor'
try { Reject { Update-GuiTask $request } 'migration refuses independently running monitor' } finally { $lease.Dispose() }
Reset-Legacy
$duplicate=Export-ScheduledTask 'PS4 Apollo Save Backup' | ConvertFrom-Json
$duplicate.TaskName=Get-AppTaskName; $script:tasks[$duplicate.TaskName]=$duplicate
Update-GuiTask $request
Assert ($script:tasks.Count -eq 1 -and $script:tasks.ContainsKey('PS4 Apollo Save Backup')) 'recognized duplicate tasks consolidated after verification'
$script:tasks=@{}; $request.StartAutomatically=$false
Update-GuiTask $request
Assert ($script:tasks.Count -eq 0) 'fresh setup without autostart does not create a task'
$request.StartAutomatically=$true; Update-GuiTask $request
Assert ($script:tasks.ContainsKey((Get-AppTaskName))) 'fresh setup uses per-user task name'
foreach ($mode in @('denied-export', 'denied-stop', 'denied-register', 'denied-enable')) {
    Reset-Legacy 'Running'; $script:fault=$mode
    $caught=$null
    try { Update-GuiTask $request } catch { $caught=$_ }
    Assert ($null -ne $caught -and $caught.Exception.Data['GuiElevationRequired']) "$mode requests one-time authorization for recognized task"
    Assert ($script:restores -eq 0 -and $caught.Exception.Message -notmatch 'could not be restored|Access denied|Task Scheduler') "$mode avoids privileged rollback and confusing raw permission message"
    $script:fault=''
    Update-GuiTask $request -ElevatedRetry
    Update-GuiTask $request -VerifyOnly
    Assert ($script:tasks['PS4 Apollo Save Backup'].Actions[0].Execute -eq $request.GuiExe) "$mode helper retry completes migration and read-only verification"
}
Reset-Legacy
$before=Export-ScheduledTask 'PS4 Apollo Save Backup'; $script:fault='denied-register'
try { Update-GuiTask $request } catch { }
Assert ((Export-ScheduledTask 'PS4 Apollo Save Backup') -eq $before -and $script:restores -eq 0) 'denied first write leaves original disabled task intact without rollback'
$caught=$null
try { Update-GuiTask $request -ElevatedRetry } catch { $caught=$_ }
Assert ($null -ne $caught -and -not $caught.Exception.Data['GuiElevationRequired'] -and $script:restores -eq 0) 'helper permission failure cannot cause a repeated UAC loop or denied rollback'
Reset-Legacy
Reject { Update-GuiTask $request -VerifyOnly } 'read-only verification rejects an unmigrated action'
Assert ($script:writes -eq 0) 'read-only verification never modifies a task'
$script:tasks=@{}; $script:fault='denied-register'; $caught=$null
try { Update-GuiTask $request } catch { $caught=$_ }
Assert ($null -ne $caught -and -not $caught.Exception.Data['GuiElevationRequired']) 'fresh registration denial does not broaden elevation beyond recognized existing tasks'
Reset-Legacy
$script:tasks['PS4 Apollo Save Backup'].Actions[0].Execute='unrelated.exe'; $caught=$null
try { Update-GuiTask $request -ElevatedRetry } catch { $caught=$_ }
Assert ($null -ne $caught -and $script:writes -eq 0) 'helper rechecks ownership and refuses a replaced unrelated task'
$script:tasks=@{}; $caught=$null
try { Update-GuiTask $request -ElevatedRetry } catch { $caught=$_ }
Assert ($null -ne $caught -and $script:writes -eq 0) 'helper refuses when the recognized task disappeared'
Reset-Legacy
$unprepared = [pscustomobject]@{ Root=$request.Root; GuiExe=$request.GuiExe; BackupRoot=(Join-Path $work 'unprepared-data'); StartAutomatically=$true }
Reject { Update-GuiTask $unprepared -ElevatedRetry } 'helper refuses data roots not prepared by the normal process'
Assert (-not (Test-Path -LiteralPath $unprepared.BackupRoot) -and $script:writes -eq 0) 'elevated helper cannot create caller-selected data directories or lock files'
Reset-Legacy; $script:fault='denied-folder'; $caught=$null
try { Update-GuiTask $request } catch { $caught=$_ }
Assert ($null -ne $caught -and -not $caught.Exception.Data['GuiElevationRequired'] -and $script:writes -eq 0) 'data-folder permission failures cannot request scheduler elevation'
foreach ($file in $sentinels) { Assert ((Get-FileHash -LiteralPath $file.Path).Hash -eq $file.Hash) "migration preserves $([IO.Path]::GetFileName($file.Path))" }
Write-Host "PASS: $passed GUI migration assertions. No real Scheduled Task was modified."
