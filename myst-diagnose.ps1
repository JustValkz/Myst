# Myst / AutoClicker client diagnostics — logs to C:\ProgramData\PSLOGS\PSLOG.138.8.7.2026
#Requires -Version 5.1

param(
    [switch]$Public,
    [switch]$Private
)

$ErrorActionPreference = 'Continue'

function Get-MystPsLogDirectory {
    return 'C:\ProgramData\PSLOGS\PSLOG.138.8.7.2026'
}

function Initialize-MystPsLogSession {
    param([string]$SessionName = 'myst-diagnose')

    $dir = Get-MystPsLogDirectory
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:MystPsLogPath = Join-Path $dir ("{0}-{1}.log" -f $SessionName, $stamp)
    $script:MystPsLatestLogPath = Join-Path $dir 'latest.log'

    $header = @(
        "=== Myst diagnostic log ==="
        "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')"
        "Session: $SessionName"
        "Computer: $env:COMPUTERNAME"
        "User: $env:USERNAME"
        "PowerShell: $($PSVersionTable.PSVersion)"
        "==========================="
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

function Test-UrlReachable {
    param(
        [string]$Url,
        [int]$MinBytes = 64
    )

    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    } catch {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -Headers @{
            'Cache-Control' = 'no-cache, no-store, must-revalidate'
            'Pragma'        = 'no-cache'
        }
        $size = if ($response.RawContentLength -ge 0) { $response.RawContentLength } else { $response.Content.Length }
        if ($size -lt $MinBytes) {
            Write-MystPsLog "URL too small ($size bytes): $Url" 'FAIL'
            return $false
        }
        Write-MystPsLog "URL OK ($size bytes): $Url" 'PASS'
        return $true
    } catch {
        Write-MystPsLog "URL failed: $Url :: $($_.Exception.Message)" 'FAIL'
        return $false
    }
}

function Get-FileSummary {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-MystPsLog "Missing file: $Path" 'FAIL'
        return $null
    }

    $item = Get-Item -LiteralPath $Path -Force
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    Write-MystPsLog "File: $Path | size=$($item.Length) | modified=$($item.LastWriteTime) | sha256=$hash" 'PASS'
    return $item
}

function Test-ProcessHasModule {
    param(
        [int]$ProcessId,
        [string]$ModulePath
    )

    try {
        $proc = Get-Process -Id $ProcessId -ErrorAction Stop
        foreach ($mod in $proc.Modules) {
            if ($mod.FileName -ieq $ModulePath) { return $true }
        }
    } catch {}
    return $false
}

$mode = if ($Public) { 'public' } elseif ($Private) { 'private' } else { 'auto' }
$logPath = Initialize-MystPsLogSession -SessionName "myst-diagnose-$mode"
Write-MystPsLog "Diagnostic mode: $mode"
Write-MystPsLog "Log file: $logPath"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-MystPsLog ("Running as Administrator: {0}" -f $isAdmin) $(if ($isAdmin) { 'PASS' } else { 'WARN' })

Write-MystPsLog "OS: $([Environment]::OSVersion.VersionString)"
Write-MystPsLog "Build: $(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' | Select-Object -ExpandProperty DisplayVersion -ErrorAction SilentlyContinue)"

$baseUrl = 'https://raw.githubusercontent.com/JustValkz/Myst/main'
$manifest = $null
try {
    $manifest = Invoke-RestMethod -Uri "$baseUrl/update.json" -Headers @{
        'Cache-Control' = 'no-cache, no-store, must-revalidate'
        'Pragma'        = 'no-cache'
    }
    Write-MystPsLog "Remote Myst version: $($manifest.version) (commit $($manifest.published_commit))" 'PASS'
} catch {
    Write-MystPsLog "Could not read update.json: $($_.Exception.Message)" 'FAIL'
}

Write-MystPsLog '--- Network / GitHub ---'
Test-UrlReachable -Url "$baseUrl/update.json" -MinBytes 32 | Out-Null
Test-UrlReachable -Url "$baseUrl/sbscmp64_mscorwks.dll" -MinBytes 100000 | Out-Null
Test-UrlReachable -Url "$baseUrl/AutoClicker-3.0.exe" -MinBytes 65536 | Out-Null
Test-UrlReachable -Url "$baseUrl/offsets.hpp" -MinBytes 256 | Out-Null
Test-UrlReachable -Url "$baseUrl/offsets.json" -MinBytes 256 | Out-Null

$dllPath = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\sbscmp64_mscorwks.dll'
$localManifestPath = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\.update.json'
$localHpp = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\.offsets.hpp'
$localJson = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\.offsets.json'
$exePath = Join-Path $env:APPDATA 'AutoClicker\AutoClicker-3.0.exe'
$publicHpp = Join-Path $env:TEMP '.myst-offsets.hpp'
$publicJson = Join-Path $env:TEMP '.myst-offsets.json'

Write-MystPsLog '--- Private DLL install ---'
Get-FileSummary -Path $dllPath | Out-Null
Get-FileSummary -Path $localManifestPath | Out-Null
Get-FileSummary -Path $localHpp | Out-Null
Get-FileSummary -Path $localJson | Out-Null

if ($localManifestPath -and (Test-Path -LiteralPath $localManifestPath)) {
    try {
        $localManifest = Get-Content -LiteralPath $localManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-MystPsLog "Installed DLL version (local manifest): $($localManifest.version)" 'INFO'
        if ($manifest -and $localManifest.version -and [string]$localManifest.version -ne [string]$manifest.version) {
            Write-MystPsLog "Version mismatch: local $($localManifest.version) vs remote $($manifest.version) — reinstall option 1" 'WARN'
        }
    } catch {
        Write-MystPsLog "Could not parse local .update.json: $($_.Exception.Message)" 'WARN'
    }
}

Write-MystPsLog '--- Public EXE install ---'
Get-FileSummary -Path $exePath | Out-Null
Get-FileSummary -Path $publicHpp | Out-Null
Get-FileSummary -Path $publicJson | Out-Null

Write-MystPsLog '--- Processes ---'
$roblox = @(Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue)
if ($roblox.Count -gt 0) {
    Write-MystPsLog "Roblox running: $($roblox.Count) process(es)" 'PASS'
} else {
    Write-MystPsLog 'Roblox not running — start Roblox before testing menu/offsets in-game' 'WARN'
}

$runtimeBrokers = @(Get-Process -Name 'RuntimeBroker' -ErrorAction SilentlyContinue)
Write-MystPsLog "RuntimeBroker processes: $($runtimeBrokers.Count)"
$dllLoaded = $false
foreach ($proc in $runtimeBrokers) {
    if (Test-ProcessHasModule -ProcessId $proc.Id -ModulePath $dllPath) {
        Write-MystPsLog "Myst DLL loaded in RuntimeBroker PID $($proc.Id)" 'PASS'
        $dllLoaded = $true
    }
}
if (-not $dllLoaded -and (Test-Path -LiteralPath $dllPath)) {
    Write-MystPsLog 'Myst DLL present on disk but not loaded — run installer option 1' 'WARN'
}

$autoClicker = @(Get-Process -Name 'AutoClicker-3.0' -ErrorAction SilentlyContinue)
if ($autoClicker.Count -gt 0) {
    Write-MystPsLog "AutoClicker EXE running: PID $($autoClicker[0].Id)" 'PASS'
} else {
    Write-MystPsLog 'AutoClicker EXE not running' 'INFO'
}

Write-MystPsLog '--- Overlay window ---'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class MystDiagOverlayProbe {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
}
'@ -ErrorAction SilentlyContinue | Out-Null

$overlay = [MystDiagOverlayProbe]::FindWindow('Windows.UI.Core.CoreWindow', $null)
if ($overlay -ne [IntPtr]::Zero) {
    Write-MystPsLog "Overlay window detected (HWND=$overlay)" 'PASS'
} else {
    Write-MystPsLog 'Overlay window not found — Myst may not be loaded, or Roblox is not open' 'WARN'
}

Write-MystPsLog '--- Legacy / blocked paths ---'
foreach ($legacy in @(
        (Join-Path $env:ProgramData 'Myst')
        (Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\AutoClickerHost.dll')
    )) {
    if (Test-Path -LiteralPath $legacy) {
        Write-MystPsLog "Legacy path still present (remove): $legacy" 'WARN'
    }
}

try {
    $sac = Get-MpComputerStatus -ErrorAction Stop
    Write-MystPsLog "Smart App Control: $($sac.SmartAppControlState)" $(if ($sac.SmartAppControlState -eq 'On') { 'WARN' } else { 'INFO' })
} catch {
    Write-MystPsLog 'Smart App Control status unavailable' 'INFO'
}

Write-MystPsLog '--- Menu key (Insert) ---'
if (-not ('Win32.User32' -as [type])) {
    Add-Type @'
namespace Win32 {
    public static class User32 {
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern short GetAsyncKeyState(int vKey);
    }
}
'@
}
Write-MystPsLog 'Press INSERT within the next 3 seconds to verify the key is detected...' 'INFO'
Start-Sleep -Milliseconds 500
$insertSeen = $false
$deadline = (Get-Date).AddSeconds(3)
while ((Get-Date) -lt $deadline) {
    if (([Win32.User32]::GetAsyncKeyState(0x2D) -band 0x8000) -ne 0) {
        $insertSeen = $true
        break
    }
    Start-Sleep -Milliseconds 50
}
Write-MystPsLog ("Insert key detected in test window: {0}" -f $insertSeen) $(if ($insertSeen) { 'PASS' } else { 'INFO' })
Write-MystPsLog 'In-game: default menu key is Insert (private DLL). Public EXE also uses Insert unless rebound in Settings.' 'INFO'

Write-MystPsLog '--- Summary ---'
if (-not $isAdmin -and -not (Test-Path -LiteralPath $exePath)) {
    Write-MystPsLog 'Recommendation: run installer in Administrator PowerShell for private DLL install' 'WARN'
}
if ($manifest) {
    Write-MystPsLog "Latest install (private): irm $baseUrl/install.ps1 | iex" 'INFO'
    Write-MystPsLog "Latest install (public):  irm $baseUrl/install-public.ps1 | iex" 'INFO'
}
Write-MystPsLog "Full log saved to: $logPath" 'PASS'
Write-MystPsLog "Latest log copy: $script:MystPsLatestLogPath" 'PASS'

Write-Host ''
Write-Host "  Done. Send the log file from:" -ForegroundColor Cyan
Write-Host "  $logPath" -ForegroundColor White
Write-Host ''
