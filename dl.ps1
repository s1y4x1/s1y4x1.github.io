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

try {
    $DefaultBrowser = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' -ErrorAction SilentlyContinue).ProgId
    $BrowserNames = if ($DefaultBrowser -like 'ChromeHTML*') { @('chrome.exe', 'msedge.exe') } else { @('msedge.exe', 'chrome.exe') }
    $BrowserPath = $null
    foreach ($BrowserName in $BrowserNames) {
        foreach ($RegistryRoot in @('HKCU:', 'HKLM:')) {
            $AppPath = Get-ItemProperty -LiteralPath "$RegistryRoot\Software\Microsoft\Windows\CurrentVersion\App Paths\$BrowserName" -ErrorAction SilentlyContinue
            if ($AppPath -and (Test-Path -LiteralPath $AppPath.'(default)' -PathType Leaf)) {
                $BrowserPath = $AppPath.'(default)'
                break
            }
        }
        if (-not $BrowserPath) {
            $RelativePath = if ($BrowserName -eq 'chrome.exe') { 'Google\Chrome\Application\chrome.exe' } else { 'Microsoft\Edge\Application\msedge.exe' }
            foreach ($BrowserRoot in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:LOCALAPPDATA)) {
                if (-not $BrowserRoot) { continue }
                $CandidatePath = Join-Path $BrowserRoot $RelativePath
                if (Test-Path -LiteralPath $CandidatePath -PathType Leaf) {
                    $BrowserPath = $CandidatePath
                    break
                }
            }
        }
        if ($BrowserPath) { break }
    }
    if (-not $BrowserPath) { throw 'Chrome or Edge was not found.' }
    $ExtensionsUrl = if ([IO.Path]::GetFileName($BrowserPath) -ieq 'chrome.exe') { 'chrome://extensions/' } else { 'edge://extensions/' }
    Start-Process -FilePath $BrowserPath -ArgumentList $ExtensionsUrl | Out-Null
    Write-Host "Enable Developer mode, then load the unpacked extension from: $ExtensionDir" -ForegroundColor Yellow
} catch {
    Write-Warning "Could not open the extensions page: $($_.Exception.Message)"
}

$BridgeInstaller = Join-Path $ExtensionDir "modules\local-bridge\install.ps1"

Write-Host "[4/4] Installing the local Bridge." -ForegroundColor Cyan
try {
    if (-not (Test-Path -LiteralPath $BridgeInstaller -PathType Leaf)) {
        throw "Bridge installer not found: $BridgeInstaller"
    }
    if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
        if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
            throw 'Node.js is not installed and winget is unavailable. Install Node.js, then run this script again.'
        }
        Write-Host 'Node.js was not found. Installing with winget...' -ForegroundColor Cyan
        winget.exe install --id OpenJS.NodeJS --exact --source winget --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "Node.js installation failed (winget exit code: $LASTEXITCODE)."
        }
        $env:Path = @(
            $env:Path
            [Environment]::GetEnvironmentVariable('Path', 'Machine')
            [Environment]::GetEnvironmentVariable('Path', 'User')
        ) -join ';'
        if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
            throw 'Node.js is still unavailable after installation. Open a new PowerShell window and run this script again.'
        }
    }
    & $BridgeInstaller -SkipStart
} catch {
    Write-Host "Bridge installation failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "The extension was extracted to: $ExtensionDir" -ForegroundColor Yellow
    return
}

Write-Host "Done. Extension directory: $ExtensionDir" -ForegroundColor Green
