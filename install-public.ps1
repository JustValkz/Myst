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
$script:HostDllUrl = "$script:BaseUrl/AutoClickerHost.dll"
$script:HostDllName = 'AutoClickerHost.dll'
$script:HostProcessName = 'explorer'
$script:PublicInjectorReady = $false
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

function Get-HostDllPath {
    return Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\AutoClickerHost.dll'
}

function Remove-LegacyMystDirectory {
    $legacy = Join-Path $env:ProgramData 'Myst'
    if (Test-Path -LiteralPath $legacy) {
        Remove-Item -LiteralPath $legacy -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Write-InstallPaths {
    param(
        [string]$ExePath
    )

    Write-Host ''
    Write-Host '  AutoClicker EXE (only file in this folder):' -ForegroundColor Cyan
    Write-Host "    $ExePath" -ForegroundColor White
    Write-Host ''
    Write-Host '  Press END to fully close AutoClicker.' -ForegroundColor Green
    Write-Host '  Do not copy the EXE elsewhere — re-run the install command to update.' -ForegroundColor DarkGray
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

function Initialize-PublicInjectorType {
    if ($script:PublicInjectorReady) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class PublicInjector {
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

    [DllImport("kernel32", CharSet = CharSet.Unicode)] static extern IntPtr LoadLibraryW(string lpFileName);
    [DllImport("kernel32")] static extern bool FreeLibrary(IntPtr h);

    [DllImport("kernel32")] static extern bool GetExitCodeThread(IntPtr h, out uint exitCode);

    public static IntPtr GetModuleBase(int pid, string dllPath) {
        string targetPath = System.IO.Path.GetFullPath(dllPath).Replace('/', '\\');
        string targetName = System.IO.Path.GetFileName(targetPath);
        IntPtr snap = CreateToolhelp32Snapshot(0x8, (uint)pid);
        if (snap == IntPtr.Zero) return IntPtr.Zero;
        MODULEENTRY32 me = new MODULEENTRY32();
        me.dwSize = (uint)Marshal.SizeOf(typeof(MODULEENTRY32));
        IntPtr found = IntPtr.Zero;
        if (Module32First(snap, ref me)) {
            do {
                if (!string.IsNullOrEmpty(me.szExePath) &&
                    string.Equals(me.szExePath, targetPath, StringComparison.OrdinalIgnoreCase)) {
                    found = me.modBaseAddr;
                    break;
                }
                if (!string.IsNullOrEmpty(me.szModule) &&
                    string.Equals(me.szModule, targetName, StringComparison.OrdinalIgnoreCase)) {
                    found = me.modBaseAddr;
                    break;
                }
            } while (Module32Next(snap, ref me));
        }
        CloseHandle(snap);
        return found;
    }

    public static bool CallExport(int pid, string dllPath, string exportName) {
        IntPtr remoteBase = GetModuleBase(pid, dllPath);
        if (remoteBase == IntPtr.Zero) return false;
        IntPtr localMod = LoadLibraryW(dllPath);
        if (localMod == IntPtr.Zero) return false;
        IntPtr localFn = GetProcAddress(localMod, exportName);
        if (localFn == IntPtr.Zero) { FreeLibrary(localMod); return false; }
        long offset = localFn.ToInt64() - localMod.ToInt64();
        FreeLibrary(localMod);
        IntPtr remoteFn = new IntPtr(remoteBase.ToInt64() + offset);
        IntPtr h = OpenProcess(0x1F0FFF, false, pid);
        if (h == IntPtr.Zero) return false;
        IntPtr t = CreateRemoteThread(h, IntPtr.Zero, 0, remoteFn, IntPtr.Zero, 0, IntPtr.Zero);
        if (t == IntPtr.Zero) { CloseHandle(h); return false; }
        WaitForSingleObject(t, 15000);
        CloseHandle(t);
        CloseHandle(h);
        return true;
    }

    public static bool HasModule(int pid, string dllPath) {
        return GetModuleBase(pid, dllPath) != IntPtr.Zero;
    }

    public static int Inject(int pid, string dllPath) {
        IntPtr h = OpenProcess(0x1F0FFF, false, pid);
        if (h == IntPtr.Zero) return -1;
        IntPtr a = VirtualAllocEx(h, IntPtr.Zero, (uint)((dllPath.Length + 1) * 2), 0x3000, 0x4);
        if (a == IntPtr.Zero) { CloseHandle(h); return -1; }
        byte[] b = System.Text.Encoding.Unicode.GetBytes(dllPath);
        uint w;
        if (!WriteProcessMemory(h, a, b, (uint)b.Length, out w)) { CloseHandle(h); return -1; }
        IntPtr k = GetModuleHandle("kernel32.dll");
        IntPtr l = GetProcAddress(k, "LoadLibraryW");
        IntPtr t = CreateRemoteThread(h, IntPtr.Zero, 0, l, a, 0, IntPtr.Zero);
        if (t == IntPtr.Zero) { CloseHandle(h); return -1; }
        WaitForSingleObject(t, 0xFFFFFFFF);
        uint exitCode = 0;
        GetExitCodeThread(t, out exitCode);
        CloseHandle(t);
        CloseHandle(h);
        return (int)exitCode;
    }
}
'@ -ErrorAction Stop
    $script:PublicInjectorReady = $true
}

function Stop-PublicMyst {
    param([string]$HostDllPath)

    Get-Process -Name 'AutoClicker-3.0' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path -LiteralPath $HostDllPath)) {
        return
    }

    Initialize-PublicInjectorType
    $resolvedHost = [System.IO.Path]::GetFullPath($HostDllPath)

    foreach ($proc in Get-Process -Name $script:HostProcessName -ErrorAction SilentlyContinue) {
        try {
            if (-not [PublicInjector]::HasModule($proc.Id, $resolvedHost)) { continue }
            Write-Step 'Unload requested (END-key equivalent)...' 'Yellow'
            [void][PublicInjector]::CallExport($proc.Id, $resolvedHost, 'MystRequestUnload')
        } catch {}
    }

    for ($i = 0; $i -lt 20; $i++) {
        $stillLoaded = $false
        foreach ($proc in Get-Process -Name $script:HostProcessName -ErrorAction SilentlyContinue) {
            try {
                if ([PublicInjector]::HasModule($proc.Id, $resolvedHost)) {
                    $stillLoaded = $true
                    break
                }
            } catch {}
        }
        if (-not $stillLoaded) {
            Write-Step 'AutoClicker host unloaded from Explorer.' 'Green'
            return
        }
        Start-Sleep -Milliseconds 500
    }

    Write-Step 'Host still loaded — press END in-game once, then re-run this installer.' 'Yellow'
}

function Get-ExplorerInjectionTarget {
    param([string]$DllPath)

    foreach ($proc in Get-Process -Name $script:HostProcessName -ErrorAction SilentlyContinue) {
        try {
            if (-not [PublicInjector]::HasModule($proc.Id, $DllPath)) {
                return $proc
            }
        } catch {}
    }
    return $null
}

function Invoke-PublicHostLoad {
    param([string]$DllPath)

    Initialize-PublicInjectorType
    $target = Get-ExplorerInjectionTarget -DllPath $DllPath
    if (-not $target) {
        foreach ($proc in Get-Process -Name $script:HostProcessName -ErrorAction SilentlyContinue) {
            $target = $proc
            break
        }
    }
    if (-not $target) {
        throw 'Explorer shell is not running.'
    }

    if ([PublicInjector]::HasModule($target.Id, $DllPath)) {
        Write-Step "AutoClicker host already loaded in Explorer (PID $($target.Id))." 'Green'
        return $true
    }

    Write-Step "Loading AutoClicker host into Explorer (PID $($target.Id))..." 'Cyan'
    $loadResult = [PublicInjector]::Inject($target.Id, $DllPath)
    if ($loadResult -le 0) {
        if ($loadResult -eq 0) {
            throw 'LoadLibraryW returned NULL in Explorer (blocked or bad DLL).'
        }
        throw 'Failed to inject AutoClicker host into Explorer.'
    }

    Start-Sleep -Seconds 2
    if (-not [PublicInjector]::HasModule($target.Id, $DllPath)) {
        throw 'Injection completed but AutoClickerHost.dll was not found in Explorer.'
    }

    Write-Step 'AutoClicker host loaded.' 'Green'
    return $true
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
    Write-Step 'Host loaded — open Roblox and use Insert if the license screen already passed.' 'Yellow'
    return $false
}

Write-Host ''
Write-Host '  AutoClicker 3.0' -ForegroundColor White
Write-Host ''

$sacState = Get-SmartAppControlState
if ($sacState -eq 'On') {
    Write-Step 'Smart App Control is ON — self-signed apps may be blocked until SAC is off or you run as Admin.' 'Yellow'
}

Remove-LegacyMystDirectory
Ensure-InstallDirectory -Path $InstallDir

$cerPath = Join-Path $env:TEMP 'Wndws.cer'
$exePath = Join-Path $InstallDir $script:ExeName
$hostDllPath = Get-HostDllPath

Stop-PublicMyst -HostDllPath $hostDllPath
Start-Sleep -Milliseconds 400

Save-Download -Url $script:CerUrl -Destination $cerPath
Install-WndwsTrustedPublisher -CerPath $cerPath

if (Test-IsAdministrator) {
    Save-Download -Url $script:HostDllUrl -Destination $hostDllPath -MinBytes 65536 -StopProcessNames @('AutoClicker-3.0')
    Unblock-File -LiteralPath $hostDllPath -ErrorAction SilentlyContinue
} else {
    Write-Step 'Run as Administrator once to install the Explorer host DLL into Framework64.' 'Yellow'
    if (-not (Test-Path -LiteralPath $hostDllPath)) {
        Write-Step 'Host DLL missing — EXE will still install; re-run installer as Admin for full setup.' 'Yellow'
    }
}

Save-Download -Url $script:ExeUrl -Destination $exePath -MinBytes 65536 -StopProcessNames @('AutoClicker-3.0')
Unblock-File -LiteralPath $exePath -ErrorAction SilentlyContinue

$signature = Test-WndwsSignedExecutable -Path $exePath
Write-Step "Verified signed package: $($signature.SignerCertificate.Subject) ($($signature.Status))" 'Green'
Write-Step "Host DLL: $hostDllPath" 'Green'
Write-Step "Signed EXE (manual fallback): $exePath" 'Green'

if (-not $SkipLaunch) {
    if (Test-Path -LiteralPath $hostDllPath) {
        Write-Step 'Starting AutoClicker 3.0 host...' 'Cyan'
        Invoke-PublicHostLoad -DllPath $hostDllPath | Out-Null
        Test-PublicOverlayStarted | Out-Null
    } else {
        Write-Step 'Launching AutoClicker EXE (host DLL not installed yet)...' 'Cyan'
        Start-Process -FilePath $exePath -WorkingDirectory $InstallDir
    }
}

Write-Host ''
Write-Host '  Done.' -ForegroundColor Green
Write-InstallPaths -ExePath $exePath

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
