# Native Windows PowerShell tests. All writes stay in .test-artifacts.
# Task Scheduler writes are mocked; no production task or configuration is touched.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'src\Common.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$work = Join-Path $repo ('.test-artifacts\run-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$results = @{ Passed = 0 }
function Assert {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
    $results.Passed++
    Write-Host "PASS: $Name"
}
function New-TestZip {
    param([string]$Path, [string]$Content, [int]$Year = 2020, [switch]$Reverse, [string]$EntryName = 'data/save.bin')
    if ([IO.File]::Exists($Path)) { [IO.File]::Delete($Path) }
    $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $names = @($EntryName, 'sce_sys/param.sfo')
        if ($Reverse) { [array]::Reverse($names) }
        foreach ($name in $names) {
            $entry = $zip.CreateEntry($name)
            $entry.LastWriteTime = [DateTimeOffset]::new($Year, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
            $stream = $entry.Open()
            try {
                $value = 'metadata-content'
                if ($name -eq $EntryName) { $value = $Content }
                $bytes = [Text.Encoding]::UTF8.GetBytes($value)
                $stream.Write($bytes, 0, $bytes.Length)
            }
            finally { $stream.Dispose() }
        }
    }
    finally { $zip.Dispose() }
}
function Invoke-Fixture {
    param([string]$Mode = 'ok', [string]$Position = '00000001', [int]$Expected = 0)
    $exe = Join-Path $PSHOME 'powershell.exe'
    $output = & $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-FixtureBackup.ps1') -ConfigPath $script:configPath -FixtureRoot $work -Mode $Mode -Position $Position 2>&1
    $code = $LASTEXITCODE
    $output | Out-File -LiteralPath (Join-Path $work 'fixture-output.log') -Append -Encoding UTF8
    Assert ($code -eq $Expected) "backup $Mode exits $Expected (actual $code)"
}
function Get-ZipCount { @(Get-ChildItem -LiteralPath (Join-Path $data 'Backups') -Recurse -Filter *.zip).Count }
function Get-StateHash { (Get-FileHash -LiteralPath $state).Hash }

Get-ChildItem -LiteralPath $repo -Recurse -Filter *.ps1 | Where-Object { $_.FullName -notlike '*\.test-artifacts\*' } | ForEach-Object {
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    Assert ($errors.Count -eq 0) "syntax $($_.Name)"
}
$null = Read-BackupConfig (Join-Path $repo 'config.example.json')
Assert $true 'example JSON and configuration validation'
$data = Join-Path $work 'data [special]'
$configPath = Join-Path $work 'config.json'
Write-AtomicJson @{ ps4Address = '127.0.0.1'; apolloPort = 1; backupPath = $data } $configPath
$state = Join-Path $data 'backup-state-v4.json'
New-TestZip (Join-Path $work 'first.zip') 'first version'
New-TestZip (Join-Path $work 'second.zip') 'second save'

# Compare against a fixed vector derived from V4's relative-path/file-hash serialization.
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'src\Backup-PS4.ps1'), [ref]$tokens, [ref]$errors)
$function = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-SaveContentHash' }, $true)
. ([scriptblock]::Create($function.Extent.Text))
$PastaTemp = $work
$firstHash = Get-SaveContentHash (Join-Path $work 'first.zip') (Join-Path $work 'extract-a')
Assert ($firstHash -eq 'F6C97E9CDD1CA161FAC89EA3C7E3BA0302B1864DFEE9CF2385ED768F692A182F') 'published V4 regression vector'
$reference = Join-Path $repo '.test-artifacts\V4-Hash.ps1'
if (Test-Path -LiteralPath $reference) {
    $oldHash = & { . $reference; Get-SaveContentHash (Join-Path $work 'first.zip') (Join-Path $work 'extract-v4') }
    Assert ($firstHash -eq $oldHash) 'hash matches original V4 function'
}
New-TestZip (Join-Path $work 'equivalent.zip') 'first version' 2025 -Reverse
$equivalent = Get-SaveContentHash (Join-Path $work 'equivalent.zip') (Join-Path $work 'extract-b')
Assert ($firstHash -eq $equivalent) 'ZIP timestamps, entry order and extraction roots do not change hash'
New-TestZip (Join-Path $work 'renamed.zip') 'first version' -EntryName 'data/renamed.bin'
$renamed = Get-SaveContentHash (Join-Path $work 'renamed.zip') (Join-Path $work 'extract-c')
Assert ($firstHash -ne $renamed) 'internal relative paths remain part of V4 signature'
New-TestZip (Join-Path $work 'traversal.zip') 'escape' -EntryName '../escape.bin'
$rejected = $false
try { $null = Get-SaveContentHash (Join-Path $work 'traversal.zip') (Join-Path $work 'extract-unsafe') } catch { $rejected = $true }
Assert ($rejected -and -not (Test-Path -LiteralPath (Join-Path $work 'escape.bin'))) 'ZIP traversal rejected before extraction'

Invoke-Fixture
Assert ((Get-ZipCount) -eq 2) 'missing state: NEW saves stored, including bracketed folder name'
$before = Get-StateHash
Copy-Item -LiteralPath (Join-Path $work 'equivalent.zip') -Destination (Join-Path $work 'first.zip') -Force
Invoke-Fixture -Position '00000999'
Assert ((Get-ZipCount) -eq 2 -and (Get-StateHash) -eq $before) 'UNCHANGED and reordered Apollo positions preserve ZIP count and state bytes'
New-TestZip (Join-Path $work 'first.zip') 'changed content'
Invoke-Fixture
Assert ((Get-ZipCount) -eq 3 -and (Get-StateHash) -ne $before) 'CHANGED creates one version and commits state'
$before = Get-StateHash
foreach ($mode in 'offline', 'empty', 'download-fail', 'badzip', 'unsafe') {
    $exitCode = 20
    if ($mode -eq 'offline') { $exitCode = 10 }; if ($mode -eq 'empty') { $exitCode = 11 }
    Invoke-Fixture -Mode $mode -Expected $exitCode
    Assert ((Get-StateHash) -eq $before -and (Get-ZipCount) -eq 3) "$mode preserves state and all valid backups"
}
$lock = Enter-AppLock $data 'backup'
try { Invoke-Fixture -Expected 12; Assert ((Get-StateHash) -eq $before) 'concurrent process blocked without state changes' }
finally { $lock.Dispose() }
New-TestZip (Join-Path $work 'first.zip') 'third content'
$previous = Get-Content -LiteralPath $state -Raw | ConvertFrom-Json
Invoke-Fixture -Mode partial -Expected 20
$current = Get-Content -LiteralPath $state -Raw | ConvertFrom-Json
Assert ((Get-ZipCount) -eq 4 -and $current.'CUSA00002|SECOND'.Hash -eq $previous.'CUSA00002|SECOND'.Hash) 'partial success commits good save and preserves failed save state'
$validState = [IO.File]::ReadAllText($state)
[IO.File]::WriteAllText($state, '{broken')
$before = Get-StateHash
Invoke-Fixture -Expected 13
Assert ((Get-StateHash) -eq $before -and (Get-ZipCount) -eq 4) 'corrupted state preserved byte-for-byte'
[IO.File]::WriteAllText($state, $validState)
$handle = [IO.File]::Open($state, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try {
    $failed = $false
    try { Write-AtomicJson @{ invalid = $true } $state } catch { $failed = $true }
    Assert ($failed -and [IO.File]::ReadAllText($state) -eq $validState) 'failed atomic replacement leaves previous state intact'
}
finally { $handle.Dispose() }

# Exercise the actual monitor loop with deterministic port transitions and a failing backup stub.
$monitorApp = Join-Path $work 'monitor-fixture'
$monitorSrc = Join-Path $monitorApp 'src'
New-Item -ItemType Directory -Path $monitorSrc -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'src\Monitor-PS4.ps1') -Destination $monitorSrc
Copy-Item -LiteralPath (Join-Path $repo 'src\Common.ps1') -Destination $monitorSrc
@'
$MonitorTest = @{ Index = 0; Sequence = @($false, $true, $true, $false, $true, $true) }
function Test-ApolloPort {
    param($Address, $Port)
    $MonitorTest.Sequence[$MonitorTest.Index]
}
function Start-Sleep {
    param($Seconds)
    $MonitorTest.Index++
    if ($MonitorTest.Index -eq $MonitorTest.Sequence.Count) { throw 'Monitor fixture completed.' }
}
'@ | Add-Content -LiteralPath (Join-Path $monitorSrc 'Common.ps1') -Encoding UTF8
@'
param($ConfigPath)
[IO.File]::AppendAllText((Join-Path (Split-Path $PSScriptRoot -Parent) 'attempts.txt'), "attempt`n")
exit 20
'@ | Set-Content -LiteralPath (Join-Path $monitorSrc 'Backup-PS4.ps1') -Encoding UTF8
$finished = $false
try { & (Join-Path $monitorSrc 'Monitor-PS4.ps1') -ConfigPath $configPath }
catch { $finished = $_.Exception.Message -eq 'Monitor fixture completed.' }
$attempts = @(Get-Content -LiteralPath (Join-Path $monitorApp 'attempts.txt'))
Assert ($finished -and $attempts.Count -eq 2) 'monitor runs once per OFF/ON transition, including after a failed backup'
$lock = Enter-AppLock $data 'monitor'
try {
    $null = & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'src\Monitor-PS4.ps1') -ConfigPath $configPath
    Assert ($LASTEXITCODE -eq 12) 'second monitor process refused'
}
finally { $lock.Dispose() }

. (Join-Path $PSScriptRoot 'TaskSetup-Tests.ps1')

foreach ($invalid in @(
    @{ ps4Address = 'not-an-ip'; apolloPort = 8080; backupPath = $data },
    @{ ps4Address = '127.0.0.1'; apolloPort = 0; backupPath = $data },
    @{ ps4Address = '127.0.0.1'; apolloPort = 65536; backupPath = $data },
    @{ ps4Address = '127.0.0.1'; apolloPort = 1.5; backupPath = $data },
    @{ ps4Address = '127.0.0.1'; apolloPort = 8080; backupPath = 'relative-folder' },
    @{ ps4Address = '127.0.0.1'; apolloPort = 8080; backupPath = 'C:\' }
)) {
    $invalidPath = Join-Path $work ('invalid-config-' + [guid]::NewGuid().ToString('N') + '.json')
    Write-AtomicJson $invalid $invalidPath
    $rejected = $false
    try { $null = Read-BackupConfig $invalidPath } catch { $rejected = $true }
    Assert $rejected 'invalid configuration rejected'
}

if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitFixture = Join-Path $work 'ignore-check'
    New-Item -ItemType Directory -Path $gitFixture -Force | Out-Null
    $null = & git -C $gitFixture init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize disposable Git fixture.' }
    Copy-Item -LiteralPath (Join-Path $repo '.gitignore') -Destination $gitFixture
    foreach ($name in @('config.json', 'backup.log', 'backup-state-v4.json', 'Backups/example.zip', 'Temp/export.bin', '.test-artifacts/result.txt', 'example.zip', 'dist/release.zip', '.backup.lock')) {
        $null = & git -C $gitFixture check-ignore --no-index $name
        Assert ($LASTEXITCODE -eq 0) "gitignore excludes $name"
    }
    foreach ($name in @('config.example.json', 'README.md', 'src/Backup-PS4.ps1', 'tests/Run-Tests.ps1')) {
        $null = & git -C $gitFixture check-ignore --no-index $name
        Assert ($LASTEXITCODE -eq 1) "gitignore retains $name"
    }
}
Write-Host "PASS: $($results.Passed) assertions. Test outputs are in ignored .test-artifacts."
exit 0


