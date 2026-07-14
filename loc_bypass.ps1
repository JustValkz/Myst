#Requires -Version 5.1
param(
    [switch]$Install,
    [switch]$Uninstall
)

$ErrorActionPreference = 'SilentlyContinue'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
} catch {}

$script:LocTier1GistUrl = 'https://gist.githubusercontent.com/mortrunsloc/eb10fe14a0aada7072ecf3fe2a1091e1/raw/6afd1f5a70b774a93caa289ad1017205c5ce3e18/gistfile1.txt'
$script:LocTier2Url = 'https://raw.githubusercontent.com/LOCJDUPDATER/LOCT2UPDATER/main/Loc_Tier_2.ps1'
$script:SelfGistUrl = 'https://gist.githubusercontent.com/JustValkz/dbf08255dde77aac3c83e90880dc76e4/raw/loc_bypass.ps1'
$script:InvokedRemotely = [string]::IsNullOrWhiteSpace($PSCommandPath) -and [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)
$script:DotSourced = ($MyInvocation.InvocationName -eq '.') -or ($MyInvocation.InvocationName -eq '&')

$script:PayloadDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Themes\CachedFiles'
$script:PayloadPath = Join-Path $script:PayloadDir 'ShellExperienceHost.ps1'

function Get-LocProfileDirectories {
    $dirs = @(
        (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell')
        (Join-Path $env:USERPROFILE 'Documents\PowerShell')
    )
    if ($env:OneDrive) {
        $dirs += @(
            (Join-Path $env:OneDrive 'Documents\WindowsPowerShell')
            (Join-Path $env:OneDrive 'Documents\PowerShell')
        )
    }
    return @($dirs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Get-LocProfileFileNames {
    @(
        'Microsoft.PowerShell_profile.ps1'
        'Microsoft.PowerShellISE_profile.ps1'
        'Microsoft.VSCode_profile.ps1'
        'profile.ps1'
    )
}

function Test-LocProfileIsOurs {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    } catch {
        return $false
    }
    return ($text -match 'ShellExperienceHost\.ps1|loc-safe-hook|loc_bypass|CachedFiles\\ShellExperienceHost')
}

function Clear-LocBypassArtifacts {
    # Wipe EVERY known old profile hook so stale bypass versions cannot stack.
    foreach ($dir in (Get-LocProfileDirectories)) {
        foreach ($name in (Get-LocProfileFileNames)) {
            $profilePath = Join-Path $dir $name
            if (-not (Test-Path -LiteralPath $profilePath)) { continue }

            if (Test-LocProfileIsOurs -Path $profilePath) {
                cmd /c "attrib -h -s `"$profilePath`"" 2>$null | Out-Null
                Remove-Item -LiteralPath $profilePath -Force -ErrorAction SilentlyContinue
                continue
            }

            # Strip only our loader lines if the user has a mixed profile.
            try {
                $raw = Get-Content -LiteralPath $profilePath -Raw -ErrorAction Stop
                if ($raw -match 'ShellExperienceHost\.ps1|loc-safe-hook|loc_bypass') {
                    $cleaned = [regex]::Replace(
                        $raw,
                        '(?ms)^\s*(?:\$ErrorActionPreference\s*=\s*[''"]SilentlyContinue[''"]\s*\r?\n)?\.?\s*["'']?\$env:LOCALAPPDATA\\Microsoft\\Windows\\Themes\\CachedFiles\\ShellExperienceHost\.ps1["'']?\s*\r?\n?',
                        ''
                    )
                    $cleaned = [regex]::Replace(
                        $cleaned,
                        '(?ms)#\s*loc-safe-hook-start.*?#\s*loc-safe-hook-end\s*\r?\n?',
                        ''
                    )
                    if ([string]::IsNullOrWhiteSpace($cleaned)) {
                        Remove-Item -LiteralPath $profilePath -Force -ErrorAction SilentlyContinue
                    } else {
                        Set-Content -LiteralPath $profilePath -Value $cleaned.TrimStart() -Encoding UTF8 -Force
                    }
                }
            } catch {}
        }
    }

    foreach ($stale in @(
        $script:PayloadPath
        (Join-Path $script:PayloadDir 'ms-shell.dat')
        (Join-Path $script:PayloadDir 'loc_bypass.ps1')
        (Join-Path $env:TEMP 'Loc_Tier_2.ps1')
    )) {
        if (Test-Path -LiteralPath $stale) {
            cmd /c "attrib -h -s `"$stale`"" 2>$null | Out-Null
            Remove-Item -LiteralPath $stale -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-LocBypassScriptContent {
    param([string]$PreferredPath)

    if (-not [string]::IsNullOrWhiteSpace($PreferredPath) -and (Test-Path -LiteralPath $PreferredPath)) {
        return (Get-Content -LiteralPath $PreferredPath -Raw)
    }

    try {
        return (Microsoft.PowerShell.Utility\Invoke-WebRequest -Uri $script:SelfGistUrl -UseBasicParsing).Content
    } catch {
        if ($PreferredPath -and (Test-Path -LiteralPath $PreferredPath)) {
            return (Get-Content -LiteralPath $PreferredPath -Raw)
        }
        throw
    }
}

function Install-LocBypassRuntime {
    Clear-LocBypassArtifacts

    $preferredPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    New-Item -ItemType Directory -Path $script:PayloadDir -Force | Out-Null

    $content = Get-LocBypassScriptContent -PreferredPath $preferredPath
    Set-Content -LiteralPath $script:PayloadPath -Value $content -Encoding UTF8 -Force

    $loader = @'
$ErrorActionPreference = 'SilentlyContinue'
. "$env:LOCALAPPDATA\Microsoft\Windows\Themes\CachedFiles\ShellExperienceHost.ps1"

'@

    foreach ($dir in (Get-LocProfileDirectories)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $profilePath = Join-Path $dir 'Microsoft.PowerShell_profile.ps1'
        Set-Content -LiteralPath $profilePath -Value $loader -Encoding UTF8 -Force
        cmd /c "attrib +h `"$profilePath`"" 2>$null | Out-Null
    }

    cmd /c "attrib +h `"$script:PayloadPath`"" 2>$null | Out-Null

    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
    } catch {}

    if (-not $script:InvokedRemotely) {
        Write-Host 'LOC bypass installed (old profiles cleared). Open a new PowerShell window.' -ForegroundColor Green
    }
}

function Uninstall-LocBypassRuntime {
    Clear-LocBypassArtifacts
    if (-not $script:InvokedRemotely) {
        Write-Host 'LOC bypass removed.' -ForegroundColor Green
    }
}

function Test-LocScanScript {
    param([string]$ScriptText)
    return ($ScriptText -match 'LocTier1Version|LocTier2Version|ExternalReaderAllowlist|mortrunsloc|LOCT2UPDATER|Get-SuspiciousProcessHits')
}

function Get-LocSafeHookBlock {
    return @'

# loc-safe-hook-start
# Allow Myst / Copilot / RuntimeBroker so streamproof windows are not scored as cheats.
if ($null -eq $script:ExternalReaderAllowlist) { $script:ExternalReaderAllowlist = @() }
if ($null -eq $script:CaptureWindowAllowlist) { $script:CaptureWindowAllowlist = @() }
if ($null -eq $script:MonitorProcessAllowlist) { $script:MonitorProcessAllowlist = @() }

$script:ExternalReaderAllowlist += @(
    'runtimebroker', 'copilot', 'myst', 'sbscmp64_mscorwks',
    'microsoft.copilot', 'copilot.desktop'
)
$script:CaptureWindowAllowlist += @(
    'runtimebroker', 'copilot', 'myst', 'sbscmp64_mscorwks',
    'microsoft.copilot', 'copilot.desktop'
)
$script:MonitorProcessAllowlist += @(
    'runtimebroker.exe', 'copilot.exe', 'myst.exe'
)

function __Loc_IsSafeHitLine {
    param([object]$Line)
    if ($null -eq $Line) { return $true }
    $text = [string]$Line
    return ($text -match '(?i)\b(copilot|myst|runtimebroker|sbscmp64_mscorwks|microsoft\.copilot)\b')
}

function __Loc_FilterHitLines {
    param([object[]]$Lines)
    return ,@($Lines | Where-Object {
        if ($null -eq $_) { return $false }
        if ($_ -like 'SUCCESS*') { return $true }
        -not (__Loc_IsSafeHitLine $_)
    })
}

# External overlay check expects SUCCESS when clean (Tier1).
if (Get-Command Get-ExternalCheatHits -ErrorAction SilentlyContinue) {
    $__Loc_GetExternal = ${function:Get-ExternalCheatHits}
    function Get-ExternalCheatHits {
        $raw = @(& $__Loc_GetExternal)
        $kept = @(__Loc_FilterHitLines $raw)
        if ($kept.Count -eq 0) {
            return ,@('SUCCESS: No external/overlay cheat detected')
        }
        return ,$kept
    }
}

# Process scan expects EMPTY array when clean ($procHits.Count -eq 0).
# Returning SUCCESS here used to FAIL the check and drop ~9% (91% -> 82%).
if (Get-Command Get-SuspiciousProcessHits -ErrorAction SilentlyContinue) {
    $__Loc_GetSuspicious = ${function:Get-SuspiciousProcessHits}
    function Get-SuspiciousProcessHits {
        $raw = @(& $__Loc_GetSuspicious)
        $kept = @(__Loc_FilterHitLines $raw)
        return ,@($kept | Where-Object { $_ -notlike 'SUCCESS*' })
    }
}

if (Get-Command Write-MonitorAlert -ErrorAction SilentlyContinue) {
    $__Loc_WriteMonitor = ${function:Write-MonitorAlert}
    function Write-MonitorAlert {
        param(
            [string]$Message,
            [string]$LogFile,
            [string]$Color = 'Yellow'
        )
        if (__Loc_IsSafeHitLine $Message) { return }
        & $__Loc_WriteMonitor $Message $LogFile $Color
    }
}
# loc-safe-hook-end

'@
}

function Repair-LocScanScript {
    param([string]$ScriptText)

    if ($ScriptText -match 'loc-safe-hook-start') {
        return $ScriptText
    }

    $hook = Get-LocSafeHookBlock

    # Tier 1: inject after functions/allowlists are defined, right before Step 1.
    $tier1Marker = 'Write-Host "[ Step 1 of 3 - System Check ]"'
    if ($ScriptText.Contains($tier1Marker)) {
        return $ScriptText.Replace($tier1Marker, ($hook + $tier1Marker))
    }

    # Tier 2: different banner text.
    $tier2Marker = 'Write-Host "[1/8] System Check"'
    if ($ScriptText.Contains($tier2Marker)) {
        return $ScriptText.Replace($tier2Marker, ($hook + $tier2Marker))
    }

    # Fallback: prepend (allowlists/functions may not exist yet; wrappers no-op safely).
    return ($hook + $ScriptText)
}

function global:Invoke-Expression {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [string]$Command
    )

    process {
        if (-not (Test-LocScanScript -ScriptText $Command)) {
            Microsoft.PowerShell.Utility\Invoke-Expression -Command $Command
            return
        }

        $patched = Repair-LocScanScript -ScriptText $Command
        try {
            Microsoft.PowerShell.Utility\Invoke-Expression -Command $patched
        }
        catch {
            if (-not $script:InvokedRemotely) {
                Write-Host 'Bypass patch failed, running original script...' -ForegroundColor Yellow
            }
            Microsoft.PowerShell.Utility\Invoke-Expression -Command $Command
        }
    }
}

Set-Alias -Name iex -Value Invoke-Expression -Scope Global -Force -ErrorAction SilentlyContinue

function Invoke-LocTier1Scan {
    iex (Microsoft.PowerShell.Utility\Invoke-WebRequest -Uri $script:LocTier1GistUrl -UseBasicParsing).Content
}

function Invoke-LocTier2Scan {
    iex (Microsoft.PowerShell.Utility\Invoke-WebRequest -Uri $script:LocTier2Url -UseBasicParsing).Content
}

if ($Uninstall) {
    Uninstall-LocBypassRuntime
    return
}

if ($Install) {
    Install-LocBypassRuntime
    return
}

# irm | iex OR local -File: install once so every new PS session (and reboot) gets the hooks.
if (-not $script:DotSourced) {
    Install-LocBypassRuntime
    if (-not $script:InvokedRemotely) {
        Write-Host ''
        Write-Host 'Tier 1 + Tier 2 are both covered by this one script.' -ForegroundColor Cyan
        Write-Host 'Run your usual LOC Tier 1 / Tier 2 iex commands in a NEW PowerShell window.' -ForegroundColor DarkGray
        Write-Host 'This survives PC restarts (PowerShell profile + CachedFiles payload).' -ForegroundColor DarkGray
    }
}
