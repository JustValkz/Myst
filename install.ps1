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

function Enable-MystInstallerWeb {
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    } catch {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }
}

function Invoke-MystWebRequestText {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [int]$Retries = 3
    )

    Enable-MystInstallerWeb
    $last = $null
    for ($attempt = 0; $attempt -lt $Retries; $attempt++) {
        try {
            return (Invoke-WebRequest -Uri $Uri -UseBasicParsing -Headers @{
                'Cache-Control' = 'no-cache, no-store, must-revalidate'
                'Pragma'        = 'no-cache'
            }).Content
        } catch {
            $last = $_
            if ($attempt -lt ($Retries - 1)) {
                Start-Sleep -Milliseconds (400 * ($attempt + 1))
            }
        }
    }

    throw $last
}

function Wait-MystInstallPause {
    param(
        [switch]$Failed,
        [int]$ExitCode = 0
    )

    if (-not $Failed -and $ExitCode -eq 0) { return }

    Write-Host ''
    if ($Failed -or $ExitCode -ne 0) {
        Write-Host '  Install did not finish successfully.' -ForegroundColor Red
    }
    Write-Host '  Press Enter to close this window...' -ForegroundColor Yellow
    try {
        if ([Environment]::UserInteractive) {
            [void][Console]::ReadLine()
        } else {
            Start-Sleep -Seconds 10
        }
    } catch {
        Start-Sleep -Seconds 10
    }
}

function Get-MystBundleUrl {
    $base = 'https://raw.githubusercontent.com/JustValkz/Myst/main/install-bundle.ps1'
    $cacheHeaders = @{
        'Cache-Control' = 'no-cache, no-store, must-revalidate'
        'Pragma'        = 'no-cache'
    }

    try {
        $manifest = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/JustValkz/Myst/main/update.json' -Headers $cacheHeaders
        if ($manifest -and $manifest.version) {
            return "$base`?v=$($manifest.version)"
        }
    } catch {}

    return "$base`?t=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
}

$bundleUrl = Get-MystBundleUrl
$exitCode = 0

try {
    Write-Host ''
    Write-Host '  Myst installer' -ForegroundColor Cyan
    Write-Host '  Downloading latest installer bundle...' -ForegroundColor DarkGray
    Write-Host ''

    $body = Invoke-MystWebRequestText -Uri $bundleUrl -Retries 4

    while ($body.Length -gt 0 -and ([int][char]$body[0] -eq 0xFEFF)) {
        $body = $body.Substring(1)
    }

    if ([string]::IsNullOrWhiteSpace($body)) {
        throw 'Installer bundle download was empty.'
    }

    $env:MYST_INSTALL_FROM_BUNDLE = '1'

    $installer = [scriptblock]::Create($body)
    & $installer @PSBoundParameters
    if ($LASTEXITCODE) { $exitCode = [int]$LASTEXITCODE }
} catch {
    Write-Host ''
    Write-Host "  Installer failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.InvocationInfo -and $_.InvocationInfo.ScriptLineNumber) {
        Write-Host "  (line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim()))" -ForegroundColor DarkGray
    }
    Write-Host '  Check your internet connection and try again in Administrator PowerShell.' -ForegroundColor DarkGray
    Write-Host '  If this persists, raw GitHub may be serving a cached bundle — wait 1 minute and retry.' -ForegroundColor DarkGray
    $exitCode = 1
    Wait-MystInstallPause -Failed -ExitCode $exitCode
    exit $exitCode
}

if ($exitCode -ne 0) {
    Wait-MystInstallPause -Failed -ExitCode $exitCode
}

exit $exitCode
