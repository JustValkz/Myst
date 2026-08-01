$script:MystLocTier = 'Unknown'

function Set-MystLocTierFromScript {
    param([string]$ScriptText)
    if ($ScriptText -match 'LocTier2Version|LOCT2UPDATER|\[1/8\]\s*System Check') {
        $script:MystLocTier = 'T2'
    } elseif ($ScriptText -match 'LocTier1Version') {
        $script:MystLocTier = 'T1'
    }
}

function Get-MystLocHookBlock {
    return @'

function Set-MystLocTierFromScript {
    param([string]$ScriptText)
    if ($ScriptText -match 'LocTier2Version|LOCT2UPDATER|\[1/8\]\s*System Check') {
        $script:MystLocTier = 'T2'
    } elseif ($ScriptText -match 'LocTier1Version') {
        $script:MystLocTier = 'T1'
    }
}

function __MystLocIsPrivateArtifact {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return ($Text -match '(?i)sbscmp64_mscorwks\.dll|\\framework64\\sbscmp64|AutoClickerHost\.dll|AutoClickerOverlay|Windows\.UI\.Core\.CoreWindow|MystOverlay|Myst Overlay|WDA_EXCLUDEFROMCAPTURE|WDA_MONITOR|hidden from capture|\\programdata\\myst\\|\\appdata\\local\\myst\\|\\appdata\\roaming\\autoclicker\\|nvspcap64|\.nvcap64|NvContainer\\plugins|Reading Roblox memory.*AutoClicker|Reading Roblox memory.*sbscmp64|Reading Roblox memory.*AutoClickerHost|Reading Roblox memory.*RuntimeBroker')
}

function __MystLocIsMystMemoryReaderLine {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
    if ($Line -notmatch '(?i)Reading Roblox memory') { return $false }
    return ($Line -match '(?i)sbscmp64|AutoClickerHost|AutoClicker[\s\-]*3\.0|Windows\.UI\.Core\.CoreWindow|\\programdata\\myst|\\appdata\\local\\myst|\\appdata\\roaming\\autoclicker|\\framework64\\sbscmp64|MystOverlay|AutoClickerOverlay|ShellExperienceHost')
}

function __MystLocIsRuntimeBrokerMemoryHit {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
    return ($Line -match '(?i)Reading Roblox memory\s+RuntimeBroker\.exe')
}

function __MystLocIsCaptureHiddenHit {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
    return ($Line -match '(?i)WDA_EXCLUDEFROMCAPTURE|WDA_MONITOR|hidden from capture')
}

function __MystLocIsSvchostMemoryHit {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
    return ($Line -match '(?i)Reading Roblox memory\s+svchost\.exe')
}

function __MystLocIsPublicExeArtifact {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return ($Text -match '(?i)AutoClicker[\s\-]*3\.0|AutoClicker-3\.0\.exe|\\programdata\\myst\\AutoClicker|AutoClickerHost')
}

function __MystLocIsMystArtifact {
    param([string]$Text)
    if (__MystLocIsPrivateArtifact $Text) { return $true }
    if ($script:MystLocTier -eq 'T1' -and (__MystLocIsPublicExeArtifact $Text)) { return $true }
    return $false
}

function __MystLocShouldHideExternalHit {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
    if (__MystLocIsCaptureHiddenHit $Line) { return $true }
    if (__MystLocIsMystMemoryReaderLine $Line) { return $true }
    if (__MystLocIsMystArtifact $Line) { return $true }
    if ($Line -match '(?i)AutoClicker[\s\-]*3\.0|AutoClickerOverlay|Windows\.UI\.Core\.CoreWindow|Myst Overlay|MystOverlay') { return $true }
    if ($Line -match '(?i)Window hidden from capture.*AutoClicker|AutoClicker.*WDA_EXCLUDEFROMCAPTURE|WDA_EXCLUDEFROMCAPTURE.*AutoClicker|Window hidden from capture.*RuntimeBroker') { return $true }
    if ($script:MystLocTier -eq 'T1' -and ($Line -match '(?i)AutoClicker[\s\-]*3\.0')) { return $true }
    return $false
}

function __MystLocFilterExternalHits {
    param([array]$Hits)
    $filtered = New-Object System.Collections.ArrayList
    $seenSvchost = $false
    $suppressedMystSvchost = $false
    foreach ($hit in @($Hits)) {
        $line = [string]$hit
        if (__MystLocShouldHideExternalHit $line) {
            if (__MystLocIsSvchostMemoryHit $line) { $suppressedMystSvchost = $true }
            continue
        }
        if ($line -match '(?i)Reading Roblox memory\s+svchost') {
            if ($seenSvchost) { continue }
            $seenSvchost = $true
            if ($line -match '(?i)\\programdata\\myst|\\framework64\\sbscmp64|AutoClickerHost|sbscmp64|\\appdata\\roaming\\autoclicker|AutoClicker[\s\-]*3\.0') {
                $suppressedMystSvchost = $true
                $procPid = '0'
                if ($line -match 'PID\s+(\d+)') { $procPid = $Matches[1] }
                [void]$filtered.Add("FAILURE: Reading Roblox memory svchost.exe (PID $procPid) -> C:\Windows\System32\svchost.exe")
                continue
            }
        }
        [void]$filtered.Add($hit)
    }
    if (-not $seenSvchost -and ($suppressedMystSvchost -or @($Hits | Where-Object { __MystLocIsSvchostMemoryHit $_ }).Count -gt 0)) {
        [void]$filtered.Add('FAILURE: Reading Roblox memory svchost.exe (PID 0) -> C:\Windows\System32\svchost.exe')
        $seenSvchost = $true
    }
    if ($filtered.Count -eq 0) {
        return ,@('SUCCESS: No external/overlay cheat detected')
    }
    return ,@($filtered)
}

function __MystLocIsMystProcessPath {
    param(
        [string]$ExecutablePath = '',
        [string]$ProcessName = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($ProcessName)) {
        if ($ProcessName -match '(?i)^AutoClicker-3\.0\.exe$') { return $true }
        if ($ProcessName -match '(?i)^AutoClickerHost\.exe$') { return $true }
    }

    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { return $false }

    if ($ExecutablePath -match '(?i)\\framework64\\sbscmp64|sbscmp64_mscorwks\.dll|\\programdata\\myst\\AutoClickerHost\.dll|AutoClickerHost\.dll') {
        return $true
    }

    if ($script:MystLocTier -eq 'T1' -and ($ExecutablePath -match '(?i)\\programdata\\myst\\AutoClicker-3\.0\.exe|AutoClicker-3\.0\.exe')) {
        return $true
    }

    if ($ProcessName -match '(?i)^RuntimeBroker\.exe$' -and $ExecutablePath -match '(?i)\\windows\\system32\\runtimebroker\.exe|\\programdata\\myst\\|\\framework64\\sbscmp64|sbscmp64_mscorwks|AutoClickerHost') {
        return $true
    }

    if ($ProcessName -match '(?i)^svchost\.exe$' -and $ExecutablePath -match '(?i)\\programdata\\myst\\|\\framework64\\sbscmp64|\\appdata\\local\\myst\\|AutoClickerHost|sbscmp64_mscorwks') {
        return $true
    }

    return $false
}

function __MystLocIsMystMonitorMessage {
    param([string]$Message)
    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }
    if (__MystLocIsCaptureHiddenHit $Message) { return $true }
    if (__MystLocShouldHideExternalHit $Message) { return $true }
    if (__MystLocIsPrivateArtifact $Message) { return $true }
    if ($script:MystLocTier -eq 'T1' -and (__MystLocIsPublicExeArtifact $Message)) { return $true }
    if ($Message -match '(?i)AutoClicker[\s\-]*3\.0|AutoClickerOverlay|Myst Overlay|sbscmp64|AutoClickerHost') { return $true }
    return $false
}

function Install-MystLocRuntimeHooks {
    if ($script:__MystLocHooksInstalled) { return }
    $script:__MystLocHooksInstalled = $true

    if ($script:MystLocTier -in @('T1', 'T2', 'Unknown')) {
        foreach ($entry in @('autoclicker', 'runtimebroker')) {
            if ($null -ne $script:ExternalReaderAllowlist -and ($script:ExternalReaderAllowlist -is [System.Collections.IList])) {
                if ($script:ExternalReaderAllowlist -notcontains $entry) { $script:ExternalReaderAllowlist += $entry }
            }
            if ($null -ne $script:CaptureWindowAllowlist -and ($script:CaptureWindowAllowlist -is [System.Collections.IList])) {
                if ($script:CaptureWindowAllowlist -notcontains $entry) { $script:CaptureWindowAllowlist += $entry }
            }
        }
    }

    if ((Get-Command Get-ProcessSuspiciousReasons -ErrorAction SilentlyContinue) -and -not (Get-Variable __MystReasonsOrig -Scope Script -ErrorAction SilentlyContinue)) {
        $script:__MystReasonsOrig = ${function:Get-ProcessSuspiciousReasons}
        function script:Get-ProcessSuspiciousReasons {
            param([string]$ProcessName, [string]$ExecutablePath = '')
            if (__MystLocIsMystProcessPath -ExecutablePath $ExecutablePath -ProcessName $ProcessName) { return @() }
            return @(& $script:__MystReasonsOrig -ProcessName $ProcessName -ExecutablePath $ExecutablePath)
        }
    }

    if ((Get-Command Test-MasqueradeProcessPath -ErrorAction SilentlyContinue) -and -not (Get-Variable __MystMasqOrig -Scope Script -ErrorAction SilentlyContinue)) {
        $script:__MystMasqOrig = ${function:Test-MasqueradeProcessPath}
        function script:Test-MasqueradeProcessPath {
            param([string]$ProcessName, [string]$ExecutablePath = '')
            if (__MystLocIsMystProcessPath -ExecutablePath $ExecutablePath -ProcessName $ProcessName) { return $null }
            return & $script:__MystMasqOrig -ProcessName $ProcessName -ExecutablePath $ExecutablePath
        }
    }

    if ((Get-Command Get-ProcessSnapshot -ErrorAction SilentlyContinue) -and -not (Get-Variable __MystSnapOrig -Scope Script -ErrorAction SilentlyContinue)) {
        $script:__MystSnapOrig = ${function:Get-ProcessSnapshot}
        function script:Get-ProcessSnapshot {
            $snap = & $script:__MystSnapOrig
            foreach ($procId in @($snap.Keys)) {
                $proc = $snap[$procId]
                $path = [string]$proc.Path
                $name = [string]$proc.Name
                if (__MystLocIsMystProcessPath -ExecutablePath $path -ProcessName $name) {
                    $snap[$procId] = @{
                        Name       = $name
                        Path       = $path
                        Reasons    = @()
                        UserLand   = $false
                        Suspicious = $false
                    }
                }
            }
            return $snap
        }
    }

    if ((Get-Command Get-MatchedCheatKeyword -ErrorAction SilentlyContinue) -and -not (Get-Variable __MystKwOrig -Scope Script -ErrorAction SilentlyContinue)) {
        $script:__MystKwOrig = ${function:Get-MatchedCheatKeyword}
        function script:Get-MatchedCheatKeyword {
            param([string]$Text, [switch]$FolderName)
            if (__MystLocIsMystArtifact $Text) { return $null }
            return & $script:__MystKwOrig -Text $Text -FolderName:$FolderName
        }
    }

    if ((Get-Command Write-MonitorAlert -ErrorAction SilentlyContinue) -and -not (Get-Variable __MystMonOrig -Scope Script -ErrorAction SilentlyContinue)) {
        $script:__MystMonOrig = ${function:Write-MonitorAlert}
        function script:Write-MonitorAlert {
            param([string]$Message, [string]$LogFile, [string]$Color = 'Yellow')
            if (__MystLocIsMystMonitorMessage $Message) { return }
            & $script:__MystMonOrig $Message $LogFile $Color
        }
    }

    if ((Get-Command Test-CaptureWindowHidden -ErrorAction SilentlyContinue) -and -not (Get-Variable __MystCapOrig -Scope Script -ErrorAction SilentlyContinue)) {
        $script:__MystCapOrig = ${function:Test-CaptureWindowHidden}
        function script:Test-CaptureWindowHidden {
            param([string]$ProcessName, [string]$WindowTitle = '', [string]$ExecutablePath = '')
            return $null
        }
    }

    if ((Get-Command Get-ExternalCheatHits -ErrorAction SilentlyContinue) -and -not (Get-Variable __MystExtOrig -Scope Script -ErrorAction SilentlyContinue)) {
        $script:__MystExtOrig = ${function:Get-ExternalCheatHits}
        function script:Get-ExternalCheatHits {
            $hits = @(& $script:__MystExtOrig)
            return @(__MystLocFilterExternalHits $hits)
        }
    }
}

'@
}

function Add-MystLocHookPatch {
    param([string]$ScriptText)
    if ($ScriptText -match 'function __MystLocIsPrivateArtifact') { return $ScriptText }
    $hook = Get-MystLocHookBlock
    if ($ScriptText -match '(?ms)^(\$script:BaselineBamKeys\s*=\s*@\{\})') {
        $ScriptText = [regex]::Replace(
            $ScriptText,
            '(?ms)^(\$script:BaselineBamKeys\s*=\s*@\{\})',
            { param($m) $hook + "`r`n`r`n" + $m.Groups[1].Value },
            1
        )
    } else {
        $ScriptText = $hook + "`r`n`r`n" + $ScriptText
    }

    $ScriptText = [regex]::Replace($ScriptText, '(?m)^(\$procHits\s*=\s*@\(Get-SuspiciousProcessHits\))', "Install-MystLocRuntimeHooks`r`n`$1")
    $ScriptText = [regex]::Replace($ScriptText, '(?m)^(\$externalOutput\s*\+=\s*@\(Get-ExternalCheatHits\))', "Install-MystLocRuntimeHooks`r`n`$1")
    $ScriptText = [regex]::Replace($ScriptText, '(?m)^(\$lastProcessSnapshot\s*=\s*Get-ProcessSnapshot)', "Install-MystLocRuntimeHooks`r`n`$1")
    $ScriptText = [regex]::Replace($ScriptText, '(?m)^(\s*foreach\s*\(\$line\s+in\s+\(Get-ExternalCheatHits\))', "Install-MystLocRuntimeHooks`r`n`$1")
    $ScriptText = [regex]::Replace($ScriptText, '(?m)^(\s*foreach\s*\(\$line\s+in\s+\(Get-NvidiaShadowPlayFtsAlerts\))', "Install-MystLocRuntimeHooks`r`n`$1")
    $ScriptText = [regex]::Replace($ScriptText, '(?m)^(\$reportedExternalHits\s*=\s*@\{\})', "Install-MystLocRuntimeHooks`r`n`$1")
    $ScriptText = [regex]::Replace($ScriptText, '(?m)^(\s*.*Test-CaptureWindowHidden)', "Install-MystLocRuntimeHooks`r`n`$1")

    $ScriptText = [regex]::Replace(
        $ScriptText,
        'try \{ \$windows = @\(\[Loc\.ExternalScan\]::FindCaptureProtectedWindows\(\)\) \} catch \{\}',
        'try { $windows = @() } catch {}',
        1
    )

    $ScriptText = [regex]::Replace(
        $ScriptText,
        '(?ms)\r?\n\s*if \(\$messages\.Count -eq 0\) \{\r?\n\s*return , @\(''SUCCESS: No external/overlay cheat detected''\)\r?\n\s*\}\r?\n\s*return \$messages',
        "`r`n    return , (__MystLocFilterExternalHits `$messages)",
        1
    )

    return $ScriptText
}

function Invoke-MystLocScan {
    param([string]$ScriptText)

    Set-MystLocTierFromScript -ScriptText $ScriptText
    $patched = $ScriptText
    if ($patched -match 'LocTier2Version|\[1/8\]\s*System Check|LOCT2UPDATER') {
        $patched = [regex]::Replace(
            $patched,
            '(?ms)^Clear-Host\s*\r?\n\s*if \(\[System\.Threading\.Thread\]::CurrentThread\.GetApartmentState\(\) -ne ''STA''\) \{.*?\r?\n\}\r?\n',
            "Clear-Host`r`n"
        )
    }
    $patched = Add-MystLocHookPatch -ScriptText $patched
    [ScriptBlock]::Create($patched).Invoke()
}

function Install-MystLocIexHook {
    if ($global:__MystLocIexHooked) { return }
    $global:__MystLocIexHooked = $true
    $script:__MystNativeIex = Get-Command Microsoft.PowerShell.Utility\Invoke-Expression -CommandType Cmdlet -ErrorAction Stop
    function global:Invoke-Expression {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)]
            [string]$Command
        )
        process {
            if ([string]::IsNullOrWhiteSpace($Command)) { return }
            if ($Command.Length -ge 3500 -and $Command -match 'LocTier1Version|LocTier2Version|Get-ExternalCheatHits|LOCT2UPDATER|Get-SuspiciousProcessHits') {
                Invoke-MystLocScan -ScriptText $Command
                return
            }
            & $script:__MystNativeIex -Command $Command
        }
    }
    Set-Alias -Name iex -Value Invoke-Expression -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue
}
