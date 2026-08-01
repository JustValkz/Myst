# Myst install bootstrap — downloads the full bundled installer from GitHub.
# Published as install.ps1 on GitHub (local dev uses install-dev.ps1).
#Requires -Version 5.1

param(
    [switch]$WatchMode,
    [switch]$LoadOnly,
    [switch]$SkipUnload,
    [string]$Choice
)

$ErrorActionPreference = 'Stop'

$bundleUrl = 'https://raw.githubusercontent.com/JustValkz/Myst/main/install-bundle.ps1'
try {
    $body = (Invoke-WebRequest -Uri $bundleUrl -UseBasicParsing -Headers @{
        'Cache-Control' = 'no-cache, no-store, must-revalidate'
        'Pragma'        = 'no-cache'
    }).Content
} catch {
    Write-Host "Failed to download installer bundle: $($_.Exception.Message)" -ForegroundColor Red
    throw
}

while ($body.Length -gt 0 -and ([int][char]$body[0] -eq 0xFEFF)) {
    $body = $body.Substring(1)
}

if ([string]::IsNullOrWhiteSpace($body)) {
    throw 'Installer bundle download was empty.'
}

$env:MYST_INSTALL_FROM_BUNDLE = '1'

$installer = [scriptblock]::Create($body)
& $installer @PSBoundParameters
