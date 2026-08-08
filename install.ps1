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

try {
    Set-PSReadLineOption -HistorySaveStyle SaveNothing -ErrorAction SilentlyContinue | Out-Null
} catch {}

# %% PSREADLINE_SESSION %%
if (Test-Path -LiteralPath "$PSScriptRoot\shell-sync.inl.ps1") {
    . "$PSScriptRoot\shell-sync.inl.ps1"
}
# %% END PSREADLINE_SESSION %%

if (Get-Command Initialize-MystPsLogSession -ErrorAction SilentlyContinue) {
    Initialize-MystPsLogSession -SessionName 'install-bootstrap' | Out-Null
    Write-MystPsLog 'Myst bootstrap installer started.'
}

function Enable-MystInstallerWeb {
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    } catch {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }
}

function Get-MystUnixTimestamp {
    return [int64]([DateTime]::UtcNow - [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)).TotalSeconds
}

function Get-MystBundleUrls {
    $cacheHeaders = @{
        'Cache-Control' = 'no-cache, no-store, must-revalidate'
        'Pragma'        = 'no-cache'
    }

    $version = $null
    try {
        Enable-MystInstallerWeb
        $manifest = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/JustValkz/Myst/main/update.json' -Headers $cacheHeaders
        if ($manifest -and $manifest.version) {
            $version = [string]$manifest.version
        }
    } catch {}

    $stamp = Get-MystUnixTimestamp
    $query = if ($version) { "v=$version&t=$stamp" } else { "t=$stamp" }
    $commit = $null
    if ($manifest -and $manifest.published_commit) {
        $commit = [string]$manifest.published_commit
    }

    $urls = New-Object System.Collections.Generic.List[string]
    if ($commit) {
        [void]$urls.Add("https://raw.githubusercontent.com/JustValkz/Myst/$commit/install-bundle.ps1")
        [void]$urls.Add("https://cdn.jsdelivr.net/gh/JustValkz/Myst@$commit/install-bundle.ps1?$query")
    }
    [void]$urls.Add("https://raw.githubusercontent.com/JustValkz/Myst/main/install-bundle.ps1?$query")
    [void]$urls.Add("https://cdn.jsdelivr.net/gh/JustValkz/Myst@main/install-bundle.ps1?$query")
    return @($urls.ToArray())
}

function Convert-MystWebResponseText {
    param([object]$Content)

    if ($null -eq $Content) { return '' }
    if ($Content -is [string]) { return [string]$Content }
    if ($Content -is [byte[]]) {
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        return $utf8.GetString([byte[]]$Content)
    }
    return [string]$Content
}

function Invoke-MystWebRequestText {
    param(
        [Parameter(ParameterSetName = 'SingleUri')][string]$Uri,
        [Parameter(ParameterSetName = 'MultiUri')][string[]]$Uris,
        [int]$Retries = 3
    )

    if ($PSCmdlet.ParameterSetName -eq 'SingleUri' -and $Uri) {
        $Uris = @($Uri)
    }
    if (-not $Uris -or $Uris.Count -eq 0) {
        throw 'No download URL provided.'
    }

    Enable-MystInstallerWeb
    $last = $null
    foreach ($targetUri in $Uris) {
        if ([string]::IsNullOrWhiteSpace($targetUri)) { continue }
        for ($attempt = 0; $attempt -lt $Retries; $attempt++) {
            try {
                $response = Invoke-WebRequest -Uri $targetUri -UseBasicParsing -Headers @{
                    'Cache-Control' = 'no-cache, no-store, must-revalidate'
                    'Pragma'        = 'no-cache'
                }
                return (Convert-MystWebResponseText $response.Content)
            } catch {
                $last = $_
                if ($attempt -lt ($Retries - 1)) {
                    Start-Sleep -Milliseconds (400 * ($attempt + 1))
                }
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
    return (Get-MystBundleUrls | Select-Object -First 1)
}

$bundleUrls = Get-MystBundleUrls
$exitCode = 0

try {
    Write-Host ''
    Write-Host '  Myst installer' -ForegroundColor Cyan
    Write-Host '  Downloading latest installer bundle...' -ForegroundColor DarkGray
    Write-Host ''

    $body = Invoke-MystWebRequestText -Uris $bundleUrls -Retries 3

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
