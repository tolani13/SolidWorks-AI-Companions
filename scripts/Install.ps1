[CmdletBinding()]
param(
    [string]$Destination = (Join-Path $env:LOCALAPPDATA "SolidWorksAICompanions\App"),
    [switch]$InstallCodexSkills,
    [switch]$CreateDesktopShortcut,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$sourceRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$destinationRoot = [System.IO.Path]::GetFullPath($Destination)
$requiredItems = @("app", "skills", "scripts", "tests", "README.md", "config.example.json")

if (-not (Get-Command "python.exe" -ErrorAction SilentlyContinue)) {
    throw "Python 3 was not found. Install Python 3.11 or newer and enable 'Add Python to PATH'."
}

foreach ($item in $requiredItems) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $item))) {
        throw "Bundle is incomplete. Missing: $item"
    }
}

$sameLocation = $sourceRoot.TrimEnd("\") -ieq $destinationRoot.TrimEnd("\")
if (-not $sameLocation) {
    if ((Test-Path -LiteralPath $destinationRoot) -and -not $Force) {
        throw "Destination already exists: $destinationRoot. Re-run with -Force to refresh it."
    }

    $createdDestination = New-Item -ItemType Directory -Path $destinationRoot -Force
    foreach ($name in @("app", "skills", "scripts", "tests")) {
        $sourceDirectory = Join-Path $sourceRoot $name
        $targetDirectory = Join-Path $destinationRoot $name
        $createdTarget = New-Item -ItemType Directory -Path $targetDirectory -Force
        Get-ChildItem -LiteralPath $sourceDirectory -Force |
            Copy-Item -Destination $targetDirectory -Recurse -Force
    }
    foreach ($name in @("README.md", "config.example.json")) {
        Copy-Item -LiteralPath (Join-Path $sourceRoot $name) -Destination (Join-Path $destinationRoot $name) -Force
    }
}

if ($InstallCodexSkills) {
    $codexSkillsRoot = Join-Path $env:USERPROFILE ".codex\skills"
    $createdSkillsRoot = New-Item -ItemType Directory -Path $codexSkillsRoot -Force
    foreach ($skillName in @("solidworks-orbit", "solidworks-forge", "solidworks-prism")) {
        $sourceSkill = Join-Path $destinationRoot "skills\$skillName"
        $targetSkill = Join-Path $codexSkillsRoot $skillName
        if ((Test-Path -LiteralPath $targetSkill) -and -not $Force) {
            Write-Warning "Codex skill already exists and was not replaced: $targetSkill"
            continue
        }
        $createdSkill = New-Item -ItemType Directory -Path $targetSkill -Force
        Get-ChildItem -LiteralPath $sourceSkill -Force |
            Copy-Item -Destination $targetSkill -Recurse -Force
        Write-Host "Installed Codex skill: $skillName"
    }
}

if ($CreateDesktopShortcut) {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktop "SOLIDWORKS AI Companions.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = (Get-Command "powershell.exe").Source
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$destinationRoot\scripts\Start.ps1`""
    $shortcut.WorkingDirectory = $destinationRoot
    $shortcut.Description = "Launch ORBIT, FORGE, and PRISM"
    $shortcut.Save()
    Write-Host "Created desktop shortcut: $shortcutPath"
}

& (Join-Path $destinationRoot "scripts\Start.ps1") -SmokeTest
if ($LASTEXITCODE -ne 0) {
    throw "Installed application smoke test failed."
}

Write-Host "Installed application: $destinationRoot"
