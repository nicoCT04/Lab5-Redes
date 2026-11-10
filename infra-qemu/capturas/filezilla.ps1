# Abre FileZilla conectado por SFTP como wpadmin y captura su ventana.
param([string]$Pass, [string]$Png, [int]$Espera = 10, [switch]$Abrir)
. "$PSScriptRoot\capturar.ps1"
$Fz = "$env:LOCALAPPDATA\Programs\FileZilla-3.71.1\filezilla.exe"
if ($Abrir) {
  Start-Process $Fz -ArgumentList "sftp://wpadmin:$Pass@192.168.56.10:22022/wordpress", "--local=`"$env:USERPROFILE\Documents\lab5-sftp`""
  Start-Sleep $Espera
}
# Ventana principal por título (MainWindowHandle puede apuntar a un tooltip)
. "$PSScriptRoot\clic.ps1" -Dialogo "__no__" -Botones "x" | Out-Null
$h = [U]::Superiores((Get-Process filezilla).Id) | Where-Object { [U]::Texto($_) -like "* - FileZilla" } | Select-Object -First 1
[Win]::MoveWindow($h, 40, 40, 1400, 900, $true) | Out-Null
Start-Sleep 1
[Win]::Capturar($h, $Png)
Write-Host "captura: $Png ($([U]::Texto($h)))"
