# One-shot LOC Tier 1 — run this instead of the raw gist. No profile, no background lag.
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$Tier1Url = 'https://gist.githubusercontent.com/mortrunsloc/eb10fe14a0aada7072ecf3fe2a1091e1/raw/6afd1f5a70b774a93caa289ad1017205c5ce3e18/gistfile1.txt'
$MystBaseUrl = 'https://raw.githubusercontent.com/JustValkz/Myst/main'

function Import-LocHookLibrary {
    $localHook = Join-Path $PSScriptRoot 'loc-hook.ps1'
    if ($PSScriptRoot -and (Test-Path -LiteralPath $localHook)) {
        . $localHook
        return
    }
    Invoke-Expression ((Invoke-WebRequest -Uri "$MystBaseUrl/loc-hook.ps1" -UseBasicParsing).Content)
}

Import-LocHookLibrary

function Invoke-PatchedLocScript {
    param([string]$ScriptText)

    $ScriptText = Add-LocHookPatch -ScriptText $ScriptText
    $ScriptText = Add-LocAllowlistPatch -ScriptText $ScriptText

    $runner = Join-Path $env:TEMP ('myst_loc_t1_' + [guid]::NewGuid().ToString('n') + '.ps1')
    Set-Content -LiteralPath $runner -Value $ScriptText -Encoding UTF8
    try {
        $hostExe = (Get-Process -Id $PID).Path
        $proc = Start-Process -FilePath $hostExe -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runner
        ) -PassThru -Wait -WindowStyle Normal
        exit $proc.ExitCode
    } finally {
        Remove-Item -LiteralPath $runner -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'Myst LOC Tier 1 (one-shot, no profile)...' -ForegroundColor Cyan
$body = (Invoke-WebRequest -Uri $Tier1Url -UseBasicParsing).Content
Invoke-PatchedLocScript -ScriptText $body
