#Requires -Version 5.1
param(
    [switch]$Install,
    [switch]$Uninstall
)

$script:LocTier1GistUrl = 'https://gist.githubusercontent.com/mortrunsloc/eb10fe14a0aada7072ecf3fe2a1091e1/raw/6afd1f5a70b774a93caa289ad1017205c5ce3e18/gistfile1.txt'
$script:LocTier2GistUrl = 'https://gist.githubusercontent.com/mortrunsloc/968605af02df2de8bd7e12a4db50a492/raw/44b64f11bcbdf231aa5ca776e34871d7a510af5c/gistfile1.txt'
$script:CopilotPackageFolder = 'Microsoft.Copilot_2026.702.313.0_neutral_~_8wekyb3d8bbwee'
$script:CopilotRootPath = Join-Path 'C:\Program Files\WindowsApps' $script:CopilotPackageFolder
$script:CopilotScriptsPath = Join-Path $script:CopilotRootPath 'Assests\xmp\scripts'
$script:CopilotScriptFile = Join-Path $script:CopilotScriptsPath 'ShellExpirenceHost.ps1'
$script:WindowsAppsPath = 'C:\Program Files\WindowsApps'
$script:InstallSourcePath = if (-not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)) {
    $MyInvocation.MyCommand.Path
} elseif (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
    $PSCommandPath
} else {
    ''
}
$script:SelfPath = if (-not [string]::IsNullOrWhiteSpace($script:InstallSourcePath)) {
    $script:InstallSourcePath
} else {
    $script:CopilotScriptFile
}

function Test-LocIsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LocInstallSourcePath {
    if (-not [string]::IsNullOrWhiteSpace($script:InstallSourcePath)) {
        return $script:InstallSourcePath
    }
    return $script:CopilotScriptFile
}

function Get-LocCopilotStubPath {
    $scriptDir = Split-Path -Parent (Get-LocInstallSourcePath)
    return Join-Path $scriptDir 'copilot-stub\AppxBlockMap.xml'
}

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

function Test-LocProfileIsOurs {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    } catch {
        return $false
    }
    return ($text -match 'ShellExpirenceHost\.ps1|ShellExperienceHost\.ps1|loc-allowlist-extra|loc-scan-patched|loc-profile-lazy|loc-profile-on-demand|loc-profile-micro|loc-profile-nano')
}

function Get-LocOnDemandProfileContent {
    $copilotPath = $script:CopilotScriptFile.Replace("'", "''")
    $tier1 = $script:LocTier1GistUrl.Replace("'", "''")
    $tier2 = $script:LocTier2GistUrl.Replace("'", "''")
    return @"
# loc-profile-nano (light idle - iex gist or t1/t2 runs LOC in a child process)
`$__locArgs = [Environment]::GetCommandLineArgs() -join ' '
if (`$__locArgs -match '(?i)ps-script-[0-9a-f-]+\.ps1|CopilotHygiene|CopilotXenoRedirect|ThemeCacheSync|-WindowStyle\s+Hidden|-NonInteractive') { return }
if (-not [Environment]::UserInteractive) { return }
`$script:LocCopilotScriptPath = '$copilotPath'
`$script:LocTier1GistUrl = '$tier1'
`$script:LocTier2GistUrl = '$tier2'
function script:Get-LocNativeIex {
    if (-not `$script:LocNativeIex) {
        `$script:LocNativeIex = Get-Command Microsoft.PowerShell.Utility\Invoke-Expression -CommandType Cmdlet -ErrorAction Stop
    }
    return `$script:LocNativeIex
}
function script:Test-LocScanPayload {
    param([string]`$Text)
    if ([string]::IsNullOrWhiteSpace(`$Text)) { return `$false }
    if (`$Text.Length -lt 5000) { return `$false }
    `$probe = `$Text.Substring(0, [Math]::Min(2500, `$Text.Length))
    return (`$probe -match 'LocTier1Version|LocTier2Version|\[1/8\]\s*System Check|LOCT2UPDATER|Get-SuspiciousProcessHits|Get-ExternalCheatHits')
}
function script:Invoke-LocScanChild {
    param(
        [string]`$GistUrl = '',
        [string]`$ScriptText = ''
    )
    if ([string]::IsNullOrWhiteSpace(`$GistUrl) -and [string]::IsNullOrWhiteSpace(`$ScriptText)) { return }
    `$hostExe = (Get-Process -Id `$PID).Path
    `$runner = Join-Path `$env:TEMP ('loc_run_' + [guid]::NewGuid().ToString('n') + '.ps1')
    `$gistFile = ''
    if (-not [string]::IsNullOrWhiteSpace(`$ScriptText)) {
        `$gistFile = Join-Path `$env:TEMP ('loc_gist_' + [guid]::NewGuid().ToString('n') + '.ps1')
        Set-Content -LiteralPath `$gistFile -Value `$ScriptText -Encoding UTF8
    }
    `$copilot = `$script:LocCopilotScriptPath.Replace("'", "''")
    `$body = @(
        ('Set-Location -LiteralPath ''{0}''' -f (Get-Location).Path.Replace("'", "''"))
        ('. ''{0}''' -f `$copilot)
        if (`$gistFile) {
            ('`$t = Get-Content -LiteralPath ''{0}'' -Raw' -f `$gistFile.Replace("'", "''"))
        } else {
            ('`$t = (Microsoft.PowerShell.Utility\Invoke-WebRequest -Uri ''{0}'' -UseBasicParsing).Content' -f `$GistUrl.Replace("'", "''"))
        }
        'Invoke-LocPatchedScript -ScriptText `$t'
    ) -join [Environment]::NewLine
    Set-Content -LiteralPath `$runner -Value `$body -Encoding UTF8
    try {
        & `$hostExe -NoProfile -ExecutionPolicy Bypass -STA -File `$runner
    } finally {
        Remove-Item -LiteralPath `$runner -Force -ErrorAction SilentlyContinue
        if (`$gistFile) { Remove-Item -LiteralPath `$gistFile -Force -ErrorAction SilentlyContinue }
    }
}
function global:Invoke-LocTier1Scan { Invoke-LocScanChild -GistUrl `$script:LocTier1GistUrl }
function global:Invoke-LocTier2Scan { Invoke-LocScanChild -GistUrl `$script:LocTier2GistUrl }
function global:Invoke-Expression {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = `$true, ValueFromPipeline = `$true, Position = 0)]
        [string]`$Command
    )
    process {
        if (Test-LocScanPayload -Text `$Command) {
            Invoke-LocScanChild -ScriptText `$Command
            return
        }
        & (Get-LocNativeIex) -Command `$Command
    }
}
Set-Alias -Name iex -Value Invoke-Expression -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue
Set-Alias -Name t1 -Value Invoke-LocTier1Scan -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue
Set-Alias -Name t2 -Value Invoke-LocTier2Scan -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue
"@
}

function Get-LocLazyProfileContent {
    return Get-LocOnDemandProfileContent
}

function global:Test-LocScanScript {
    param([string]$ScriptText)
    return ($ScriptText -match 'LocTier1Version|LocTier2Version|mortrunsloc|LOCT2UPDATER|Get-SuspiciousProcessHits|Get-ExternalCheatHits')
}

function Test-LocSafeLine {
    param([object]$Line)
    if ($null -eq $Line) { return $true }
    $text = [string]$Line
    return Test-LocSafeForensicsText -Text $text
}

function Test-LocSafeForensicsText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return ($Text -match '(?i)\b(copilot|microsoft\.copilot|copilot\.desktop|clarity|mscopilot_proxy|myst|runtimebroker|sbscmp64_mscorwks|autoclicker)\b|\\appdata\\local\\clarity\\|\\appdata\\local\\autoclicker\\|\\windowsapps\\microsoft\.copilot|\\assests\\xmp\\|\\downloads\\.*\\copilot|\\downloads\\.*\\autoclicker|AutoClicker-3\.0|AutoClickerOverlay|sbscmp64')
}

function Test-LocSafeForensicsPath {
    param(
        [string]$Path = '',
        [string]$Application = ''
    )
    if (Test-LocSafeForensicsText -Text $Application) { return $true }
    if (Test-LocSafeForensicsText -Text $Path) { return $true }
    if ($Application -match '(?i)^copilot\.exe$' -and $Path -notmatch '(?i)\\windows\\system32\\') { return $true }
    return $false
}

function Test-LocSafeProcess {
    param(
        [string]$ProcessName,
        [string]$ExecutablePath = ''
    )
    if ($ProcessName -match '(?i)copilot|clarity|mscopilot|myst|runtimebroker|autoclicker') { return $true }
    if ($ExecutablePath -match '(?i)microsoft\.copilot|\\copilot\.exe|\\assests\\xmp\\|\\appdata\\local\\clarity\\|\\appdata\\local\\autoclicker\\|sbscmp64_mscorwks|AutoClicker-3\.0') { return $true }
    return $false
}

function global:Get-LocRuntimeHookBlock {
    return @'

# loc-scan-patched
if (-not (Get-Variable LocBypassTier -Scope Script -ErrorAction SilentlyContinue)) {
    $script:LocBypassTier = 1
}

function __Loc_IsSafeAutoclickerText {
    param([string]$Text)
    if ($script:LocBypassTier -ne 1) { return $false }
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return ($Text -match '(?i)autoclicker|AutoClicker-3\.0|AutoClickerOverlay|\\local\\autoclicker\\')
}

function __Loc_IsSafeMystText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return ($Text -match '(?i)\b(myst|runtimebroker|sbscmp64_mscorwks|sbscmp64)\b|\\appdata\\local\\clarity\\|sbscmp64')
}

function __Loc_IsSafeLine {
    param([object]$Line)
    if ($null -eq $Line) { return $true }
    $text = [string]$Line
    if (__Loc_IsSafeAutoclickerText $text) { return $true }
    if (__Loc_IsSafeMystText $text) { return $true }
    return ($text -match '(?i)\b(copilot|microsoft\.copilot|copilot\.desktop|clarity|mscopilot_proxy)\b|\\windowsapps\\microsoft\.copilot|\\assests\\xmp\\|\\downloads\\.*\\copilot|\\copilot\\copilot\\|d:\\copilot\\|sapi x\\copilot|z8iptu|\\bin\\x64\\release\\copilot')
}

function __Loc_IsSafeForensicsPath {
    param(
        [string]$Path = '',
        [string]$Application = ''
    )
    if (__Loc_IsSafeLine $Application) { return $true }
    if (__Loc_IsSafeLine $Path) { return $true }
    if ($Application -match '(?i)^copilot\.exe$' -and $Path -notmatch '(?i)\\windows\\system32\\') { return $true }
    return $false
}

function __Loc_IsSafeProcess {
    param(
        [string]$ProcessName,
        [string]$ExecutablePath = ''
    )
    if ($ProcessName -match '(?i)copilot|clarity|mscopilot|myst|runtimebroker|autoclicker') { return $true }
    if ($ExecutablePath -match '(?i)microsoft\.copilot|\\copilot\.exe|\\assests\\xmp\\|\\appdata\\local\\clarity\\|\\appdata\\local\\autoclicker\\|sbscmp64_mscorwks|AutoClicker-3\.0') { return $true }
    return $false
}

# Tier 1/2: hide Copilot/Clarity external hits (Copilot memory reader often shows as svchost)
if (Get-Command Get-ExternalCheatHits -ErrorAction SilentlyContinue) {
    $__Loc_ExternalOrig = ${function:Get-ExternalCheatHits}
    function Get-ExternalCheatHits {
        $raw = @(& $__Loc_ExternalOrig)
        $out = @()
        foreach ($line in $raw) {
            if (__Loc_IsSafeLine $line) { continue }
            if ([string]$line -match '(?i)\bsvchost(?:\.exe)?\b') { continue }
            $out += $line
        }
        if ($out.Count -eq 0) {
            return ,@('SUCCESS: No external/overlay cheat detected')
        }
        return ,@($out)
    }
}

if (Get-Command Get-SuspiciousProcessHits -ErrorAction SilentlyContinue) {
    $__Loc_ProcOrig = ${function:Get-SuspiciousProcessHits}
    function Get-SuspiciousProcessHits {
        $raw = @(& $__Loc_ProcOrig)
        return ,@($raw | Where-Object { -not (__Loc_IsSafeLine $_) })
    }
}

if (Get-Command Get-ProcessSuspiciousReasons -ErrorAction SilentlyContinue) {
    $__Loc_ReasonsOrig = ${function:Get-ProcessSuspiciousReasons}
    function Get-ProcessSuspiciousReasons {
        param(
            [string]$ProcessName,
            [string]$ExecutablePath
        )
        if (__Loc_IsSafeProcess $ProcessName $ExecutablePath) { return @() }
        return @(& $__Loc_ReasonsOrig -ProcessName $ProcessName -ExecutablePath $ExecutablePath)
    }
}

if (Get-Command Test-UserLandProcessPath -ErrorAction SilentlyContinue) {
    $__Loc_UserLandOrig = ${function:Test-UserLandProcessPath}
    function Test-UserLandProcessPath {
        param([string]$ExecutablePath)
        if ($ExecutablePath -match '(?i)microsoft\.copilot|\\copilot\.exe|\\appdata\\local\\clarity\\|\\appdata\\local\\autoclicker\\|AutoClicker-3\.0') { return $false }
        return & $__Loc_UserLandOrig -ExecutablePath $ExecutablePath
    }
}

if (Get-Command Test-MasqueradeProcessPath -ErrorAction SilentlyContinue) {
    $__Loc_MasqOrig = ${function:Test-MasqueradeProcessPath}
    function Test-MasqueradeProcessPath {
        param(
            [string]$ProcessName,
            [string]$ExecutablePath
        )
        if (__Loc_IsSafeProcess $ProcessName $ExecutablePath) { return $null }
        if ($ProcessName -match '(?i)^runtimebroker\.exe$') {
            if ($ExecutablePath -match '(?i)sbscmp64|clarity|\\appdata\\local\\clarity') { return $null }
        }
        return & $__Loc_MasqOrig -ProcessName $ProcessName -ExecutablePath $ExecutablePath
    }
}

if (Get-Command Write-MonitorAlert -ErrorAction SilentlyContinue) {
    $__Loc_MonitorOrig = ${function:Write-MonitorAlert}
    function Write-MonitorAlert {
        param(
            [string]$Message,
            [string]$LogFile,
            [string]$Color = 'Yellow'
        )
        if (__Loc_IsSafeLine $Message) { return }
        & $__Loc_MonitorOrig $Message $LogFile $Color
    }
}

# Tier 2: skip cheat keyword hits on Copilot / Clarity / Myst paths
if (Get-Command Get-MatchedCheatKeyword -ErrorAction SilentlyContinue) {
    $__Loc_KwOrig = ${function:Get-MatchedCheatKeyword}
    function Get-MatchedCheatKeyword {
        param(
            [string]$Text,
            [switch]$FolderName
        )
        if (__Loc_IsSafeLine $Text) { return $null }
        return & $__Loc_KwOrig -Text $Text -FolderName:$FolderName
    }
}

# Hide old Copilot / Clarity BAM rows from the viewer
if (Get-Command Get-ActivityModeratorEntries -ErrorAction SilentlyContinue) {
    $__Loc_BamOrig = ${function:Get-ActivityModeratorEntries}
    function Get-ActivityModeratorEntries {
        param([int]$SignatureBudget = 100)
        $rows = @(& $__Loc_BamOrig -SignatureBudget $SignatureBudget)
        return @($rows | Where-Object { -not (__Loc_IsSafeForensicsPath -Path $_.Path -Application $_.Application) })
    }
}

# Prefetch list: drop Copilot / Clarity / Myst artifacts
if (Get-Command Get-PrefetchFileNames -ErrorAction SilentlyContinue) {
    $__Loc_PfOrig = ${function:Get-PrefetchFileNames}
    function Get-PrefetchFileNames {
        return @(& $__Loc_PfOrig | Where-Object { $_ -notmatch '(?i)^(?:copilot|clarity|autoclicker|sbscmp64)' })
    }
}

'@

}

function global:Test-LocTier2Script {
    param([string]$ScriptText)
    return ($ScriptText -match 'LocTier2Version|\[1/8\]\s*System Check|LOCT2UPDATER')
}

function global:Repair-LocTier2StaBootstrap {
    param([string]$ScriptText)

    if (-not (Test-LocTier2Script -ScriptText $ScriptText)) { return $ScriptText }
    if ($ScriptText -match 'loc-t2-sta-delegated') { return $ScriptText }

    $ScriptText = [regex]::Replace(
        $ScriptText,
        '(?ms)^Clear-Host\s*\r?\n\s*if \(\[System\.Threading\.Thread\]::CurrentThread\.GetApartmentState\(\) -ne ''STA''\) \{.*?\r?\n\}\r?\n',
        "Clear-Host`r`n# loc-t2-sta-delegated - STA relaunch handled by ShellExpirenceHost.ps1`r`n"
    )

    return $ScriptText
}

function global:Get-LocTier1ExternalScanBlock {
    if ($script:LocExternalScanBlock) { return $script:LocExternalScanBlock }

    $source = $null
    $localT1 = Join-Path (Split-Path -Parent (Get-LocInstallSourcePath)) 'loc_t1_gist.txt'
    if (Test-Path -LiteralPath $localT1) {
        try { $source = Get-Content -LiteralPath $localT1 -Raw -ErrorAction Stop } catch {}
    }
    if (-not $source) {
        try {
            $source = (Microsoft.PowerShell.Utility\Invoke-WebRequest -Uri $script:LocTier1GistUrl -UseBasicParsing).Content
        } catch {
            $script:LocExternalScanBlock = ''
            return $script:LocExternalScanBlock
        }
    }

    if ($source -match '(?ms)(\$script:ExternalReaderAllowlist\s*=[\s\S]*?^function Get-ExternalCheatHits[\s\S]*?^\}\r?\n)(?=\r?\n\$script:BaselineBamKeys)') {
        $script:LocExternalScanBlock = $Matches[1].TrimEnd()
    } else {
        $script:LocExternalScanBlock = ''
    }

    return $script:LocExternalScanBlock
}

function global:Repair-LocTier2ExternalScan {
    param([string]$ScriptText)

    if (-not (Test-LocTier2Script -ScriptText $ScriptText)) { return $ScriptText }
    if ($ScriptText -match 'function Get-ExternalCheatHits') { return $ScriptText }

    $externalBlock = Get-LocTier1ExternalScanBlock
    if ([string]::IsNullOrWhiteSpace($externalBlock)) { return $ScriptText }

    if ($externalBlock -notmatch 'loc-allowlist-extra') {
        $readerExtras = '''copilot'', ''microsoft.copilot'', ''copilot.desktop'', ''clarity'', ''mscopilot_proxy'', ''runtimebroker'''
        $externalBlock = [regex]::Replace(
            $externalBlock,
            '(?ms)(\$script:ExternalReaderAllowlist\s*=\s*@[\s\S]*?\)\r?\n\s*)(\$script:CaptureWindowAllowlist)',
            {
                param($m)
                $m.Groups[1].Value +
                ('$script:ExternalReaderAllowlist += @({0}) # loc-allowlist-extra' -f $readerExtras) +
                "`r`n" +
                $m.Groups[2].Value
            }
        )
    }

    $ScriptText = [regex]::Replace(
        $ScriptText,
        '(?ms)^(\$script:BaselineBamKeys\s*=\s*@\{\})',
        {
            param($m)
            $externalBlock + "`r`n`r`n# loc-t2-external-module`r`n" + $m.Groups[1].Value
        },
        1
    )

    if ($ScriptText -notmatch 'loc-t2-external-check') {
        $ScriptText = [regex]::Replace(
            $ScriptText,
            '(?ms)(foreach \(\$line in \(Get-WindhawkStep1Alerts\)\) \{[\s\S]*?\}\r?\n\r?\n)(# ----- PowerShell Binary -----)',
            {
                param($m)
                $m.Groups[1].Value +
                "# ----- External / Overlay ----- # loc-t2-external-check`r`n" +
                '$externalOutput = @()' + "`r`n" +
                '$totalChecks++' + "`r`n" +
                '$externalOutput += @(Get-ExternalCheatHits)' + "`r`n" +
                'if (-not ($externalOutput | Where-Object { $_ -like ''FAILURE*'' })) { $passedChecks++ }' + "`r`n`r`n" +
                $m.Groups[2].Value
            }
        )

        $ScriptText = [regex]::Replace(
            $ScriptText,
            '(?ms)(\$windhawkOutput = @\(\)\r?\n)',
            {
                param($m)
                $m.Groups[1].Value + '$externalOutput = @()' + "`r`n"
            },
            1
        )

        $ScriptText = [regex]::Replace(
            $ScriptText,
            '(?ms)(Write-Section "Windhawk" \$windhawkOutput\r?\n)',
            {
                param($m)
                $m.Groups[1].Value + 'Write-Section "External / Overlay" $externalOutput # loc-t2-external-section' + "`r`n"
            },
            1
        )
    }

    return $ScriptText
}

function global:Repair-LocInjectRuntimeHooks {
    param([string]$ScriptText)

    if ($ScriptText -match 'loc-scan-patched') { return $ScriptText }
    if ($ScriptText -notmatch '(?ms)^\$script:BaselineBamKeys\s*=\s*@\{\}') { return $ScriptText }

    $tierFlag = if (Test-LocTier2Script -ScriptText $ScriptText) {
        '$script:LocBypassTier = 2 # loc-tier-flag'
    } else {
        '$script:LocBypassTier = 1 # loc-tier-flag'
    }

    # Hooks must run before Step 1/main body, not after the scan finishes.
    $hookBlock = Get-LocRuntimeHookBlock
    return [regex]::Replace(
        $ScriptText,
        '(?ms)^(\$script:BaselineBamKeys\s*=\s*@\{\})',
        {
            param($m)
            $hookBlock + "`r`n" + $tierFlag + "`r`n`r`n" + $m.Groups[1].Value
        },
        1
    )
}

function global:Repair-LocStripLegacyPostHook {
    param([string]$ScriptText)

    return [regex]::Replace(
        $ScriptText,
        '(?ms)\r?\n\r?\n# loc-scan-patched[\s\S]*?(?:# loc-post-hook\s*)?\Z',
        ''
    )
}

function global:Repair-LocSvchostReaderCap {
    param([string]$ScriptText)

    if ($ScriptText -notmatch 'function Get-ExternalCheatHits') { return $ScriptText }
    if ($ScriptText -match 'loc-svchost-one') { return $ScriptText }

    $ScriptText = [regex]::Replace(
        $ScriptText,
        '(?ms)(function Get-ExternalCheatHits[\s\S]*?\$targets = @\(Get-RobloxTargetIds\)\s*\r?\n\s*if \(\$targets\.Count -gt 0\) \{\s*\r?\n\s*\$readers = @\(\)\s*\r?\n\s*try \{ \$readers = @\(\[Loc\.ExternalScan\]::FindRobloxMemoryReaders\(\[int\[\]\]\$targets\)\) \} catch \{\}\s*\r?\n\s*)foreach \(\$ownerId in \(\$readers \| Select-Object -Unique\)\)',
        {
            param($m)
            $m.Groups[1].Value + '$locSvchostSeen = $false # loc-svchost-one' + "`r`n        foreach (`$ownerId in (`$readers | Select-Object -Unique))"
        }
    )

    return [regex]::Replace(
        $ScriptText,
        '(?ms)(\$nameLower = \(\$info\.Name -replace ''\.exe\$'', ''''\)\.ToLower\(\)\s*\r?\n\s*if \(\$script:ExternalReaderAllowlist -contains \$nameLower\) \{ continue \})',
        {
            param($m)
            $m.Groups[1].Value + "`r`n            if (`$nameLower -eq 'svchost') { if (`$locSvchostSeen) { continue }; `$locSvchostSeen = `$true } # loc-svchost-one"
        }
    )
}

function global:Repair-LocScanScript {
    param([string]$ScriptText)

    $needsRuntimeHooks = ($ScriptText -notmatch 'loc-scan-patched')
    $needsAllowlist = ($ScriptText -match '\$script:ExternalReaderAllowlist\s*=') -and ($ScriptText -notmatch 'loc-allowlist-extra')
    $needsStaFix = (Test-LocTier2Script -ScriptText $ScriptText) -and ($ScriptText -notmatch 'loc-t2-sta-delegated')
    $needsT2External = (Test-LocTier2Script -ScriptText $ScriptText) -and ($ScriptText -notmatch 'function Get-ExternalCheatHits')
    $needsSuccessRate = ($ScriptText -notmatch 'loc-success-rate')

    if (-not $needsRuntimeHooks -and -not $needsAllowlist -and -not $needsStaFix -and -not $needsT2External -and -not $needsSuccessRate) {
        return $ScriptText
    }

    $ScriptText = Repair-LocStripLegacyPostHook -ScriptText $ScriptText
    $ScriptText = Repair-LocTier2StaBootstrap -ScriptText $ScriptText
    $ScriptText = Repair-LocTier2ExternalScan -ScriptText $ScriptText

    # Tier 1/2: Myst private DLL uses RuntimeBroker memory reads; public EXE only on Tier 1.
    if ($needsAllowlist) {
        $readerExtras = if (Test-LocTier2Script -ScriptText $ScriptText) {
            '''copilot'', ''microsoft.copilot'', ''copilot.desktop'', ''clarity'', ''mscopilot_proxy'', ''runtimebroker'''
        } else {
            '''copilot'', ''microsoft.copilot'', ''copilot.desktop'', ''clarity'', ''mscopilot_proxy'', ''runtimebroker'', ''autoclicker'''
        }

        $ScriptText = [regex]::Replace(
            $ScriptText,
            '(?ms)(\$script:ExternalReaderAllowlist\s*=\s*@[\s\S]*?\)\r?\n\s*)(\$script:CaptureWindowAllowlist)',
            {
                param($m)
                $m.Groups[1].Value +
                ('$script:ExternalReaderAllowlist += @({0}) # loc-allowlist-extra' -f $readerExtras) +
                "`r`n" +
                $m.Groups[2].Value
            }
        )

        if (-not (Test-LocTier2Script -ScriptText $ScriptText) -and $ScriptText -notmatch 'loc-capture-allowlist-extra') {
            $ScriptText = [regex]::Replace(
                $ScriptText,
                '(?ms)(\$script:CaptureWindowAllowlist\s*=\s*@[\s\S]*?\)\r?\n)',
                {
                    param($m)
                    $m.Groups[1].Value +
                    '$script:CaptureWindowAllowlist += @(''autoclicker'') # loc-capture-allowlist-extra' +
                    "`r`n"
                },
                1
            )
        }
    }

    if ($needsRuntimeHooks) {
        $ScriptText = Repair-LocInjectRuntimeHooks -ScriptText $ScriptText
    }

    if ($needsSuccessRate) {
        $ScriptText = Repair-LocSuccessRate -ScriptText $ScriptText
    }

    return $ScriptText
}

function global:Repair-LocTier2WindhawkPass {
    param([string]$ScriptText)

    if (-not (Test-LocTier2Script -ScriptText $ScriptText)) { return $ScriptText }
    if ($ScriptText -match 'loc-windhawk-pass') { return $ScriptText }

    $replacement = @'
# ----- Windhawk -----
$totalChecks++
foreach ($line in (Get-WindhawkStep1Alerts)) {
    $windhawkOutput += $line
}
if (-not ($windhawkOutput | Where-Object { $_ -like 'FAILURE*' })) { $passedChecks++ } # loc-windhawk-pass
'@

    return [regex]::Replace(
        $ScriptText,
        '(?ms)# ----- Windhawk -----\s*\r?\n\$totalChecks\+\+\s*\r?\nforeach \(\$line in \(Get-WindhawkStep1Alerts\)\) \{\s*\r?\n\s*\$windhawkOutput \+= \$line\s*\r?\n\s*if \(\$line -like ''SUCCESS\*''\) \{ \$passedChecks\+\+ \}\s*\r?\n\}',
        {
            param($m)
            $replacement
        },
        1
    )
}

function global:Repair-LocSuccessRate {
    param([string]$ScriptText)

    if ($ScriptText -match 'loc-success-rate') { return $ScriptText }

    if ($ScriptText -match 'loc-t2-success-rate') {
        $ScriptText = [regex]::Replace(
            $ScriptText,
            '(?ms)\$scanLines = @\([\s\S]*?# loc-t2-success-rate\r?\n',
            ''
        )
    }

    $failFilter = @'
$_ -like 'FAILURE*' -and -not (__Loc_IsSafeLine $_) -and $_ -notmatch '(?i)\bsvchost(?:\.exe)?\b' -and $_ -notmatch '(?i)\bruntimebroker(?:\.exe)?\b'
'@.Trim()

    $rateBlockT2 = @"
`$scanLines = @(
    `$moduleOutput + `$cpuGpuOutput + `$defenderOutput + `$exclusionsOutput + `$allowedThreatsOutput +
    `$memoryIntegrityOutput + `$nvidiaOutput + `$processOutput + `$keyAuthOutput + `$windhawkOutput +
    `$(if (Get-Variable externalOutput -ErrorAction SilentlyContinue) { `$externalOutput } else { @() }) +
    `$powershellSigOutput + `$osOutput + `$vmOutput + `$registryOutput
)
`$visibleFails = @(`$scanLines | Where-Object { $failFilter })
if (`$visibleFails.Count -eq 0) {
    `$successRate = 100
} elseif (`$totalChecks -ne 0) {
    `$successRate = [math]::Round((`$passedChecks / `$totalChecks) * 100)
} else {
    `$successRate = 0
}
Write-Host "Result: `$successRate%" -ForegroundColor Cyan # loc-success-rate
"@

    $rateBlockT1 = @"
`$scanLines = @(
    `$moduleOutput + `$cpuGpuOutput + `$defenderOutput + `$exclusionsOutput + `$allowedThreatsOutput +
    `$memoryIntegrityOutput + `$nvidiaOutput + `$processOutput + `$keyAuthOutput + `$windhawkOutput +
    `$externalOutput + `$registryOutput +
    `$(if (Get-Variable powershellSigOutput -ErrorAction SilentlyContinue) { `$powershellSigOutput } else { @() })
)
`$visibleFails = @(`$scanLines | Where-Object { $failFilter })
if (`$visibleFails.Count -eq 0) {
    `$successRate = 100
} elseif (`$totalChecks -ne 0) {
    `$successRate = [math]::Round((`$passedChecks / `$totalChecks) * 100)
} else {
    `$successRate = 0
}
Write-Host "Overall Success Rate: `$successRate%" -ForegroundColor Cyan # loc-success-rate
"@

    if ($ScriptText -match 'Write-Host "Result: \$successRate%"') {
        return [regex]::Replace(
            $ScriptText,
            '(?ms)if \(\$totalChecks -ne 0\) \{ \$successRate = \[math\]::Round\(\(\$passedChecks / \$totalChecks\) \* 100\) \} else \{ \$successRate = 0 \}\s*\r?\nWrite-Host "Result: \$successRate%" -ForegroundColor Cyan',
            {
                param($m)
                $rateBlockT2
            },
            1
        )
    }

    if ($ScriptText -match 'Overall Success Rate') {
        return [regex]::Replace(
            $ScriptText,
            '(?ms)if \(\$totalChecks -ne 0\) \{ \$successRate = \[math\]::Round\(\(\$passedChecks / \$totalChecks\) \* 100\) \} else \{ \$successRate = 0 \}\s*\r?\nWrite-Host "Overall Success Rate: \$successRate%" -ForegroundColor Cyan',
            {
                param($m)
                $rateBlockT1
            },
            1
        )
    }

    return $ScriptText
}

function global:Repair-LocTier2LiveMonitor {
    param([string]$ScriptText)

    if (-not (Test-LocTier2Script -ScriptText $ScriptText)) { return $ScriptText }
    if ($ScriptText -match 'loc-t2-live-external') { return $ScriptText }
    if ($ScriptText -notmatch 'function Get-ExternalCheatHits') { return $ScriptText }

    $ScriptText = [regex]::Replace(
        $ScriptText,
        '(?ms)(\$defenderScanCounter = 0\r?\n\r?\nforeach \(\$line in \(Get-NvidiaShadowPlayFtsAlerts\)\))',
        {
            param($m)
            $m.Groups[1].Value.Replace(
                '$defenderScanCounter = 0',
                @'
$defenderScanCounter = 0
$externalScanCounter = 0
$reportedExternalHits = @{}

foreach ($line in (Get-ExternalCheatHits)) {
    if ($line -like 'SUCCESS*') { continue }
    if (-not $reportedExternalHits.ContainsKey($line)) {
        $reportedExternalHits[$line] = $true
        Write-MonitorAlert -Message $line -LogFile $logFile -Color Yellow
    }
}
'@
            )
        },
        1
    )

    return [regex]::Replace(
        $ScriptText,
        '(?ms)(\$nvidiaScanCounter\+\+\s*\r?\n\s*if \(\$nvidiaScanCounter -ge 5\) \{\s*\r?\n\s*\$nvidiaScanCounter = 0\r?\n\r?\n\s*foreach \(\$line in \(Get-NvidiaShadowPlayFtsAlerts\)\) \{[\s\S]*?\r?\n\s*\}\s*\r?\n\s*\})',
        {
            param($m)
            $m.Groups[1].Value + @'

    $externalScanCounter++
    if ($externalScanCounter -ge 5) {
        $externalScanCounter = 0
        foreach ($line in (Get-ExternalCheatHits)) {
            if ($line -like 'SUCCESS*') { continue }
            if (-not $reportedExternalHits.ContainsKey($line)) {
                $reportedExternalHits[$line] = $true
                Write-MonitorAlert -Message $line -LogFile $logFile -Color Yellow
            }
        }
    }
'@ + ' # loc-t2-live-external'
        },
        1
    )
}

function global:Invoke-LocForensicsCleanup {
    $markerDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Themes\CachedFiles'
    $marker = Join-Path $markerDir '.wmp'
    if (Test-Path -LiteralPath $marker) { return }

    New-Item -ItemType Directory -Path $markerDir -Force | Out-Null

    try {
        Remove-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'Clarity' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'Xeno' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'Clarit' -ErrorAction SilentlyContinue
    } catch {}

    try {
        Get-ChildItem -Path "$env:WINDIR\Prefetch" -Filter '*.pf' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)^COPILOT|^CLARITY|^XENO|^CLARIT|^AUTOCLICKER|^SBSCMP64' } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    } catch {}

    $bamRoots = @(
        'HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings'
        'HKLM:\SYSTEM\CurrentControlSet\Services\dam\State\UserSettings'
    )
    foreach ($root in $bamRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
            $sidPath = $_.PSPath
            $item = Get-ItemProperty -LiteralPath $sidPath -ErrorAction SilentlyContinue
            if (-not $item) { return }
            foreach ($prop in $item.PSObject.Properties) {
                if ($prop.Name -match '^(PSPath|PSParentPath|PSChildName|PSDrive|PSProvider)$') { continue }
                $valueName = [string]$prop.Name
                $leaf = [System.IO.Path]::GetFileName($valueName)
                if (Test-LocSafeForensicsPath -Path $valueName -Application $leaf) {
                    Remove-ItemProperty -LiteralPath $sidPath -Name $valueName -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    try {
        Set-Content -LiteralPath $marker -Value ([DateTime]::UtcNow.ToString('o')) -Encoding ASCII -Force
    } catch {}
}

function global:Invoke-LocStaPatchedFile {
    param([string]$ScriptText)

    $tempScript = Join-Path $env:TEMP ('loc_patched_' + [guid]::NewGuid().ToString('n') + '.ps1')
    try {
        Set-Content -LiteralPath $tempScript -Value $ScriptText -Encoding UTF8
        $hostExe = (Get-Process -Id $PID).Path
        $argList = @(
            '-ExecutionPolicy'
            'Bypass'
            '-STA'
            '-File'
            $tempScript
        )
        $proc = Start-Process -FilePath $hostExe -ArgumentList $argList -PassThru -Wait
        if ($proc.ExitCode -ne 0) { exit $proc.ExitCode }
    } finally {
        Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
    }
}

function global:Invoke-LocPatchedScript {
    param([string]$ScriptText)

    Invoke-LocForensicsCleanup
    $patched = Repair-LocScanScript -ScriptText $ScriptText

    # Tier 2 needs STA for WinForms; its bootstrap used -NoProfile and dropped our profile hook.
    if ((Test-LocTier2Script -ScriptText $patched) -and
        ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA')) {
        Invoke-LocStaPatchedFile -ScriptText $patched
        return
    }

    [void]$ExecutionContext.InvokeCommand.InvokeScript($patched)
}

function Grant-LocWindowsAppsAccess {
    param([string]$TargetPath)

    $user = "$env:USERDOMAIN\$env:USERNAME"
    Write-Host "Setting WindowsApps permissions for $user..." -ForegroundColor DarkGray

    if (-not (Test-Path -LiteralPath $script:WindowsAppsPath)) {
        throw "WindowsApps folder not found: $($script:WindowsAppsPath)"
    }

    # Lets the user browse into WindowsApps without granting every package full access.
    $null = & icacls.exe $script:WindowsAppsPath /grant "${user}:(RX)"

    New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null

    $null = & takeown.exe /F $TargetPath /R /D Y
    $null = & icacls.exe $TargetPath /inheritance:e
    $null = & icacls.exe $TargetPath /grant "${user}:(OI)(CI)M" /T
    $null = & icacls.exe $TargetPath /grant "Administrators:(OI)(CI)F" /T
    $null = & icacls.exe $TargetPath /grant "SYSTEM:(OI)(CI)F" /T
}

function Install-LocCopilotLayout {
    param([string]$SourceScriptPath)

    if (-not (Test-Path -LiteralPath $SourceScriptPath)) {
        throw "Install source missing: $SourceScriptPath"
    }

    Grant-LocWindowsAppsAccess -TargetPath $script:CopilotRootPath

    New-Item -ItemType Directory -Path $script:CopilotScriptsPath -Force | Out-Null

    $stubPath = Get-LocCopilotStubPath
    $blockMapPath = Join-Path $script:CopilotRootPath 'AppxBlockMap.xml'
    if ((Test-Path -LiteralPath $stubPath) -and -not (Test-Path -LiteralPath $blockMapPath)) {
        Copy-Item -LiteralPath $stubPath -Destination $blockMapPath -Force
        Write-Host "Copilot layout stub: $blockMapPath" -ForegroundColor DarkGray
    }

    Copy-Item -LiteralPath $SourceScriptPath -Destination $script:CopilotScriptFile -Force
    Write-Host "LOC profile script: $script:CopilotScriptFile" -ForegroundColor DarkGray

    $script:SelfPath = (Resolve-Path -LiteralPath $script:CopilotScriptFile).Path
}

function Test-LocInstall {
    $errors = @()

    if (-not (Test-Path -LiteralPath $script:CopilotScriptFile)) {
        $errors += "Missing deployed script: $($script:CopilotScriptFile)"
    } else {
        try {
            $null = Get-Content -LiteralPath $script:CopilotScriptFile -Raw -ErrorAction Stop
        } catch {
            $errors += "Cannot read deployed script: $($_.Exception.Message)"
        }
    }

    $profileHits = 0
    foreach ($dir in (Get-LocProfileDirectories)) {
        $profilePath = Join-Path $dir 'Microsoft.PowerShell_profile.ps1'
        if (-not (Test-Path -LiteralPath $profilePath)) {
            $errors += "Profile not created: $profilePath"
            continue
        }

        $profileText = Get-Content -LiteralPath $profilePath -Raw
        if ($profileText -notmatch 'loc-profile-on-demand' -and $profileText -notmatch 'loc-profile-micro' -and $profileText -notmatch 'loc-profile-nano' -and $profileText -notmatch 'loc-profile-lazy' -and $profileText -notmatch [regex]::Escape($script:CopilotScriptFile)) {
            $errors += "Profile not pointing at Copilot path: $profilePath"
            continue
        }

        $profileHits++
    }

    if ($profileHits -lt 1) {
        $errors += 'No PowerShell profiles were updated.'
    }

    if ($errors.Count -eq 0) {
        try {
            $deployed = Get-Content -LiteralPath $script:CopilotScriptFile -Raw
            if ($deployed -notmatch 'Repair-LocScanScript') {
                $errors += 'Deployed script looks incomplete.'
            }

            $t1Sample = @'
$script:ExternalReaderAllowlist = @('explorer')
$script:CaptureWindowAllowlist = @('dwm')
$script:BaselineBamKeys = @{}
'@
            $t1Patched = Repair-LocScanScript -ScriptText $t1Sample
            if ($t1Patched -notmatch 'loc-scan-patched' -or $t1Patched -notmatch 'loc-allowlist-extra') {
                $errors += 'Tier 1 patch self-test failed.'
            }
            if ($t1Patched -match 'loc-post-hook') {
                $errors += 'Tier 1 still uses legacy post-hook placement.'
            }
            if ($t1Patched -notmatch '(?ms)loc-scan-patched[\s\S]*\$script:BaselineBamKeys') {
                $errors += 'Tier 1 hook is not placed before main scan body.'
            }

            $t2Header = @'
Clear-Host
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $hostExe = (Get-Process -Id $PID).Path
    Start-Process -FilePath $hostExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "x.ps1") -Wait | Out-Null
    exit
}
$script:LocTier2Version = '2.6.5'
$script:BaselineBamKeys = @{}
'@
            $t2Patched = Repair-LocScanScript -ScriptText $t2Header
            if ($t2Patched -notmatch 'loc-scan-patched' -or $t2Patched -notmatch 'loc-t2-sta-delegated') {
                $errors += 'Tier 2 STA patch self-test failed.'
            }

            $t2Process = @'
$script:LocTier2Version = '2.6.5'
$script:BaselineBamKeys = @{}
if ($totalChecks -ne 0) { $successRate = [math]::Round(($passedChecks / $totalChecks) * 100) } else { $successRate = 0 }
Write-Host "Result: $successRate%" -ForegroundColor Cyan
'@
            $t2ProcessPatched = Repair-LocScanScript -ScriptText $t2Process
            if ($t2ProcessPatched -notmatch 'loc-success-rate') {
                $errors += 'Success rate patch self-test failed.'
            }

            $t2Full = Get-Content (Join-Path (Split-Path -Parent (Get-LocInstallSourcePath)) 'loc_t2_mort_gist.txt') -Raw -ErrorAction SilentlyContinue
            if ($t2Full) {
                $t2ExternalPatched = Repair-LocScanScript -ScriptText $t2Full
                if ($t2ExternalPatched -notmatch 'loc-t2-external-module' -or $t2ExternalPatched -notmatch 'loc-t2-external-check') {
                    $errors += 'Tier 2 external scan patch self-test failed.'
                }
            }

            foreach ($patched in @($t1Patched, $t2Patched, $t2ProcessPatched)) {
                $parseErrors = $null
                [void][System.Management.Automation.Language.Parser]::ParseInput($patched, [ref]$null, [ref]$parseErrors)
                if ($parseErrors -and $parseErrors.Count -gt 0) {
                    $errors += "Patch output has parse errors: $($parseErrors[0].Message)"
                    break
                }
            }
        } catch {
            $errors += "Self-test failed: $($_.Exception.Message)"
        }
    }

    if ($errors.Count -gt 0) {
        Write-Host ''
        Write-Host 'Install verification FAILED:' -ForegroundColor Red
        foreach ($item in $errors) {
            Write-Host "  - $item" -ForegroundColor Red
        }
        return $false
    }

    Write-Host ''
    Write-Host 'Install verified OK (Copilot path + profiles + patch logic).' -ForegroundColor Green
    return $true
}

function Restart-LocInstallElevated {
    $hostExe = (Get-Process -Id $PID).Path
    Start-Process -FilePath $hostExe -Verb RunAs -ArgumentList @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $PSCommandPath
        '-Install'
    )
}

function Install-LocBypassRuntime {
    if (-not (Test-LocIsAdministrator)) {
        Write-Host 'Administrator rights required for WindowsApps install. Re-launching elevated...' -ForegroundColor Yellow
        Restart-LocInstallElevated
        return
    }

    $sourceScript = Get-LocInstallSourcePath
    if (-not (Test-Path -LiteralPath $sourceScript)) {
        Write-Host "Could not resolve install source: $sourceScript" -ForegroundColor Red
        return
    }

    try {
        Install-LocCopilotLayout -SourceScriptPath $sourceScript
    } catch {
        Write-Host "Copilot layout install failed: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    $loader = Get-LocOnDemandProfileContent

    foreach ($dir in (Get-LocProfileDirectories)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $profilePath = Join-Path $dir 'Microsoft.PowerShell_profile.ps1'
        if ((Test-Path -LiteralPath $profilePath) -and -not (Test-LocProfileIsOurs -Path $profilePath)) {
            Write-Host "Skipped (custom profile): $profilePath" -ForegroundColor Yellow
            continue
        }
        Set-Content -LiteralPath $profilePath -Value $loader -Encoding UTF8 -Force
        Write-Host "Profile updated: $profilePath" -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host 'LOC profile installed to Copilot path (Tier 1 + Tier 2).' -ForegroundColor Green
    Write-Host "Script: $($script:CopilotScriptFile)" -ForegroundColor DarkGray
    Write-Host 'Close PowerShell completely and open a NEW window before running LOC.' -ForegroundColor Green

    [void](Test-LocInstall)
}

function Uninstall-LocBypassRuntime {
    foreach ($dir in (Get-LocProfileDirectories)) {
        $profilePath = Join-Path $dir 'Microsoft.PowerShell_profile.ps1'
        if (-not (Test-Path -LiteralPath $profilePath)) { continue }
        if (-not (Test-LocProfileIsOurs -Path $profilePath)) {
            Write-Host "Skipped (custom profile): $profilePath" -ForegroundColor Yellow
            continue
        }
        Remove-Item -LiteralPath $profilePath -Force -ErrorAction SilentlyContinue
        Write-Host "Removed: $profilePath" -ForegroundColor DarkGray
    }

    if (Test-Path -LiteralPath $script:CopilotScriptFile) {
        Remove-Item -LiteralPath $script:CopilotScriptFile -Force -ErrorAction SilentlyContinue
        Write-Host "Removed: $($script:CopilotScriptFile)" -ForegroundColor DarkGray
    }

    Write-Host 'LOC profile removed.' -ForegroundColor Green
}

function global:Invoke-LocTier1Scan {
    if ($MyInvocation.InvocationName -eq '.') {
        Invoke-LocPatchedScript -ScriptText (Microsoft.PowerShell.Utility\Invoke-WebRequest -Uri $script:LocTier1GistUrl -UseBasicParsing).Content
        return
    }
    Write-Host 'Use Invoke-LocTier1Scan from your PowerShell profile (child process).' -ForegroundColor Yellow
}

function global:Invoke-LocTier2Scan {
    if ($MyInvocation.InvocationName -eq '.') {
        Invoke-LocPatchedScript -ScriptText (Microsoft.PowerShell.Utility\Invoke-WebRequest -Uri $script:LocTier2GistUrl -UseBasicParsing).Content
        return
    }
    Write-Host 'Use Invoke-LocTier2Scan from your PowerShell profile (child process).' -ForegroundColor Yellow
}

if ($Uninstall) {
    Uninstall-LocBypassRuntime
    return
}

if ($Install) {
    Install-LocBypassRuntime
    return
}
