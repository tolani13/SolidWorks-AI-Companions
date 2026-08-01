[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$bundleRoot = Split-Path -Parent $PSScriptRoot
$application = Join-Path $bundleRoot "app\sw_companions.py"
$bridge = Join-Path $bundleRoot "skills\solidworks-forge\scripts\Invoke-SolidWorksBridge.ps1"
$tests = Join-Path $bundleRoot "tests"

$pythonCommand = Get-Command "python.exe" -ErrorAction SilentlyContinue
if ($null -eq $pythonCommand) {
    throw "Python 3 was not found."
}

& $pythonCommand.Source -m py_compile $application
if ($LASTEXITCODE -ne 0) {
    throw "Python compilation failed."
}

& $pythonCommand.Source -m unittest discover -s $tests -p "test_*.py" -v
if ($LASTEXITCODE -ne 0) {
    throw "Python tests failed."
}

& $pythonCommand.Source $application --smoke-test
if ($LASTEXITCODE -ne 0) {
    throw "Application smoke test failed."
}

$parseTokens = $null
$parseErrors = $null
$parsedBridge = [System.Management.Automation.Language.Parser]::ParseFile(
    $bridge,
    [ref]$parseTokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    $messages = ($parseErrors | ForEach-Object { $_.Message }) -join "; "
    throw "PowerShell bridge has parse errors: $messages"
}

$bridgeOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bridge -Action status -ArgumentsJson "{}"
$bridgeResult = ($bridgeOutput | Select-Object -Last 1) | ConvertFrom-Json
if ($null -eq $bridgeResult.ok -or $bridgeResult.action -ne "status") {
    throw "Bridge status response did not match its JSON contract."
}

Write-Host "All tests passed. Live modifying CAD actions were not run."
