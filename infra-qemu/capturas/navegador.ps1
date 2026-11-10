# Abre una URL en Edge (perfil temporal, sin asistentes de primer uso) y captura solo esa ventana.
param([string]$Url, [string]$Png, [string]$Titulo, [int]$Espera = 8)
. "$PSScriptRoot\capturar.ps1"
$Perfil = "$env:TEMP\lab5\edge-perfil"
$Edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
$p = Start-Process $Edge -PassThru -ArgumentList "--user-data-dir=`"$Perfil`"", "--no-first-run",
  "--no-default-browser-check", "--disable-features=msEdgeSidebarV2,msHubApps", "--window-size=1400,900",
  "--window-position=40,40", "--new-window", $Url
Start-Sleep $Espera
$v = Esperar-Ventana "msedge" $Titulo 20
[Win]::Capturar($v.MainWindowHandle, $Png)
Write-Host "captura: $Png ($($v.MainWindowTitle))"
