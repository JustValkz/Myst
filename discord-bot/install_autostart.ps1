$ErrorActionPreference = 'Stop'

$botDir = $PSScriptRoot
$runScript = Join-Path $botDir 'run_hidden.vbs'
$watchScript = Join-Path $botDir 'watch_bot.vbs'
$wscript = Join-Path $env:Windir 'System32\wscript.exe'
$taskName = 'MystLicenseBot'
$watchTaskName = 'MystLicenseBotWatch'
$startupLink = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\MystLicenseBot.lnk'

function Test-BotRunning {
    $indexScript = Join-Path $botDir 'src\index.js'
    Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*$indexScript*" } |
        Select-Object -First 1
}

function Start-BotHidden {
    if (Test-BotRunning) { return }
    Start-Process -FilePath $wscript -ArgumentList "//B `"$runScript`"" -WindowStyle Hidden
    Start-Sleep -Seconds 3
}

function Install-StartupShortcut {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($startupLink)
    $shortcut.TargetPath = $wscript
    $shortcut.Arguments = "//B `"$runScript`""
    $shortcut.WorkingDirectory = $botDir
    $shortcut.WindowStyle = 7
    $shortcut.Description = 'Myst License Discord Bot'
    $shortcut.Save()
}

function Remove-StartupShortcut {
    if (Test-Path -LiteralPath $startupLink) {
        Remove-Item -LiteralPath $startupLink -Force -ErrorAction SilentlyContinue
    }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    try {
        $logonAction = New-ScheduledTaskAction -Execute $wscript -Argument "//B `"$runScript`""
        $logonTrigger = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Days 3650)

        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName $taskName -Action $logonAction -Trigger $logonTrigger -Principal $principal -Settings $settings -Force | Out-Null

        $watchAction = New-ScheduledTaskAction -Execute $wscript -Argument "//B `"$watchScript`""
        $watchTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)

        Unregister-ScheduledTask -TaskName $watchTaskName -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName $watchTaskName -Action $watchAction -Trigger $watchTrigger -Principal $principal -Settings $settings -Force | Out-Null

        Remove-StartupShortcut
        Write-Host "Installed silent scheduled tasks: $taskName, $watchTaskName"
    } catch {
        Write-Host "Scheduled tasks skipped: $($_.Exception.Message)" -ForegroundColor Yellow
        Install-StartupShortcut
        Write-Host "Installed silent Startup shortcut instead."
    }
} else {
    Install-StartupShortcut
    Write-Host "Installed silent Startup shortcut (runs at login)."
}

Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*$botDir\src\index.js*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Start-Sleep -Seconds 1
Start-BotHidden

$proc = Test-BotRunning
if ($proc) {
    Write-Host "Myst bot running hidden (PID $($proc.ProcessId))."
} else {
    Write-Host "Failed to start bot. Check .env and Node.js." -ForegroundColor Red
    exit 1
}
