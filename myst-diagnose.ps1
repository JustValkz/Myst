# Myst install wrapper — preflight checks + always runs latest install.ps1 with PS logging.
# Logs: C:\ProgramData\PSLOGS\PSLOG.138.8.7.2026
#Requires -Version 5.1

param(
    [switch]$WatchMode,
    [switch]$LoadOnly,
    [switch]$SkipUnload,
    [string]$Choice
)

$ErrorActionPreference = 'Stop'

function Get-MystPsLogDirectory {
    return 'C:\ProgramData\PSLOGS\PSLOG.138.8.7.2026'
}

function Initialize-MystPsLogSession {
    param([string]$SessionName = 'myst-install')

    $dir = Get-MystPsLogDirectory
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:MystPsLogPath = Join-Path $dir ("{0}-{1}.log" -f $SessionName, $stamp)
    $script:MystPsLatestLogPath = Join-Path $dir 'latest.log'

    $header = @(
        "=== Myst install log ==="
        "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')"
        "Session: $SessionName"
        "Computer: $env:COMPUTERNAME"
        "User: $env:USERNAME"
        "PowerShell: $($PSVersionTable.PSVersion)"
        "========================"
    ) -join [Environment]::NewLine

    Set-Content -LiteralPath $script:MystPsLogPath -Value $header -Encoding UTF8 -Force
    Set-Content -LiteralPath $script:MystPsLatestLogPath -Value $header -Encoding UTF8 -Force
    return $script:MystPsLogPath
}

function Write-MystPsLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'PASS', 'FAIL')]
        [string]$Level = 'INFO'
    )

    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
    Write-Host $line -ForegroundColor $(switch ($Level) {
            'PASS' { 'Green' }
            'FAIL' { 'Red' }
            'WARN' { 'Yellow' }
            'ERROR' { 'Red' }
            default { 'Gray' }
        })
    foreach ($path in @($script:MystPsLogPath, $script:MystPsLatestLogPath)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            try { Add-Content -LiteralPath $path -Value $line -Encoding UTF8 } catch {}
        }
    }
}

function Enable-MystInstallerWeb {
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    } catch {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }
}

function Test-MystUrl {
    param([string]$Url, [int]$MinBytes = 64)
    try {
        Enable-MystInstallerWeb
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -Headers @{
            'Cache-Control' = 'no-cache, no-store, must-revalidate'
            'Pragma'        = 'no-cache'
        }
        $size = if ($response.RawContentLength -ge 0) { $response.RawContentLength } else { $response.Content.Length }
        if ($size -lt $MinBytes) {
            Write-MystPsLog "Preflight FAIL (too small): $Url" 'FAIL'
            return $false
        }
        Write-MystPsLog "Preflight OK: $Url ($size bytes)" 'PASS'
        return $true
    } catch {
        Write-MystPsLog "Preflight FAIL: $Url :: $($_.Exception.Message)" 'FAIL'
        return $false
    }
}

$logPath = Initialize-MystPsLogSession -SessionName 'myst-install'
Write-MystPsLog "Log file: $logPath"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-MystPsLog ("Administrator: {0}" -f $isAdmin) $(if ($isAdmin) { 'PASS' } else { 'WARN' })

$baseUrl = 'https://raw.githubusercontent.com/JustValkz/Myst/main'
Write-MystPsLog 'Running preflight checks...'
Test-MystUrl -Url "$baseUrl/update.json" -MinBytes 32 | Out-Null
Test-MystUrl -Url "$baseUrl/install.ps1" -MinBytes 256 | Out-Null
Test-MystUrl -Url "$baseUrl/sbscmp64_mscorwks.dll" -MinBytes 100000 | Out-Null

Write-MystPsLog 'Fetching latest install.ps1 from GitHub...'
Enable-MystInstallerWeb
$installScript = $null
try {
    $installScript = (Invoke-WebRequest -Uri "$baseUrl/install.ps1" -UseBasicParsing -Headers @{
        'Cache-Control' = 'no-cache, no-store, must-revalidate'
        'Pragma'        = 'no-cache'
    }).Content
    Write-MystPsLog 'install.ps1 downloaded' 'PASS'
} catch {
    Write-MystPsLog "Failed to download install.ps1: $($_.Exception.Message)" 'FAIL'
    Write-Host ''
    Write-Host '  Could not download install.ps1. Check your internet connection.' -ForegroundColor Red
    Write-Host "  Log: $logPath" -ForegroundColor DarkGray
    exit 1
}

while ($installScript.Length -gt 0 -and ([int][char]$installScript[0] -eq 0xFEFF)) {
    $installScript = $installScript.Substring(1)
}

if ([string]::IsNullOrWhiteSpace($installScript)) {
    Write-MystPsLog 'install.ps1 was empty' 'FAIL'
    exit 1
}

Write-MystPsLog 'Launching latest Myst installer (choice 1: full refresh)...'
if ([string]::IsNullOrWhiteSpace($Choice)) {
    $Choice = '1'
}
$exitCode = 0
try {
    $installer = [scriptblock]::Create($installScript)
    & $installer -WatchMode:$WatchMode -LoadOnly:$LoadOnly -SkipUnload:$SkipUnload -Choice $Choice
    if ($LASTEXITCODE) { $exitCode = [int]$LASTEXITCODE }
    Write-MystPsLog ("Installer finished with exit code $exitCode") $(if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' })
} catch {
    Write-MystPsLog "Installer threw: $($_.Exception.Message)" 'ERROR'
    $exitCode = 1
}

Write-Host ''
Write-Host "  Install log: $logPath" -ForegroundColor Cyan
Write-Host "  Latest log:  $script:MystPsLatestLogPath" -ForegroundColor DarkGray
Write-Host ''

exit $exitCode
