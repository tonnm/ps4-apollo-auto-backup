param([switch]$SelfContained, [string]$Runtime = 'win-x64')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$oldCli = $env:DOTNET_CLI_HOME; $oldPackages = $env:NUGET_PACKAGES
$oldRoaming = $env:APPDATA; $oldLocal = $env:LOCALAPPDATA
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
$env:DOTNET_ADD_GLOBAL_TOOLS_TO_PATH = 'false'
try {
    $env:DOTNET_CLI_HOME = Join-Path $repo '.dotnet-home'
    $env:NUGET_PACKAGES = Join-Path $repo '.nuget'
    $env:APPDATA = Join-Path $env:DOTNET_CLI_HOME 'AppData\Roaming'
    $env:LOCALAPPDATA = Join-Path $env:DOTNET_CLI_HOME 'AppData\Local'
    New-Item -ItemType Directory -Force $env:APPDATA, $env:LOCALAPPDATA | Out-Null
    $kind = 'framework-dependent'; if ($SelfContained) { $kind = 'self-contained' }
    $output = Join-Path $repo "dist\v1.1.0-$Runtime-$kind"
    $arguments = @('publish', (Join-Path $repo 'gui\Apollo.Gui\Apollo.Gui.csproj'), '-c', 'Release', '-r', $Runtime,
        '--self-contained', $SelfContained.ToString().ToLowerInvariant(), '-o', $output, '--nologo',
        ('-p:RestoreConfigFile=' + (Join-Path $PSScriptRoot 'NuGet.Config')))
    if ($SelfContained) { $arguments += '-p:RuntimeFrameworkVersion=10.0.12' }
    & dotnet @arguments
    if ($LASTEXITCODE -ne 0) { throw 'GUI publishing failed.' }
    $files = @(Get-ChildItem -LiteralPath $output -File -Recurse | Where-Object { $_.Name -ne 'package-manifest.json' } | ForEach-Object {
        [ordered]@{ Path = $_.FullName.Substring($output.Length + 1).Replace('\', '/'); Sha256 = (Get-FileHash -LiteralPath $_.FullName).Hash }
    })
    $files | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'package-manifest.json') -Encoding UTF8
    Compress-Archive -Path (Join-Path $output '*') -DestinationPath ($output + '.zip') -Force
    (Get-FileHash -LiteralPath ($output + '.zip')).Hash | Set-Content -LiteralPath ($output + '.zip.sha256') -Encoding ASCII
    Write-Host "[OK] Published v1.1.0: $output"
}
finally { $env:DOTNET_CLI_HOME = $oldCli; $env:NUGET_PACKAGES = $oldPackages; $env:APPDATA = $oldRoaming; $env:LOCALAPPDATA = $oldLocal }
