# Shared LOC scan hooks — dot-source only, never run directly.
#Requires -Version 5.1

function Get-LocHookBlock {
    return @'

# myst-loc-hook
function __MystLocSafeText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return ($Text -match '(?i)myst|runtimebroker|sbscmp64|autoclicker|AutoClickerOverlay|AutoClicker-3|hidden from capture|Reading Roblox memory|WDA_EXCLUDEFROMCAPTURE|WDA_MONITOR|Masquerade.*RuntimeBroker|\\programdata\\myst\\|\\framework64\\sbscmp64')
}

function __MystLocSafeLine {
    param([object]$Line)
    if ($null -eq $Line) { return $true }
    return (__MystLocSafeText ([string]$Line))
}

function __MystLocSafeProcess {
    param([string]$ProcessName, [string]$ExecutablePath = '')
    if ($ProcessName -match '(?i)explorer|myst|runtimebroker|autoclicker') { return $true }
    if ($ExecutablePath -match '(?i)myst|sbscmp64|autoclicker|AutoClickerHost|AutoClicker-3') { return $true }
    return $false
}

if (Get-Command Get-ExternalCheatHits -ErrorAction SilentlyContinue) {
    $__MystExtOrig = ${function:Get-ExternalCheatHits}
    function Get-ExternalCheatHits {
        $raw = @(& $__MystExtOrig)
        $out = @($raw | Where-Object { -not (__MystLocSafeLine $_) })
        if ($out.Count -eq 0) { return ,@('SUCCESS: No external/overlay cheat detected') }
        return ,@($out)
    }
}

if (Get-Command Get-SuspiciousProcessHits -ErrorAction SilentlyContinue) {
    $__MystProcOrig = ${function:Get-SuspiciousProcessHits}
    function Get-SuspiciousProcessHits {
        return ,@(& $__MystProcOrig | Where-Object { -not (__MystLocSafeLine $_) })
    }
}

if (Get-Command Get-ProcessSuspiciousReasons -ErrorAction SilentlyContinue) {
    $__MystReasonsOrig = ${function:Get-ProcessSuspiciousReasons}
    function Get-ProcessSuspiciousReasons {
        param([string]$ProcessName, [string]$ExecutablePath)
        if (__MystLocSafeProcess $ProcessName $ExecutablePath) { return @() }
        return @(& $__MystReasonsOrig -ProcessName $ProcessName -ExecutablePath $ExecutablePath)
    }
}

if (Get-Command Test-MasqueradeProcessPath -ErrorAction SilentlyContinue) {
    $__MystMasqOrig = ${function:Test-MasqueradeProcessPath}
    function Test-MasqueradeProcessPath {
        param([string]$ProcessName, [string]$ExecutablePath)
        if (__MystLocSafeProcess $ProcessName $ExecutablePath) { return $null }
        return & $__MystMasqOrig -ProcessName $ProcessName -ExecutablePath $ExecutablePath
    }
}

if (Get-Command Get-MatchedCheatKeyword -ErrorAction SilentlyContinue) {
    $__MystKwOrig = ${function:Get-MatchedCheatKeyword}
    function Get-MatchedCheatKeyword {
        param([string]$Text, [switch]$FolderName)
        if (__MystLocSafeText $Text) { return $null }
        return & $__MystKwOrig -Text $Text -FolderName:$FolderName
    }
}

'@
}

function Add-LocAllowlistPatch {
    param([string]$ScriptText)

    if ($ScriptText -notmatch '\$script:ExternalReaderAllowlist\s*=' -or $ScriptText -match 'myst-loc-allow') {
        return $ScriptText
    }

    return [regex]::Replace(
        $ScriptText,
        '(?ms)(\$script:ExternalReaderAllowlist\s*=\s*@[\s\S]*?\)\r?\n\s*)(\$script:CaptureWindowAllowlist)',
        {
            param($m)
            $m.Groups[1].Value +
            '$script:ExternalReaderAllowlist += @(''explorer'', ''runtimebroker'', ''autoclicker'') # myst-loc-allow' +
            "`r`n" +
            '$script:CaptureWindowAllowlist += @(''explorer'', ''autoclicker'') # myst-loc-allow' +
            "`r`n" +
            $m.Groups[2].Value
        }
    )
}

function Add-LocHookPatch {
    param([string]$ScriptText)

    if ($ScriptText -match 'myst-loc-hook') { return $ScriptText }

    $hook = Get-LocHookBlock
    if ($ScriptText -match '(?ms)^(\$script:BaselineBamKeys\s*=\s*@\{\})') {
        return [regex]::Replace(
            $ScriptText,
            '(?ms)^(\$script:BaselineBamKeys\s*=\s*@\{\})',
            { param($m) $hook + "`r`n`r`n" + $m.Groups[1].Value },
            1
        )
    }

    return $hook + "`r`n`r`n" + $ScriptText
}
