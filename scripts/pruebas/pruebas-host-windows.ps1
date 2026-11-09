# [Fernando] Pruebas desde el equipo HOST con Windows (PowerShell).
# Uso:  powershell -ExecutionPolicy Bypass -File scripts\pruebas\pruebas-host-windows.ps1 -Dominio redes-lab5-wp.duckdns.org
param([Parameter(Mandatory=$true)][string]$Dominio)
$WEB = "192.168.56.10"; $DB = "192.168.56.20"; $SSH = 22022; $MYSQL = 33306

function T($m) { Write-Host "`n===== $m =====" -ForegroundColor Cyan }

T "ping a ambas VM";              Test-Connection $WEB -Count 2; Test-Connection $DB -Count 2
T "Resolucion local (hosts)";     Get-Content C:\Windows\System32\drivers\etc\hosts | Select-String $Dominio
                                  Resolve-DnsName $Dominio -Type A | Select-Object Name, IPAddress
T "Puertos abiertos";             Test-NetConnection $WEB -Port $SSH | Select ComputerName,RemotePort,TcpTestSucceeded
                                  Test-NetConnection $WEB -Port 443  | Select ComputerName,RemotePort,TcpTestSucceeded
                                  Test-NetConnection $DB  -Port $SSH | Select ComputerName,RemotePort,TcpTestSucceeded
T "Puertos que deben estar CERRADOS (22 y MySQL desde host)"
                                  Test-NetConnection $WEB -Port 22     -WarningAction SilentlyContinue | Select ComputerName,RemotePort,TcpTestSucceeded
                                  Test-NetConnection $DB  -Port $MYSQL -WarningAction SilentlyContinue | Select ComputerName,RemotePort,TcpTestSucceeded
# Alias 'web' y 'db' de ~/.ssh/config (IP, puerto 22022, usuario y llave del lab).
# BatchMode evita quedarse esperando una contraseña si algo falla.
T "SSH a ambas VM";               ssh -o BatchMode=yes web "hostname; lsb_release -d"
                                  ssh -o BatchMode=yes db  "hostname; lsb_release -d"
T "HTTPS con certificado valido"; curl.exe -sI "https://$Dominio" | Select-Object -First 5
