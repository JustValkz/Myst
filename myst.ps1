# Myst bootstrap - keeps irm | iex working even if GitHub CDN serves a stale UTF-8 BOM.
#Requires -Version 5.1

param(
    [switch]$WatchMode,
    [switch]$LoadOnly,
    [switch]$SkipUnload,
    [string]$Choice
)

$ErrorActionPreference = 'Stop'

$BodyUrl = 'https://raw.githubusercontent.com/JustValkz/Myst/main/myst-install.ps1'

function Get-MystInstallBody {
    param(
        [string]$Url = 'https://raw.githubusercontent.com/JustValkz/Myst/main/myst-install.ps1'
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        $Url = 'https://raw.githubusercontent.com/JustValkz/Myst/main/myst-install.ps1'
    }

    $text = (Invoke-WebRequest -Uri $Url -UseBasicParsing -Headers @{
        'Cache-Control' = 'no-cache, no-store, must-revalidate'
        'Pragma'        = 'no-cache'
    }).Content
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
