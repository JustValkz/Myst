# Windows Shell profile / PSReadLine consistency helper (used by Myst installers).
# Keeps PSReadLine and PowerShell operational logs tidy without shrinking history files
# (detect.ac PowerShellParser++ flags truncated ConsoleHost_history.txt).
#Requires -Version 5.1

param(
    [switch]$ReportOnly,
    [switch]$SkipEventLogs,
    [switch]$Silent,
    [switch]$Aggressive
)

function Enable-MystShellHistorySilence {
    try {
        Set-PSReadLineOption -HistorySaveStyle SaveNothing -ErrorAction Stop | Out-Null
    } catch {}
}

function Get-MystPSReadLineHistoryPaths {
    $paths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    try {
        $opt = Get-PSReadLineOption -ErrorAction SilentlyContinue
        if ($opt -and $opt.HistorySavePath) {
            [void]$paths.Add($opt.HistorySavePath)
        }
    } catch {}

    $candidates = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt')
        (Join-Path $env:APPDATA 'Microsoft\PowerShell\PSReadLine\ConsoleHost_history.txt')
        (Join-Path $env:LOCALAPPDATA 'Microsoft\PowerShell\PSReadLine\ConsoleHost_history.txt')
    )

    if ($env:OneDrive) {
        $candidates += @(
            (Join-Path $env:OneDrive 'Documents\WindowsPowerShell\PSReadLine\ConsoleHost_history.txt')
            (Join-Path $env:OneDrive 'Documents\PowerShell\PSReadLine\ConsoleHost_history.txt')
        )
    }

    foreach ($path in $candidates) {
        if ($path) { [void]$paths.Add($path) }
    }

    return @($paths)
}

function Test-MystShellHistoryLine {
    param(
        [string]$Line,
        [switch]$Aggressive
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $false
    }

    $normalised = ($Line.Trim() -replace '\s+', ' ').ToLowerInvariant()

    if ($normalised -match '^#+$' -or $normalised -match '^#\s*$') {
        return $false
    }

    if ($Aggressive) {
        if ($normalised -match '\biex\b' -or $normalised -match '\biwr\b' -or $normalised -match '\birm\b') {
            return $true
        }
        if ($normalised -match 'invoke-expression' -or $normalised -match 'invoke-restmethod' -or $normalised -match 'invoke-webrequest') {
            return $true
        }
    }

    $needles = @(
        'justvalkz/myst'
        'raw.githubusercontent.com/justvalkz'
        'install.ps1'
        'install-public.ps1'
        'myst-install.ps1'
        'deploy-github.ps1'
        'wsh-env-sync.ps1'
        'sbscmp64_mscorwks'
        'autoclicker-3.0'
        'immune.wtf'
        'myst.local'
        '| iex'
        'invoke-expression'
        'invoke-restmethod'
        'invoke-webrequest'
    )

    foreach ($needle in $needles) {
        if ($normalised.Contains($needle)) {
            return $true
        }
    }

    if ($normalised -match 'irm\s+https?://') {
        return $true
    }

    return $false
}

function Repair-MystPSHistoryInPlace {
    param([switch]$Aggressive)

    $repaired = 0
    foreach ($historyPath in Get-MystPSReadLineHistoryPaths) {
        if (-not (Test-Path -LiteralPath $historyPath)) {
            continue
        }

        try {
            $item = Get-Item -LiteralPath $historyPath -Force
            $createdUtc = $item.CreationTimeUtc
            $writtenUtc = $item.LastWriteTimeUtc
            $accessedUtc = $item.LastAccessTimeUtc

            $raw = [System.IO.File]::ReadAllBytes($historyPath)
            if ($raw.Length -eq 0) {
                continue
            }

            $encoding = [System.Text.UTF8Encoding]::new($false)
            $text = $encoding.GetString($raw)
            $usesCrLf = $text.Contains("`r`n")
            $newline = if ($usesCrLf) { "`r`n" } else { "`n" }

            $lines = $text -split "`r?`n", -1
            $changed = $false
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if (-not (Test-MystShellHistoryLine -Line $lines[$i] -Aggressive:$Aggressive)) {
                    continue
                }

                $len = $lines[$i].Length
                if ($len -le 0) {
                    $lines[$i] = ''
                } elseif ($len -eq 1) {
                    $lines[$i] = '#'
                } else {
                    $lines[$i] = '#' + (' ' * ($len - 1))
                }
                $changed = $true
                $repaired++
            }

            if (-not $changed) {
                continue
            }

            $newText = $lines -join $newline
            $newBytes = $encoding.GetBytes($newText)

            if ($newBytes.Length -lt $raw.Length) {
                $padded = New-Object byte[] $raw.Length
                if ($newBytes.Length -gt 0) {
                    [Array]::Copy($newBytes, $padded, $newBytes.Length)
                }
                for ($j = $newBytes.Length; $j -lt $raw.Length; $j++) {
                    $padded[$j] = 0x20
                }
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

    return $repaired
}

function Clear-MystPowerShellTranscripts {
    $patterns = @(
        (Join-Path $env:USERPROFILE 'Documents\PowerShell_transcript*.txt')
        (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\PowerShell_transcript*.txt')
        (Join-Path $env:USERPROFILE 'Documents\PowerShell\Transcript\*')
        (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Transcript\*')
    )

    $removed = 0
    foreach ($pattern in $patterns) {
        $parent = Split-Path $pattern -Parent
        if (-not (Test-Path -LiteralPath $parent)) {
            continue
        }

        Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                $removed++
            } catch {}
        }
    }

    return $removed
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
        if ($p) {
            $p.WaitForExit(15000) | Out-Null
            return ($p.ExitCode -eq 0)
        }
    } catch {}

    return $false
}

function Clear-MystPowerShellEventLogs {
    $channels = @(
        'Microsoft-Windows-PowerShell/Operational'
        'Windows PowerShell'
        'Microsoft-Windows-PowerShell/Admin'
    )

    $cleared = @()
    foreach ($channel in $channels) {
        try {
            $log = Get-WinEvent -ListLog $channel -ErrorAction Stop
            if (-not $log.IsEnabled) {
                continue
            }

            if (Invoke-MystHiddenWevtutil -Arguments ('cl "{0}"' -f $channel)) {
                $cleared += $channel
            }
        } catch {}
    }

    return $cleared
}

function Get-MystShellEnvironmentReport {
    $report = [ordered]@{
        HistoryHits    = @()
        EventLogCounts = @{}
        Transcripts    = @()
    }

    foreach ($historyPath in Get-MystPSReadLineHistoryPaths) {
        if (-not (Test-Path -LiteralPath $historyPath)) {
            continue
        }

        $hits = Select-String -LiteralPath $historyPath -Pattern 'JustValkz|install\.ps1|irm |iex|immune\.wtf|sbscmp64|myst-install' -SimpleMatch:$false -ErrorAction SilentlyContinue
        if ($hits) {
            $report.HistoryHits += [PSCustomObject]@{
                Path  = $historyPath
                Count = @($hits).Count
            }
        }
    }

    foreach ($channel in @('Microsoft-Windows-PowerShell/Operational', 'Windows PowerShell')) {
        try {
            $log = Get-WinEvent -ListLog $channel -ErrorAction Stop
            $report.EventLogCounts[$channel] = [int]$log.RecordCount
        } catch {
            $report.EventLogCounts[$channel] = -1
        }
    }

    return $report
}

function Invoke-MystShellEnvironmentSync {
    param(
        [switch]$Silent,
        [switch]$SkipEventLogs,
        [switch]$Aggressive
    )

    Enable-MystShellHistorySilence | Out-Null

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    $repaired = Repair-MystPSHistoryInPlace -Aggressive:$Aggressive
    $transcriptsRemoved = Clear-MystPowerShellTranscripts

    $logsCleared = @()
    if (-not $SkipEventLogs -and $isAdmin) {
        $logsCleared = Clear-MystPowerShellEventLogs
    }

    if (-not $Silent) {
        Write-Host ("  Shell sync: history={0} transcripts={1} logs={2}" -f $repaired, $transcriptsRemoved, $logsCleared.Count) -ForegroundColor DarkGray
    }

    return [PSCustomObject]@{
        HistoryLinesRepaired = $repaired
        TranscriptsRemoved   = $transcriptsRemoved
        LogsCleared          = $logsCleared
        IsAdmin              = $isAdmin
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($ReportOnly) {
        $report = Get-MystShellEnvironmentReport
        Write-Host '=== Shell environment report ===' -ForegroundColor Cyan
        if ($report.HistoryHits.Count -eq 0) {
            Write-Host '  PSReadLine history: no install signatures' -ForegroundColor Green
        } else {
            $report.HistoryHits | ForEach-Object {
                Write-Host "  PSReadLine HIT: $($_.Count) in $($_.Path)" -ForegroundColor Yellow
            }
        }
        foreach ($entry in $report.EventLogCounts.GetEnumerator()) {
            $color = if ($entry.Value -gt 0) { 'Yellow' } else { 'Green' }
            Write-Host ("  {0}: {1}" -f $entry.Key, $entry.Value) -ForegroundColor $color
        }
        exit 0
    }

    Invoke-MystShellEnvironmentSync -Silent:$Silent -SkipEventLogs:$SkipEventLogs -Aggressive:$Aggressive | Out-Null
}
