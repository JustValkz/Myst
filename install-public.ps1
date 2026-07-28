# Install Myst Public (standalone EXE).
#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

$BaseUrl = 'https://raw.githubusercontent.com/JustValkz/Myst/main'
$InstallDir = Join-Path $env:LOCALAPPDATA 'MystPublic'
$ExePath = Join-Path $InstallDir 'MystPublic.exe'

function Write-Step {
    param([string]$Message, [string]$Color = 'Cyan')
    Write-Host $Message -ForegroundColor $Color
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

Write-Step 'Downloading MystPublic.exe...'
$exeUrl = "$BaseUrl/MystPublic.exe"
Invoke-WebRequest -Uri $exeUrl -OutFile $ExePath -UseBasicParsing

Write-Step 'Launching Myst Public...' 'Green'
Start-Process -FilePath $ExePath
Write-Step "Installed to $ExePath" 'Green'
