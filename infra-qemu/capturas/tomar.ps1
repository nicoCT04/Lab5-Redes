# Abre una consola, corre los comandos y captura solo esa ventana.
param([string]$Lista, [string]$Png, [int]$Ancho = 120, [int]$Alto = 40, [int]$Espera = 120, [int]$CapturarTras = 0)
. "$PSScriptRoot\capturar.ps1"
$Titulo = "Lab5 - " + [IO.Path]::GetFileNameWithoutExtension($Png)
Remove-Item "$Lista.listo" -ErrorAction SilentlyContinue
$p = Start-Process conhost.exe -PassThru -ArgumentList "powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\correr.ps1`" -Lista `"$Lista`" -Titulo `"$Titulo`" -Ancho $Ancho -Alto $Alto"
if ($CapturarTras -gt 0) { Start-Sleep $CapturarTras }
else { for ($i = 0; $i -lt $Espera -and -not (Test-Path "$Lista.listo"); $i++) { Start-Sleep 1 } }
Start-Sleep 1
$v = Get-Process powershell, conhost, telnet -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and ($_.MainWindowTitle -like "*$Titulo*" -or $_.MainWindowTitle -like "*Telnet*") } | Select-Object -First 1
if (-not $v) { $v = Esperar-Ventana "powershell" $Titulo 10 }
[Win]::Capturar($v.MainWindowHandle, $Png)
Stop-Process -Id $v.Id -Force -ErrorAction SilentlyContinue
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Write-Host "captura: $Png"
