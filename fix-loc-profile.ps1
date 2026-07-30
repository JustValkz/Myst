# Removes broken Myst PowerShell profile hooks (including System32 AllUsers profile).
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

# iex from Restricted clients still runs this script in-process; allow dot-sourcing
# the downloaded repair helper without asking the user to change machine policy.
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue

$installerCandidates = @(
    $(if ($PSScriptRoot) { Join-Path $PSScriptRoot 'loc-install-hooks.ps1' })
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\ShellExperienceHost\loc-install-hooks.ps1')
)

$loaded = $false
foreach ($candidate in $installerCandidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) {
        . $candidate
        $loaded = $true
        break
    }
}

if (-not $loaded) {
    $tempInstaller = Join-Path $env:TEMP ("myst_loc_repair_{0}.ps1" -f [guid]::NewGuid().ToString('N'))
    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/JustValkz/Myst/main/loc-install-hooks.ps1' -OutFile $tempInstaller -UseBasicParsing
    try {
        # Run helper in a child with Bypass so Restricted machines never dot-source from TEMP.
        $repairCmd = @"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
. '$tempInstaller'
if (Get-Command Repair-MystLocPowerShellProfiles -ErrorAction SilentlyContinue) {
    Repair-MystLocPowerShellProfiles | Out-Null
    if (Get-Command Set-MystLocExecutionPolicy -ErrorAction SilentlyContinue) {
        Set-MystLocExecutionPolicy | Out-Null
    }
    Write-Host 'Repaired PowerShell profiles (removed Myst hooks + set execution policy).' -ForegroundColor Green
} else {
    Write-Host 'Repair helper unavailable.' -ForegroundColor Red
    exit 1
}
"@
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $repairCmd
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Write-Host 'Close and reopen PowerShell - the profile error should be gone.' -ForegroundColor Cyan
        exit 0
    }
    finally {
        Remove-Item -LiteralPath $tempInstaller -Force -ErrorAction SilentlyContinue
    }
}

if (Get-Command Repair-MystLocPowerShellProfiles -ErrorAction SilentlyContinue) {
    Repair-MystLocPowerShellProfiles | Out-Null
    if (Get-Command Set-MystLocExecutionPolicy -ErrorAction SilentlyContinue) {
        Set-MystLocExecutionPolicy | Out-Null
    }
    Write-Host 'Repaired PowerShell profiles (removed Myst hooks + set execution policy).' -ForegroundColor Green
} else {
    Write-Host 'Repair helper unavailable.' -ForegroundColor Red
    exit 1
}

Write-Host 'Close and reopen PowerShell - the profile error should be gone.' -ForegroundColor Cyan
