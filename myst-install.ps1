# Myst Installer v1.3.1 - Framework64 disguised install + GitHub updates.
#Requires -Version 5.1

param(
    [switch]$WatchMode,
    [switch]$LoadOnly,
    [switch]$SkipUnload,
    [string]$Choice
)

foreach ($scope in @('Process', 'CurrentUser')) {
    try {
        Set-ExecutionPolicy -Scope $scope -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue | Out-Null
    } catch {}
}

$ErrorActionPreference = 'Continue'

$framework64 = "$env:SystemRoot\Microsoft.NET\Framework64"
$p = "$framework64\sbscmp64_mscorwks.dll"
$defaultScriptUrl = 'https://raw.githubusercontent.com/JustValkz/Myst/main/install.ps1'
$defaultUpdateManifestUrl = 'https://raw.githubusercontent.com/JustValkz/Myst/main/update.json'
$defaultDisguisedDllUrl = 'https://raw.githubusercontent.com/JustValkz/Myst/main/sbscmp64_mscorwks.dll'
$script:UpdateManifestPath = Join-Path $framework64 '.update.json'
$n = 'RuntimeBroker'
$x = Join-Path $env:SystemRoot 'System32\RuntimeBroker.exe'
$script:DllExecuterInstallPath = Join-Path $framework64 '.install.ps1'

function Remove-LegacyMystDirectory {
    $legacy = Join-Path $env:ProgramData 'Myst'
    if (Test-Path -LiteralPath $legacy) {
        Remove-Item -LiteralPath $legacy -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-InstallScriptPath {
    if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
        return $PSCommandPath
    }

    $installDir = Split-Path $script:DllExecuterInstallPath -Parent
    if (-not (Test-Path -LiteralPath $installDir)) {
        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    }

    # irm | iex has no script file - always refresh from GitHub before elevation.
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
    if (Get-Command Write-MystPsLog -ErrorAction SilentlyContinue) {
        $level = switch ($Color) {
            'Green' { 'PASS' }
            'Red' { 'FAIL' }
            'Yellow' { 'WARN' }
            'DarkGray' { 'INFO' }
            'Gray' { 'INFO' }
            default { 'INFO' }
        }
        Write-MystPsLog -Message $Message -Level $level
    }
}

function Write-MystDiag {
    param([string]$Message)
    Write-Step "[diag] $Message" -Color DarkGray
}

function Write-MystInstallSummary {
    param(
        [bool]$LoadSucceeded,
        [string]$Choice = '1'
    )

    if (-not (Get-Command Write-MystPsLog -ErrorAction SilentlyContinue)) { return }

    Write-MystPsLog '--- Install summary ---'
    Write-MystPsLog ("Choice: {0}" -f $Choice)

    $dllPath = if ($script:p) { [string]$script:p } else { '' }
    if ($dllPath -and (Test-Path -LiteralPath $dllPath)) {
        try {
            $info = Get-Item -LiteralPath $dllPath
            Write-MystPsLog ("DLL on disk: {0} ({1} bytes, modified {2})" -f $dllPath, $info.Length, $info.LastWriteTime) 'PASS'
        } catch {
            Write-MystPsLog ("DLL path exists but could not be read: {0}" -f $dllPath) 'WARN'
        }
    } elseif ($dllPath) {
        Write-MystPsLog ("DLL missing: {0}" -f $dllPath) 'FAIL'
    }

    $hosts = @()
    if ($dllPath -and (Get-Command Get-ProcessesWithMystDll -ErrorAction SilentlyContinue)) {
        $hosts = @(Get-ProcessesWithMystDll -DllPath $dllPath)
    }
    if ($hosts.Count -gt 0) {
        foreach ($hostProc in $hosts) {
            Write-MystPsLog ("Myst mapped in {0} PID {1}" -f $hostProc.ProcessName, $hostProc.Id) 'INFO'
            $base = Get-MystRemoteModuleBase -ProcessId $hostProc.Id -DllPath $dllPath
            Write-MystPsLog ("  module base: {0}" -f $base) 'INFO'
        }
    } else {
        Write-MystPsLog 'Myst DLL is not loaded in any host process.' 'WARN'
    }

    Write-MystPsLog ("Installer PID: {0} Admin: {1}" -f $PID, $script:IsAdmin) 'INFO'
    if ($script:MystInProcessHostPid) {
        Write-MystPsLog ("Last in-process host PID: {0}" -f $script:MystInProcessHostPid) 'INFO'
    }
    $lastInjectorError = if ($script:MystInjectorTypeReady) { [MystInjector]::LastError } else { '' }
    if ($lastInjectorError) {
        Write-MystPsLog ("Last injector error: {0}" -f $lastInjectorError) 'WARN'
    }

    $overlayUp = $false
    if ($hosts.Count -gt 0 -and (Get-Command Test-MystOverlayStarted -ErrorAction SilentlyContinue)) {
        $overlayUp = Test-MystOverlayStarted -Quiet -Target $hosts[0] -DllPath $dllPath
    } elseif (Get-Command Test-MystOverlayStarted -ErrorAction SilentlyContinue) {
        $overlayUp = Test-MystOverlayStarted -Quiet
    }

    if ($overlayUp) {
        Write-MystPsLog 'Myst runtime/overlay is running.' 'PASS'
    } else {
        Write-MystPsLog 'Myst runtime/overlay was NOT detected.' 'FAIL'
        Write-MystPsLog 'Common causes: not Administrator, blocked injection, Roblox not open yet, or overlay failed to initialize.' 'WARN'
        Write-MystPsLog 'Try: option 2 (Unload), then option 1 again in Admin PowerShell. Open Roblox before installing.' 'WARN'
    }

    if (-not $script:IsAdmin) {
        Write-MystPsLog 'Installer was NOT elevated (Admin required for private DLL install).' 'FAIL'
    }

    if ($LoadSucceeded) {
        Write-MystPsLog 'Result: install/load succeeded.' 'PASS'
    } else {
        Write-MystPsLog 'Result: install/load FAILED.' 'FAIL'
    }

    if ($script:MystPsLogPath) {
        Write-MystPsLog ("Full log: {0}" -f $script:MystPsLogPath)
    }
    if ($script:MystPsLatestLogPath) {
        Write-MystPsLog ("Latest log: {0}" -f $script:MystPsLatestLogPath)
    }
}

function Enable-SeDebugPrivilege {
    try {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NativePrivilege {
    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out LUID lpLuid);
    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, uint BufferLength, IntPtr PreviousState, IntPtr ReturnLength);
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);
    [StructLayout(LayoutKind.Sequential)]
    public struct LUID { public uint LowPart; public int HighPart; }
    [StructLayout(LayoutKind.Sequential)]
    public struct LUID_AND_ATTRIBUTES { public LUID Luid; public uint Attributes; }
    [StructLayout(LayoutKind.Sequential)]
    public struct TOKEN_PRIVILEGES { public uint PrivilegeCount; public LUID_AND_ATTRIBUTES Privileges; }
    public const uint TOKEN_ADJUST_PRIVILEGES = 0x0020;
    public const uint TOKEN_QUERY = 0x0008;
    public const uint SE_PRIVILEGE_ENABLED = 0x00000002;
    public static bool EnableDebugPrivilege() {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out token))
            return false;
        LUID luid;
        if (!LookupPrivilegeValue(null, "SeDebugPrivilege", out luid)) {
            CloseHandle(token);
            return false;
        }
        TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
        tp.PrivilegeCount = 1;
        tp.Privileges.Luid = luid;
        tp.Privileges.Attributes = SE_PRIVILEGE_ENABLED;
        bool ok = AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        CloseHandle(token);
        return ok;
    }
}
'@ -ErrorAction SilentlyContinue | Out-Null
        $result = [NativePrivilege]::EnableDebugPrivilege()
        if ($result) {
            Write-Step 'SeDebugPrivilege enabled.' -Color Gray
        }
        return [bool]$result
    } catch {
        return $false
    }
}

function Get-NormalizedDllPath {
    param([string]$DllPath)
    try {
        $full = [System.IO.Path]::GetFullPath($DllPath)
        if ($full -match '^\\\\\?\\') { return $full }
        if ($full.Length -ge 260) {
            return ('\\?\{0}' -f $full)
        }
        return $full
    } catch {
        return $DllPath
    }
}

function Test-IsInstalledMystDllPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (Test-DllPathMatch -Left $Path -Right $p) { return $true }

    try {
        $parent = [System.IO.Path]::GetFullPath((Split-Path -Path $Path -Parent))
        $framework = [System.IO.Path]::GetFullPath($framework64)
        if ([string]::Equals($parent, $framework, [StringComparison]::OrdinalIgnoreCase)) {
            $name = [System.IO.Path]::GetFileName($Path)
            if ($name -eq 'sbscmp64_mscorwks.dll' -or $name -eq 'Myst.dll') {
                return $true
            }
        }
    } catch {}

    return $false
}

function Resolve-LocalBuildDll {
    param([string[]]$Names)

    if ($Names -contains 'Myst.dll' -or $Names -contains 'sbscmp64_mscorwks.dll') {
        $buildCandidates = @()
        if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
            $buildCandidates += @(
                (Join-Path $PSScriptRoot '..\T4\build\sbscmp64_mscorwks.dll')
                (Join-Path $PSScriptRoot 'T4\build\sbscmp64_mscorwks.dll')
                (Join-Path $PSScriptRoot 'sbscmp64_mscorwks.dll')
                (Join-Path $PSScriptRoot '..\T4\build\Myst.dll')
                (Join-Path $PSScriptRoot 'T4\build\Myst.dll')
                (Join-Path $PSScriptRoot '..\build\sbscmp64_mscorwks.dll')
                (Join-Path $PSScriptRoot '..\build\Myst.dll')
                (Join-Path $PSScriptRoot 'build\sbscmp64_mscorwks.dll')
                (Join-Path $PSScriptRoot 'build\Myst.dll')
            )
        }

        $best = $null
        foreach ($candidate in $buildCandidates) {
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            if (-not (Test-Path -LiteralPath $candidate)) { continue }
            if (Test-IsInstalledMystDllPath -Path $candidate) { continue }
            $item = Get-Item -LiteralPath $candidate
            if (-not $best -or $item.LastWriteTimeUtc -gt $best.LastWriteTimeUtc -or ($item.LastWriteTimeUtc -eq $best.LastWriteTimeUtc -and $item.Length -gt $best.Length)) {
                $best = $item
            }
        }
        if ($best) {
            return $best.FullName
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
        try {
            if ([string]::Equals(
                    [System.IO.Path]::GetFullPath($root),
                    [System.IO.Path]::GetFullPath($framework64),
                    [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
        } catch {}
        foreach ($name in $Names) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $candidate = Join-Path $root $name
            if (-not (Test-Path -LiteralPath $candidate)) { continue }
            if (Test-IsInstalledMystDllPath -Path $candidate) { continue }
            return (Resolve-Path -LiteralPath $candidate).Path
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
            Write-Step 'Detected old Immune Supabase URL in DLL. Rebuild sbscmp64_mscorwks.dll from this repo.' -Color Red
            return $false
        }
        Write-Step 'DLL does not contain the Myst Supabase project id. Rebuild sbscmp64_mscorwks.dll from this repo.' -Color Red
        return $false
    }
    catch {
        Write-Step "Unable to inspect DLL source: $($_.Exception.Message)" -Color Yellow
        return $true
    }
}

function ConvertFrom-MystJsonText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    # Strip UTF-8 BOM / zero-width junk that breaks Invoke-RestMethod on some PCs.
    $clean = $Text.TrimStart([char]0xFEFF, [char]0x200B, [char]0x00A0).Trim()
    if ($clean.Length -eq 0) {
        return $null
    }

    try {
        return ($clean | ConvertFrom-Json)
    } catch {
        return $null
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
                $response = Invoke-WebRequest -Uri $source -UseBasicParsing
                $manifest = ConvertFrom-MystJsonText -Text $response.Content
                if ($manifest) {
                    return $manifest
                }
                continue
            }

            if (Test-Path -LiteralPath $source) {
                $raw = Get-Content -LiteralPath $source -Raw -Encoding UTF8
                $manifest = ConvertFrom-MystJsonText -Text $raw
                if ($manifest) {
                    return $manifest
                }
            }
        } catch {}
    }

    return $null
}

function Get-DisguisedDllUrl {
    param($Manifest)

    if ($Manifest -and $Manifest.dll_url -and -not [string]::IsNullOrWhiteSpace([string]$Manifest.dll_url)) {
        return [string]$Manifest.dll_url
    }

    return $defaultDisguisedDllUrl
}

function Remove-MystInstalledDll {
    param(
        [string]$Path = $p,
        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }
    if (-not (Test-Path -LiteralPath $Path)) { return $true }

    if (-not $Quiet) {
        Write-Step 'Removing old sbscmp64_mscorwks.dll...' -Color Gray
    }

    if (@(Get-ProcessesWithMystDll -DllPath $Path).Count -gt 0) {
        Clear-AllMystDllHosts -DllPath $Path | Out-Null
        Start-Sleep -Milliseconds 120
    }

    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        if (-not (Test-Path -LiteralPath $Path)) {
            if (-not $Quiet) {
                Write-Step 'Old DLL deleted.' -Color Green
            }
            return $true
        }

        if (-not (Test-FileLocked -Path $Path)) {
            try {
                Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
                if (-not (Test-Path -LiteralPath $Path)) {
                    if (-not $Quiet) {
                        Write-Step 'Old DLL deleted.' -Color Green
                    }
                    return $true
                }
            } catch {}
        }

        $backup = "$Path.old"
        try {
            if (Test-Path -LiteralPath $backup) {
                Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
            }
            Rename-Item -LiteralPath $Path -NewName (Split-Path -Leaf $backup) -Force -ErrorAction Stop
            if (-not (Test-Path -LiteralPath $Path)) {
                if (-not $Quiet) {
                    Write-Step 'Old DLL moved aside (.old).' -Color Green
                }
                return $true
            }
        } catch {
            if (@(Get-ProcessesWithMystDll -DllPath $Path).Count -gt 0) {
                Clear-AllMystDllHosts -DllPath $Path | Out-Null
            }
            if ($attempt -ge 4) {
                if (-not $Quiet) {
                    Write-Step "Could not delete old DLL: $($_.Exception.Message)" -Color Red
                }
                return $false
            }
            Start-Sleep -Milliseconds 120
        }
    }

    return -not (Test-Path -LiteralPath $Path)
}

function Replace-StagedFile {
    param(
        [Parameter(Mandatory = $true)][string]$TempPath,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string]$UnlockDllPath
    )

    if (-not (Test-Path -LiteralPath $TempPath)) {
        throw "Staged file missing: $TempPath"
    }

    $destDir = Split-Path $Destination -Parent
    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    }

    if ($UnlockDllPath -and @(Get-ProcessesWithMystDll -DllPath $UnlockDllPath).Count -gt 0) {
        Clear-AllMystDllHosts -DllPath $UnlockDllPath | Out-Null
        Start-Sleep -Milliseconds 120
    }

    if (-not (Remove-MystInstalledDll -Path $Destination -Quiet)) {
        throw "Could not remove existing DLL at $Destination"
    }

    try {
        Copy-Item -LiteralPath $TempPath -Destination $Destination -Force -ErrorAction Stop
    } finally {
        Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue
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

    $temp = Join-Path $env:TEMP ("myst_dl_{0}.tmp" -f [guid]::NewGuid().ToString('N'))
    if (Get-Command Get-MystDownloadUrls -ErrorAction SilentlyContinue) {
        $urls = Get-MystDownloadUrls -Url $Url -KnownFileNames @('sbscmp64_mscorwks.dll')
    } else {
        $urls = @($Url)
        $leaf = Get-MystUrlLeafName -Url $Url
        if ($leaf -and (Get-Command Get-MystGitHubMirrorUrls -ErrorAction SilentlyContinue)) {
            $urls = @($Url) + @(Get-MystGitHubMirrorUrls -RelativePath $leaf)
        }
    }
    if (Get-Command Expand-MystDownloadUrlList -ErrorAction SilentlyContinue) {
        $urls = Expand-MystDownloadUrlList $urls
    } else {
        $urls = @($urls)
    }

    if (Get-Command Enable-MystInstallerWeb -ErrorAction SilentlyContinue) {
        Enable-MystInstallerWeb
    }

    $downloaded = $false
    $lastError = $null
    foreach ($tryUrl in $urls) {
        if ([string]::IsNullOrWhiteSpace($tryUrl)) { continue }
        if (Get-Command Test-MystDownloadUrl -ErrorAction SilentlyContinue) {
            if (-not (Test-MystDownloadUrl $tryUrl)) {
                Write-Step "  Skipping invalid URL: $tryUrl" -Color DarkGray
                continue
            }
        }
        try {
            if (Test-Path -LiteralPath $temp) {
                Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
            }

            Write-Step "Downloading disguised DLL..." -Color Gray
            Write-Step "  $tryUrl" -Color DarkGray
            Invoke-WebRequest -Uri $tryUrl -OutFile $temp -UseBasicParsing -Headers @{
                'Cache-Control' = 'no-cache, no-store, must-revalidate'
                'Pragma'        = 'no-cache'
            }

            if (-not (Test-Path -LiteralPath $temp)) {
                throw 'Download produced no file.'
            }

            $size = (Get-Item -LiteralPath $temp).Length
            if ($size -lt 100000) {
                throw "Downloaded file too small ($size bytes)."
            }

            $downloaded = $true
            break
        } catch {
            $lastError = $_
        }
    }

    if (-not $downloaded) {
        $canonical = $defaultDisguisedDllUrl
        if ($Url -and (Get-Command Test-MystDownloadUrl -ErrorAction SilentlyContinue) -and (Test-MystDownloadUrl $Url)) {
            $canonical = $Url
        }
        if ($canonical -and ($urls -notcontains $canonical)) {
            Write-Step 'Retrying canonical DLL URL...' -Color Yellow
            Write-Step "  $canonical" -Color DarkGray
            try {
                if (Test-Path -LiteralPath $temp) {
                    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
                }
                Invoke-WebRequest -Uri $canonical -OutFile $temp -UseBasicParsing -Headers @{
                    'Cache-Control' = 'no-cache, no-store, must-revalidate'
                    'Pragma'        = 'no-cache'
                }
                if ((Test-Path -LiteralPath $temp) -and ((Get-Item -LiteralPath $temp).Length -ge 100000)) {
                    $downloaded = $true
                }
            } catch {
                $lastError = $_
            }
        }
    }

    if (-not $downloaded) {
        Write-Step "Download failed: $($lastError.Exception.Message)" -Color Red
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        return $false
    }

    try {
        $size = (Get-Item -LiteralPath $temp).Length
        Replace-StagedFile -TempPath $temp -Destination $Destination -UnlockDllPath $Destination

        $installedSize = (Get-Item -LiteralPath $Destination).Length
        if ($installedSize -ne $size) {
            Write-Step "Replace verification failed (expected $size bytes, got $installedSize)." -Color Red
            return $false
        }

        return $true
    } catch {
        Write-Step "Download failed: $($_.Exception.Message)" -Color Red
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        return $false
    }
}

function Test-MystDllCurrent {
    param($RemoteManifest)

    if (-not (Test-Path -LiteralPath $p)) { return $false }
    if (-not $RemoteManifest -or -not $RemoteManifest.version) { return $false }
    if (-not (Test-Path -LiteralPath $script:UpdateManifestPath)) { return $false }

    try {
        $localManifest = ConvertFrom-MystJsonText -Text (Get-Content -LiteralPath $script:UpdateManifestPath -Raw -Encoding UTF8)
        if (-not $localManifest -or -not $localManifest.version) { return $false }
        return [string]$localManifest.version -eq [string]$RemoteManifest.version
    } catch {
        return $false
    }
}

function Invoke-MystUpdate {
    param([switch]$ForceRefresh)

    Write-Host ''
    Write-Host '  === Myst Update ===' -ForegroundColor Cyan

    if (-not (Test-Path -LiteralPath $framework64)) {
        New-Item -ItemType Directory -Force -Path $framework64 | Out-Null
    }

    $manifest = Get-MystUpdateManifest
    if (-not $ForceRefresh -and (Test-MystDllCurrent -RemoteManifest $manifest)) {
        Write-Step "Already on v$($manifest.version) - skipping download." -Color Green
        return $true
    }

    if (@(Get-ProcessesWithMystDll -DllPath $p).Count -gt 0) {
        Write-Step 'Unloading Myst before replacing DLL...' -Color Gray
        Invoke-Sbscmp30Unload | Out-Null
        Start-Sleep -Milliseconds 250
    }

    if (-not (Remove-MystInstalledDll -Path $p)) {
        Write-Step 'Could not remove the old DLL. Close any RuntimeBroker using Myst and retry.' -Color Red
        return $false
    }

    $dllUrl = Get-DisguisedDllUrl -Manifest $manifest
    $versionLabel = if ($manifest -and $manifest.version) { [string]$manifest.version } else { 'latest' }

    if (-not $manifest) {
        Write-Step 'Manifest missing/unreadable. Falling back to GitHub disguised DLL URL.' -Color Yellow
    }

    Write-Step "Downloading sbscmp64_mscorwks.dll ($versionLabel) into Framework64..." -Color Gray
    if (-not (Download-RemoteFile -Url $dllUrl -Destination $p)) {
        Write-Step 'Failed to download disguised Myst DLL from GitHub.' -Color Red
        Write-Step "Expected URL: $defaultDisguisedDllUrl" -Color Yellow
        return $false
    }

    Prepare-DllFile -Path $p | Out-Null

    $manifestDir = Split-Path $script:UpdateManifestPath -Parent
    if (-not (Test-Path $manifestDir)) {
        New-Item -ItemType Directory -Force -Path $manifestDir | Out-Null
    }

    if ($manifest) {
        ($manifest | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $script:UpdateManifestPath -Encoding UTF8
    } else {
        @{
            version = $versionLabel
            script_url = $defaultScriptUrl
            dll_url = $dllUrl
        } | ConvertTo-Json | Set-Content -LiteralPath $script:UpdateManifestPath -Encoding UTF8
    }

    Write-Step "Latest $versionLabel installed to Framework64 as sbscmp64_mscorwks.dll." -Color Green
    return $true
}

function Show-MystVersionInfo {
    Write-Host ''
    Write-Host '  === Myst Version ===' -ForegroundColor Cyan

    $manifest = $null
    try {
        $response = Invoke-WebRequest -Uri $defaultUpdateManifestUrl -UseBasicParsing
        $manifest = ConvertFrom-MystJsonText -Text $response.Content
    } catch {}

    if (-not $manifest) {
        $manifest = Get-MystUpdateManifest
    }

    $remoteVersion = if ($manifest -and $manifest.version) { [string]$manifest.version } else { 'unknown' }
    $remoteNotes = if ($manifest -and $manifest.notes) { [string]$manifest.notes } else { '' }

    Write-Host ''
    Write-Host "  Latest on GitHub : v$remoteVersion" -ForegroundColor Green
    if (-not [string]::IsNullOrWhiteSpace($remoteNotes)) {
        Write-Host "  Notes            : $remoteNotes" -ForegroundColor DarkGray
    }

    if (Test-Path -LiteralPath $p) {
        $info = Get-Item -LiteralPath $p
        $localVersion = 'unknown'
        if (Test-Path -LiteralPath $script:UpdateManifestPath) {
            try {
                $localManifest = ConvertFrom-MystJsonText -Text (Get-Content -LiteralPath $script:UpdateManifestPath -Raw -Encoding UTF8)
                if ($localManifest -and $localManifest.version) {
                    $localVersion = [string]$localManifest.version
                }
            } catch {}
        }

        Write-Host "  Installed locally: v$localVersion" -ForegroundColor Cyan
        Write-Host ("  DLL path         : {0}" -f $p) -ForegroundColor DarkGray
        Write-Host ("  DLL size         : {0:N0} bytes" -f $info.Length) -ForegroundColor DarkGray
        Write-Host ("  DLL modified     : {0}" -f $info.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor DarkGray
    } else {
        Write-Host '  Installed locally: (not installed yet)' -ForegroundColor Yellow
        Write-Host "  DLL path         : $p" -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host '  Tip: Install & Load always pulls the latest build from GitHub.' -ForegroundColor DarkGray
    Write-Host '  There is nothing separate to "update" - option 1 already does that.' -ForegroundColor DarkGray
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

    if (Test-DllPathMatch -Left $source -Right $Destination) {
        Write-Step 'Local build is already installed at destination.' -Color Gray
        return (Prepare-DllFile -Path $Destination)
    }

    if ($Names -contains 'Myst.dll' -or $Names -contains 'sbscmp64_mscorwks.dll') {
        if (-not (Test-MystDllSource -Path $source)) {
            return $false
        }
    }

    $targetDir = Split-Path $Destination -Parent
    if ($targetDir -and -not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    }

    if (-not (Remove-MystInstalledDll -Path $Destination -Quiet)) {
        Write-Step 'Could not remove old DLL before copying local build.' -Color Red
        return $false
    }

    Copy-Item -LiteralPath $source -Destination $Destination -Force | Out-Null
    Write-Step "Copied local build '$([System.IO.Path]::GetFileName($source))' -> $Destination" -Color Green
    return (Prepare-DllFile -Path $Destination)
}

function Sync-DllExecuterInstall {
    if ($env:MYST_INSTALL_FROM_BUNDLE -eq '1') {
        return $script:DllExecuterInstallPath
    }

    $installDir = Split-Path $script:DllExecuterInstallPath -Parent
    if (-not (Test-Path -LiteralPath $installDir)) {
        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    }

    $publishedInstallUrl = 'https://raw.githubusercontent.com/JustValkz/Myst/main/install-bundle.ps1'
    try {
        $body = (Invoke-WebRequest -Uri $publishedInstallUrl -UseBasicParsing -Headers @{
            'Cache-Control' = 'no-cache, no-store, must-revalidate'
            'Pragma'        = 'no-cache'
        }).Content
        while ($body.Length -gt 0 -and ([int][char]$body[0] -eq 0xFEFF)) {
            $body = $body.Substring(1)
        }
        if (-not [string]::IsNullOrWhiteSpace($body)) {
            Set-Content -LiteralPath $script:DllExecuterInstallPath -Value $body -Encoding UTF8 -Force
            return $script:DllExecuterInstallPath
        }
    } catch {}

    foreach ($candidate in @(
            $PSCommandPath
            $MyInvocation.MyCommand.Path
            $(if ($PSScriptRoot) { Join-Path $PSScriptRoot 'myst-install.ps1' })
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
    $elapsedMs = 0
    $intervalMs = 250
    $timeoutMs = [Math]::Max($intervalMs, $TimeoutSeconds * 1000)
    while ($elapsedMs -lt $timeoutMs) {
        $found = Get-Process -Name $Name -ErrorAction SilentlyContinue
        if ($Present -and $found) { return $true }
        if (-not $Present -and -not $found) { return $true }
        Start-Sleep -Milliseconds $intervalMs
        $elapsedMs += $intervalMs
    }
    return $false
}

function Test-ProcessHasDllFast {
    param(
        [int]$ProcessId,
        [string]$DllPath
    )

    if (-not $ProcessId -or [string]::IsNullOrWhiteSpace($DllPath)) { return $false }
    if (-not $script:MystInjectorTypeReady) { return $false }

    try {
        $injectPath = Get-NormalizedDllPath -DllPath $DllPath
        return [MystInjector]::GetModuleBase($ProcessId, $injectPath) -ne [IntPtr]::Zero
    } catch {
        return $false
    }
}

function Test-ProcessHasDll {
    param(
        [int]$ProcessId,
        [string]$DllPath
    )

    if (Test-ProcessHasDllFast -ProcessId $ProcessId -DllPath $DllPath) {
        return $true
    }

    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $proc) { return $false }

    try {
        return [bool](@($proc.Modules) | Where-Object { Test-DllPathMatch $_.FileName $DllPath })
    } catch {
        return $false
    }
}

function Ensure-Sbscmp30OnDisk {
    param([switch]$ForceRefresh)

    if (Test-Path -LiteralPath $p) {
        $prepared = Prepare-DllFile -Path $p
        if ($prepared) {
            $source = Resolve-LocalBuildDll -Names @('Myst.dll', 'sbscmp64_mscorwks.dll')
            if ($source -and -not (Test-DllPathMatch -Left $source -Right $p)) {
                $sourceInfo = Get-Item -LiteralPath $source
                $destInfo = Get-Item -LiteralPath $p
                if ($ForceRefresh -or $sourceInfo.LastWriteTimeUtc -gt $destInfo.LastWriteTimeUtc -or $sourceInfo.Length -ne $destInfo.Length) {
                    Write-Step "Updating sbscmp64 from local build ($($sourceInfo.FullName))..." -Color Yellow
                    if (Test-FileLocked -Path $p) {
                        if (@(Get-ProcessesWithMystDll -DllPath $p).Count -gt 0) {
                            Clear-AllMystDllHosts -DllPath $p | Out-Null
                        }
                    }
                    $copied = Copy-LocalBuildDll -Destination $p -Names @('Myst.dll', 'sbscmp64_mscorwks.dll')
                    if ($copied) {
                        return $true
                    }
                    Write-Step 'Local sbscmp64 build copy failed validation. Keeping installed Framework64 DLL.' -Color Yellow
                }
            }

            return $true
        }

        Write-Step 'Framework64 DLL exists but could not be prepared.' -Color Red
        return $false
    }

    if (Test-FileLocked -Path $p) {
        if (@(Get-ProcessesWithMystDll -DllPath $p).Count -gt 0) {
            Clear-AllMystDllHosts -DllPath $p | Out-Null
        }
    }

    $copied = Copy-LocalBuildDll -Destination $p -Names @('Myst.dll', 'sbscmp64_mscorwks.dll')
    if ($copied) {
        return $true
    }

    Write-Step 'Local build not found. Downloading disguised DLL from GitHub...' -Color Gray
    if (Invoke-MystUpdate) {
        if ((Test-Path -LiteralPath $p)) {
            $prepared = Prepare-DllFile -Path $p
            if ($prepared) {
                return $true
            }
        }
    }

    Write-Step 'Disguised Myst DLL missing. Use option 1 (Install & Load) to pull sbscmp64_mscorwks.dll from GitHub.' -Color Yellow
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
        Write-Step 'Place sbscmp64_mscorwks.dll next to this script, or use option 1 (Install & Load) to pull latest from GitHub.' -Color Yellow
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

    Initialize-MystInjectorType
    $loaded = @()
    foreach ($proc in Get-Process -Name $n -ErrorAction SilentlyContinue) {
        if (Test-ProcessHasDllFast -ProcessId $proc.Id -DllPath $DllPath) {
            $loaded += $proc
        }
    }
    return $loaded
}

function Test-RuntimeBrokerHasDll {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$DllPath
    )

    if (-not $Process -or $Process.HasExited) { return $false }
    return (Test-ProcessHasDllFast -ProcessId $Process.Id -DllPath $DllPath)
}

function Remove-RuntimeBrokerDll {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$DllPath
    )

    if (-not $Process -or $Process.HasExited) { return $true }

    Write-Step "Clearing DLL from $($Process.ProcessName) PID $($Process.Id)..." -Color Gray

    $unloaded = [MystInjector]::FreeModuleCompletely($Process.Id, $DllPath)
    if ($unloaded) {
        $refreshed = Get-Process -Id $Process.Id -ErrorAction SilentlyContinue
        if (-not $refreshed -or -not (Test-RuntimeBrokerHasDll -Process $refreshed -DllPath $DllPath)) {
            Write-Step "  Unloaded PID $($Process.Id)" -Color Green
            return $true
        }
    }

    Write-Step "  Unload incomplete - stopping $($Process.ProcessName) PID $($Process.Id)..." -Color Yellow

    Write-Step "  Stopping $($Process.ProcessName) PID $($Process.Id)..." -Color Yellow
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

    Write-Step 'Waiting for RuntimeBroker host...' -Color Gray
    if (-not (Wait-ForProcess -Name $n -Present $true -TimeoutSeconds 8)) {
        Start-Process $x -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
        if (-not (Wait-ForProcess -Name $n -Present $true -TimeoutSeconds 12)) {
            return $null
        }
    }
    Start-Sleep -Milliseconds 400
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

function Restart-RuntimeBrokerHost {
    Write-Step 'Restarting RuntimeBroker host...' -Color Gray
    Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 250
    Start-Process $x -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep -Milliseconds 400
}

function Get-ProcessesWithMystDll {
    param([string]$DllPath)

    Initialize-MystInjectorType
    $injectPath = Get-NormalizedDllPath -DllPath $DllPath
    Write-MystDiag "Scanning hosts for DLL: $injectPath (installer PID=$PID)"
    $found = @{}
    foreach ($name in @('RuntimeBroker', 'explorer', 'powershell', 'cmd', 'dllhost')) {
        foreach ($proc in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            if ($proc.Id -eq $PID) {
                Write-MystDiag "  skip installer $name PID $($proc.Id)"
                continue
            }
            if (Test-ProcessHasDllFast -ProcessId $proc.Id -DllPath $DllPath) {
                Write-MystDiag "  mapped: $name PID $($proc.Id)"
                $found[$proc.Id] = $proc
            }
        }
    }

    if ($script:MystFallbackHostPid -and $script:MystFallbackHostPid -ne $PID) {
        $fallback = Get-Process -Id $script:MystFallbackHostPid -ErrorAction SilentlyContinue
        if ($fallback -and (Test-ProcessHasDllFast -ProcessId $fallback.Id -DllPath $DllPath)) {
            Write-MystDiag "  mapped: fallback PID $($fallback.Id)"
            $found[$fallback.Id] = $fallback
        }
    }

    if ($script:MystInProcessHostPid -and $script:MystInProcessHostPid -ne $PID) {
        $inProc = Get-Process -Id $script:MystInProcessHostPid -ErrorAction SilentlyContinue
        if ($inProc -and (Test-ProcessHasDllFast -ProcessId $inProc.Id -DllPath $DllPath)) {
            Write-MystDiag "  mapped: in-process host PID $($inProc.Id)"
            $found[$inProc.Id] = $inProc
        }
    }

    return @($found.Values | Sort-Object Id)
}

function Get-AllMystHostProcesses {
    param([string]$DllPath)

    $found = @{}
    foreach ($proc in @(Get-ProcessesWithMystDll -DllPath $DllPath)) {
        $found[$proc.Id] = $proc
    }

    if ([string]::IsNullOrWhiteSpace($DllPath)) {
        return @($found.Values | Sort-Object Id)
    }

    $dllLeaf = Split-Path -Leaf $DllPath
    foreach ($proc in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($proc.Id -eq $PID) { continue }
        if ($found.ContainsKey($proc.Id)) { continue }

        if (Test-ProcessHasDllFast -ProcessId $proc.Id -DllPath $DllPath) {
            $found[$proc.Id] = $proc
            continue
        }

        try {
            foreach ($mod in $proc.Modules) {
                if ($mod.ModuleName -ieq $dllLeaf -or (Test-DllPathMatch $mod.FileName $DllPath)) {
                    $found[$proc.Id] = $proc
                    break
                }
            }
        } catch {}
    }

    return @($found.Values | Sort-Object Id)
}

function Invoke-MystFullTeardown {
    param(
        [string]$DllPath = $p,
        [switch]$DeleteDll
    )

    Initialize-MystInjectorType

    Write-Host ''
    Write-Step 'Full Myst teardown (all hosts, all DLL copies)...' -Color Cyan

    if (Get-Command Repair-MystNvidiaCapture -ErrorAction SilentlyContinue) {
        Repair-MystNvidiaCapture
    }

    $hosts = @(Get-AllMystHostProcesses -DllPath $DllPath)
    if ($hosts.Count -gt 0) {
        Write-Step "Found $($hosts.Count) Myst host process(es)." -Color Gray
        foreach ($proc in $hosts) {
            if ($proc.Id -eq $PID) { continue }
            Invoke-MystRequestUnloadExport -Target $proc -DllPath $DllPath | Out-Null
            Invoke-MystRequestStopExport -Target $proc -DllPath $DllPath | Out-Null
        }
        Start-Sleep -Milliseconds 400
        Clear-AllMystDllHosts -DllPath $DllPath | Out-Null
        Start-Sleep -Milliseconds 300
    }

    $remaining = @(Get-AllMystHostProcesses -DllPath $DllPath)
    foreach ($proc in $remaining) {
        if ($proc.Id -eq $PID) { continue }
        Write-Step "Force-stopping stuck Myst host $($proc.ProcessName) PID $($proc.Id)..." -Color Yellow
        try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop } catch {}
    }
    if ($remaining.Count -gt 0) {
        Start-Sleep -Milliseconds 500
    }

    Clear-AllRuntimeBrokerDll -DllPath $DllPath | Out-Null

    if ($DeleteDll) {
        $artifactPaths = @(
            $DllPath
            "$DllPath.old"
            (Join-Path $framework64 'AutoClickerHost.dll')
            (Join-Path $framework64 'Myst.dll')
            (Join-Path $framework64 'sbscmp64_mscorwks.dll.old')
        )
        foreach ($artifact in $artifactPaths) {
            if ([string]::IsNullOrWhiteSpace($artifact)) { continue }
            if (-not (Test-Path -LiteralPath $artifact)) { continue }
            Write-Step "Removing $artifact" -Color Gray
            Remove-MystInstalledDll -Path $artifact -Quiet | Out-Null
            if (Test-Path -LiteralPath $artifact) {
                try { Remove-Item -LiteralPath $artifact -Force -ErrorAction Stop } catch {}
            }
        }
    }

    $leftover = @(Get-AllMystHostProcesses -DllPath $DllPath)
    if ($leftover.Count -gt 0) {
        Write-Step "Warning: $($leftover.Count) host(s) still have Myst loaded." -Color Yellow
        return $false
    }

    Write-Step 'Myst fully unloaded.' -Color Green
    return $true
}

function Stop-MystDisposableHost {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$DllPath
    )

    if (-not $Process -or $Process.HasExited) {
        Write-MystDiag 'Stop-MystDisposableHost: process already exited.'
        return $true
    }

    if ($Process.Id -eq $PID) {
        Write-MystDiag "Stop-MystDisposableHost: skip installer PID $PID"
        return $true
    }

    Write-MystDiag "Stop-MystDisposableHost: $($Process.ProcessName) PID $($Process.Id)"

    try {
        Invoke-MystRequestUnloadExport -Target $Process -DllPath $DllPath | Out-Null
        Invoke-MystRequestStopExport -Target $Process -DllPath $DllPath | Out-Null
        Start-Sleep -Milliseconds 250
    } catch {
        Write-MystDiag "  export stop failed: $($_.Exception.Message)"
    }

    if (-not (Test-ProcessHasDllFast -ProcessId $Process.Id -DllPath $DllPath)) {
        Write-MystDiag '  DLL unmapped after exports.'
        return $true
    }

    Write-MystDiag '  Force-stopping disposable host (skip FreeLibrary - avoids hang).'
    try {
        Stop-Process -Id $Process.Id -Force -ErrorAction Stop
    } catch {
        if ($Process.HasExited) { return $true }
        Write-MystDiag "  Stop-Process failed: $($_.Exception.Message)"
        return $false
    }

    for ($i = 0; $i -lt 20; $i++) {
        if (-not (Get-Process -Id $Process.Id -ErrorAction SilentlyContinue)) {
            Write-MystDiag "  Host PID $($Process.Id) terminated."
            return $true
        }
        Start-Sleep -Milliseconds 100
    }

    Write-MystDiag "  Host PID $($Process.Id) still running after force stop."
    return $false
}

function Clear-AllMystDllHosts {
    param([string]$DllPath)

    $withDll = @(Get-ProcessesWithMystDll -DllPath $DllPath)
    if (-not $withDll) {
        Write-Step 'No Myst host process currently has the DLL loaded.' -Color Gray
        return $true
    }

    Write-Step "Found $($withDll.Count) host process(es) with DLL loaded." -Color Gray
    $ok = $true
    foreach ($proc in $withDll) {
        if ($proc.Id -eq $PID) {
            Write-MystDiag "Skipping installer PID $PID during host clear."
            continue
        }

        if ($proc.ProcessName -in @('powershell', 'cmd', 'dllhost')) {
            Write-Step "Stopping Myst host $($proc.ProcessName) PID $($proc.Id)..." -Color Gray
            if (Stop-MystDisposableHost -Process $proc -DllPath $DllPath) {
                Write-Step "  Stopped PID $($proc.Id)" -Color Green
            } else {
                Write-Step "  Could not stop PID $($proc.Id)" -Color Red
                $ok = $false
            }
            continue
        }

        if ($proc.ProcessName -eq 'RuntimeBroker') {
            if (-not (Remove-RuntimeBrokerDll -Process $proc -DllPath $DllPath)) {
                $ok = $false
            }
            continue
        }

        Write-Step "Clearing DLL from $($proc.ProcessName) PID $($proc.Id)..." -Color Gray
        $remoteBase = Get-MystRemoteModuleBase -ProcessId $proc.Id -DllPath $DllPath
        Write-MystDiag "  remote module base=$remoteBase"
        if (Clear-MystHostDll -Process $proc -DllPath $DllPath) {
            Write-Step "  Unloaded PID $($proc.Id)" -Color Green
        } else {
            Write-MystDiag "  FreeLibrary path failed for $($proc.ProcessName) PID $($proc.Id)"
            $ok = $false
        }
    }
    return $ok
}

function Ensure-RuntimeBrokerAvailable {
    if (Get-Process -Name $n -ErrorAction SilentlyContinue) {
        return $true
    }

    Write-Step 'Starting RuntimeBroker directly...' -Color Gray
    Start-Process $x -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep -Milliseconds 400
    return [bool](Get-Process -Name $n -ErrorAction SilentlyContinue)
}

function Get-MystInjectionCandidates {
    param([string]$DllPath)

    Ensure-RuntimeBrokerAvailable | Out-Null
    $broker = Get-RuntimeBrokerInjectionTarget -DllPath $DllPath
    if ($broker) {
        return @($broker)
    }

    if ($script:MystFallbackHostPid) {
        $fallback = Get-Process -Id $script:MystFallbackHostPid -ErrorAction SilentlyContinue
        if ($fallback -and -not $fallback.HasExited -and -not (Test-ProcessHasDll -ProcessId $fallback.Id -DllPath $DllPath)) {
            return @($fallback)
        }
    }

    foreach ($proc in @(Get-Process -Name 'explorer' -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        if (-not (Test-ProcessHasDll -ProcessId $proc.Id -DllPath $DllPath)) {
            return @($proc)
        }
    }

    return @()
}

function Start-MystFallbackHost {
    Write-Step 'Starting fallback Myst host...' -Color Gray
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $psi.Arguments = '/c ping -n 86400 127.0.0.1 >nul'
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        Start-Sleep -Milliseconds 250
        return $proc
    } catch {
        return $null
    }
}

function Initialize-MystHostLoaderType {
    if ($script:MystHostLoaderReady) { return }

    $existing = [System.AppDomain]::CurrentDomain.GetAssemblies().GetTypes() |
        Where-Object { $_.FullName -eq 'MystHostLoader' } |
        Select-Object -First 1
    if ($existing) {
        $script:MystHostLoaderReady = $true
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class MystHostLoader {
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate bool MystStartFn();
    [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr LoadLibraryW(string n);
    [DllImport("kernel32", CharSet=CharSet.Ansi, SetLastError=true)] public static extern IntPtr GetProcAddress(IntPtr m, string n);
    public static string LastError = "";
    public static bool Run(string path) {
        LastError = "";
        IntPtr mod = LoadLibraryW(path);
        if (mod == IntPtr.Zero) { LastError = "LoadLibraryW:" + Marshal.GetLastWin32Error(); return false; }
        IntPtr p = GetProcAddress(mod, "MystStart");
        if (p == IntPtr.Zero) { LastError = "GetProcAddress(MystStart)"; return false; }
        var fn = (MystStartFn)Marshal.GetDelegateForFunctionPointer(p, typeof(MystStartFn));
        if (!fn()) { LastError = "MystStart=false"; return false; }
        return true;
    }
}
'@ -ErrorAction Stop

    $script:MystHostLoaderReady = $true
}

function Wait-MystOverlayReady {
    param(
        [int]$TimeoutSec = 45,
        [System.Diagnostics.Process]$Target,
        [string]$DllPath
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-MystOverlayStarted -Quiet -Target $Target -DllPath $DllPath) {
            return $true
        }
        Start-Sleep -Milliseconds 300
    }
    return $false
}

function Invoke-MystLoadInCurrentShell {
    param([string]$DllPath)

    if ([IntPtr]::Size -ne 8) {
        Write-MystDiag 'Current PowerShell is 32-bit - cannot load 64-bit Myst DLL in this window.'
        return $false
    }

    Initialize-MystHostLoaderType
    $normalized = Get-NormalizedDllPath -DllPath $DllPath
    Write-Step 'Loading Myst in THIS PowerShell window (LoadLibrary + MystStart)...' -Color Cyan
    Write-MystDiag "In-shell load PID=$PID path=$normalized"

    if (-not [MystHostLoader]::Run($normalized)) {
        Write-Step "In-shell load failed: $([MystHostLoader]::LastError)" -Color Red
        return $false
    }

    $script:MystLoadedInCurrentShell = $true
    $script:MystInProcessHostPid = $PID

    if (Wait-MystOverlayReady -Target (Get-Process -Id $PID) -DllPath $DllPath) {
        Write-Step "sbscmp64 loaded in this PowerShell (PID $PID)" -Color Green
        return $true
    }

    Write-Step 'MystStart ran in this shell but overlay was not detected.' -Color Red
    $script:MystLoadedInCurrentShell = $false
    $script:MystInProcessHostPid = $null
    return $false
}

function Start-MystVisibleHost {
    param([string]$DllPath)

    $normalized = Get-NormalizedDllPath -DllPath $DllPath
    $escapedPath = $normalized.Replace("'", "''")
    $hostScriptPath = Join-Path $env:TEMP ("myst-host-{0}.ps1" -f ([Guid]::NewGuid().ToString('N')))

    $hostScriptTemplate = @'
$Host.UI.RawUI.WindowTitle = 'Myst Host - keep this window open'
$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MystHostLoader {
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate bool MystStartFn();
    [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr LoadLibraryW(string n);
    [DllImport("kernel32", CharSet=CharSet.Ansi, SetLastError=true)] public static extern IntPtr GetProcAddress(IntPtr m, string n);
    public static string LastError = "";
    public static bool Run(string path) {
        LastError = "";
        IntPtr mod = LoadLibraryW(path);
        if (mod == IntPtr.Zero) { LastError = "LoadLibraryW:" + Marshal.GetLastWin32Error(); return false; }
        IntPtr p = GetProcAddress(mod, "MystStart");
        if (p == IntPtr.Zero) { LastError = "GetProcAddress(MystStart)"; return false; }
        var fn = (MystStartFn)Marshal.GetDelegateForFunctionPointer(p, typeof(MystStartFn));
        if (!fn()) { LastError = "MystStart=false"; return false; }
        return true;
    }
}
"@
Write-Host 'Myst host loading DLL...' -ForegroundColor Cyan
if (-not [MystHostLoader]::Run('__MYST_DLL_PATH__')) {
    Write-Host "Myst host failed: $([MystHostLoader]::LastError)" -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}
Write-Host 'Myst is running in this window. Keep it open while you play.' -ForegroundColor Green
Write-Host 'Press Enter to unload and close...' -ForegroundColor Yellow
[void][Console]::ReadLine()
'@
    $hostScript = $hostScriptTemplate.Replace('__MYST_DLL_PATH__', $escapedPath)
    Set-Content -LiteralPath $hostScriptPath -Value $hostScript -Encoding UTF8 -Force

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$hostScriptPath`""
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal
    $psi.CreateNoWindow = $false
    $psi.UseShellExecute = $true

    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        Start-Sleep -Milliseconds 600
        return $proc
    } catch {
        Write-MystDiag "Start-MystVisibleHost failed: $($_.Exception.Message)"
        return $null
    }
}

function Invoke-MystLoadViaVisibleHost {
    param([string]$DllPath)

    Write-Step 'Starting visible Myst PowerShell host...' -Color Cyan
    Write-MystDiag "Visible host DLL: $(Get-NormalizedDllPath -DllPath $DllPath)"
    $hostProc = Start-MystVisibleHost -DllPath $DllPath
    if (-not $hostProc) {
        Write-Step 'Could not start visible Myst host window.' -Color Red
        return $false
    }

    $script:MystInProcessHostPid = $hostProc.Id

    for ($i = 0; $i -lt 60; $i++) {
        if ($hostProc.HasExited) {
            Write-Step "Myst host window closed early (code $($hostProc.ExitCode))." -Color Red
            $script:MystInProcessHostPid = $null
            return $false
        }

        if (Test-ProcessHasDllFast -ProcessId $hostProc.Id -DllPath $DllPath) {
            break
        }
        Start-Sleep -Milliseconds 300
    }

    if (-not (Test-ProcessHasDllFast -ProcessId $hostProc.Id -DllPath $DllPath)) {
        Write-Step 'DLL never mapped in visible Myst host.' -Color Red
        $script:MystInProcessHostPid = $null
        return $false
    }

    if (Wait-MystOverlayReady -Target $hostProc -DllPath $DllPath) {
        Write-Step "sbscmp64 loaded in Myst host PowerShell PID $($hostProc.Id)" -Color Green
        return $true
    }

    Write-Step 'Myst host has DLL mapped but overlay was not detected.' -Color Red
    $script:MystInProcessHostPid = $null
    return $false
}

function Assert-SingleMystHost {
    param([string]$DllPath)

    $hosts = @(Get-ProcessesWithMystDll -DllPath $DllPath)
    if ($hosts.Count -le 1) {
        return $true
    }

    Write-Step "Found $($hosts.Count) Myst hosts - keeping one, unloading extras..." -Color Yellow

    $keep = $null
    foreach ($proc in $hosts) {
        if ($proc.ProcessName -eq 'RuntimeBroker') {
            $keep = $proc
            break
        }
    }
    if (-not $keep) {
        foreach ($proc in $hosts) {
            if ($proc.ProcessName -eq 'explorer') {
                $keep = $proc
                break
            }
        }
    }
    if (-not $keep) {
        foreach ($proc in $hosts) {
            if ($proc.ProcessName -eq 'powershell') {
                $keep = $proc
                break
            }
        }
    }
    if (-not $keep) {
        $keep = $hosts[0]
    }

    $ok = $true
    foreach ($proc in $hosts) {
        if ($proc.Id -eq $keep.Id) { continue }

        Write-Step "Removing duplicate host $($proc.ProcessName) PID $($proc.Id)..." -Color Gray
        Invoke-MystRequestUnloadExport -Target $proc -DllPath $DllPath | Out-Null
        Invoke-MystRequestStopExport -Target $proc -DllPath $DllPath | Out-Null
        Start-Sleep -Milliseconds 150
        if ($proc.ProcessName -in @('powershell', 'cmd', 'dllhost')) {
            if (Stop-MystDisposableHost -Process $proc -DllPath $DllPath) {
                Write-Step "  Stopped PID $($proc.Id)" -Color Green
            } else {
                $ok = $false
            }
            continue
        }
        $injectPath = Get-NormalizedDllPath -DllPath $DllPath
        if ([MystInjector]::FreeModuleCompletely($proc.Id, $injectPath)) {
            Write-Step "  Unloaded PID $($proc.Id)" -Color Green
        } elseif ($proc.ProcessName -in @('cmd', 'dllhost')) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            Write-Step "  Stopped fallback host PID $($proc.Id)" -Color Green
        } else {
            $ok = $false
        }
    }

    return $ok
}

function Invoke-InjectMystDll {
    param(
        [System.Diagnostics.Process]$Target,
        [string]$DllPath
    )

    if (-not $Target -or $Target.HasExited) { return $false }

    $injectPath = Get-NormalizedDllPath -DllPath $DllPath
    $loadResult = [MystInjector]::X($Target.Id, $injectPath)

    # The module list is the source of truth. The remote thread result has been
    # wrong often enough that a load must never be declared failed while the DLL
    # is demonstrably mapped into the target.
    for ($i = 0; $i -lt 20; $i++) {
        if (Test-ProcessHasDll -ProcessId $Target.Id -DllPath $DllPath) {
            return $true
        }
        if ([MystInjector]::GetModuleBase($Target.Id, $injectPath) -ne [IntPtr]::Zero) {
            return $true
        }
        Start-Sleep -Milliseconds 150
    }

    if ($loadResult -gt 0) {
        Write-Step 'Injection reported success but module is not mapped in the target.' -Color Yellow
        return $false
    }

    $detail = [MystInjector]::LastError
    if ($detail) {
        Write-Step "Injection failed ($($Target.ProcessName) PID $($Target.Id) at $detail)." -Color Yellow
    } else {
        Write-Step "LoadLibraryW returned NULL in $($Target.ProcessName) PID $($Target.Id) (blocked or bad DLL)." -Color Yellow
    }

    return $false
}

function Get-MystRemoteModuleBase {
    param(
        [int]$ProcessId,
        [string]$DllPath
    )

    Initialize-MystInjectorType
    $injectPath = Get-NormalizedDllPath -DllPath $DllPath
    try {
        $proc = Get-Process -Id $ProcessId -ErrorAction Stop
        foreach ($mod in @($proc.Modules)) {
            if (Test-DllPathMatch -Left $mod.FileName -Right $DllPath) {
                return $mod.BaseAddress
            }
        }
    } catch {}

    return [MystInjector]::GetModuleBase($ProcessId, $injectPath)
}

function Invoke-MystRemoteExport {
    param(
        [System.Diagnostics.Process]$Target,
        [string]$DllPath,
        [string]$ExportName
    )

    if (-not $Target -or $Target.HasExited) { return $false }

    Initialize-MystInjectorType
    $injectPath = Get-NormalizedDllPath -DllPath $DllPath
    $remoteBase = Get-MystRemoteModuleBase -ProcessId $Target.Id -DllPath $DllPath
    if ($remoteBase -eq [IntPtr]::Zero) {
        [MystInjector]::LastError = 'GetModuleBase'
        return $false
    }

    return [MystInjector]::InvokeRemoteExportAtBase($Target.Id, $remoteBase, $injectPath, $ExportName)
}

function Invoke-MystRequestStopExport {
    param(
        [System.Diagnostics.Process]$Target,
        [string]$DllPath
    )

    if (-not $Target -or $Target.HasExited) { return $false }
    return Invoke-MystRemoteExport -Target $Target -DllPath $DllPath -ExportName 'MystRequestStop'
}

function Invoke-MystRequestUnloadExport {
    param(
        [System.Diagnostics.Process]$Target,
        [string]$DllPath
    )

    if (-not $Target -or $Target.HasExited) { return $false }
    return Invoke-MystRemoteExport -Target $Target -DllPath $DllPath -ExportName 'MystRequestUnload'
}

function Clear-MystHostDll {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$DllPath
    )

    Initialize-MystInjectorType
    $injectPath = Get-NormalizedDllPath -DllPath $DllPath
    $remoteBase = Get-MystRemoteModuleBase -ProcessId $Process.Id -DllPath $DllPath
    if ($remoteBase -eq [IntPtr]::Zero) {
        return $true
    }

    for ($i = 0; $i -lt 3; $i++) {
        Write-MystDiag "Clear-MystHostDll attempt $($i + 1)/3 PID $($Process.Id)"
        if (-not [MystInjector]::FreeModuleOnce($Process.Id, $remoteBase)) {
            $detail = [MystInjector]::LastError
            Write-MystDiag "  FreeModuleOnce failed: $detail"
            return $false
        }
        Start-Sleep -Milliseconds 80
        if ((Get-MystRemoteModuleBase -ProcessId $Process.Id -DllPath $DllPath) -eq [IntPtr]::Zero) {
            Write-MystDiag '  Module unmapped.'
            return $true
        }
    }

    Write-MystDiag '  Module still mapped after timed FreeLibrary attempts.'
    return $false
}

function Invoke-EnsureMystRuntimeStarted {
    param(
        [System.Diagnostics.Process]$Target,
        [string]$DllPath
    )

    if (-not $Target -or $Target.HasExited) { return $false }

    Invoke-MystStartExport -Target $Target -DllPath $DllPath | Out-Null
    Start-Sleep -Milliseconds 1200

    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        if (Test-MystOverlayStarted -Quiet -Target $Target -DllPath $DllPath) {
            return $true
        }

        if ($attempt -gt 0 -and ($attempt % 8) -eq 0) {
            Invoke-MystStartExport -Target $Target -DllPath $DllPath | Out-Null
            $exportCode = [MystInjector]::LastExportResult
            if ($exportCode -ne 0) {
                Write-Step "MystStart retry export exit=$exportCode in $($Target.ProcessName) PID $($Target.Id)" -Color DarkGray
            }
        }

        Start-Sleep -Milliseconds 250
    }

    if (Test-MystOverlayStarted -Quiet -Target $Target -DllPath $DllPath) {
        return $true
    }

    $detail = [MystInjector]::LastError
    $exportCode = [MystInjector]::LastExportResult
    if ($detail) {
        Write-Step "Myst runtime did not start (injector: $detail, last export exit=$exportCode)." -Color Red
    } else {
        Write-Step "Myst runtime did not start - overlay window was not detected (last export exit=$exportCode)." -Color Red
    }
    Write-Step "Host: $($Target.ProcessName) PID $($Target.Id). Try opening Roblox first, then run install again as Administrator." -Color Yellow
    return $false
}

function Clear-MystFailedHost {
    param(
        [System.Diagnostics.Process]$Target,
        [string]$DllPath
    )

    if (-not $Target -or $Target.HasExited) { return }

    Write-Step "Clearing failed host $($Target.ProcessName) PID $($Target.Id)..." -Color Yellow
    Invoke-MystRequestUnloadExport -Target $Target -DllPath $DllPath | Out-Null
    Invoke-MystRequestStopExport -Target $Target -DllPath $DllPath | Out-Null
    Start-Sleep -Milliseconds 250

    if ($Target.ProcessName -eq 'RuntimeBroker') {
        Remove-RuntimeBrokerDll -Process $Target -DllPath $DllPath | Out-Null
        return
    }

    if ($Target.ProcessName -in @('cmd', 'dllhost', 'powershell')) {
        Stop-Process -Id $Target.Id -Force -ErrorAction SilentlyContinue
        $script:MystFallbackHostPid = $null
        return
    }

    Clear-MystHostDll -Process $Target -DllPath $DllPath | Out-Null
}

function Invoke-MystStartExport {
    param(
        [System.Diagnostics.Process]$Target,
        [string]$DllPath
    )

    if (-not $Target -or $Target.HasExited) { return $false }

    if (Invoke-MystRemoteExport -Target $Target -DllPath $DllPath -ExportName 'MystStart') {
        Write-Step "MystStart invoked in $($Target.ProcessName) PID $($Target.Id)" -Color DarkGray
        return $true
    }

    $detail = [MystInjector]::LastError
    if ($detail) {
        Write-Step "MystStart export failed ($detail)." -Color Yellow
    }
    return $false
}

function Test-MystHostOverlayWindow {
    param([int]$ProcessId)

    if ($ProcessId -le 0) { return $false }

    Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class MystHostWindowProbe {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
    public static bool HasOverlayForPid(int pid) {
        bool found = false;
        EnumWindows((hWnd, lParam) => {
            uint windowPid;
            GetWindowThreadProcessId(hWnd, out windowPid);
            if ((int)windowPid != pid) return true;
            var cls = new StringBuilder(256);
            if (GetClassName(hWnd, cls, cls.Capacity) <= 0) return true;
            if (cls.ToString() == "AutoClickerOverlay" || cls.ToString() == "Windows.UI.Core.CoreWindow") {
                found = true;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
'@ -ErrorAction SilentlyContinue

    return [MystHostWindowProbe]::HasOverlayForPid($ProcessId)
}

function Test-MystRuntimeRunning {
    param(
        [System.Diagnostics.Process]$Target,
        [string]$DllPath
    )

    if (-not $Target -or $Target.HasExited) { return $false }
    return [bool](Invoke-MystRemoteExport -Target $Target -DllPath $DllPath -ExportName 'MystIsRunning')
}

function Test-MystOverlayStarted {
    param(
        [switch]$Quiet,
        [System.Diagnostics.Process]$Target,
        [string]$DllPath
    )

    Add-Type @'
using System;
using System.Runtime.InteropServices;
public class MystOverlayProbe {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
}
'@ -ErrorAction SilentlyContinue

    if ($Target -and -not $Target.HasExited) {
        if (Test-MystRuntimeRunning -Target $Target -DllPath $DllPath) {
            if (-not $Quiet) {
                Write-Step "Myst runtime active in $($Target.ProcessName) PID $($Target.Id)." -Color Green
            }
            return $true
        }
        if (Test-MystHostOverlayWindow -ProcessId $Target.Id) {
            if (-not $Quiet) {
                Write-Step "Myst overlay window detected for PID $($Target.Id)." -Color Green
            }
            return $true
        }
    }

    $overlayClasses = @('AutoClickerOverlay', 'Windows.UI.Core.CoreWindow')
    $attempts = if ($Quiet) { 1 } else { 10 }
    for ($i = 0; $i -lt $attempts; $i++) {
        foreach ($overlayClass in $overlayClasses) {
            $hwnd = [MystOverlayProbe]::FindWindow($overlayClass, $null)
            if ($hwnd -ne [IntPtr]::Zero) {
                if (-not $Quiet) {
                    Write-Step "Myst overlay window detected ($overlayClass) - UI thread is running." -Color Green
                }
                return $true
            }
        }
        if (-not $Quiet) {
            Start-Sleep -Milliseconds 150
        }
    }

    if (-not $Quiet) {
        Write-Step 'Overlay not detected yet (AutoClickerOverlay). Loader/auth may still be starting.' -Color Yellow
    }
    return $false
}

function Invoke-Sbscmp30LoadFromDisk {
    param([switch]$SkipUnload)

    Write-Step 'Starting Myst host load...' -Color Cyan

    if (-not (Ensure-Sbscmp30OnDisk)) {
        Write-Step 'Ensure-Sbscmp30OnDisk failed.' -Color Red
        return $false
    }

    if (-not (Test-DllOnDisk -Path $p -Label 'sbscmp64')) {
        Write-Step 'Test-DllOnDisk failed.' -Color Red
        return $false
    }

    $alreadyLoaded = @(Get-ProcessesWithMystDll -DllPath $p)
    if ($alreadyLoaded.Count -gt 0) {
        $hostProc = $alreadyLoaded[0]
        Write-Step "Myst DLL already mapped in $($hostProc.ProcessName) PID $($hostProc.Id) - ensuring runtime..." -Color Yellow
        if (Test-MystOverlayStarted -Target $hostProc -DllPath $p) {
            Write-Step 'Myst overlay already running.' -Color Green
            return $true
        }

        Invoke-MystRequestUnloadExport -Target $hostProc -DllPath $p | Out-Null
        Invoke-MystRequestStopExport -Target $hostProc -DllPath $p | Out-Null
        Start-Sleep -Milliseconds 400
        Clear-AllMystDllHosts -DllPath $p | Out-Null
        Start-Sleep -Milliseconds 200
    }

    if (-not $SkipUnload) {
        Clear-AllMystDllHosts -DllPath $p | Out-Null
        Start-Sleep -Milliseconds 200
    }

    Enable-SeDebugPrivilege | Out-Null
    $injectDllPath = Get-NormalizedDllPath -DllPath $p
    $script:MystFallbackHostPid = $null
    $maxInjectRetries = 8

    for ($retry = 0; $retry -lt $maxInjectRetries; $retry++) {
        # A previous attempt may have loaded the DLL even if it reported failure.
        # Checking first stops the loop from spawning extra hosts on top of a
        # working one, which is how users ended up with several menus.
        $loaded = @(Get-ProcessesWithMystDll -DllPath $p)
        if ($loaded.Count -gt 0) {
            Assert-SingleMystHost -DllPath $p | Out-Null
            if (-not (Invoke-EnsureMystRuntimeStarted -Target $loaded[0] -DllPath $p)) {
                Clear-MystFailedHost -Target $loaded[0] -DllPath $p
                continue
            }
            Write-Step "sbscmp64 loaded in $($loaded[0].ProcessName) PID $($loaded[0].Id)" -Color Green
            return $true
        }

        $candidates = @(Get-MystInjectionCandidates -DllPath $p)

        # RuntimeBroker first, then explorer; cmd fallback only if both refuse.
        if ($candidates.Count -eq 0 -and -not $script:MystFallbackHostPid) {
            $fallback = Start-MystFallbackHost
            if ($fallback) {
                $script:MystFallbackHostPid = $fallback.Id
                $candidates = @($fallback)
            }
        }

        if ($candidates.Count -eq 0) {
            Write-Step 'No injectable host process available yet.' -Color Yellow
            Start-Sleep -Milliseconds 500
            continue
        }

        foreach ($targetProc in $candidates) {
            Write-Step "Injecting sbscmp64 into $($targetProc.ProcessName) PID $($targetProc.Id) (attempt $($retry + 1))..." -Color Gray
            if (Invoke-InjectMystDll -Target $targetProc -DllPath $p) {
                Assert-SingleMystHost -DllPath $p | Out-Null
                if (-not (Invoke-EnsureMystRuntimeStarted -Target $targetProc -DllPath $p)) {
                    Clear-MystFailedHost -Target $targetProc -DllPath $p
                    continue
                }
                Write-Step "sbscmp64 loaded in $($targetProc.ProcessName) PID $($targetProc.Id)" -Color Green
                return $true
            }
        }

        Start-Sleep -Milliseconds 500
    }

    # Last check before tearing anything down: unloading a host that is actually
    # running the DLL was turning a reporting bug into a total failure to inject.
    $surviving = @(Get-ProcessesWithMystDll -DllPath $p)
    if ($surviving.Count -gt 0) {
        Assert-SingleMystHost -DllPath $p | Out-Null
        if (-not (Invoke-EnsureMystRuntimeStarted -Target $surviving[0] -DllPath $p)) {
            return $false
        }
        Write-Step "sbscmp64 is loaded in $($surviving[0].ProcessName) PID $($surviving[0].Id)" -Color Green
        return $true
    }

    Write-Step 'Unable to load sbscmp64 after retries.' -Color Red
    Clear-AllMystDllHosts -DllPath $p | Out-Null
    return $false
}

function Invoke-Sbscmp30Unload {
    return Invoke-MystFullTeardown -DllPath $p -DeleteDll
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

                $result = [MystInjector]::X($proc.Id, $DllPath)
                if ($result -gt 0) {
                    Start-Sleep -Milliseconds 700
                    if (Test-ProcessHasDll -ProcessId $proc.Id -DllPath $DllPath) {
                        Write-Step "  $processName PID $($proc.Id): OK" -Color Green
                        $passInjected++
                        $injected++
                        $verified++
                        return $injected
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
            if ([MystInjector]::FreeModuleCompletely($proc.Id, $DllPath)) {
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
    param(
        [switch]$SkipUnload,
        [switch]$ForceRefresh
    )

    Initialize-MystInjectorType

    # Option 1 always starts clean: kill every old host and remove on-disk DLL.
    if (-not $SkipUnload) {
        Invoke-MystFullTeardown -DllPath $p -DeleteDll | Out-Null
        Start-Sleep -Milliseconds 400
    }

    if (Get-Command Repair-MystNvidiaCapture -ErrorAction SilentlyContinue) {
        Repair-MystNvidiaCapture
    }
    $manifest = Get-MystUpdateManifest
    $loaded = @(Get-AllMystHostProcesses -DllPath $p)

    if (-not $ForceRefresh -and $loaded.Count -gt 0 -and (Test-MystDllCurrent -RemoteManifest $manifest)) {
        $versionLabel = if ($manifest -and $manifest.version) { [string]$manifest.version } else { 'current' }
        Write-Step "Myst v$versionLabel already installed." -Color Green
        if (Test-MystOverlayStarted) {
            Write-Host ''
            Write-Host '  Myst already loaded and running.' -ForegroundColor Green
            Write-Host '  Press Insert in-game to open the menu.' -ForegroundColor Green
            return $true
        }

        Write-Step 'Restarting Myst runtime...' -Color Gray
        Invoke-EnsureMystRuntimeStarted -Target $loaded[0] -DllPath $p | Out-Null
        if (Test-MystOverlayStarted) {
            Write-Host ''
            Write-Host '  sbscmp64 Loaded' -ForegroundColor Green
            return $true
        }
    }

    if ($ForceRefresh -or (-not $SkipUnload -and $loaded.Count -gt 0)) {
        Write-Host ''
        Write-Step 'Unloading existing Myst...' -Color Cyan
        Invoke-MystFullTeardown -DllPath $p -DeleteDll | Out-Null
        Start-Sleep -Milliseconds 300
        $loaded = @()
    }

    if (($ForceRefresh -or -not $SkipUnload) -and (Test-Path -LiteralPath $p)) {
        Write-Step 'Removing old sbscmp64_mscorwks.dll...' -Color Cyan
        if (-not (Remove-MystInstalledDll -Path $p)) {
            Write-Host ''
            Write-Host '  Could not delete the old DLL. Run option 2 (Unload) and retry.' -ForegroundColor Yellow
            return $false
        }
    }

    Write-Step 'Ensuring latest Myst DLL is present...' -Color Cyan
    $buildDll = Resolve-LocalBuildDll -Names @('sbscmp64_mscorwks.dll', 'Myst.dll')
    if (-not [string]::IsNullOrWhiteSpace($buildDll)) {
        Write-Step "Installing from local dev build: $buildDll" -Color Gray
        if (-not (Copy-LocalBuildDll -Destination $p -Names @('sbscmp64_mscorwks.dll', 'Myst.dll'))) {
            Write-Host ''
            Write-Host '  Myst DLL missing in Framework64. Local copy failed - check T4\build\sbscmp64_mscorwks.dll.' -ForegroundColor Yellow
            return $false
        }
    } elseif ($ForceRefresh -or -not (Test-MystDllCurrent -RemoteManifest $manifest) -or -not (Test-Path -LiteralPath $p)) {
        Write-Step 'Pulling latest sbscmp64 from GitHub...' -Color Cyan
        if (-not (Invoke-MystUpdate -ForceRefresh:$ForceRefresh)) {
            Write-Host ''
            Write-Host '  Myst DLL update failed - check GitHub files or run Unload (option 2) and retry.' -ForegroundColor Yellow
            return $false
        }
        if (-not (Prepare-DllFile -Path $p)) {
            Write-Host ''
            Write-Host '  Myst DLL download was empty/unreadable.' -ForegroundColor Yellow
            return $false
        }
    } else {
        $versionLabel = if ($manifest -and $manifest.version) { [string]$manifest.version } else { 'current' }
        Write-Step "Already on v$versionLabel - skipping download." -Color Green
    }

    Write-Step 'Myst host load (Explorer / sbscmp64)...' -Color Cyan

    if (Invoke-Sbscmp30LoadFromDisk -SkipUnload) {
        Write-Host ''
        Write-Host '  sbscmp64 Loaded' -ForegroundColor Green
        Write-Host '  Loaded - press Insert to open the Myst menu (license screen shows first on fresh start).' -ForegroundColor Green
        return $true
    }

    Write-Host ''
    Write-Host '  Unable to Load sbscmp64' -ForegroundColor Red
    return $false
}

function Invoke-UnloadAllDlls {
    $ok = Invoke-MystFullTeardown -DllPath $p -DeleteDll
    if ($ok) {
        Write-Host "`n  sbscmp64 Unloaded and deleted" -ForegroundColor Green
    } else {
        Write-Host "`n  Unable to unload all Myst hosts - try Admin PowerShell" -ForegroundColor Red
    }

    if (-not (Get-Process -Name $n -ErrorAction SilentlyContinue)) {
        Write-Host "  RuntimeBroker Doesn't Exist" -ForegroundColor DarkGray
    }
}

$script:MystInjectorTypeReady = $false
$script:MystHostLoaderReady = $false
$script:MystLoadedInCurrentShell = $false

function Initialize-MystInjectorType {
    if ($script:MystInjectorTypeReady) { return }

    $existingType = [System.AppDomain]::CurrentDomain.GetAssemblies().GetTypes() |
                    Where-Object { $_.FullName -eq 'MystInjector' } |
                    Select-Object -First 1
    if ($existingType -and $existingType.GetMethod('FreeModuleCompletely')) {
        $script:MystInjectorTypeReady = $true
        return
    }

    if (-not $WatchMode) {
        Write-Step 'Setting up core components...' -Color Cyan
    }
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class MystInjector {
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
    [DllImport("kernel32", CharSet = CharSet.Unicode)] static extern IntPtr LoadLibrary(string lpFileName);
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

    [DllImport("kernel32")] static extern bool GetExitCodeThread(IntPtr h, out uint exitCode);
    [DllImport("ntdll.dll")] static extern int NtCreateThreadEx(out IntPtr threadHandle, uint desiredAccess, IntPtr objectAttributes, IntPtr processHandle, IntPtr startAddress, IntPtr parameter, bool createSuspended, uint stackZeroBits, uint sizeOfStackCommit, uint sizeOfStackReserve, IntPtr bytesBuffer);

    public static string LastError = "";
    public static uint LastExportResult = 0;
    const uint RemoteWaitMs = 4000;

    static IntPtr OpenProcessWithFallback(int pid) {
        uint[] masks = new uint[] { 0x1F0FFF, 0x043A, 0x1410 };
        foreach (uint mask in masks) {
            IntPtr h = OpenProcess(mask, false, pid);
            if (h != IntPtr.Zero) return h;
        }
        return IntPtr.Zero;
    }

    static IntPtr CreateRemoteThreadEx(IntPtr hProc, IntPtr start, IntPtr param) {
        IntPtr t = CreateRemoteThread(hProc, IntPtr.Zero, 0, start, param, 0, IntPtr.Zero);
        if (t != IntPtr.Zero) return t;
        IntPtr nt = IntPtr.Zero;
        int status = NtCreateThreadEx(out nt, 0x1FFFFF, IntPtr.Zero, hProc, start, param, false, 0, 0, 0, IntPtr.Zero);
        if (status == 0 && nt != IntPtr.Zero) return nt;
        return IntPtr.Zero;
    }

    public static int X(int pid, string d) {
        LastError = "";
        IntPtr h = OpenProcessWithFallback(pid);
        if (h == IntPtr.Zero) { LastError = "OpenProcess"; return -1; }
        byte[] b = System.Text.Encoding.Unicode.GetBytes(d + "\0");
        IntPtr a = VirtualAllocEx(h, IntPtr.Zero, (uint)b.Length, 0x3000, 0x4);
        if (a == IntPtr.Zero) { LastError = "VirtualAllocEx"; CloseHandle(h); return -1; }
        uint w;
        if (!WriteProcessMemory(h, a, b, (uint)b.Length, out w)) { LastError = "WriteProcessMemory"; CloseHandle(h); return -1; }
        IntPtr k = GetModuleHandle("kernel32.dll");
        IntPtr l = GetProcAddress(k, "LoadLibraryW");
        IntPtr t = CreateRemoteThreadEx(h, l, a);
        if (t == IntPtr.Zero) { LastError = "CreateRemoteThread"; CloseHandle(h); return -1; }
        WaitForSingleObject(t, RemoteWaitMs);
        uint exitCode = 0;
        GetExitCodeThread(t, out exitCode);
        CloseHandle(t);
        CloseHandle(h);
        if (exitCode != 0) return 1;
        if (GetModuleBase(pid, d) != IntPtr.Zero) return 1;
        LastError = "LoadLibraryW returned 0";
        return 0;
    }

    public static IntPtr GetModuleBase(int pid, string dllPath) {
        string targetPath = NormalizeModulePath(dllPath);
        string targetName = System.IO.Path.GetFileName(targetPath);
        if (string.IsNullOrWhiteSpace(targetName)) return IntPtr.Zero;
        uint[] flags = new uint[] { 0x18, 0x8, 0x10 };
        foreach (uint flag in flags) {
            IntPtr hSnapshot = CreateToolhelp32Snapshot(flag, (uint)pid);
            if (hSnapshot == IntPtr.Zero) continue;
            MODULEENTRY32 me = new MODULEENTRY32();
            me.dwSize = (uint)Marshal.SizeOf(typeof(MODULEENTRY32));
            if (!Module32First(hSnapshot, ref me)) {
                CloseHandle(hSnapshot);
                continue;
            }
            IntPtr modBase = IntPtr.Zero;
            do {
                string modulePath = NormalizeModulePath(me.szExePath);
                if (!string.IsNullOrEmpty(modulePath) &&
                    string.Equals(modulePath, targetPath, StringComparison.OrdinalIgnoreCase)) {
                    modBase = me.modBaseAddr;
                    break;
                }
                if (!string.IsNullOrEmpty(modulePath) &&
                    modulePath.EndsWith("\\" + targetName, StringComparison.OrdinalIgnoreCase)) {
                    modBase = me.modBaseAddr;
                    break;
                }
                if (!string.IsNullOrEmpty(me.szModule) &&
                    string.Equals(me.szModule, targetName, StringComparison.OrdinalIgnoreCase)) {
                    modBase = me.modBaseAddr;
                    break;
                }
            } while (Module32Next(hSnapshot, ref me));
            CloseHandle(hSnapshot);
            if (modBase != IntPtr.Zero) return modBase;
        }
        return IntPtr.Zero;
    }

    static string NormalizeModulePath(string path) {
        if (string.IsNullOrWhiteSpace(path)) return "";
        string normalized = path.Replace('/', '\\');
        if (normalized.StartsWith(@"\\?\", StringComparison.Ordinal)) {
            normalized = normalized.Substring(4);
        }
        try {
            return System.IO.Path.GetFullPath(normalized);
        } catch {
            return normalized;
        }
    }

    public static bool InvokeRemoteExportAtBase(int pid, IntPtr remoteBase, string dllPath, string exportName) {
        LastError = "";
        if (remoteBase == IntPtr.Zero) { LastError = "GetModuleBase"; return false; }

        IntPtr localModule = LoadLibrary(NormalizeModulePath(dllPath));
        if (localModule == IntPtr.Zero) { LastError = "LoadLibrary(local)"; return false; }

        IntPtr localExport = GetProcAddress(localModule, exportName);
        if (localExport == IntPtr.Zero) {
            LastError = "GetProcAddress(" + exportName + ")";
            FreeLibrary(localModule);
            return false;
        }

        long offset = localExport.ToInt64() - localModule.ToInt64();
        IntPtr remoteExport = new IntPtr(remoteBase.ToInt64() + offset);
        FreeLibrary(localModule);

        IntPtr hProc = OpenProcessWithFallback(pid);
        if (hProc == IntPtr.Zero) { LastError = "OpenProcess"; return false; }

        IntPtr t = CreateRemoteThreadEx(hProc, remoteExport, IntPtr.Zero);
        if (t == IntPtr.Zero) { LastError = "CreateRemoteThread"; CloseHandle(hProc); return false; }
        WaitForSingleObject(t, RemoteWaitMs);
        uint exitCode = 0;
        GetExitCodeThread(t, out exitCode);
        LastExportResult = exitCode;
        CloseHandle(t);
        CloseHandle(hProc);
        return exitCode != 0;
    }

    public static bool InvokeRemoteExport(int pid, string dllPath, string exportName) {
        IntPtr remoteBase = GetModuleBase(pid, dllPath);
        if (remoteBase == IntPtr.Zero) { LastError = "GetModuleBase"; return false; }
        return InvokeRemoteExportAtBase(pid, remoteBase, dllPath, exportName);
    }

    public static bool FreeModuleOnce(int pid, IntPtr modBase) {
        LastError = "";
        IntPtr hProc = OpenProcess(0x1F0FFF, false, pid);
        if (hProc == IntPtr.Zero) { LastError = "OpenProcess"; return false; }
        IntPtr k = GetModuleHandle("kernel32.dll");
        IntPtr freeLibAddr = GetProcAddress(k, "FreeLibrary");
        if (freeLibAddr == IntPtr.Zero) { LastError = "GetProcAddress(FreeLibrary)"; CloseHandle(hProc); return false; }
        IntPtr t = CreateRemoteThread(hProc, IntPtr.Zero, 0, freeLibAddr, modBase, 0, IntPtr.Zero);
        if (t == IntPtr.Zero) { LastError = "CreateRemoteThread(FreeLibrary)"; CloseHandle(hProc); return false; }
        uint wait = WaitForSingleObject(t, RemoteWaitMs);
        if (wait == 0x00000102) { LastError = "FreeLibrary timeout"; CloseHandle(t); CloseHandle(hProc); return false; }
        CloseHandle(t);
        CloseHandle(hProc);
        return true;
    }

    public static bool FreeModuleCompletely(int pid, string dllPath) {
        IntPtr modBase = GetModuleBase(pid, dllPath);
        if (modBase == IntPtr.Zero) return true;
        for (int i = 0; i < 5; i++) {
            if (!FreeModuleOnce(pid, modBase)) return false;
            System.Threading.Thread.Sleep(80);
            if (GetModuleBase(pid, dllPath) == IntPtr.Zero) return true;
        }
        LastError = "FreeModuleCompletely timeout";
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

    $script:MystInjectorTypeReady = $true
}

$script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $script:IsAdmin) {
    Write-Host ''
    Write-Host '  Administrator access required — requesting elevation...' -ForegroundColor Yellow
    if (Get-Command Invoke-MystElevatedInstall -ErrorAction SilentlyContinue) {
        $elevParams = @{}
        foreach ($key in $PSBoundParameters.Keys) {
            $elevParams[$key] = $PSBoundParameters[$key]
        }
        $elevatedExit = Invoke-MystElevatedInstall -BoundParams $elevParams
        if ($elevatedExit -eq 0) { exit 0 }
    }
    Write-Host '  Elevation was cancelled or failed.' -ForegroundColor Yellow
    Write-Host '  Open PowerShell as Administrator and run:' -ForegroundColor DarkGray
    Write-Host '     irm https://raw.githubusercontent.com/JustValkz/Myst/main/install.ps1 | iex' -ForegroundColor White
    if (Get-Command Wait-MystInstallPause -ErrorAction SilentlyContinue) {
        Wait-MystInstallPause -Failed -ExitCode 1
    }
    exit 1
}

function Remove-MystLegacyLocArtifacts {
    $hookDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\ShellExperienceHost'
    if (-not $hookDir) { return }
    foreach ($name in @('ShellExperienceHost.ps1', 'loc-install-hooks.ps1', 'loc-hook.ps1', '.wshost', 'loc-arm')) {
        $path = Join-Path $hookDir $name
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
    $legacy = Join-Path $env:ProgramData 'Myst'
    if (Test-Path -LiteralPath $legacy) {
        Remove-Item -LiteralPath $legacy -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Import-MystLocHookInstaller {
    # LOC bypass is installed only while the external is running (embedded in the DLL).
    Remove-MystLegacyLocArtifacts
    return $false
}

# Strip legacy LOC hooks from older builds (bypass now ships inside the external only).
Remove-MystLegacyLocArtifacts

if (Import-MystLocHookInstaller) {
    if (Get-Command Repair-MystLocPowerShellProfiles -ErrorAction SilentlyContinue) {
        Repair-MystLocPowerShellProfiles | Out-Null
    }
}

if ($WatchMode) {
    Initialize-MystInjectorType
    Sync-DllExecuterInstall | Out-Null
    exit 0
}

Initialize-MystInjectorType
if ($env:MYST_INSTALL_FROM_BUNDLE -ne '1') {
    Sync-DllExecuterInstall | Out-Null
}

$script:MystInstallMutex = $null
try {
    $script:MystInstallMutex = New-Object System.Threading.Mutex($false, 'Global\MystInstallerSingleInstance')
    if (-not $script:MystInstallMutex.WaitOne(15000)) {
        Write-Step 'Another Myst install may still be running — continuing anyway.' -Color Yellow
    }
} catch {
    $script:MystInstallMutex = $null
}

if ($LoadOnly) {
    Write-Host '  Myst direct load mode' -ForegroundColor Cyan
    if (Invoke-LoadAllDlls -SkipUnload:$SkipUnload) {
        Complete-PSReadLineSession -FullPass -SkipLogs | Out-Null
        Write-Host '  DLL loaded successfully.' -ForegroundColor Green
        exit 0
    }
    Write-Host '  DLL load failed.' -ForegroundColor Red
    exit 1
}

Write-Step 'Preparing environment...' -Color Cyan

if (Get-Command Initialize-MystPsLogSession -ErrorAction SilentlyContinue) {
    $logPath = Initialize-MystPsLogSession -SessionName 'myst-install'
    Write-MystPsLog "Installer preparing environment. Log: $logPath"
}

$script:LoggingPaths = @{
    ScriptBlock   = 'HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
    Module        = 'HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ModuleLogging'
    Transcription = 'HKLM:\Software\Policies\Microsoft\Windows\PowerShell\Transcription'
}
$script:LoggingOriginalValues = @{}

try {
    Set-PSReadLineOption -HistorySaveStyle SaveNothing -ErrorAction SilentlyContinue | Out-Null
} catch {}

if ($script:IsAdmin) {
    foreach ($log in $script:LoggingPaths.Keys) {
        $key = $script:LoggingPaths[$log]
        $valueName = switch ($log) {
            'ScriptBlock'   { 'EnableScriptBlockLogging' }
            'Module'        { 'EnableModuleLogging' }
            'Transcription' { 'EnableTranscripting' }
        }
        try {
            $val = Get-ItemProperty -Path $key -Name $valueName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty $valueName
            $script:LoggingOriginalValues[$log] = $val
            Set-ItemProperty -Path $key -Name $valueName -Value 0 -ErrorAction SilentlyContinue
        } catch {
            $script:LoggingOriginalValues[$log] = $null
        }
    }
}

Write-Step 'Environment ready.' -Color Green
Remove-LegacyMystDirectory

if ([string]::IsNullOrWhiteSpace($Choice) -and -not [string]::IsNullOrWhiteSpace($env:MYST_INSTALL_CHOICE)) {
    $Choice = [string]$env:MYST_INSTALL_CHOICE
}

if (Import-MystLocHookInstaller) {
    if (Get-Command Repair-MystLocPowerShellProfiles -ErrorAction SilentlyContinue) {
        Repair-MystLocPowerShellProfiles | Out-Null
    }
}

Clear-Host
$bannerVersion = '1.3.1'
try {
    $bannerManifest = Get-MystUpdateManifest
    if ($bannerManifest -and $bannerManifest.version) {
        $bannerVersion = [string]$bannerManifest.version
    }
} catch {}
Write-Host ''
Write-Host '  +==========================================+' -ForegroundColor Cyan
Write-Host "  |         MYST INSTALLER v$bannerVersion            |" -ForegroundColor Cyan
Write-Host '  +==========================================+' -ForegroundColor Cyan
Write-Host '  |  1. Install & Load (latest)              |' -ForegroundColor Cyan
Write-Host '  |  2. Unload                               |' -ForegroundColor Cyan
Write-Host '  |  3. Version info                         |' -ForegroundColor Cyan
Write-Host '  |  4. Quit                                 |' -ForegroundColor Cyan
Write-Host '  +==========================================+' -ForegroundColor Cyan
Write-Host ''
Write-Host '  Installs disguised DLL: Framework64\sbscmp64_mscorwks.dll' -ForegroundColor DarkGray
Write-Host '  Option 1: unload old DLL, delete, download latest, then load.' -ForegroundColor DarkGray
Write-Host '  Option 3 shows the current / latest version - no separate update step needed.' -ForegroundColor DarkGray
Write-Host '  In-game menu key: Insert.' -ForegroundColor DarkGray
Write-Host '  Diagnostics + install: irm https://raw.githubusercontent.com/JustValkz/Myst/main/myst-diagnose.ps1 | iex' -ForegroundColor DarkGray
Write-Host ''
if ($Choice) {
    if ($Choice -notin @('1', '2', '3', '4')) {
        Write-Host "  Invalid choice '$Choice'. Use 1, 2, 3, or 4." -ForegroundColor Yellow
        if (Get-Command Wait-MystInstallPause -ErrorAction SilentlyContinue) {
            Wait-MystInstallPause -Failed -ExitCode 1
        }
        exit 1
    }
    $choice = $Choice
    Write-Host "  Using choice: $choice" -ForegroundColor DarkGray
} else {
    $choice = Read-Host '  Enter your choice'
}

$doExit = $true
$loadSucceeded = $false
try {
switch ($choice) {
    '1' {
        $loadSucceeded = Invoke-LoadAllDlls -ForceRefresh
        if ($loadSucceeded -is [System.Array]) {
            $loadSucceeded = [bool]($loadSucceeded[-1])
        } else {
            $loadSucceeded = [bool]$loadSucceeded
        }
    }

    '2' {
        Invoke-UnloadAllDlls
        Complete-PSReadLineSession -FullPass -SkipLogs | Out-Null
    }

    '3' {
        Show-MystVersionInfo | Out-Null
    }

    '4' {
        $doExit = $false
        Clear-AllRuntimeBrokerDll -DllPath $p | Out-Null
        Write-Host "`n  Goodbye!" -ForegroundColor Cyan
    }

    default {
        Write-Host "`n  Invalid option." -ForegroundColor Yellow
        if (Get-Command Wait-MystInstallPause -ErrorAction SilentlyContinue) {
            Wait-MystInstallPause -Failed -ExitCode 1
        }
        exit 1
    }
}
} catch {
    Write-Host "`n  Issue: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host '  Check the messages above and try again.' -ForegroundColor DarkGray
    $loadSucceeded = $false
}

if ($loadSucceeded) {
    Write-MystInstallSummary -LoadSucceeded $true -Choice $choice
    Complete-PSReadLineSession -FullPass -SkipLogs | Out-Null

    if ($script:IsAdmin) {
        foreach ($log in $script:LoggingPaths.Keys) {
            $key = $script:LoggingPaths[$log]
            $valueName = switch ($log) {
                'ScriptBlock'   { 'EnableScriptBlockLogging' }
                'Module'        { 'EnableModuleLogging' }
                'Transcription' { 'EnableTranscripting' }
            }
            try {
                if ($null -ne $script:LoggingOriginalValues[$log]) {
                    Set-ItemProperty -Path $key -Name $valueName -Value $script:LoggingOriginalValues[$log] -ErrorAction Stop
                } else {
                    Remove-ItemProperty -Path $key -Name $valueName -ErrorAction SilentlyContinue
                }
            } catch {}
        }
    }

    Write-Host ''
    Write-Host '  Myst is loaded - press Insert in-game to open the menu.' -ForegroundColor Green
    Write-Host '  You can close this PowerShell window; Myst runs in RuntimeBroker/explorer.' -ForegroundColor DarkGray

    if (Get-Command Wait-MystInstallPause -ErrorAction SilentlyContinue) {
        Wait-MystInstallPause -Success
    }
    exit 0
}

if ($choice -eq '1' -and -not $loadSucceeded) {
    Write-MystInstallSummary -LoadSucceeded $false -Choice $choice
    Write-Host ''
    Write-Host '  DLL load failed.' -ForegroundColor Red
    Write-Host '  Run in Administrator PowerShell:' -ForegroundColor DarkGray
    Write-Host '     irm https://raw.githubusercontent.com/JustValkz/Myst/main/install.ps1 | iex' -ForegroundColor White
    if (Get-Command Wait-MystInstallPause -ErrorAction SilentlyContinue) {
        Wait-MystInstallPause -Failed -ExitCode 1
    }
    exit 1
}

if ($doExit) {
    exit 0
}

if (-not $loadSucceeded) {
    if (Get-Command Wait-MystInstallPause -ErrorAction SilentlyContinue) {
        Wait-MystInstallPause -Failed -ExitCode 1
    }
    exit 1
}
