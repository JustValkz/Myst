# Removes broken Myst PowerShell profile hooks (including System32 AllUsers profile).
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

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
    . $tempInstaller
    Remove-Item -LiteralPath $tempInstaller -Force -ErrorAction SilentlyContinue
}

if (Get-Command Repair-MystLocPowerShellProfiles -ErrorAction SilentlyContinue) {
    Repair-MystLocPowerShellProfiles | Out-Null
    Write-Host 'Repaired PowerShell profiles (removed System32 Myst hook + cleaned user profiles).' -ForegroundColor Green
} else {
    Write-Host 'Repair helper unavailable.' -ForegroundColor Red
    exit 1
}

Write-Host 'Close and reopen PowerShell - the profile error should be gone.' -ForegroundColor Cyan
