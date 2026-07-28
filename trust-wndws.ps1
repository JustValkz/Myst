# One-time: trust the Wndws publisher cert so AutoClicker-3.0.exe is not blocked locally.
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$CerPath = Join-Path $PSScriptRoot 'Wndws.cer'

if (-not (Test-Path -LiteralPath $CerPath)) {
    Write-Host 'Downloading Wndws.cer...' -ForegroundColor Cyan
    $url = 'https://raw.githubusercontent.com/JustValkz/Myst/main/Wndws.cer'
    Invoke-WebRequest -Uri $url -OutFile $CerPath -UseBasicParsing
}

$existing = Get-ChildItem Cert:\CurrentUser\Root |
    Where-Object { $_.Subject -eq 'CN=Wndws' } |
    Select-Object -First 1

if ($existing) {
    Write-Host 'Wndws certificate is already trusted on this PC.' -ForegroundColor Green
    exit 0
}

Import-Certificate -FilePath $CerPath -CertStoreLocation Cert:\CurrentUser\Root | Out-Null
Write-Host 'Wndws certificate installed to Trusted Root (Current User).' -ForegroundColor Green
Write-Host 'You can now run AutoClicker-3.0.exe.' -ForegroundColor Green
