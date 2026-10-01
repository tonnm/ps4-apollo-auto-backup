# ============================================================
# PS4 APOLLO BACKUP MONITOR V4
#
# Waits for Apollo Web Server to become available.
#
# Apollo OFF -> wait
# Apollo ON  -> run backup once
# Apollo ON  -> do not run again
# Apollo OFF -> rearm
# Apollo ON  -> run next backup
# ============================================================

param([string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config.json'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$Config = Read-BackupConfig $ConfigPath
$ApolloIP = $Config.ps4Address
$ApolloPort = $Config.apolloPort
$BackupScript = Join-Path $PSScriptRoot 'Backup-PS4.ps1'
$LogFile = Join-Path $Config.backupPath 'monitor.log'
$MonitorLock = $null
$Intervalo = 10

function Write-MonitorLog {

    param(
        [string]$Mensagem
    )

    $DataHora = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $Linha = "[$DataHora] [INFO] $Mensagem"

    Write-Host $Linha

    Add-AppLogLine -Path $LogFile -Line $Linha
}

function Test-Apollo {
    Test-ApolloPort -Address $ApolloIP -Port $ApolloPort
}

try {
New-Item `
    -ItemType Directory `
    -Force `
    -Path $Config.backupPath |
    Out-Null

Write-Host ""
Write-Host "=========================================="
Write-Host "       PS4 APOLLO MONITOR - v1.0.0"
Write-Host "=========================================="
Write-Host ""

try { $MonitorLock = Enter-AppLock $Config.backupPath 'monitor' }
catch { Write-Warning 'Monitor is already running or its folder is not writable.'; exit 12 }
Write-MonitorLog "Monitor started."
Write-MonitorLog "Waiting for the configured Apollo TCP port."

$ApolloAnterior = $false

while ($true) {

    $ApolloAtual = Test-Apollo

    # Apollo changed from OFF to ON

    if ($ApolloAtual -and -not $ApolloAnterior) {

        Write-MonitorLog "Apollo detected."
        Write-MonitorLog "Starting PS4 save backup."

        try {

            & $BackupScript -ConfigPath $ConfigPath

            $ExitCode = $LASTEXITCODE

            if ($ExitCode -eq 0) {

                Write-MonitorLog "Backup completed successfully."

            }
            else {

                Write-MonitorLog "Backup finished with exit code $ExitCode."
            }

        }
        catch {

            Write-MonitorLog "Backup execution failed: $($_.Exception.Message)"
        }

        Write-MonitorLog "Waiting for Apollo to close before next backup."
    }

    # Apollo changed from ON to OFF

    if (-not $ApolloAtual -and $ApolloAnterior) {

        Write-MonitorLog "Apollo disconnected."
        Write-MonitorLog "Monitor rearmed."
    }

    $ApolloAnterior = $ApolloAtual

    Start-Sleep -Seconds $Intervalo
}
}
finally {
    if ($MonitorLock) { $MonitorLock.Dispose() }
}
