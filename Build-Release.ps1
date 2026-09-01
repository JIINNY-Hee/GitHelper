param(
    [string]$Version = '1.0.0'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $root 'GitHelper.ps1'
$icon = Join-Path $root 'GitHelper.ico'
$output = Join-Path $root 'GitHelper.exe'
$zip = Join-Path $root 'GitHelper.zip'

if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    Import-Module ps2exe -ErrorAction Stop
}

Invoke-ps2exe -inputFile $source -outputFile $output -noConsole -DPIAware -supportOS `
    -iconFile $icon -title "GitHelper v$Version" -product 'GitHelper' -version "$Version.0"

Compress-Archive -LiteralPath $output -DestinationPath $zip -Force
Write-Host "Built: $output"
Write-Host "Built: $zip"
