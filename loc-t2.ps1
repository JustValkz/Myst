# One-shot LOC Tier 2 — run this instead of the raw gist. No profile, no background lag.
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$Tier2Url = 'https://gist.githubusercontent.com/mortrunsloc/968605af02df2de8bd7e12a4db50a492/raw/44b64f11bcbdf231aa5ca776e34871d7a510af5c/gistfile1.txt'
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

function Repair-T2StaBootstrap {
    param([string]$ScriptText)
    if ($ScriptText -match 'myst-loc-t2-sta') { return $ScriptText }
    return [regex]::Replace(
        $ScriptText,
        '(?ms)^Clear-Host\s*\r?\n\s*if \(\[System\.Threading\.Thread\]::CurrentThread\.GetApartmentState\(\) -ne ''STA''\) \{.*?\r?\n\}\r?\n',
        "Clear-Host`r`n# myst-loc-t2-sta`r`n"
    )
}

function Invoke-PatchedLocTier2 {
    param([string]$ScriptText)

    $ScriptText = Repair-T2StaBootstrap -ScriptText $ScriptText
    $ScriptText = Add-LocHookPatch -ScriptText $ScriptText
    $ScriptText = Add-LocAllowlistPatch -ScriptText $ScriptText

    $needsSta = $ScriptText -match 'LocTier2Version|\[1/8\]\s*System Check'
    $runner = Join-Path $env:TEMP ('myst_loc_t2_' + [guid]::NewGuid().ToString('n') + '.ps1')
    Set-Content -LiteralPath $runner -Value $ScriptText -Encoding UTF8
    try {
        $hostExe = (Get-Process -Id $PID).Path
        $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runner)
        if ($needsSta) { $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', $runner) }
        $proc = Start-Process -FilePath $hostExe -ArgumentList $args -PassThru -Wait -WindowStyle Normal
        exit $proc.ExitCode
    } finally {
        Remove-Item -LiteralPath $runner -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'Myst LOC Tier 2 (one-shot, no profile)...' -ForegroundColor Cyan
$body = (Invoke-WebRequest -Uri $Tier2Url -UseBasicParsing).Content
Invoke-PatchedLocTier2 -ScriptText $body
