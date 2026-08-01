[CmdletBinding()]
param(
    [switch]$SmokeTest,
    [switch]$Console
)

$ErrorActionPreference = "Stop"
$bundleRoot = Split-Path -Parent $PSScriptRoot
$application = Join-Path $bundleRoot "app\sw_companions.py"

if (-not (Test-Path -LiteralPath $application -PathType Leaf)) {
    throw "Application entry point is missing: $application"
}

$pythonCommand = Get-Command "python.exe" -ErrorAction SilentlyContinue
if ($null -eq $pythonCommand) {
    throw "Python 3 was not found. Install Python 3.11 or newer and enable 'Add Python to PATH'."
}

if ($SmokeTest) {
    & $pythonCommand.Source $application --smoke-test
    exit $LASTEXITCODE
}

if ($Console) {
    & $pythonCommand.Source $application
    exit $LASTEXITCODE
}

$pythonDirectory = Split-Path -Parent $pythonCommand.Source
$pythonWindowed = Join-Path $pythonDirectory "pythonw.exe"
if (Test-Path -LiteralPath $pythonWindowed -PathType Leaf) {
    Start-Process -FilePath $pythonWindowed -ArgumentList @($application) -WorkingDirectory $bundleRoot -WindowStyle Hidden
}
else {
    Start-Process -FilePath $pythonCommand.Source -ArgumentList @($application) -WorkingDirectory $bundleRoot -WindowStyle Hidden
}
