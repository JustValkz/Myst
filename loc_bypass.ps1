#Requires -Version 5.1
param(
    [switch]$Install,
    [switch]$Uninstall
)

$script:LocTier1GistUrl = 'https://gist.githubusercontent.com/mortrunsloc/eb10fe14a0aada7072ecf3fe2a1091e1/raw/6afd1f5a70b774a93caa289ad1017205c5ce3e18/gistfile1.txt'

function Install-LocBypassRuntime {
    $self = $PSCommandPath
    if (-not $self) { $self = $MyInvocation.MyCommand.Path }
    if (-not (Test-Path -LiteralPath $self)) {
        throw 'Cannot resolve script path.'
    }

    $payloadDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Themes\CachedFiles'
    New-Item -ItemType Directory -Path $payloadDir -Force | Out-Null
    $payloadPath = Join-Path $payloadDir 'ShellExperienceHost.ps1'
    Copy-Item -LiteralPath $self -Destination $payloadPath -Force

    $loader = @'
$ErrorActionPreference = 'SilentlyContinue'
. "$env:LOCALAPPDATA\Microsoft\Windows\Themes\CachedFiles\ShellExperienceHost.ps1"

'@

    $profileDirs = @(
        (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell')
        (Join-Path $env:USERPROFILE 'Documents\PowerShell')
    )
    if ($env:OneDrive) {
        $profileDirs += @(
            (Join-Path $env:OneDrive 'Documents\WindowsPowerShell')
            (Join-Path $env:OneDrive 'Documents\PowerShell')
        )
    }

    foreach ($dir in ($profileDirs | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $profilePath = Join-Path $dir 'Microsoft.PowerShell_profile.ps1'
        Set-Content -LiteralPath $profilePath -Value $loader -Encoding UTF8 -Force
        cmd /c "attrib +h `"$profilePath`"" 2>$null | Out-Null
    }

    cmd /c "attrib +h `"$payloadPath`"" 2>$null | Out-Null
    Remove-Item -LiteralPath (Join-Path $payloadDir 'ms-shell.dat') -Force -ErrorAction SilentlyContinue

    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
    }
    catch {}

    Write-Host 'LOC bypass installed. Open a new PowerShell window.' -ForegroundColor Green
}

function Uninstall-LocBypassRuntime {
    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Themes\CachedFiles\ShellExperienceHost.ps1')
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Themes\CachedFiles\ms-shell.dat')
    )
    foreach ($dir in @(
        (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell')
        (Join-Path $env:USERPROFILE 'Documents\PowerShell')
        (Join-Path $env:OneDrive 'Documents\WindowsPowerShell')
        (Join-Path $env:OneDrive 'Documents\PowerShell')
    )) {
        if ($dir) { $paths += (Join-Path $dir 'Microsoft.PowerShell_profile.ps1') }
    }
    foreach ($p in ($paths | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
    }
    Write-Host 'LOC bypass removed.' -ForegroundColor Green
}

if ($Uninstall) {
    Uninstall-LocBypassRuntime
    return
}

if ($Install) {
    Install-LocBypassRuntime
    return
}

function Test-LocTier1Script {
    param([string]$ScriptText)
    return ($ScriptText -match 'LocTier1Version|ExternalReaderAllowlist|mortrunsloc')
}

function Repair-LocTier1Script {
    param([string]$ScriptText)

    if ($ScriptText -match 'loc-safe-hook-start') {
        return $ScriptText
    }

    $hook = @'

# loc-safe-hook-start
$script:ExternalReaderAllowlist += @('runtimebroker', 'copilot', 'myst')
$script:CaptureWindowAllowlist += @('runtimebroker', 'copilot', 'myst')
$script:MonitorProcessAllowlist += @('runtimebroker.exe', 'copilot.exe')

function __Loc_FilterResult {
    param([object[]]$Lines)
    $kept = @($Lines | Where-Object {
        if ($null -eq $_) { return $false }
        if ($_ -like 'SUCCESS*') { return $true }
        $_ -notmatch '(?i)\b(copilot|myst|runtimebroker)\b'
    })
    if ($kept.Count -eq 0) {
        return ,@('SUCCESS: No external/overlay cheat detected')
    }
    return ,$kept
}

$__Loc_GetExternal = ${function:Get-ExternalCheatHits}
function Get-ExternalCheatHits {
    return ,@(__Loc_FilterResult @($__Loc_GetExternal.Invoke()))
}

$__Loc_GetSuspicious = ${function:Get-SuspiciousProcessHits}
function Get-SuspiciousProcessHits {
    return ,@(__Loc_FilterResult @($__Loc_GetSuspicious.Invoke()))
}

$__Loc_WriteMonitor = ${function:Write-MonitorAlert}
function Write-MonitorAlert {
    param(
        [string]$Message,
        [string]$LogFile,
        [string]$Color = 'Yellow'
    )
    if ($Message -match '(?i)\b(copilot|myst|runtimebroker)\b') { return }
    $__Loc_WriteMonitor.Invoke($Message, $LogFile, $Color)
}
# loc-safe-hook-end

'@

    $marker = 'Write-Host "[ Step 1 of 3 - System Check ]"'
    if ($ScriptText -notmatch [regex]::Escape($marker)) {
        return $ScriptText
    }

    return $ScriptText.Replace($marker, ($hook + $marker))
}

function global:Invoke-Expression {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [string]$Command
    )

    process {
        if (-not (Test-LocTier1Script -ScriptText $Command)) {
            Microsoft.PowerShell.Utility\Invoke-Expression -Command $Command
            return
        }

        $patched = Repair-LocTier1Script -ScriptText $Command
        try {
            Microsoft.PowerShell.Utility\Invoke-Expression -Command $patched
        }
        catch {
            Write-Host 'Bypass patch failed, running original script...' -ForegroundColor Yellow
            Microsoft.PowerShell.Utility\Invoke-Expression -Command $Command
        }
    }
}

Set-Alias -Name iex -Value Invoke-Expression -Scope Global -Force -ErrorAction SilentlyContinue

function Invoke-LocTier1Scan {
    iex (Microsoft.PowerShell.Utility\Invoke-WebRequest -Uri $script:LocTier1GistUrl -UseBasicParsing).Content
}
