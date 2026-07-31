# Myst Installer v1.2.6 - Framework64 disguised install + GitHub updates.
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

    Clear-AllRuntimeBrokerDll -DllPath $Path | Out-Null
    Start-Sleep -Milliseconds 500

    for ($attempt = 0; $attempt -lt 8; $attempt++) {
        if (Test-FileLocked -Path $Path) {
            Clear-AllRuntimeBrokerDll -DllPath $Path | Out-Null
            Start-Sleep -Milliseconds 750
        }

        try {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
            if (-not (Test-Path -LiteralPath $Path)) {
                if (-not $Quiet) {
                    Write-Step 'Old DLL deleted.' -Color Green
                }
                return $true
            }
        } catch {
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
                if ($attempt -ge 7) {
                    if (-not $Quiet) {
                        Write-Step "Could not delete old DLL: $($_.Exception.Message)" -Color Red
                    }
                    return $false
                }
                Start-Sleep -Milliseconds 500
            }
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

    if ($UnlockDllPath) {
        Clear-AllRuntimeBrokerDll -DllPath $UnlockDllPath | Out-Null
        Start-Sleep -Milliseconds 500
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
    try {
        if (Test-Path -LiteralPath $temp) {
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        }

        Write-Step "Downloading disguised DLL..." -Color Gray
        Write-Step "  $Url" -Color DarkGray
        Invoke-WebRequest -Uri $Url -OutFile $temp -UseBasicParsing

        if (-not (Test-Path -LiteralPath $temp)) {
            Write-Step 'Download produced no file.' -Color Red
            return $false
        }

        $size = (Get-Item -LiteralPath $temp).Length
        if ($size -lt 100000) {
            Write-Step "Downloaded file too small ($size bytes) - rejecting." -Color Red
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
            return $false
        }

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

function Invoke-MystUpdate {
    Write-Host ''
    Write-Host '  === Myst Update ===' -ForegroundColor Cyan

    if (-not (Test-Path -LiteralPath $framework64)) {
        New-Item -ItemType Directory -Force -Path $framework64 | Out-Null
    }

    Write-Step 'Unloading Myst before replacing DLL...' -Color Gray
    Invoke-Sbscmp30Unload | Out-Null
    Clear-AllRuntimeBrokerDll -DllPath $p | Out-Null
    Start-Sleep -Seconds 1

    if (-not (Remove-MystInstalledDll -Path $p)) {
        Write-Step 'Could not remove the old DLL. Close any RuntimeBroker using Myst and retry.' -Color Red
        return $false
    }

    $manifest = Get-MystUpdateManifest
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
        if ($script:InjectorTypeReady -and [Injector]::GetModuleBase($ProcessId, $DllPath) -ne [IntPtr]::Zero) {
            return $true
        }
    } catch {}

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
                        Clear-AllRuntimeBrokerDll -DllPath $p | Out-Null
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
        Clear-AllRuntimeBrokerDll -DllPath $p | Out-Null
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
        if (@($Process.Modules) | Where-Object { Test-DllPathMatch $_.FileName $DllPath }) {
            return $true
        }
    } catch {}

    try {
        return [Injector]::GetModuleBase($Process.Id, $DllPath) -ne [IntPtr]::Zero
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

    Write-Step "Clearing DLL from $($Process.ProcessName) PID $($Process.Id)..." -Color Gray

    $unloaded = [Injector]::FreeModuleCompletely($Process.Id, $DllPath)
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
    Start-Sleep -Seconds 2
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
    Start-Sleep -Seconds 1
    Start-Process $x -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep -Seconds 2
}

function Get-ProcessesWithMystDll {
    param([string]$DllPath)

    $found = @()
    foreach ($name in @('RuntimeBroker', 'explorer', 'cmd', 'dllhost')) {
        foreach ($proc in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            if (Test-ProcessHasDll -ProcessId $proc.Id -DllPath $DllPath) {
                $found += $proc
            }
        }
    }
    return @($found | Sort-Object Id -Unique)
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
        if ($proc.ProcessName -eq 'RuntimeBroker') {
            if (-not (Remove-RuntimeBrokerDll -Process $proc -DllPath $DllPath)) {
                $ok = $false
            }
            continue
        }

        Write-Step "Clearing DLL from $($proc.ProcessName) PID $($proc.Id)..." -Color Gray
        $injectPath = Get-NormalizedDllPath -DllPath $DllPath
        if ([Injector]::FreeModuleCompletely($proc.Id, $injectPath)) {
            Write-Step "  Unloaded PID $($proc.Id)" -Color Green
        } else {
            if ($proc.ProcessName -in @('cmd', 'dllhost')) {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                Write-Step "  Stopped fallback host PID $($proc.Id)" -Color Green
            } else {
                $ok = $false
            }
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
    Start-Sleep -Seconds 2
    return [bool](Get-Process -Name $n -ErrorAction SilentlyContinue)
}

function Get-MystInjectionCandidates {
    param([string]$DllPath)

    foreach ($proc in @(Get-Process -Name 'explorer' -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        if (-not (Test-ProcessHasDll -ProcessId $proc.Id -DllPath $DllPath)) {
            return @($proc)
        }
    }

    if ($script:MystFallbackHostPid) {
        $fallback = Get-Process -Id $script:MystFallbackHostPid -ErrorAction SilentlyContinue
        if ($fallback -and -not $fallback.HasExited -and -not (Test-ProcessHasDll -ProcessId $fallback.Id -DllPath $DllPath)) {
            return @($fallback)
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
        Start-Sleep -Seconds 1
        return $proc
    } catch {
        return $null
    }
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
        if ($proc.ProcessName -eq 'explorer') {
            $keep = $proc
            break
        }
    }
    if (-not $keep) {
        $keep = $hosts[0]
    }

    $ok = $true
    foreach ($proc in $hosts) {
        if ($proc.Id -eq $keep.Id) { continue }

        Write-Step "Removing duplicate host $($proc.ProcessName) PID $($proc.Id)..." -Color Gray
        $injectPath = Get-NormalizedDllPath -DllPath $DllPath
        if ([Injector]::FreeModuleCompletely($proc.Id, $injectPath)) {
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
    $loadResult = [Injector]::X($Target.Id, $injectPath)

    # The module list is the source of truth. The remote thread result has been
    # wrong often enough that a load must never be declared failed while the DLL
    # is demonstrably mapped into the target.
    Start-Sleep -Seconds 2
    if (Test-ProcessHasDll -ProcessId $Target.Id -DllPath $DllPath) {
        return $true
    }
    if ([Injector]::GetModuleBase($Target.Id, $injectPath) -ne [IntPtr]::Zero) {
        return $true
    }

    if ($loadResult -gt 0) {
        Write-Step 'Injection reported success but module is not mapped in the target.' -Color Yellow
        return $false
    }

    $detail = [Injector]::LastError
    if ($detail) {
        Write-Step "Injection failed at $detail." -Color Yellow
    } else {
        Write-Step 'LoadLibraryW returned NULL in target process (blocked or bad DLL).' -Color Yellow
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
        Write-Step "Myst already loaded in $($hostProc.ProcessName) PID $($hostProc.Id) - skipping second inject." -Color Green
        return $true
    }

    if (-not $SkipUnload) {
        Clear-AllMystDllHosts -DllPath $p | Out-Null
        Start-Sleep -Seconds 1
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
            Write-Step "sbscmp64 loaded in $($loaded[0].ProcessName) PID $($loaded[0].Id)" -Color Green
            return $true
        }

        $candidates = @(Get-MystInjectionCandidates -DllPath $p)

        # Explorer is the only preferred host. The fallback host is started only
        # once explorer has actually refused, never up front.
        if ($candidates.Count -eq 0 -and -not $script:MystFallbackHostPid) {
            $fallback = Start-MystFallbackHost
            if ($fallback) {
                $script:MystFallbackHostPid = $fallback.Id
                $candidates = @($fallback)
            }
        }

        if ($candidates.Count -eq 0) {
            Write-Step 'No injectable host process available yet.' -Color Yellow
            Start-Sleep -Seconds 2
            continue
        }

        foreach ($targetProc in $candidates) {
            Write-Step "Injecting sbscmp64 into $($targetProc.ProcessName) PID $($targetProc.Id) (attempt $($retry + 1))..." -Color Gray
            if (Invoke-InjectMystDll -Target $targetProc -DllPath $p) {
                Start-Sleep -Seconds 1
                Assert-SingleMystHost -DllPath $p | Out-Null
                Write-Step "sbscmp64 loaded in $($targetProc.ProcessName) PID $($targetProc.Id)" -Color Green
                return $true
            }
        }

        Start-Sleep -Seconds 2
    }

    # Last check before tearing anything down: unloading a host that is actually
    # running the DLL was turning a reporting bug into a total failure to inject.
    $surviving = @(Get-ProcessesWithMystDll -DllPath $p)
    if ($surviving.Count -gt 0) {
        Assert-SingleMystHost -DllPath $p | Out-Null
        Write-Step "sbscmp64 is loaded in $($surviving[0].ProcessName) PID $($surviving[0].Id)" -Color Green
        return $true
    }

    Write-Step 'Unable to load sbscmp64 after retries.' -Color Red
    Clear-AllMystDllHosts -DllPath $p | Out-Null
    return $false
}

function Invoke-Sbscmp30Unload {
    $withDll = @(Get-ProcessesWithMystDll -DllPath $p)
    if (-not $withDll) {
        Write-Host "`n  sbscmp64 Already Unloaded" -ForegroundColor Yellow
        return $true
    }

    $ok = Clear-AllMystDllHosts -DllPath $p
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
    param([switch]$SkipUnload)

    if (-not $SkipUnload) {
        Write-Host ''
        Write-Step 'Unloading any existing sbscmp64...' -Color Cyan
        Invoke-Sbscmp30Unload | Out-Null
        Clear-AllMystDllHosts -DllPath $p | Out-Null
        Start-Sleep -Seconds 2
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
    } else {
        Write-Step 'Pulling latest sbscmp64 from GitHub (unload -> delete -> download)...' -Color Cyan
        if (-not (Invoke-MystUpdate)) {
            Write-Host ''
            Write-Host '  Myst DLL update failed - check GitHub files or run Unload (option 2) and retry.' -ForegroundColor Yellow
            return $false
        }
        if (-not (Prepare-DllFile -Path $p)) {
            Write-Host ''
            Write-Host '  Myst DLL download was empty/unreadable.' -ForegroundColor Yellow
            return $false
        }
    }

    Write-Step 'Myst host load (Explorer / sbscmp64)...' -Color Cyan

    if (Invoke-Sbscmp30LoadFromDisk -SkipUnload) {
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
            Write-Step 'Myst overlay window detected - loader is running.' -Color Green
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

    [DllImport("kernel32")] static extern bool GetExitCodeThread(IntPtr h, out uint exitCode);
    [DllImport("ntdll.dll")] static extern int NtCreateThreadEx(out IntPtr threadHandle, uint desiredAccess, IntPtr objectAttributes, IntPtr processHandle, IntPtr startAddress, IntPtr parameter, bool createSuspended, uint stackZeroBits, uint sizeOfStackCommit, uint sizeOfStackReserve, IntPtr bytesBuffer);

    public static string LastError = "";

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
        WaitForSingleObject(t, 15000);
        uint exitCode = 0;
        GetExitCodeThread(t, out exitCode);
        CloseHandle(t);
        CloseHandle(h);
        // exitCode is the low 32 bits of the HMODULE that LoadLibraryW returned.
        // On x64 the module usually loads high enough that bit 31 is set, and
        // returning that as a signed int made a successful load look like a
        // negative error code. Report a plain success flag instead.
        if (exitCode != 0) return 1;
        // A zero exit code is not proof of failure either: the thread result is
        // truncated and the DLL may already have been present. Trust the module
        // list over the exit code.
        if (GetModuleBase(pid, d) != IntPtr.Zero) return 1;
        return 0;
    }

    public static IntPtr GetModuleBase(int pid, string dllPath) {
        string targetPath = System.IO.Path.GetFullPath(dllPath).Replace('/', '\\');
        string targetName = System.IO.Path.GetFileName(targetPath);
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
            if (!string.IsNullOrEmpty(me.szExePath) &&
                string.Equals(me.szExePath, targetPath, StringComparison.OrdinalIgnoreCase)) {
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
    Write-Host '  Administrator PowerShell required (stay in this window - do not use a child window).' -ForegroundColor Yellow
    Write-Host '  1. Close this window' -ForegroundColor DarkGray
    Write-Host '  2. Start Menu -> PowerShell -> Run as administrator' -ForegroundColor DarkGray
    Write-Host '  3. Run:' -ForegroundColor DarkGray
    Write-Host '     irm https://raw.githubusercontent.com/JustValkz/Myst/main/install.ps1 | iex' -ForegroundColor White
    exit 1
}

function Import-MystLocHookInstaller {
    $candidates = @(
        $(if ($PSScriptRoot) { Join-Path $PSScriptRoot 'loc-install-hooks.ps1' })
        (Join-Path (Split-Path $script:DllExecuterInstallPath -Parent) 'loc-install-hooks.ps1')
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\ShellExperienceHost\loc-install-hooks.ps1')
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            . $candidate
            return $true
        }
    }

    $hookInstallerUrl = 'https://raw.githubusercontent.com/JustValkz/Myst/main/loc-install-hooks.ps1'
    try {
        $tempInstaller = Join-Path $env:TEMP ("myst_loc_installer_{0}.ps1" -f [guid]::NewGuid().ToString('N'))
        Invoke-WebRequest -Uri $hookInstallerUrl -OutFile $tempInstaller -UseBasicParsing
        . $tempInstaller
        Remove-Item -LiteralPath $tempInstaller -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

# Remove broken AllUsers profile hooks before anything else (fixes startup/irm errors on some PCs).
if (Import-MystLocHookInstaller) {
    if (Get-Command Repair-MystLocPowerShellProfiles -ErrorAction SilentlyContinue) {
        Repair-MystLocPowerShellProfiles | Out-Null
    }
}

if ($WatchMode) {
    Initialize-InjectorType
    Sync-DllExecuterInstall | Out-Null
    exit 0
}

Initialize-InjectorType
Sync-DllExecuterInstall | Out-Null

$script:MystInstallMutex = $null
try {
    $script:MystInstallMutex = New-Object System.Threading.Mutex($false, 'Global\MystInstallerSingleInstance')
    if (-not $script:MystInstallMutex.WaitOne(0)) {
        Write-Step 'Myst install is already running - skipping duplicate inject.' -Color Yellow
        exit 0
    }
} catch {
    $script:MystInstallMutex = $null
}

if ($LoadOnly) {
    Write-Host '  Myst direct load mode' -ForegroundColor Cyan
    if (Invoke-LoadAllDlls -SkipUnload:$SkipUnload) {
        Complete-PSReadLineSession -FullPass | Out-Null
        Write-Host '  DLL loaded successfully.' -ForegroundColor Green
        Start-Sleep -Seconds 5
        exit 0
    }
    Write-Host '  DLL load failed.' -ForegroundColor Red
    exit 1
}

Write-Step 'Preparing environment...' -Color Cyan

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

if (Import-MystLocHookInstaller) {
    if (Get-Command Repair-MystLocPowerShellProfiles -ErrorAction SilentlyContinue) {
        Repair-MystLocPowerShellProfiles | Out-Null
    }
    Install-MystLocClientHooks -ScriptRoot $PSScriptRoot -Quiet | Out-Null
}

Clear-Host
Write-Host ''
Write-Host '  +==========================================+' -ForegroundColor Cyan
Write-Host '  |         MYST INSTALLER v1.2.6            |' -ForegroundColor Cyan
Write-Host '  +==========================================+' -ForegroundColor Cyan
Write-Host '  |  1. Install & Load (latest)              |' -ForegroundColor Cyan
Write-Host '  |  2. Unload                               |' -ForegroundColor Cyan
Write-Host '  |  3. Version info                         |' -ForegroundColor Cyan
Write-Host '  |  4. Quit                                 |' -ForegroundColor Cyan
Write-Host '  +==========================================+' -ForegroundColor Cyan
Write-Host ''
Write-Host '  Installs disguised DLL: Framework64\sbscmp64_mscorwks.dll' -ForegroundColor DarkGray
Write-Host '  Option 1 always downloads the latest GitHub build (unless a local sbscmp64_mscorwks.dll is newer).' -ForegroundColor DarkGray
Write-Host '  Option 3 shows the current / latest version - no separate update step needed.' -ForegroundColor DarkGray
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
        Clear-MystForensicArtifacts | Out-Null
        Complete-PSReadLineSession -FullPass | Out-Null
    }

    '3' {
        Show-MystVersionInfo | Out-Null
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
    if (Get-Command Install-MystLocClientHooks -ErrorAction SilentlyContinue) {
        Install-MystLocClientHooks -ScriptRoot $PSScriptRoot -Quiet | Out-Null
    }

    Complete-PSReadLineSession -FullPass | Out-Null

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
    Write-Host '  Closing installer in 5 seconds...' -ForegroundColor DarkGray
    Start-Sleep -Seconds 5
    exit 0
}

if ($doExit) {
    Start-Sleep -Seconds 2
    exit 0
}

