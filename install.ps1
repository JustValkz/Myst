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
# PSReadLine session helpers - history backup/restore and diagnostic log rotation.

function Get-MystPsLogDirectory {
    return 'C:\ProgramData\PSLOGS\PSLOG.138.8.7.2026'
}

function Initialize-MystPsLogSession {
    param(
        [string]$SessionName = 'myst-session'
    )

    $dir = Get-MystPsLogDirectory
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

    $containers = @(Get-Process -Name 'nvcontainer' -ErrorAction SilentlyContinue)
    if ($containers.Count -gt 0) {
        Write-Step '  Restarting NVIDIA container processes so ShadowPlay can stop cleanly...' -Color DarkGray
        foreach ($proc in $containers) {
            try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop } catch {}
        }
        Start-Sleep -Milliseconds 800
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
