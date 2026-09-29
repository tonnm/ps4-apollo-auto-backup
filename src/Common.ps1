# Shared configuration and safe local file operations. Windows PowerShell 5.1.
function Read-BackupConfig {
    param([string]$Path)
    $config = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $address = [string]$config.ps4Address
    $ip = $null
    if (-not [System.Net.IPAddress]::TryParse($address, [ref]$ip) -or
        $ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw 'ps4Address must be an IPv4 address.'
    }
    $port = 0
    if (-not [int]::TryParse([string]$config.apolloPort, [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
        throw 'apolloPort must be an integer from 1 to 65535.'
    }
    $pathValue = [Environment]::ExpandEnvironmentVariables([string]$config.backupPath)
    if ($pathValue -notmatch '^[A-Za-z]:\\' -or $pathValue -match '[<>"|?*%]' -or $pathValue.Substring(2).Contains(':')) {
        throw 'backupPath must be an absolute local Windows directory; unresolved variables and UNC paths are not supported.'
    }
    $root = [IO.Path]::GetFullPath($pathValue).TrimEnd('\')
    if ($root.Length -le 3) { throw 'Choose a dedicated backup folder, not a drive root.' }
    [pscustomobject]@{ ps4Address = $address; apolloPort = $port; backupPath = $root }
}

function Enter-AppLock {
    param([string]$Root, [string]$Name)
    # Keep the file after closing: deleting lock files creates a race between processes.
    [IO.File]::Open((Join-Path $Root ".$Name.lock"), [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
}

function Write-AtomicJson {
    param([object]$Value, [string]$Path)
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $json = $Value | ConvertTo-Json -Depth 10
        $null = $json | ConvertFrom-Json -ErrorAction Stop
        [IO.File]::WriteAllText($temp, $json, (New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temp, $Path) }
    }
    finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}

function Assert-SafeSaveName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -match '[<>:"/\\|?*\x00-\x1f]' -or
        $Name -match '[. ]$' -or $Name -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)') {
        throw 'Apollo returned a save name that is unsafe as a Windows folder name.'
    }
}

function Remove-TempItem {
    param([string]$Path, [string]$Root)
    $full = [IO.Path]::GetFullPath($Path)
    $parent = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    if (-not $full.StartsWith($parent, [StringComparison]::OrdinalIgnoreCase)) { throw 'Temporary path escapes its root.' }
    if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop }
}

function Test-ApolloPort {
    param([string]$Address, [int]$Port)
    $tcp = New-Object Net.Sockets.TcpClient
    $wait = $null
    try {
        $result = $tcp.BeginConnect($Address, $Port, $null, $null)
        $wait = $result.AsyncWaitHandle
        if (-not $wait.WaitOne(1000, $false)) { return $false }
        $tcp.EndConnect($result)
        return $true
    }
    catch { return $false }
    finally { if ($wait) { $wait.Close() }; $tcp.Close() }
}

function Get-AppTaskName {
    'PS4ApolloAutoBackup-' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}

function Test-AppTaskUser {
    param([string]$UserId)
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($UserId -eq $current.User.Value -or $UserId -eq $current.Name) { return $true }
    if ([string]::IsNullOrWhiteSpace($UserId)) { return $false }
    try {
        $account = New-Object Security.Principal.NTAccount($UserId)
        return $account.Translate([Security.Principal.SecurityIdentifier]).Value -eq $current.User.Value
    }
    catch { return $false }
}

function Test-LegacyAppAction {
    param($Action)
    $exe = [Environment]::ExpandEnvironmentVariables([string]$Action.Execute).Trim('"')
    $expectedExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if ($exe -notin @('powershell', 'powershell.exe', $expectedExe)) { return $false }
    # Accept only known PowerShell switches followed by one -File path. Never execute it.
    $pattern = '(?i)^\s*(?:(?:-NoLogo|-NoProfile|-NonInteractive)\s+|-WindowStyle\s+Hidden\s+|-ExecutionPolicy\s+Bypass\s+)*-File\s+(?:"(?<path>[^"]+)"|(?<path>[^\s"]+))\s*$'
    $match = [regex]::Match([string]$Action.Arguments, $pattern)
    if (-not $match.Success) { return $false }
    $path = [Environment]::ExpandEnvironmentVariables($match.Groups['path'].Value)
    $knownPaths = @(
        (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Monitor-PS4.ps1'),
        (Join-Path $env:USERPROFILE 'Documents\Monitor-PS4.ps1')
    )
    if ($path -notin $knownPaths -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    # Path/name alone is insufficient: require the supplied V4 monitor's recognizable structure.
    $source = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop
    if ($source -notmatch '(?m)^#\s*PS4 APOLLO BACKUP MONITOR V4\s*$') { return $false }
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { return $false }
    $probe = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-Apollo' }, $true)
    $backup = $ast.Find({ param($n)
        $n -is [Management.Automation.Language.CommandAst] -and
        $n.InvocationOperator -eq [Management.Automation.Language.TokenKind]::Ampersand -and
        $n.CommandElements[0] -is [Management.Automation.Language.VariableExpressionAst] -and
        $n.CommandElements[0].VariablePath.UserPath -eq 'BackupScript'
    }, $true)
    return $null -ne $probe -and $null -ne $backup
}

function Get-OwnedAppTask {
    param([string]$Name, [string]$InstallRoot, [switch]$AllowLegacy)
    $task = Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskName -eq $Name -and $_.TaskPath -eq '\' }
    if ($task) {
        $expected = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $InstallRoot 'src\Monitor-PS4.ps1') + '"'
        $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (@($task.Actions).Count -ne 1 -or -not (Test-AppTaskUser $task.Principal.UserId)) {
            throw "Task '$Name' is not owned by this installation/current user. Refusing to modify it."
        }
        $installedAction = $task.Actions[0].Arguments -eq $expected -and $task.Actions[0].Execute -eq $exe
        if (-not $installedAction -and -not ($AllowLegacy -and $Name -eq 'PS4 Apollo Save Backup' -and (Test-LegacyAppAction $task.Actions[0]))) {
            throw "Task '$Name' has an unrecognized action. Refusing to modify it. Legacy migration requires the current user's original V4 monitor in Documents."
        }
    }
    $task
}

function Assert-AppTaskConfiguration {
    param([string]$Name, [string]$InstallRoot)
    $task = Get-OwnedAppTask $Name $InstallRoot
    if (-not $task) { throw "Task '$Name' was not found after registration." }
    if ($task.Settings.Enabled -ne $true -or [string]$task.State -eq 'Disabled') {
        throw "Task '$Name' is still disabled after registration."
    }
    if ($task.Actions[0].WorkingDirectory -ne $InstallRoot -or
        [string]$task.Principal.LogonType -ne 'Interactive' -or [string]$task.Principal.RunLevel -ne 'Limited' -or
        @($task.Triggers).Count -ne 1 -or $task.Triggers[0].CimClass.CimClassName -ne 'MSFT_TaskLogonTrigger' -or
        $task.Triggers[0].Enabled -ne $true -or -not (Test-AppTaskUser $task.Triggers[0].UserId)) {
        throw "Task '$Name' action, principal or logon trigger does not match the requested configuration."
    }
    $s = $task.Settings
    if ([string]$s.MultipleInstances -ne 'IgnoreNew' -or
        [Xml.XmlConvert]::ToTimeSpan($s.ExecutionTimeLimit) -ne [TimeSpan]::Zero -or
        $s.StartWhenAvailable -ne $true -or $s.DisallowStartIfOnBatteries -ne $false -or
        $s.StopIfGoingOnBatteries -ne $false -or $s.AllowDemandStart -ne $true -or
        $s.RestartCount -ne 3 -or [Xml.XmlConvert]::ToTimeSpan($s.RestartInterval) -ne [TimeSpan]::FromMinutes(1)) {
        throw "Task '$Name' settings do not match the requested configuration."
    }
    $task
}

function Wait-AppMonitorStarted {
    param([string]$Name, [string]$InstallRoot, [string]$LogPath, [long]$LogOffset)
    # A start request is asynchronous. Require Running AND a new startup record, not stale log text.
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        $task = Assert-AppTaskConfiguration $Name $InstallRoot
        if ([string]$task.State -eq 'Running' -and [IO.File]::Exists($LogPath)) {
            $stream = $null; $reader = $null
            try {
                $stream = [IO.File]::Open($LogPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
                $null = $stream.Seek($LogOffset, [IO.SeekOrigin]::Begin)
                $reader = New-Object IO.StreamReader($stream)
                if ($reader.ReadToEnd() -match '(?m)^\[[^\r\n]+\] \[INFO\] Monitor started\.\r?$') { return }
            }
            finally {
                if ($reader) { $reader.Dispose() }
                elseif ($stream) { $stream.Dispose() }
            }
        }
        Start-Sleep -Milliseconds 250
    }
    throw "Task '$Name' did not confirm monitor startup within 15 seconds. Check Task Scheduler history and monitor.log."
}

