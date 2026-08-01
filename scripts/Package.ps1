[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
$bundleRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$distRoot = Join-Path $bundleRoot "dist"
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $distRoot "SolidWorks-AI-Companions-portable.zip"
}
$archivePath = [System.IO.Path]::GetFullPath($OutputPath)
$archiveParent = [System.IO.Path]::GetDirectoryName($archivePath)
$createdArchiveParent = New-Item -ItemType Directory -Path $archiveParent -Force

$temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$stagingRoot = Join-Path $temporaryRoot ("sw-ai-companions-" + [guid]::NewGuid().ToString("N"))
$stagingRoot = [System.IO.Path]::GetFullPath($stagingRoot)
if (-not $stagingRoot.StartsWith($temporaryRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to create staging directory outside the system temporary directory."
}

$packageRoot = Join-Path $stagingRoot "SolidWorks-AI-Companions"
$createdPackageRoot = New-Item -ItemType Directory -Path $packageRoot -Force

try {
    foreach ($name in @("app", "skills", "scripts", "tests")) {
        $targetDirectory = Join-Path $packageRoot $name
        $createdTarget = New-Item -ItemType Directory -Path $targetDirectory -Force
        Get-ChildItem -LiteralPath (Join-Path $bundleRoot $name) -Force |
            Where-Object { $_.Name -ne "__pycache__" } |
            Copy-Item -Destination $targetDirectory -Recurse -Force
    }
    foreach ($name in @("README.md", "config.example.json")) {
        Copy-Item -LiteralPath (Join-Path $bundleRoot $name) -Destination (Join-Path $packageRoot $name) -Force
    }

    Compress-Archive -LiteralPath $packageRoot -DestinationPath $archivePath -CompressionLevel Optimal -Force
}
finally {
    $resolvedStaging = [System.IO.Path]::GetFullPath($stagingRoot)
    if (
        $resolvedStaging.StartsWith($temporaryRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedStaging).StartsWith("sw-ai-companions-")
    ) {
        Remove-Item -LiteralPath $resolvedStaging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$archive = Get-Item -LiteralPath $archivePath
$hash = (Get-FileHash -LiteralPath $archive.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
$checksumPath = $archive.FullName + ".sha256"
"$hash  $($archive.Name)" | Set-Content -LiteralPath $checksumPath -Encoding ascii
Write-Host "Portable archive created: $($archive.FullName)"
Write-Host "Size: $([math]::Round($archive.Length / 1KB, 1)) KB"
Write-Host "SHA-256: $hash"
Write-Host "Checksum file: $checksumPath"
