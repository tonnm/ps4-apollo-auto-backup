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
}
& (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\Backup-PS4.ps1') -ConfigPath $ConfigPath
exit $LASTEXITCODE
