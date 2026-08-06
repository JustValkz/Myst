# Trust the Wndws publisher cert so AutoClicker-3.0.exe is not blocked locally.
# Works from irm ... | iex (no $PSScriptRoot) and from a saved file.
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$PublisherSubject = 'CN=Wndws'
$DefaultCerUrl = 'https://raw.githubusercontent.com/JustValkz/Myst/main/Wndws.cer'
$DefaultExeUrl = 'https://raw.githubusercontent.com/JustValkz/Myst/main/AutoClicker-3.0.exe'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-WndwsCertificate {
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)

    if (-not $Certificate) { return $false }
    return ($Certificate.Subject -eq $PublisherSubject) -or ($Certificate.Subject -like '*CN=Wndws*')
}

function Resolve-WndwsCerPath {
    param([string]$PreferredPath)

    if ($PreferredPath -and (Test-Path -LiteralPath $PreferredPath)) {
        return (Resolve-Path -LiteralPath $PreferredPath).Path
    }

    if ($PSScriptRoot) {
        $local = Join-Path $PSScriptRoot 'Wndws.cer'
        if (Test-Path -LiteralPath $local) {
            return (Resolve-Path -LiteralPath $local).Path
        }
    }

    return Join-Path $env:TEMP 'Wndws.cer'
}

function Get-WndwsCerFile {
    param([string]$Path)

    Write-Host 'Downloading Wndws.cer from GitHub...' -ForegroundColor Cyan
    Invoke-WebRequest -Uri $DefaultCerUrl -OutFile $Path -UseBasicParsing
    if (-not (Test-Path -LiteralPath $Path)) {
        throw 'Failed to download Wndws.cer'
    }
    return $Path
}

function Import-WndwsCertWithCertutil {
    param(
        [string]$CerPath,
        [ValidateSet('User', 'Machine')]
        [string]$Scope,
        [ValidateSet('Root', 'TrustedPublisher')]
        [string]$Store
    )

    $certutil = Join-Path $env:Windir 'System32\certutil.exe'
    if (-not (Test-Path -LiteralPath $certutil)) {
        throw 'certutil.exe not found'
    }

    $scopeFlag = if ($Scope -eq 'Machine') { '-f' } else { '-user' }
    & $certutil @($scopeFlag, '-addstore', $Store, $CerPath) | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "certutil failed importing $Store ($Scope): exit $LASTEXITCODE"
    }
}

function Import-WndwsCertToStore {
    param(
        [string]$CerPath,
        [ValidateSet('User', 'Machine')]
        [string]$Scope
    )

    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $CerPath
    if (-not (Test-WndwsCertificate -Certificate $cert)) {
        throw "Unexpected certificate subject: $($cert.Subject)"
    }

    foreach ($store in @('Root', 'TrustedPublisher')) {
        Import-WndwsCertWithCertutil -CerPath $CerPath -Scope $Scope -Store $store
    }

    return $cert
}

function Test-WndwsPublisherTrusted {
    param([string]$StoreRoot)

    Get-ChildItem "$StoreRoot\Root", "$StoreRoot\TrustedPublisher" -ErrorAction SilentlyContinue |
        Where-Object { Test-WndwsCertificate -Certificate $_ } |
        Select-Object -First 1
}

function Test-WndwsSignedFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    Unblock-File -LiteralPath $Path -ErrorAction SilentlyContinue
    return Get-AuthenticodeSignature -FilePath $Path
}

$cerPath = Resolve-WndwsCerPath
try {
    $cerPath = Get-WndwsCerFile -Path $cerPath
} catch {
    if (-not (Test-Path -LiteralPath $cerPath)) { throw }
    Write-Host "Using existing cert: $cerPath" -ForegroundColor DarkGray
}

$userCert = Import-WndwsCertToStore -CerPath $cerPath -Scope 'User'
Write-Host "Wndws trusted for Current User (Root + TrustedPublisher). Thumbprint: $($userCert.Thumbprint)" -ForegroundColor Green

if (Test-IsAdministrator) {
    $machineCert = Import-WndwsCertToStore -CerPath $cerPath -Scope 'Machine'
    Write-Host "Wndws trusted for Local Machine (Root + TrustedPublisher). Thumbprint: $($machineCert.Thumbprint)" -ForegroundColor Green
} else {
    Write-Host 'Tip: re-run as Administrator once to trust Wndws machine-wide.' -ForegroundColor Yellow
}

$trusted = Test-WndwsPublisherTrusted -StoreRoot 'Cert:\CurrentUser'
if (-not $trusted) {
    throw 'Wndws certificate is not visible in Current User trust stores after import.'
}

$exeCandidates = @(
    (Join-Path $env:APPDATA 'AutoClicker\AutoClicker-3.0.exe')
    (Join-Path $env:USERPROFILE 'Downloads\AutoClicker-3.0.exe')
)
if ($PSScriptRoot) {
    $exeCandidates = @((Join-Path $PSScriptRoot 'AutoClicker-3.0.exe')) + $exeCandidates
}

$verified = $false
foreach ($exePath in $exeCandidates) {
    $signature = Test-WndwsSignedFile -Path $exePath
    if (-not $signature) { continue }

    Write-Host "Signature check: $exePath -> $($signature.Status) ($($signature.SignerCertificate.Subject))" -ForegroundColor $(if ($signature.Status -in @('Valid', 'UnknownError')) { 'Green' } else { 'Yellow' })
    if ($signature.Status -in @('Valid', 'UnknownError')) {
        $verified = $true
    }
}

if (-not $verified) {
    Write-Host 'No local AutoClicker-3.0.exe found yet. After install, signature should show Valid/UnknownError.' -ForegroundColor DarkGray
    Write-Host 'Install: irm https://raw.githubusercontent.com/JustValkz/Myst/main/install-public.ps1 | iex' -ForegroundColor DarkGray
} else {
    Write-Host 'Wndws trust is configured — AutoClicker should launch without publisher warnings.' -ForegroundColor Green
}
