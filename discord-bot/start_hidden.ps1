$botDir = $PSScriptRoot
$node = 'C:\Program Files\nodejs\node.exe'

if (-not (Test-Path $node)) {
    $node = (Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
}

if (-not $node) {
    exit 1
}

$indexScript = Join-Path $botDir 'src\index.js'

$running = Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*$indexScript*" } |
    Select-Object -First 1

if ($running) { exit 0 }

Start-Process -FilePath $node `
    -ArgumentList "`"$indexScript`"" `
    -WorkingDirectory $botDir `
    -WindowStyle Hidden | Out-Null
