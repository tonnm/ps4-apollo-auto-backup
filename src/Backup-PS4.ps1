# ============================================================
# PS4 SAVE BACKUP V4
# Apollo Save Tool -> PC
#
# - Detects all saves exposed by Apollo
# - Downloads each ZIP temporarily
# - Extracts and hashes the internal files
# - Ignores ZIP metadata and timestamps
# - Stores only new or changed saves
# - Keeps version history
# - Does not use Apollo list position as save identity
# - Does not write anything to the PS4
# ============================================================

param([string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config.json'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
try { $Config = Read-BackupConfig $ConfigPath }
catch { Write-Host "[ERROR] Configuration could not be loaded: $($_.Exception.Message)"; exit 1 }
$Apollo = "http://$($Config.ps4Address):$($Config.apolloPort)"
$BaseBackup = $Config.backupPath
$PastaDados = Join-Path $BaseBackup 'Backups'
$PastaTemp = Join-Path $BaseBackup 'Temp'
$ArquivoDB = Join-Path $BaseBackup 'backup-state-v4.json'
$ArquivoLog = Join-Path $BaseBackup 'backup.log'
$BackupLock = $null
# ------------------------------------------------------------
# LOG
# ------------------------------------------------------------

function Write-Log {

    param(
        [string]$Mensagem,
        [string]$Tipo = "INFO"
    )

    $DataHora = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Linha = "[$DataHora] [$Tipo] $Mensagem"

    Write-Host $Linha

    Add-Content `
        -LiteralPath $ArquivoLog `
        -Value $Linha `
        -Encoding UTF8
}

# ------------------------------------------------------------
# CALCULATE REAL SAVE CONTENT HASH
# ------------------------------------------------------------

function Get-SaveContentHash {

    param(
        [string]$ZipFile,
        [string]$ExtractFolder
    )

    if (Test-Path -LiteralPath $ExtractFolder) {
        Remove-TempItem -Path $ExtractFolder -Root $PastaTemp
    }

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $ExtractFolder |
        Out-Null

    # Reject archive paths outside the extraction folder before expanding any entry.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Archive = [IO.Compression.ZipFile]::OpenRead($ZipFile)
    try {
        $Prefix = [IO.Path]::GetFullPath($ExtractFolder).TrimEnd('\') + '\'
        foreach ($Entry in $Archive.Entries) {
            $EntryPath = [IO.Path]::GetFullPath([IO.Path]::Combine($Prefix, $Entry.FullName))
            if ($Entry.FullName.Contains(':') -or -not $EntryPath.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'ZIP entry escapes its extraction directory.'
            }
        }
    }
    finally { $Archive.Dispose() }

    # .NET extraction treats bracketed destination paths literally (unlike
    # Windows PowerShell 5.1 Expand-Archive internals). Hashing below is V4.
    [IO.Compression.ZipFile]::ExtractToDirectory($ZipFile, $ExtractFolder)

    $Arquivos = Get-ChildItem `
        -LiteralPath $ExtractFolder `
        -File `
        -Recurse |
        Sort-Object FullName

    if (-not $Arquivos) {
        throw "ZIP contains no files."
    }

    $Assinaturas = foreach ($Arquivo in $Arquivos) {

        $HashArquivo = (
            Get-FileHash `
                -LiteralPath $Arquivo.FullName `
                -Algorithm SHA256
        ).Hash

        $Relativo = $Arquivo.FullName.Substring(
            $ExtractFolder.Length
        ).TrimStart('\')

        "$Relativo|$HashArquivo"
    }

    $Texto = $Assinaturas -join "`n"

    $SHA256 = [System.Security.Cryptography.SHA256]::Create()

    try {

        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Texto)

        $HashBytes = $SHA256.ComputeHash($Bytes)

        $HashFinal = (
            $HashBytes |
            ForEach-Object { $_.ToString("x2") }
        ) -join ""

        return $HashFinal.ToUpper()

    }
    finally {

        $SHA256.Dispose()
    }
}

# ------------------------------------------------------------
# PREPARE DIRECTORIES
# ------------------------------------------------------------

try {
New-Item -ItemType Directory -Force -Path $BaseBackup | Out-Null
try { $BackupLock = Enter-AppLock $BaseBackup 'backup' }
catch { Write-Warning 'Backup is already running or the backup folder is not writable.'; exit 12 }
New-Item -ItemType Directory -Force -Path $PastaDados | Out-Null
New-Item -ItemType Directory -Force -Path $PastaTemp | Out-Null

Write-Host ""
Write-Host "=========================================="
Write-Host "       PS4 SAVE BACKUP - v1.0.0"
Write-Host "=========================================="
Write-Host ""

Write-Log "Starting backup v1.0.0 (V4 content comparison)."

# ------------------------------------------------------------
# LOAD STATE DATABASE
# ------------------------------------------------------------

$Estado = @{}

if (Test-Path -LiteralPath $ArquivoDB) {

    try {

        $Json = Get-Content `
            -LiteralPath $ArquivoDB `
            -Raw `
            -Encoding UTF8 |
            ConvertFrom-Json

        if ($Json -isnot [pscustomobject]) { throw 'State must be a JSON object.' }
        foreach ($Propriedade in $Json.PSObject.Properties) {
            if ($Propriedade.Value.Hash -notmatch '^[A-Fa-f0-9]{64}$' -or
                [string]::IsNullOrWhiteSpace([string]$Propriedade.Value.Arquivo) -or
                [string]::IsNullOrWhiteSpace([string]$Propriedade.Value.Data)) {
                throw 'Invalid state entry.'
            }

            $Estado[$Propriedade.Name] = @{
                Hash = $Propriedade.Value.Hash
                Arquivo = $Propriedade.Value.Arquivo
                Data = $Propriedade.Value.Data
            }
        }

        Write-Log "State loaded: $($Estado.Count) known saves."

    }
    catch {

        Write-Log "State database is invalid; preserved without changes. See docs/troubleshooting.md." "ERROR"
        exit 13
    }
}

# ------------------------------------------------------------
# CONNECT TO APOLLO
# ------------------------------------------------------------

Write-Log "Connecting to Apollo..."

try {

    $Pagina = Invoke-WebRequest `
        -Uri $Apollo `
        -UseBasicParsing `
        -MaximumRedirection 0 `
        -TimeoutSec 10

}
catch {

    Write-Log "Apollo is not available." "ERROR"
    exit 10
}

Write-Log "Apollo connected."

# ------------------------------------------------------------
# FIND SAVES
# ------------------------------------------------------------

$Links = @($Pagina.Links |
    Where-Object { $_.href -like "/zip/*" } |
    Select-Object -ExpandProperty href -Unique)

if (-not $Links) {

    Write-Log "No saves found." "ERROR"
    exit 11
}

Write-Log "$($Links.Count) saves found."

Write-Host ""

# ------------------------------------------------------------
# COUNTERS
# ------------------------------------------------------------

$Novos = 0
$Alterados = 0
$SemAlteracao = 0
$Falhas = 0

# ------------------------------------------------------------
# PROCESS SAVES
# ------------------------------------------------------------

foreach ($Link in $Links) {

    $Url = "$Apollo$Link"

    $Partes = $Link.TrimStart("/") -split "/"

    if ($Partes.Count -ne 3 -or $Partes[2] -notmatch '(?i)\.zip$') {
        Write-Log 'Skipped an unexpected Apollo ZIP link.' 'ERROR'
        $Falhas++
        continue
    }
    $ArquivoOriginal = $Partes[2]

    $NomeSave = [System.IO.Path]::GetFileNameWithoutExtension(
        $ArquivoOriginal
    )

    if ($NomeSave -match '^([A-Za-z]{4}\d{5})_(.+)$') {

        $TitleID = $Matches[1]
        $SaveName = $Matches[2]

    }
    else {

        $TitleID = "OUTROS"
        $SaveName = $NomeSave
    }

    # IMPORTANT:
    # Apollo /zip/000000xx position is NOT a stable save identifier.
    # Permanent identity uses only Title ID + Save Name.

    $Chave = "$TitleID|$SaveName"
    try { Assert-SafeSaveName $TitleID; Assert-SafeSaveName $SaveName }
    catch { Write-Log 'Skipped unsafe save folder name.' 'ERROR'; $Falhas++; continue }

    $Guid = [Guid]::NewGuid().ToString()

    $TempZip = Join-Path $PastaTemp "$Guid.zip"
    $TempExtract = Join-Path $PastaTemp $Guid

    Write-Host "[$TitleID] $SaveName"

    # --------------------------------------------------------
    # DOWNLOAD
    # --------------------------------------------------------

    try {

        Invoke-WebRequest `
            -Uri $Url `
            -OutFile $TempZip `
            -UseBasicParsing `
            -MaximumRedirection 0 `
            -TimeoutSec 120

    }
    catch {

        Write-Host "   ERROR - download failed"

        Write-Log `
            "Download failed: $ArquivoOriginal" `
            "ERROR"

        $Falhas++

        if (Test-Path -LiteralPath $TempZip) {
            Remove-TempItem $TempZip $PastaTemp
        }

        if (Test-Path -LiteralPath $TempExtract) {
            Remove-TempItem $TempExtract $PastaTemp
        }

        continue
    }

    # --------------------------------------------------------
    # CALCULATE CONTENT HASH
    # --------------------------------------------------------

    try {

        $HashAtual = Get-SaveContentHash `
            -ZipFile $TempZip `
            -ExtractFolder $TempExtract

    }
    catch {

        Write-Host "   ERROR - ZIP analysis failed"

        Write-Log `
            "ZIP analysis failed: $ArquivoOriginal - $($_.Exception.Message)" `
            "ERROR"

        $Falhas++

        if (Test-Path -LiteralPath $TempZip) {
            Remove-TempItem $TempZip $PastaTemp
        }

        if (Test-Path -LiteralPath $TempExtract) {
            Remove-TempItem $TempExtract $PastaTemp
        }

        continue
    }

    # --------------------------------------------------------
    # COMPARE
    # --------------------------------------------------------

    $ExisteAnterior = $Estado.ContainsKey($Chave)

    if ($ExisteAnterior) {

        if ($HashAtual -eq $Estado[$Chave].Hash) {

            Write-Host "   OK - no changes"

            Write-Log "$TitleID" "UNCHANGED"
            $SemAlteracao++

            Remove-TempItem $TempZip $PastaTemp

            if (Test-Path -LiteralPath $TempExtract) {
                Remove-TempItem $TempExtract $PastaTemp
            }

            continue
        }

        $TipoBackup = "CHANGED"

    }
    else {

        $TipoBackup = "NEW"
    }

    # --------------------------------------------------------
    # FINAL DIRECTORY
    # --------------------------------------------------------

    $PastaSave = Join-Path $PastaDados $TitleID
    $PastaSave = Join-Path $PastaSave $SaveName

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $PastaSave |
        Out-Null

    # --------------------------------------------------------
    # VERSION FILE
    # --------------------------------------------------------

    $DataArquivo = (Get-Date -Format "yyyy-MM-dd_HH-mm-ss-fff") + "_" + $Guid

    $Destino = Join-Path `
        $PastaSave `
        "$DataArquivo.zip"

    # Temp and Backups share a root/volume. Never overwrite an existing version.
    [IO.File]::Move($TempZip, $Destino)
    # --------------------------------------------------------
    # UPDATE STATE
    # --------------------------------------------------------

    $Estado[$Chave] = @{
        Hash = $HashAtual
        Arquivo = $Destino
        Data = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }

    Write-AtomicJson -Value $Estado -Path $ArquivoDB

    if ($TipoBackup -eq "NEW") {

        Write-Host "   NEW - first version saved"

        Write-Log "$TitleID" "NEW"

        $Novos++

    }
    else {

        Write-Host "   CHANGED - new version saved"

        Write-Log "$TitleID" "CHANGED"

        $Alterados++
    }

    if (Test-Path -LiteralPath $TempExtract) {
        Remove-TempItem $TempExtract $PastaTemp
    }
}

# ------------------------------------------------------------
# SAVE STATE DATABASE
# ------------------------------------------------------------

# State is committed after each successfully published ZIP.
# Do not rewrite state on unchanged runs or after failed downloads.
# Only this run's temporary files are removed; interrupted leftovers are harmless.

# ------------------------------------------------------------
# SUMMARY
# ------------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "             BACKUP COMPLETE"
Write-Host "=========================================="
Write-Host ""
Write-Host "New:       $Novos"
Write-Host "Changed:   $Alterados"
Write-Host "Unchanged: $SemAlteracao"
Write-Host "Failures:  $Falhas"
Write-Host ""

Write-Log "Backup complete. New=$Novos Changed=$Alterados Unchanged=$SemAlteracao Failures=$Falhas"

if ($Falhas -gt 0) {
    exit 20
}

exit 0
}
catch {
    $FailureMessage = "Backup stopped: $($_.Exception.Message)"
    try { Write-Log $FailureMessage 'ERROR' }
    catch { Write-Host "[ERROR] $FailureMessage (log could not be written)" }
    exit 1
}
finally {
    if ($BackupLock) { $BackupLock.Dispose() }
}
