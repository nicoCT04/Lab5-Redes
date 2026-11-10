# Deja Windows como "equipo host" de las VM que corren en WSL2 (QEMU), igual que con VirtualBox:
#   - ruta a 192.168.56.0/24 a través de WSL (WSL reenvía y sale como 192.168.56.1)
#   - dominio en el archivo hosts (resolución local)
#   - llave y alias ssh web/db para PowerShell y para pruebas-host-windows.ps1
#   - cliente telnet y FileZilla
# Uso (PowerShell como administrador, desde la carpeta del repo):
#   powershell -ExecutionPolicy Bypass -File infra-qemu\windows.ps1
# La IP de WSL cambia al reiniciar Windows: si deja de responder, vuelve a correrlo.
param([string]$Distro = "Ubuntu-24.04", [string]$Usuario = "lfmendoza")
$ErrorActionPreference = "Stop"
$Red = "192.168.56.0"; $Dominio = "redes-lab5-wp.duckdns.org"; $WebIp = "192.168.56.10"

Write-Host "== Ruta a la red del laboratorio" -ForegroundColor Cyan
# IP de WSL en la red que comparte con Windows (vEthernet WSL). Se usa hostname -I porque
# PowerShell 5.1 altera las comillas al pasar argumentos a wsl.exe.
$VEth = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*WSL*" } | Select-Object -First 1
$Pref = ($VEth.IPAddress -split "\.")[0..1] -join "."
$WslIp = (wsl.exe -d $Distro hostname -I).Trim() -split "\s+" |
  Where-Object { $_ -like "$Pref.*" -and $_ -notlike "192.168.56.*" -and $_ -ne $VEth.IPAddress } |
  Select-Object -First 1
if (-not $WslIp) { throw "No pude obtener la IP de WSL ($Distro)" }
# Por cmd: en PowerShell 5.1 cualquier texto de stderr de un comando nativo se vuelve error
cmd /c "route delete $Red >nul 2>&1"
cmd /c "route add $Red mask 255.255.255.0 $WslIp >nul 2>&1"
if ($LASTEXITCODE -ne 0) { throw "No se pudo agregar la ruta a $Red" }
Write-Host "192.168.56.0/24 -> WSL $WslIp"

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
# FileZilla no está en winget: se descarga de su sitio oficial
if (Test-Path "$env:ProgramFiles\FileZilla FTP Client\filezilla.exe") { Write-Host "FileZilla instalado" }
else { Write-Host "Falta FileZilla: descárgalo de https://filezilla-project.org/download.php?type=client" }

Write-Host "== Comprobación" -ForegroundColor Cyan
Test-NetConnection $WebIp -Port 22022 | Select-Object ComputerName, RemotePort, TcpTestSucceeded
