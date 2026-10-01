$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$saved = @{}
foreach ($name in @('DOTNET_CLI_TELEMETRY_OPTOUT', 'DOTNET_GENERATE_ASPNET_CERTIFICATE', 'DOTNET_ADD_GLOBAL_TOOLS_TO_PATH', 'DOTNET_CLI_HOME', 'NUGET_PACKAGES', 'APPDATA', 'LOCALAPPDATA')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
$env:DOTNET_ADD_GLOBAL_TOOLS_TO_PATH = 'false'
$env:DOTNET_CLI_HOME = Join-Path $repo '.dotnet-home'
$env:NUGET_PACKAGES = Join-Path $repo '.nuget'
$env:APPDATA = Join-Path $env:DOTNET_CLI_HOME 'AppData\Roaming'
$env:LOCALAPPDATA = Join-Path $env:DOTNET_CLI_HOME 'AppData\Local'
& dotnet run --project (Join-Path $repo 'gui\Apollo.Tests\Apollo.Tests.csproj') -c Release ('-p:RestoreConfigFile=' + (Join-Path $PSScriptRoot 'NuGet.Config')) -- $repo
if ($LASTEXITCODE -ne 0) { throw 'GUI/service tests failed.' }
}
finally { foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') } }
