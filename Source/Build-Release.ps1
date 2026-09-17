param(
    [string]$Version = '1.0.4'
)

$ErrorActionPreference = 'Stop'
$sourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $sourceDir
$outputDir = Join-Path $root 'EXE'
$source = Join-Path $sourceDir 'GitHelper.ps1'
$icon = Join-Path $sourceDir 'GitHelper.ico'
$output = Join-Path $outputDir 'GitHelper.exe'
$zip = Join-Path $outputDir 'GitHelper.zip'

if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    Import-Module ps2exe -ErrorAction Stop
}

Invoke-ps2exe -inputFile $source -outputFile $output -noConsole -DPIAware -supportOS `
    -iconFile $icon -title "GitHelper v$Version" -product 'GitHelper' -version "$Version.0" -ErrorAction Stop

if (-not (Test-Path -LiteralPath $output)) {
    throw "EXE build failed: $output"
}

Compress-Archive -LiteralPath $output -DestinationPath $zip -Force
Write-Host "Built: $output"
Write-Host "Built: $zip"
