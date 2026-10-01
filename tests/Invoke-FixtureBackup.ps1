# Test-only HTTP boundary: no connection to a console or network service.
param([string]$ConfigPath, [string]$FixtureRoot, [string]$Mode = 'ok', [string]$Position = '00000001')
$ErrorActionPreference = 'Stop'
function Invoke-WebRequest {
    param($Uri, $OutFile, [switch]$UseBasicParsing, $TimeoutSec, $MaximumRedirection)
    if ($Mode -eq 'offline') { throw 'Simulated unavailable Apollo.' }
    if (-not $OutFile) {
        if ($Mode -eq 'empty') { return [pscustomobject]@{ Links = @() } }
        $names = @('CUSA00001_SLOT [1].zip', 'CUSA00002_SECOND.zip')
        if ($Mode -eq 'unsafe') { $names = @('CUSA00001_...zip') }
        return [pscustomobject]@{ Links = @($names | ForEach-Object { [pscustomobject]@{ href = "/zip/$Position/$_" } }) }
    }
    if ($Mode -eq 'download-fail' -or ($Mode -eq 'partial' -and $Uri -like '*SECOND.zip')) {
        [IO.File]::WriteAllText($OutFile, 'partial download')
        throw 'Simulated interrupted transfer.'
    }
    if ($Mode -eq 'badzip') { [IO.File]::WriteAllText($OutFile, 'not a zip'); return }
    $source = 'first.zip'
    if ($Uri -like '*SECOND.zip') { $source = 'second.zip' }
    [IO.File]::Copy((Join-Path $FixtureRoot $source), $OutFile, $false)
    if ($Mode -eq 'log-reader' -and $source -eq 'second.zip') {
        # Hold the same access/share flags as History.ReadTail across the final save.
        $log = Join-Path ((Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json).backupPath) 'backup.log'
        $script:logReader = [IO.File]::Open($log, [IO.FileMode]::Open, [IO.FileAccess]::Read,
            ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    }
}
try { & (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\Backup-PS4.ps1') -ConfigPath $ConfigPath }
finally { if ($script:logReader) { $script:logReader.Dispose() } }
exit $LASTEXITCODE
