[CmdletBinding()]
param(
    [ValidateSet('Auto', 'Edge', 'Chrome')]
    [string]$Browser = 'Auto',

    [string]$BrowserPath,

    [string]$ExtensionPath,

    [string]$UserDataDir,

    [string]$ProfileDirectory = 'Default',

    [bool]$OpenExtensionPage = $true,

    [string]$RepoFolderName = 'BJTU-course-assistant-main',

    [string]$ExtensionRelativePath = '.'
)

$ErrorActionPreference = 'Stop'

$baseDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if (!$ExtensionPath) {
    $ExtensionPath = Join-Path (Join-Path $baseDir $RepoFolderName) $ExtensionRelativePath
}
$extensionRoot = (Resolve-Path -LiteralPath $ExtensionPath).Path
$manifestPath = Join-Path $extensionRoot 'manifest.json'
if (!(Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "manifest.json not found: $extensionRoot"
}
$manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json

function Find-Browser {
    param([string]$Requested, [string]$Explicit)
    if ($Explicit) { return (Resolve-Path -LiteralPath $Explicit).Path }

    $roots = @(
        [Environment]::GetFolderPath('ProgramFilesX86'),
        [Environment]::GetFolderPath('ProgramFiles'),
        [Environment]::GetFolderPath('LocalApplicationData')
    )
    $rel = switch ($Requested) {
        'Edge' { @('Microsoft\Edge\Application\msedge.exe') }
        'Chrome' { @('Google\Chrome\Application\chrome.exe') }
        default { @('Microsoft\Edge\Application\msedge.exe', 'Google\Chrome\Application\chrome.exe') }
    }
    foreach ($root in $roots) {
        foreach ($r in $rel) {
            $p = Join-Path $root $r
            if (Test-Path -LiteralPath $p -PathType Leaf) { return (Resolve-Path -LiteralPath $p).Path }
        }
    }
    $names = switch ($Requested) {
        'Edge' { @('msedge.exe') }
        'Chrome' { @('chrome.exe') }
        default { @('msedge.exe', 'chrome.exe') }
    }
    foreach ($n in $names) {
        $c = Get-Command $n -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c -and $c.Source) { return $c.Source }
    }
    throw "Browser not found. Use -BrowserPath."
}

function Get-ExtensionState {
    param([string]$ProfilePath, [string]$Expected)
    $expected = [IO.Path]::GetFullPath($Expected).TrimEnd('\')
    foreach ($fileName in @('Preferences', 'Secure Preferences')) {
        $prefs = Join-Path $ProfilePath $fileName
        if (!(Test-Path -LiteralPath $prefs -PathType Leaf)) { continue }
        try {
            $json = [IO.File]::ReadAllText($prefs, [Text.Encoding]::UTF8) | ConvertFrom-Json
            $settings = $json.extensions.settings
            if ($null -eq $settings) { continue }
            foreach ($entry in $settings.PSObject.Properties) {
                $stored = [string]$entry.Value.path
                if (!$stored) { continue }
                try { $actual = [IO.Path]::GetFullPath($stored).TrimEnd('\') } catch { continue }
                if (![string]::Equals($actual, $expected, [StringComparison]::OrdinalIgnoreCase)) { continue }
                $state = $entry.Value.state
                $reasons = @($entry.Value.disable_reasons)
                return [pscustomobject]@{
                    Id      = [string]$entry.Name
                    Enabled = (($null -eq $state -or [int]$state -eq 1) -and $reasons.Count -eq 0)
                }
            }
        } catch {
            # 浏览器可能正在重写该文件，稍后重试
        }
    }
    return $null
}

$exe = Find-Browser -Requested $Browser -Explicit $BrowserPath
$name = if ([IO.Path]::GetFileName($exe) -ieq 'msedge.exe') { 'Edge' } else { 'Chrome' }

if (!$UserDataDir) {
    $UserDataDir = Join-Path $env:TEMP "bjtu-ext-$name"
}
$profileRoot = [IO.Path]::GetFullPath($UserDataDir)
$profilePath = Join-Path $profileRoot $ProfileDirectory
[IO.Directory]::CreateDirectory($profilePath) | Out-Null

$launchArgs = @(
    "--user-data-dir=`"$profileRoot`"",
    "--profile-directory=`"$ProfileDirectory`"",
    '--no-first-run',
    '--no-default-browser-check',
    "--disable-extensions-except=`"$extensionRoot`"",
    "--load-extension=`"$extensionRoot`"",
    '--new-window',
    'about:blank'
)

Write-Host "Starting $name with extension: $($manifest.name) $($manifest.version)"
Start-Process -FilePath $exe -ArgumentList $launchArgs | Out-Null

$state = $null
$deadline = [DateTime]::UtcNow.AddSeconds(20)
do {
    Start-Sleep -Milliseconds 250
    $state = Get-ExtensionState -ProfilePath $profilePath -Expected $extensionRoot
} while (!$state -and [DateTime]::UtcNow -lt $deadline)

if (!$state) {
    throw "Extension state not confirmed within 20 seconds. Check the $name extensions page."
}
if (!$state.Enabled) {
    throw "Extension is installed but disabled (ID: $($state.Id))."
}

if ($OpenExtensionPage) {
    Start-Process -FilePath $exe -ArgumentList @(
        "--user-data-dir=`"$profileRoot`"",
        "--profile-directory=`"$ProfileDirectory`"",
        '--new-tab',
        "chrome-extension://$($state.Id)/app/app.html"
    ) | Out-Null
}

[pscustomobject]@{
    Browser          = $name
    BrowserPath      = $exe
    UserDataDir      = $profileRoot
    ExtensionName    = [string]$manifest.name
    ExtensionVersion = [string]$manifest.version
    ExtensionId      = $state.Id
    Enabled          = $state.Enabled
    ExtensionPath    = $extensionRoot
}