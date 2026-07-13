# Myst Installer v1.2.4 — Framework64 hidden install + optional GitHub updates.
#Requires -Version 5.1

param(
    [switch]$WatchMode,
    [switch]$LoadOnly,
    [string]$Choice
)

$ErrorActionPreference = 'Continue'

$framework64 = "$env:SystemRoot\Microsoft.NET\Framework64"
$p = "$framework64\sbscmp64_mscorwks.dll"
$defaultScriptUrl = 'https://raw.githubusercontent.com/JustValkz/Myst/main/install.ps1'
$defaultUpdateManifestUrl = 'https://raw.githubusercontent.com/JustValkz/Myst/main/update.json'
$script:UpdateManifestPath = Join-Path $env:ProgramData 'Myst\update.json'
$n = 'RuntimeBroker'
$x = "$env:SystemRoot\System32\$n.exe"
$script:DllExecuterInstallPath = Join-Path $env:ProgramData 'Myst\install.ps1'

function Resolve-InstallScriptPath {
    if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
        return $PSCommandPath
    }

    $installDir = Split-Path $script:DllExecuterInstallPath -Parent
    if (-not (Test-Path -LiteralPath $installDir)) {
        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    }

    # irm | iex has no script file — always refresh from GitHub before elevation.
    try {
        Invoke-WebRequest -Uri $defaultScriptUrl -OutFile $script:DllExecuterInstallPath -UseBasicParsing
        if (Test-Path -LiteralPath $script:DllExecuterInstallPath) {
            return $script:DllExecuterInstallPath
        }
    } catch {
        Write-Host "  Failed to download installer: $($_.Exception.Message)" -ForegroundColor Red
    }

    if (Test-Path -LiteralPath $script:DllExecuterInstallPath) {
        return $script:DllExecuterInstallPath
    }

    return $null
}

function Test-DllPathMatch {
    param(
        [string]$Left,
        [string]$Right
    )

    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return $false
    }

    try {
        $leftFull = [System.IO.Path]::GetFullPath($Left)
        $rightFull = [System.IO.Path]::GetFullPath($Right)
        return [string]::Equals($leftFull, $rightFull, [StringComparison]::OrdinalIgnoreCase)
    } catch {
        return [string]::Equals($Left, $Right, [StringComparison]::OrdinalIgnoreCase)
    }
}

function Write-Step {
    param([string]$Message, [string]$Color = 'Cyan')
    Write-Host "  [$((Get-Date).ToString('HH:mm:ss'))] $Message" -ForegroundColor $Color
}

function Resolve-LocalBuildDll {
    param([string[]]$Names)

    if ($Names -contains 'Myst.dll') {
        $buildCandidates = @()
        if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
            $buildCandidates += @(
                (Join-Path $PSScriptRoot '..\build\Myst.dll')
                (Join-Path $PSScriptRoot 'build\Myst.dll')
                (Join-Path $PSScriptRoot '..\T4\build\Myst.dll')
                (Join-Path $PSScriptRoot 'T4\build\Myst.dll')
            )
        }

        foreach ($candidate in $buildCandidates) {
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            if (Test-Path -LiteralPath $candidate) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
        }
    }

    $roots = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        [void]$roots.Add($PSScriptRoot)
        $parent = Split-Path -Path $PSScriptRoot -Parent -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            [void]$roots.Add($parent)
        }
    }

    # Optional: check Downloads for a manually dropped build
    $downloads = Join-Path $env:USERPROFILE 'Downloads'
    if (-not [string]::IsNullOrWhiteSpace($downloads) -and (Test-Path -LiteralPath $downloads)) {
        [void]$roots.Add($downloads)
    }

    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        foreach ($name in $Names) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $candidate = Join-Path $root $name
            if (Test-Path -LiteralPath $candidate) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
        }
    }

    return $null
}

function Test-MystDllSource {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $text = [System.Text.Encoding]::ASCII.GetString($bytes)
        if ($text.Contains('nxgjwtrqhrgpszpuzmkp')) {
            return $true
        }
        if ($text.Contains('eyxbrypeyeqfntyappey')) {
            Write-Step 'Detected old Immune Supabase URL in DLL. Rebuild Myst.dll from this repo.' -Color Red
            return $false
        }
        Write-Step 'DLL does not contain the Myst Supabase project id. Rebuild Myst.dll from this repo.' -Color Red
        return $false
    }
    catch {
        Write-Step "Unable to inspect DLL source: $($_.Exception.Message)" -Color Yellow
        return $true
    }
}

function Download-RemoteFile {
    param(
        [string]$Url,
        [string]$Destination
    )

    if ([string]::IsNullOrWhiteSpace($Url) -or [string]::IsNullOrWhiteSpace($Destination)) {
        return $false
    }

    $targetDir = Split-Path $Destination -Parent
    if ($targetDir -and -not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    }

    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
        return (Test-Path -LiteralPath $Destination)
    } catch {
        Write-Step "Download failed: $($_.Exception.Message)" -Color Red
        return $false
    }
}

function Get-MystUpdateManifest {
    $sources = @(
        $defaultUpdateManifestUrl,
        $script:UpdateManifestPath
    )

    foreach ($source in $sources) {
        try {
            if ($source -like 'http*') {
                return Invoke-RestMethod -Uri $source -UseBasicParsing
            }

            if (Test-Path -LiteralPath $source) {
                return Get-Content -LiteralPath $source -Raw | ConvertFrom-Json
            }
        } catch {}
    }

    return $null
}

function Invoke-MystUpdate {
    Write-Host ''
    Write-Host '  === Myst Update ===' -ForegroundColor Cyan

    $manifest = Get-MystUpdateManifest
    if (-not $manifest) {
        Write-Step 'No update manifest found. Ask the owner to publish one with /update.' -Color Yellow
        return $false
    }

    if (-not (Test-Path -LiteralPath $framework64)) {
        New-Item -ItemType Directory -Force -Path $framework64 | Out-Null
    }

    $updated = $false
    if ($manifest.dll_url) {
        Write-Step "Downloading Myst DLL ($($manifest.version))..." -Color Gray
        if (Download-RemoteFile -Url $manifest.dll_url -Destination $p) {
            Prepare-DllFile -Path $p | Out-Null
            $updated = $true
        }
    }

    if (-not $updated) {
        Write-Step 'Update manifest had no downloadable files.' -Color Red
        return $false
    }

    $manifestDir = Split-Path $script:UpdateManifestPath -Parent
    if (-not (Test-Path $manifestDir)) {
        New-Item -ItemType Directory -Force -Path $manifestDir | Out-Null
    }
    ($manifest | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $script:UpdateManifestPath -Encoding UTF8

    Write-Step "Update $($manifest.version) installed to Framework64." -Color Green
    Write-Step 'Choose option 1 to load the new build.' -Color Gray
    return $true
}

function Copy-LocalBuildDll {
    param(
        [string]$Destination,
        [string[]]$Names
    )

    if ([string]::IsNullOrWhiteSpace($Destination)) { return $false }

    $source = Resolve-LocalBuildDll -Names $Names
    if (-not $source) { return $false }

    if ($Names -contains 'Myst.dll' -or $Names -contains 'sbscmp64_mscorwks.dll') {
        if (-not (Test-MystDllSource -Path $source)) {
            return $false
        }
    }

    $targetDir = Split-Path $Destination -Parent
    if ($targetDir -and -not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    }

    Copy-Item -LiteralPath $source -Destination $Destination -Force | Out-Null
    Write-Step "Copied local build '$([System.IO.Path]::GetFileName($source))' -> $Destination" -Color Green
    return (Prepare-DllFile -Path $Destination)
}

function Sync-DllExecuterInstall {
    $installDir = Split-Path $script:DllExecuterInstallPath -Parent
    if (-not (Test-Path -LiteralPath $installDir)) {
        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    }

    foreach ($candidate in @(
            $PSCommandPath
            $MyInvocation.MyCommand.Path
            $(if ($PSScriptRoot) { Join-Path $PSScriptRoot 'myst.ps1' })
            $(if ($PSScriptRoot) { Join-Path $PSScriptRoot 'install.ps1' })
        )) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if (Test-Path -LiteralPath $candidate) {
            Copy-Item -LiteralPath $candidate -Destination $script:DllExecuterInstallPath -Force
            return $script:DllExecuterInstallPath
        }
    }

    if (Test-Path -LiteralPath $script:DllExecuterInstallPath) {
        return $script:DllExecuterInstallPath
    }

    return $null
}

function Test-FileLocked {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $stream = [System.IO.File]::Open($Path, 'Open', 'ReadWrite', 'None')
        $stream.Close()
        return $false
    } catch { return $true }
}

function Wait-ForProcess {
    param($Name, $TimeoutSeconds = 10, $Present = $true)
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $found = Get-Process -Name $Name -ErrorAction SilentlyContinue
        if ($Present -and $found) { return $true }
        if (-not $Present -and -not $found) { return $true }
        Start-Sleep -Seconds 1
        $elapsed++
    }
    return $false
}

function Test-ProcessHasDll {
    param(
        [int]$ProcessId,
        [string]$DllPath
    )

    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $proc) { return $false }

    try {
        return [bool](@($proc.Modules) | Where-Object { Test-DllPathMatch $_.FileName $DllPath })
    } catch {
        return [bool]([Injector]::GetModuleBase($ProcessId, $DllPath) -ne [IntPtr]::Zero)
    }
}

function Ensure-Sbscmp30OnDisk {
    param([switch]$ForceRefresh)

    if (Test-Path -LiteralPath $p) {
        $prepared = Prepare-DllFile -Path $p
        if ($prepared) {
            $source = Resolve-LocalBuildDll -Names @('Myst.dll', 'sbscmp64_mscorwks.dll')
            if ($source) {
                $sourceInfo = Get-Item -LiteralPath $source
                $destInfo = Get-Item -LiteralPath $p
                if ($ForceRefresh -or $sourceInfo.LastWriteTimeUtc -gt $destInfo.LastWriteTimeUtc -or $sourceInfo.Length -ne $destInfo.Length) {
                    Write-Step "Updating sbscmp64 from local Myst.dll build ($($sourceInfo.FullName))..." -Color Yellow
                    if (Test-FileLocked -Path $p) {
                        Clear-AllRuntimeBrokerDll -DllPath $p | Out-Null
                    }
                    $copied = Copy-LocalBuildDll -Destination $p -Names @('Myst.dll', 'sbscmp64_mscorwks.dll')
                    if ($copied) {
                        return $true
                    }
                    Write-Step 'Local Myst.dll copy failed validation. Keeping installed Framework64 DLL.' -Color Yellow
                }
            }

            return $true
        }

        Write-Step 'Framework64 DLL exists but could not be prepared.' -Color Red
        return $false
    }

    if (Test-FileLocked -Path $p) {
        Clear-AllRuntimeBrokerDll -DllPath $p | Out-Null
    }

    $copied = Copy-LocalBuildDll -Destination $p -Names @('Myst.dll', 'sbscmp64_mscorwks.dll')
    if ($copied) {
        return $true
    }

    Write-Step 'Local Myst DLL not found. Downloading from GitHub update manifest...' -Color Gray
    if (Invoke-MystUpdate) {
        if ((Test-Path -LiteralPath $p)) {
            $prepared = Prepare-DllFile -Path $p
            if ($prepared) {
                return $true
            }
        }
    }

    Write-Step 'Myst DLL missing. Run option 3 (Update) or place Myst.dll / sbscmp64_mscorwks.dll next to this script.' -Color Yellow
    return $false
}

function Prepare-DllFile {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $false }

    try { Unblock-File $Path -ErrorAction Stop } catch {}
    $fileSize = (Get-Item -LiteralPath $Path).Length
    Write-Step "DLL file size ($([System.IO.Path]::GetFileName($Path))): $fileSize bytes" -Color Gray
    return ($fileSize -gt 0)
}

function Test-DllOnDisk {
    param(
        [string]$Path,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        Write-Step "$Label not found on disk: $Path" -Color Red
        Write-Step 'Place Myst.dll (or sbscmp64_mscorwks.dll) next to this script, or use option 3 (Update).' -Color Yellow
        return $false
    }

    if (-not (Prepare-DllFile -Path $Path)) {
        Write-Step "$Label exists but is empty or unreadable." -Color Red
        return $false
    }

    return $true
}

function Get-RuntimeBrokersWithDll {
    param([string]$DllPath)

    $loaded = @()
    foreach ($proc in Get-Process -Name $n -ErrorAction SilentlyContinue) {
        try {
            if (@($proc.Modules) | Where-Object { Test-DllPathMatch $_.FileName $DllPath }) {
                $loaded += $proc
            }
        } catch {}
    }
    return $loaded
}

function Test-RuntimeBrokerHasDll {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$DllPath
    )

    if (-not $Process -or $Process.HasExited) { return $false }
    try {
        return [bool](@($Process.Modules) | Where-Object { Test-DllPathMatch $_.FileName $DllPath })
    } catch {
        return $false
    }
}

function Remove-RuntimeBrokerDll {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$DllPath
    )

    if (-not $Process -or $Process.HasExited) { return $true }

    Write-Step "Clearing DLL from RuntimeBroker PID $($Process.Id)..." -Color Gray

    $unloaded = [Injector]::FreeModuleCompletely($Process.Id, $DllPath)
    if ($unloaded) {
        $refreshed = Get-Process -Id $Process.Id -ErrorAction SilentlyContinue
        if (-not $refreshed -or -not (Test-RuntimeBrokerHasDll -Process $refreshed -DllPath $DllPath)) {
            Write-Step "  Unloaded PID $($Process.Id)" -Color Green
            return $true
        }
    }

    Write-Step "  Unload incomplete, stopping RuntimeBroker PID $($Process.Id) only..." -Color Yellow
    try {
        Stop-Process -Id $Process.Id -Force -ErrorAction Stop
        Wait-Process -Id $Process.Id -ErrorAction SilentlyContinue
        Write-Step "  Stopped PID $($Process.Id)" -Color Green
        return $true
    } catch {
        if ($Process.HasExited) { return $true }
        Write-Step "  Failed to stop PID $($Process.Id): $_" -Color Red
        return $false
    }
}

function Clear-AllRuntimeBrokerDll {
    param([string]$DllPath)

    $withDll = @(Get-RuntimeBrokersWithDll -DllPath $DllPath)
    if (-not $withDll) {
        Write-Step 'No RuntimeBroker instance currently has the DLL loaded.' -Color Gray
        return $true
    }

    Write-Step "Found $($withDll.Count) RuntimeBroker instance(s) with DLL loaded." -Color Gray
    $ok = $true
    foreach ($proc in $withDll) {
        if (-not (Remove-RuntimeBrokerDll -Process $proc -DllPath $DllPath)) {
            $ok = $false
        }
    }
    return $ok
}

function Start-RuntimeBrokerInstance {
    param([string]$DllPath)

    Write-Step 'Starting a new RuntimeBroker instance...' -Color Gray
    Start-Process $x -ErrorAction SilentlyContinue | Out-Null
    if (-not (Wait-ForProcess -Name $n -Present $true -TimeoutSeconds 10)) {
        return $null
    }
    Start-Sleep -Seconds 3
    return (Get-RuntimeBrokerInjectionTarget -DllPath $DllPath)
}

function Get-RuntimeBrokerInjectionTarget {
    param([string]$DllPath)

    foreach ($proc in Get-Process -Name $n -ErrorAction SilentlyContinue) {
        if (-not (Test-RuntimeBrokerHasDll -Process $proc -DllPath $DllPath)) {
            return $proc
        }
    }
    return $null
}

function Restart-ExplorerShell {
    Write-Step 'Restarting Explorer to recover RuntimeBroker...' -Color Gray
    Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Process explorer.exe -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep -Seconds 4
}

function Invoke-Sbscmp30LoadFromDisk {
    Write-Step 'Starting RuntimeBroker load...' -Color Cyan

    if (-not (Ensure-Sbscmp30OnDisk)) {
        Write-Step 'Ensure-Sbscmp30OnDisk failed.' -Color Red
        return $false
    }

    if (-not (Test-DllOnDisk -Path $p -Label 'sbscmp64')) {
        Write-Step 'Test-DllOnDisk failed.' -Color Red
        return $false
    }

    Clear-AllRuntimeBrokerDll -DllPath $p | Out-Null

    foreach ($stubborn in @(Get-RuntimeBrokersWithDll -DllPath $p)) {
        Write-Step "Force-stopping stubborn RuntimeBroker PID $($stubborn.Id)..." -Color Yellow
        try {
            Stop-Process -Id $stubborn.Id -Force -ErrorAction Stop
        } catch {
            if (-not $stubborn.HasExited) {
                Write-Step "  Could not stop PID $($stubborn.Id): $_" -Color Red
            }
        }
    }

    Start-Sleep -Seconds 2

    $targetProc = $null
    $maxInjectRetries = 3

    for ($retry = 0; $retry -lt $maxInjectRetries; $retry++) {
        $targetProc = Get-RuntimeBrokerInjectionTarget -DllPath $p
        if (-not $targetProc) {
            $targetProc = Start-RuntimeBrokerInstance -DllPath $p
        }
        if (-not $targetProc -and $retry -eq ($maxInjectRetries - 1)) {
            Restart-ExplorerShell
            $targetProc = Get-RuntimeBrokerInjectionTarget -DllPath $p
            if (-not $targetProc) {
                $targetProc = Start-RuntimeBrokerInstance -DllPath $p
            }
        }
        if (-not $targetProc) {
            Write-Step 'No usable RuntimeBroker instance available.' -Color Red
            continue
        }

        $targetPid = $targetProc.Id
        Write-Step "Injecting sbscmp64 into RuntimeBroker PID $targetPid (attempt $($retry + 1))..." -Color Gray

        if ([Injector]::X($targetPid, $p)) {
            Start-Sleep -Seconds 2
            $refreshed = Get-Process -Id $targetPid -ErrorAction SilentlyContinue
            if ($refreshed -and (Test-RuntimeBrokerHasDll -Process $refreshed -DllPath $p)) {
                Write-Step "sbscmp64 loaded in RuntimeBroker PID $targetPid" -Color Green
                return $true
            }

            $moduleBase = [Injector]::GetModuleBase($targetPid, $p)
            if ($moduleBase -ne [IntPtr]::Zero) {
                Write-Step "sbscmp64 loaded in RuntimeBroker PID $targetPid (toolhelp confirmed)" -Color Green
                return $true
            }

            Write-Step 'Injection API succeeded but module not visible in target process.' -Color Yellow
        } else {
            Write-Step 'Injection API returned failure.' -Color Yellow
        }

        $cleanup = Get-Process -Id $targetPid -ErrorAction SilentlyContinue
        if ($cleanup) {
            Remove-RuntimeBrokerDll -Process $cleanup -DllPath $p | Out-Null
        }
        Start-Sleep -Seconds 2
    }

    Write-Step 'Unable to load sbscmp64 after retries.' -Color Red
    Clear-AllRuntimeBrokerDll -DllPath $p | Out-Null
    return $false
}

function Invoke-Sbscmp30Unload {
    $withDll = @(Get-RuntimeBrokersWithDll -DllPath $p)
    if (-not $withDll) {
        Write-Host "`n  sbscmp64 Already Unloaded" -ForegroundColor Yellow
        return $true
    }

    $ok = Clear-AllRuntimeBrokerDll -DllPath $p
    if ($ok) {
        Write-Host "`n  sbscmp64 Unloaded" -ForegroundColor Green
    } else {
        Write-Host "`n  Unable to unload sbscmp64 from all RuntimeBroker instances" -ForegroundColor Red
    }
    return $ok
}

function Inject-DllIntoProcesses {
    param(
        [string]$DllPath,
        [string[]]$ProcessNames,
        [string]$Label
    )

    $injected = 0
    $verified = 0

    for ($pass = 1; $pass -le 3; $pass++) {
        $passInjected = 0
        foreach ($processName in $ProcessNames) {
            $processes = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
            if (-not $processes) {
                if ($pass -eq 1) {
                    Write-Step "No $processName.exe processes found." -Color Gray
                }
                continue
            }

            if ($pass -eq 1) {
                Write-Step "Injecting $Label into $($processes.Count) $processName.exe process(es)..." -Color Gray
            }

            foreach ($proc in $processes) {
                if (Test-ProcessHasDll -ProcessId $proc.Id -DllPath $DllPath) {
                    $verified++
                    continue
                }

                $result = [Injector]::X($proc.Id, $DllPath)
                if ($result) {
                    Start-Sleep -Milliseconds 700
                    if (Test-ProcessHasDll -ProcessId $proc.Id -DllPath $DllPath) {
                        Write-Step "  $processName PID $($proc.Id): OK" -Color Green
                        $passInjected++
                        $injected++
                        $verified++
                    } else {
                        Write-Step "  $processName PID $($proc.Id): API OK, module not visible (retrying)" -Color Yellow
                    }
                } else {
                    Write-Step "  $processName PID $($proc.Id): FAILED" -Color Red
                }
            }
        }

        if ($passInjected -eq 0) { break }
        Start-Sleep -Seconds 2
    }

    if ($verified -gt 0 -and $injected -eq 0) {
        $injected = $verified
    }

    return $injected
}

function Unload-DllFromProcesses {
    param(
        [string]$DllPath,
        [string[]]$ProcessNames,
        [string]$Label
    )

    $unloaded = 0
    foreach ($processName in $ProcessNames) {
        $processes = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
        foreach ($proc in $processes) {
            $loaded = $false
            try { $loaded = [bool](@($proc.Modules) | Where-Object { Test-DllPathMatch $_.FileName $DllPath }) } catch {}
            if (-not $loaded) { continue }

            Write-Step "Unloading $Label from $processName PID $($proc.Id)..." -Color Gray
            if ([Injector]::FreeModuleCompletely($proc.Id, $DllPath)) {
                Write-Step '  Unloaded.' -Color Green
                $unloaded++
            } else {
                Write-Step '  Failed to unload.' -Color Red
            }
        }
    }

    return $unloaded
}

function Invoke-LoadAllDlls {
    Write-Step 'Ensuring Myst DLL is present...' -Color Cyan
    $buildDll = Resolve-LocalBuildDll -Names @('Myst.dll')
    $forceRefresh = -not [string]::IsNullOrWhiteSpace($buildDll)
    if (-not (Ensure-Sbscmp30OnDisk -ForceRefresh:$forceRefresh)) {
        Write-Host ''
        Write-Host '  Myst DLL missing in Framework64. Update/download failed - check GitHub files.' -ForegroundColor Yellow
        return $false
    }

    Write-Host ''
    Write-Step 'Unloading any existing sbscmp64...' -Color Cyan
    Invoke-Sbscmp30Unload | Out-Null
    Start-Sleep -Seconds 2

    Write-Step 'RuntimeBroker load (sbscmp64)...' -Color Cyan

    if (Invoke-Sbscmp30LoadFromDisk) {
        Write-Host ''
        Write-Host '  sbscmp64 Loaded' -ForegroundColor Green
        Write-Host '  Loaded - press Insert in-game to open the Myst menu.' -ForegroundColor Green
        Test-MystOverlayStarted | Out-Null
        return $true
    }

    Write-Host ''
    Write-Host '  Unable to Load sbscmp64' -ForegroundColor Red
    return $false
}

function Test-MystOverlayStarted {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public class MystOverlayProbe {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
}
'@ -ErrorAction SilentlyContinue

    for ($i = 0; $i -lt 15; $i++) {
        $hwnd = [MystOverlayProbe]::FindWindow('MystOverlay', $null)
        if ($hwnd -ne [IntPtr]::Zero) {
            Write-Step 'Myst overlay window detected — loader is running.' -Color Green
            return $true
        }
        Start-Sleep -Seconds 1
    }

    Write-Step 'Overlay not visible yet. Open Roblox and press Insert if the license screen already passed.' -Color Yellow
    return $false
}

function Invoke-UnloadAllDlls {
    Invoke-Sbscmp30Unload | Out-Null

    if (-not (Get-Process -Name $n -ErrorAction SilentlyContinue)) {
        Write-Host "`n  RuntimeBroker Doesn't Exist" -ForegroundColor Red
    }
}

$script:InjectorTypeReady = $false

function Initialize-InjectorType {
    if ($script:InjectorTypeReady) { return }

    $existingType = [System.AppDomain]::CurrentDomain.GetAssemblies().GetTypes() |
                    Where-Object { $_.FullName -eq 'Injector' }
    $needNewType = -not $existingType -or -not ($existingType.GetMethod('FreeModuleCompletely'))

    if ($needNewType) {
        if (-not $WatchMode) {
            Write-Step 'Setting up core components...' -Color Cyan
        }
        try {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class Injector {
    [DllImport("kernel32")] static extern IntPtr OpenProcess(uint a, bool b, int c);
    [DllImport("kernel32")] static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr a, uint s, uint t, uint p);
    [DllImport("kernel32")] static extern bool WriteProcessMemory(IntPtr h, IntPtr a, byte[] b, uint s, out uint w);
    [DllImport("kernel32")] static extern IntPtr GetProcAddress(IntPtr h, string n);
    [DllImport("kernel32")] static extern IntPtr GetModuleHandle(string n);
    [DllImport("kernel32")] static extern IntPtr CreateRemoteThread(IntPtr h, IntPtr a, uint s, IntPtr x, IntPtr p, uint f, IntPtr t);
    [DllImport("kernel32")] static extern uint WaitForSingleObject(IntPtr h, uint m);
    [DllImport("kernel32")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32")] static extern IntPtr CreateToolhelp32Snapshot(uint dwFlags, uint th32ProcessID);
    [DllImport("kernel32")] static extern bool Module32First(IntPtr hSnapshot, ref MODULEENTRY32 lpme);
    [DllImport("kernel32")] static extern bool Module32Next(IntPtr hSnapshot, ref MODULEENTRY32 lpme);
    [DllImport("kernel32")] static extern bool FreeLibrary(IntPtr hLibModule);

    [StructLayout(LayoutKind.Sequential)]
    public struct MODULEENTRY32 {
        public uint dwSize;
        public uint th32ModuleID;
        public uint th32ProcessID;
        public uint GlblcntUsage;
        public uint ProccntUsage;
        public IntPtr modBaseAddr;
        public uint modBaseSize;
        public IntPtr hModule;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string szModule;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string szExePath;
    }

    public static bool X(int pid, string d) {
        IntPtr h = OpenProcess(0x1F0FFF, false, pid);
        if (h == IntPtr.Zero) return false;
        IntPtr a = VirtualAllocEx(h, IntPtr.Zero, (uint)((d.Length + 1) * 2), 0x3000, 0x4);
        if (a == IntPtr.Zero) { CloseHandle(h); return false; }
        byte[] b = System.Text.Encoding.Unicode.GetBytes(d);
        uint w;
        if (!WriteProcessMemory(h, a, b, (uint)b.Length, out w)) { CloseHandle(h); return false; }
        IntPtr k = GetModuleHandle("kernel32.dll");
        IntPtr l = GetProcAddress(k, "LoadLibraryW");
        IntPtr t = CreateRemoteThread(h, IntPtr.Zero, 0, l, a, 0, IntPtr.Zero);
        if (t == IntPtr.Zero) { CloseHandle(h); return false; }
        WaitForSingleObject(t, 0xFFFFFFFF);
        CloseHandle(t);
        CloseHandle(h);
        return true;
    }

    public static IntPtr GetModuleBase(int pid, string dllPath) {
        IntPtr hSnapshot = CreateToolhelp32Snapshot(0x8, (uint)pid);
        if (hSnapshot == IntPtr.Zero) return IntPtr.Zero;
        MODULEENTRY32 me = new MODULEENTRY32();
        me.dwSize = (uint)Marshal.SizeOf(typeof(MODULEENTRY32));
        if (!Module32First(hSnapshot, ref me)) {
            CloseHandle(hSnapshot);
            return IntPtr.Zero;
        }
        IntPtr modBase = IntPtr.Zero;
        do {
            if (string.Equals(me.szExePath, dllPath, StringComparison.OrdinalIgnoreCase)) {
                modBase = me.modBaseAddr;
                break;
            }
        } while (Module32Next(hSnapshot, ref me));
        CloseHandle(hSnapshot);
        return modBase;
    }

    public static bool FreeModuleOnce(int pid, IntPtr modBase) {
        IntPtr hProc = OpenProcess(0x1F0FFF, false, pid);
        if (hProc == IntPtr.Zero) return false;
        IntPtr k = GetModuleHandle("kernel32.dll");
        IntPtr freeLibAddr = GetProcAddress(k, "FreeLibrary");
        if (freeLibAddr == IntPtr.Zero) { CloseHandle(hProc); return false; }
        IntPtr t = CreateRemoteThread(hProc, IntPtr.Zero, 0, freeLibAddr, modBase, 0, IntPtr.Zero);
        if (t == IntPtr.Zero) { CloseHandle(hProc); return false; }
        WaitForSingleObject(t, 0xFFFFFFFF);
        CloseHandle(t);
        CloseHandle(hProc);
        return true;
    }

    public static bool FreeModuleCompletely(int pid, string dllPath) {
        IntPtr modBase = GetModuleBase(pid, dllPath);
        if (modBase == IntPtr.Zero) return true;
        for (int i = 0; i < 20; i++) {
            if (!FreeModuleOnce(pid, modBase)) return false;
            System.Threading.Thread.Sleep(200);
            if (GetModuleBase(pid, dllPath) == IntPtr.Zero) return true;
        }
        return false;
    }
}
'@ -ReferencedAssemblies System.Runtime.InteropServices -ErrorAction Stop
            if (-not $WatchMode) {
                Write-Step 'Core components ready.' -Color Green
            }
        } catch {
            if ($_.Exception.Message -notmatch 'already exists') {
                throw
            }
        }
    }

    $script:InjectorTypeReady = $true
}

$script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $script:IsAdmin) {
    Write-Host ''
    Write-Host '  Administrator rights required. Requesting elevation...' -ForegroundColor Yellow
    $scriptPath = Resolve-InstallScriptPath
    if (-not $scriptPath) {
        Write-Host '  Could not resolve installer script path.' -ForegroundColor Red
        Write-Host '  Save install.ps1 locally and run: powershell -File install.ps1' -ForegroundColor DarkGray
        exit 1
    }

    $resolved = [System.IO.Path]::GetFullPath($scriptPath)
    $dest = [System.IO.Path]::GetFullPath($script:DllExecuterInstallPath)
    if ($resolved -ne $dest) {
        try {
            Copy-Item -LiteralPath $scriptPath -Destination $script:DllExecuterInstallPath -Force
            $scriptPath = $script:DllExecuterInstallPath
        } catch {
            Write-Host "  Warning: could not cache installer: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        $scriptPath = $script:DllExecuterInstallPath
    }

    $elevateArgs = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', $scriptPath
    )
    if ($WatchMode) { $elevateArgs += '-WatchMode' }
    if ($Choice) { $elevateArgs += '-Choice', $Choice }
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $elevateArgs -Wait | Out-Null
    exit $LASTEXITCODE
}

if ($WatchMode) {
    Initialize-InjectorType
    Sync-DllExecuterInstall | Out-Null
    exit 0
}

Initialize-InjectorType
Sync-DllExecuterInstall | Out-Null

if ($LoadOnly) {
    Write-Host '  Myst direct load mode' -ForegroundColor Cyan
    if (Invoke-LoadAllDlls) {
        Write-Host '  DLL loaded successfully.' -ForegroundColor Green
        exit 0
    }
    Write-Host '  DLL load failed.' -ForegroundColor Red
    exit 1
}

Write-Step 'Preparing environment...' -Color Cyan

$loggingPaths = @{
    ScriptBlock   = 'HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
    Module        = 'HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ModuleLogging'
    Transcription = 'HKLM:\Software\Policies\Microsoft\Windows\PowerShell\Transcription'
}
$originalValues = @{}

if ($script:IsAdmin) {
    foreach ($log in $loggingPaths.Keys) {
        $key = $loggingPaths[$log]
        $valueName = switch ($log) {
            'ScriptBlock'   { 'EnableScriptBlockLogging' }
            'Module'        { 'EnableModuleLogging' }
            'Transcription' { 'EnableTranscripting' }
        }
        try {
            $val = Get-ItemProperty -Path $key -Name $valueName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty $valueName
            $originalValues[$log] = $val
            Set-ItemProperty -Path $key -Name $valueName -Value 0 -ErrorAction SilentlyContinue
        } catch {
            $originalValues[$log] = $null
        }
    }
}

try {
    $historyPath = (Get-PSReadLineOption).HistorySavePath
    if ($historyPath -and (Test-Path $historyPath)) {
        $lines = Get-Content $historyPath -ErrorAction Stop
        $originalCount = $lines.Count

        function Normalise-Command ([string]$cmd) {
            return ($cmd.Trim() -replace '\s+', ' ').ToLowerInvariant()
        }

        if ($MyInvocation.MyCommand.Path) {
            $normalisedScript = Normalise-Command $MyInvocation.Line
            $lines = $lines | Where-Object { (Normalise-Command $_) -ne $normalisedScript }
        }

        $scrubTargets = @(
            'irm http://immune.wtf | iex'
            'irm http://myst.local | iex'
        )
        foreach ($target in $scrubTargets) {
            $normalisedTarget = Normalise-Command $target
            $lines = $lines | Where-Object { (Normalise-Command $_) -ne $normalisedTarget }
        }

        $removedCount = $originalCount - $lines.Count
        if ($removedCount -gt 0) {
            $lines | Set-Content $historyPath -Force -ErrorAction Stop
        }
    }
} catch {}

if ($script:IsAdmin) {
    foreach ($log in $loggingPaths.Keys) {
        $key = $loggingPaths[$log]
        $valueName = switch ($log) {
            'ScriptBlock'   { 'EnableScriptBlockLogging' }
            'Module'        { 'EnableModuleLogging' }
            'Transcription' { 'EnableTranscripting' }
        }
        try {
            if ($null -ne $originalValues[$log]) {
                Set-ItemProperty -Path $key -Name $valueName -Value $originalValues[$log] -ErrorAction Stop
            } else {
                Remove-ItemProperty -Path $key -Name $valueName -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}

Write-Step 'Environment ready.' -Color Green

Clear-Host
Write-Host ''
Write-Host '  +==========================================+' -ForegroundColor Cyan
Write-Host '  |         MYST INSTALLER v1.2.4            |' -ForegroundColor Cyan
Write-Host '  +==========================================+' -ForegroundColor Cyan
Write-Host '  |  1. Install & Load                       |' -ForegroundColor Cyan
Write-Host '  |  2. Unload                               |' -ForegroundColor Cyan
Write-Host '  |  3. Update (download latest)             |' -ForegroundColor Cyan
Write-Host '  |  4. Quit                                 |' -ForegroundColor Cyan
Write-Host '  +==========================================+' -ForegroundColor Cyan
Write-Host ''
Write-Host '  DLLs install to Framework64 (hidden system path).' -ForegroundColor DarkGray
Write-Host '  Remote install: irm https://raw.githubusercontent.com/JustValkz/Myst/main/install.ps1 | iex' -ForegroundColor DarkGray
Write-Host '  Local dev: place Myst.dll next to myst.ps1.' -ForegroundColor DarkGray
Write-Host '  In-game menu key: Insert.' -ForegroundColor DarkGray
Write-Host ''
if ($Choice) {
    if ($Choice -notin @('1', '2', '3', '4')) {
        Write-Host "  Invalid choice '$Choice'. Use 1, 2, 3, or 4." -ForegroundColor Yellow
        exit 1
    }
    $choice = $Choice
    Write-Host "  Auto choice: $choice" -ForegroundColor DarkGray
} else {
    $choice = Read-Host '  Enter your choice'
}

$doExit = $true
$loadSucceeded = $false
try {
switch ($choice) {
    '1' {
        $loadSucceeded = Invoke-LoadAllDlls
        if ($loadSucceeded -is [System.Array]) {
            $loadSucceeded = [bool]($loadSucceeded[-1])
        } else {
            $loadSucceeded = [bool]$loadSucceeded
        }
    }

    '2' {
        Invoke-UnloadAllDlls
    }

    '3' {
        Invoke-MystUpdate | Out-Null
    }

    '4' {
        $doExit = $false
        Clear-AllRuntimeBrokerDll -DllPath $p | Out-Null
        Write-Host "`n  Goodbye!" -ForegroundColor Cyan
    }

    default { Write-Host "`n  Invalid option." -ForegroundColor Yellow }
}
} catch {
    Write-Host "`n  Issue: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host '  Check the messages above and try again.' -ForegroundColor DarkGray
}

if ($loadSucceeded) {
    Write-Host ''
    Write-Host '  DLL loaded successfully. Closing in 5 seconds...' -ForegroundColor Green
    Start-Sleep -Seconds 5
    exit 0
}

if ($doExit) {
    Start-Sleep -Seconds 2
    exit 0
}

