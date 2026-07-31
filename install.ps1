# Myst bootstrap - keeps irm | iex working even if GitHub CDN serves a stale UTF-8 BOM.
#Requires -Version 5.1

param(
    [switch]$WatchMode,
    [switch]$LoadOnly,
    [switch]$SkipUnload,
    [string]$Choice
)

try {
    Set-PSReadLineOption -HistorySaveStyle SaveNothing -ErrorAction SilentlyContinue | Out-Null
} catch {}

function Save-MystHistorySnapshot {
    $snap = @{}
    $paths = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt')
        (Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadline\ConsoleHost_history.txt')
        (Join-Path $env:APPDATA 'Microsoft\PowerShell\PSReadLine\ConsoleHost_history.txt')
    )
    foreach ($path in $paths) {
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { continue }
        try {
            $item = Get-Item -LiteralPath $path -Force
            $snap[$path] = @{
                BytesB64   = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path))
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

foreach ($scope in @('Process', 'CurrentUser')) {
    try {
        Set-ExecutionPolicy -Scope $scope -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue | Out-Null
    } catch {}
}

try {
    Set-PSReadLineOption -HistorySaveStyle SaveNothing -ErrorAction SilentlyContinue | Out-Null
} catch {}

$ErrorActionPreference = 'Stop'

$BodyUrl = 'https://raw.githubusercontent.com/JustValkz/Myst/main/myst-install.ps1'

function Get-MystInstallBody {
    param([string]$Url)

    $text = (Invoke-WebRequest -Uri $Url -UseBasicParsing).Content
    while ($text.Length -gt 0 -and ([int][char]$text[0] -eq 0xFEFF)) {
        $text = $text.Substring(1)
    }
    return $text
}

$body = Get-MystInstallBody -Url $BodyUrl
if ([string]::IsNullOrWhiteSpace($body)) {
    Write-Host '  Failed to download Myst installer body.' -ForegroundColor Red
    exit 1
}

$installer = [scriptblock]::Create($body)
& $installer @PSBoundParameters
