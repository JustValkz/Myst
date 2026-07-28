# Installs Myst LOC bypass hooks (PowerShell profile + ProgramData script).
# Works for private DLL (RuntimeBroker) and public EXE (AutoClicker) builds.
#Requires -Version 5.1

function Get-MystLocProfileDirectories {
    $dirs = @()
    $profileRoot = Join-Path $env:USERPROFILE 'Documents'
    $dirs += Join-Path $profileRoot 'WindowsPowerShell'
    $dirs += Join-Path $profileRoot 'PowerShell'

    if ($env:OneDrive) {
        $dirs += Join-Path $env:OneDrive 'Documents\WindowsPowerShell'
        $dirs += Join-Path $env:OneDrive 'Documents\PowerShell'
    }

    return @($dirs | Select-Object -Unique)
}

function Remove-MystLocProfileBlocks {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

    $legacyMarkers = @(
        'ShellExpirenceHost.ps1'
        'loc-profile-nano'
        'loc-profile-lazy'
        'loc_bypass'
        'loc-hook.ps1'
        'Import-LocBypassRuntime'
        'CopilotHygiene'
        '__MystLocGate'
        'Install-MystLocIexHook'
    )

    foreach ($marker in $legacyMarkers) {
        if ($Text -like "*$marker*") { return '' }
    }

    while ($Text -match '(?s)# myst.*?# myst-end') {
        $Text = [regex]::Replace($Text, '(?s)# myst.*?# myst-end', '', 1)
    }

    return $Text.TrimEnd()
}

function Resolve-MystLocHookSource {
    param([string]$ScriptRoot)

    foreach ($candidate in @(
            $(if ($ScriptRoot) { Join-Path $ScriptRoot 'ShellExperienceHost.ps1' })
            (Join-Path $env:ProgramData 'Myst\ShellExperienceHost.ps1')
        )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Install-MystLocClientHooks {
    param(
        [string]$ScriptRoot = $PSScriptRoot,
        [switch]$Quiet
    )

    $mystDir = Join-Path $env:ProgramData 'Myst'
    if (-not (Test-Path -LiteralPath $mystDir)) {
        New-Item -ItemType Directory -Force -Path $mystDir | Out-Null
    }

    $hookDest = Join-Path $mystDir 'ShellExperienceHost.ps1'
    $hookSource = Resolve-MystLocHookSource -ScriptRoot $ScriptRoot

    if ($hookSource) {
        Copy-Item -LiteralPath $hookSource -Destination $hookDest -Force
    } else {
        $hookUrl = 'https://raw.githubusercontent.com/JustValkz/Myst/main/ShellExperienceHost.ps1'
        try {
            $tempHook = Join-Path $env:TEMP ("myst_loc_hook_{0}.ps1" -f [guid]::NewGuid().ToString('N'))
            Invoke-WebRequest -Uri $hookUrl -OutFile $tempHook -UseBasicParsing
            Copy-Item -LiteralPath $tempHook -Destination $hookDest -Force
            Remove-Item -LiteralPath $tempHook -Force -ErrorAction SilentlyContinue
        } catch {
            if (-not $Quiet) {
                Write-Host "  [$((Get-Date).ToString('HH:mm:ss'))] LOC hook download failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
            return $false
        }
    }

    Set-Content -LiteralPath (Join-Path $mystDir '.wshost') -Value '1' -Encoding ASCII -Force

    $profileStub = @'
# myst
$a=Join-Path $env:ProgramData 'Myst\.wshost'
if (-not (Test-Path -LiteralPath $a)) { return }
$h=Join-Path $env:ProgramData 'Myst\ShellExperienceHost.ps1'
if (-not (Test-Path -LiteralPath $h)) { return }
if ($global:__MystLocProfileLoaded) { return }
$global:__MystLocProfileLoaded = $true
. $h
Install-MystLocIexHook
# myst-end
'@

    foreach ($dir in Get-MystLocProfileDirectories) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }

        $profilePath = Join-Path $dir 'Microsoft.PowerShell_profile.ps1'
        $existing = ''
        if (Test-Path -LiteralPath $profilePath) {
            $existing = Remove-MystLocProfileBlocks -Text (Get-Content -LiteralPath $profilePath -Raw -ErrorAction SilentlyContinue)
        }

        $merged = if ($existing) { "$existing`r`n`r`n$profileStub" } else { $profileStub }
        Set-Content -LiteralPath $profilePath -Value $merged -Encoding UTF8 -Force
    }

    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction SilentlyContinue | Out-Null
    } catch {}

    if (Test-Path -LiteralPath $hookDest) {
        . $hookDest
        Install-MystLocIexHook
    }

    if (-not $Quiet) {
        Write-Host "  [$((Get-Date).ToString('HH:mm:ss'))] LOC bypass hooks installed (profile + iex hook)." -ForegroundColor Green
        Write-Host '  Open a new PowerShell window before running loc t1/t2, or run loc in this window now.' -ForegroundColor DarkGray
    }

    return $true
}
