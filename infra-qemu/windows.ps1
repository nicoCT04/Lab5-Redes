# Configura Windows como cliente del laboratorio: ruta a 192.168.56.0/24 por el anfitrión,
# línea en hosts, llave y alias ssh, cliente telnet.
# Uso (PowerShell como administrador): powershell -ExecutionPolicy Bypass -File infra-qemu\windows.ps1
# Volver a correrlo si cambia la IP del anfitrión.
param([string]$Distro = "Ubuntu-24.04", [string]$Usuario = "lfmendoza")
$ErrorActionPreference = "Stop"
$Red = "192.168.56.0"; $Dominio = "redes-lab5-wp.duckdns.org"; $WebIp = "192.168.56.10"

Write-Host "== Ruta a la red del laboratorio" -ForegroundColor Cyan
# IP del anfitrión en la red que comparte con Windows
$VEth = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*WSL*" } | Select-Object -First 1
$Pref = ($VEth.IPAddress -split "\.")[0..1] -join "."
$IpAnfitrion = (wsl.exe -d $Distro hostname -I).Trim() -split "\s+" |
  Where-Object { $_ -like "$Pref.*" -and $_ -notlike "192.168.56.*" -and $_ -ne $VEth.IPAddress } |
  Select-Object -First 1
if (-not $IpAnfitrion) { throw "No pude obtener la IP del anfitrión ($Distro)" }
# Por cmd: PowerShell 5.1 trata como error el stderr de comandos nativos
cmd /c "route delete $Red >nul 2>&1"
cmd /c "route add $Red mask 255.255.255.0 $IpAnfitrion >nul 2>&1"
if ($LASTEXITCODE -ne 0) { throw "No se pudo agregar la ruta a $Red" }
Write-Host "192.168.56.0/24 -> $IpAnfitrion"

Write-Host "== Archivo hosts" -ForegroundColor Cyan
$Hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
$Linea = "$WebIp    $Dominio"
$Actual = Get-Content $Hosts | Where-Object { $_ -notmatch [regex]::Escape($Dominio) }
Set-Content -Path $Hosts -Value ($Actual + $Linea) -Encoding ascii
ipconfig /flushdns | Out-Null
Select-String -Path $Hosts -Pattern $Dominio

Write-Host "== Llave y alias SSH" -ForegroundColor Cyan
$Ssh = "$env:USERPROFILE\.ssh"; New-Item -ItemType Directory -Force $Ssh | Out-Null
$Origen = "\\wsl.localhost\$Distro\home\$Usuario\.ssh\lab5_ed25519"
Copy-Item $Origen "$Ssh\lab5_ed25519" -Force
Copy-Item "$Origen.pub" "$Ssh\lab5_ed25519.pub" -Force
# OpenSSH de Windows rechaza llaves privadas que otros usuarios pueden leer
icacls "$Ssh\lab5_ed25519" /inheritance:r /grant:r "$($env:USERNAME):(R)" | Out-Null
$Cfg = "$Ssh\config"
$Bloque = @"
# >>> lab5
Host web
    HostName 192.168.56.10
Host db
    HostName 192.168.56.20
Host web db
    User sysadmin
    Port 22022
    IdentityFile ~/.ssh/lab5_ed25519
    IdentitiesOnly yes
    UserKnownHostsFile ~/.ssh/known_hosts_lab5
    StrictHostKeyChecking accept-new
# <<< lab5
"@
$Previo = if (Test-Path $Cfg) { (Get-Content $Cfg -Raw) -replace '(?s)# >>> lab5.*?# <<< lab5\r?\n?', '' } else { "" }
Set-Content -Path $Cfg -Value ($Bloque + "`r`n" + $Previo).TrimEnd() -Encoding ascii
Write-Host "Alias web/db en $Cfg"

Write-Host "== Cliente telnet" -ForegroundColor Cyan
$T = Get-WindowsOptionalFeature -Online -FeatureName TelnetClient
if ($T.State -ne "Enabled") { Enable-WindowsOptionalFeature -Online -FeatureName TelnetClient -NoRestart | Out-Null }
Write-Host "TelnetClient habilitado"

Write-Host "== FileZilla" -ForegroundColor Cyan
# FileZilla no está en winget
if (Test-Path "$env:ProgramFiles\FileZilla FTP Client\filezilla.exe") { Write-Host "FileZilla instalado" }
else { Write-Host "Falta FileZilla: descárgalo de https://filezilla-project.org/download.php?type=client" }

Write-Host "== Comprobación" -ForegroundColor Cyan
Test-NetConnection $WebIp -Port 22022 | Select-Object ComputerName, RemotePort, TcpTestSucceeded
