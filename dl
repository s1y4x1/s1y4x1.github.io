# If execution is blocked by policy, run this first:
# Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

$ErrorActionPreference = "Stop"

$Url     = "https://s1y4x1.github.io/BJTU-course-assistant-main.zip"
$ZipFile = Join-Path $env:TEMP "BJTU-course-assistant-main.zip"

# Use the script directory when run from a file, or the current directory when piped.
$ExtractDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

Write-Host "[1/4] Downloading the extension." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $Url -OutFile $ZipFile -UseBasicParsing
} catch {
    Write-Host "Download failed: $($_.Exception.Message)" -ForegroundColor Red
    return
}

Write-Host "[2/4] Extracting to: $ExtractDir" -ForegroundColor Cyan
try {
    $ExtensionDir = Join-Path $ExtractDir "BJTU-course-assistant"
    $StagingDir = Join-Path $env:TEMP ([Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $StagingDir | Out-Null
    Expand-Archive -Path $ZipFile -DestinationPath $StagingDir -Force
    New-Item -ItemType Directory -Path $ExtensionDir -Force | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $StagingDir 'BJTU-course-assistant-main') -Force |
        Copy-Item -Destination $ExtensionDir -Recurse -Force
    $ResolvedStagingDir = [IO.Path]::GetFullPath($StagingDir)
    $TempRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    if (-not $ResolvedStagingDir.StartsWith($TempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $ResolvedStagingDir) -notmatch '^[0-9a-f]{32}$') {
        throw "Unexpected temporary directory: $ResolvedStagingDir"
    }
    Remove-Item -LiteralPath $ResolvedStagingDir -Recurse -Force
} catch {
    Write-Host "Extraction failed: $($_.Exception.Message)" -ForegroundColor Red
    return
}

Write-Host "[3/4] Removing the temporary archive." -ForegroundColor Cyan
Remove-Item $ZipFile -Force -ErrorAction SilentlyContinue

$BridgeInstaller = Join-Path $ExtensionDir "modules\local-bridge\install.ps1"

Write-Host "[4/4] Installing the local Bridge." -ForegroundColor Cyan
try {
    if (-not (Test-Path -LiteralPath $BridgeInstaller -PathType Leaf)) {
        throw "Bridge installer not found: $BridgeInstaller"
    }
    & $BridgeInstaller -SkipStart
} catch {
    Write-Host "Bridge installation failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "The extension was extracted to: $ExtensionDir" -ForegroundColor Yellow
    return
}

Write-Host "Done. Extension directory: $ExtensionDir" -ForegroundColor Green
