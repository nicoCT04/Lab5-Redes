# Ejecuta, en una consola visible, los comandos de un archivo como si se escribieran a mano.
param([string]$Lista, [string]$Titulo, [int]$Ancho = 120, [int]$Alto = 40)
$Host.UI.RawUI.WindowTitle = $Titulo
try {
  $Host.UI.RawUI.BufferSize = New-Object Management.Automation.Host.Size($Ancho, 3000)
  $Host.UI.RawUI.WindowSize = New-Object Management.Automation.Host.Size($Ancho, $Alto)
} catch {}
Set-Location $env:USERPROFILE
Clear-Host
$Nativos = 'ssh', 'telnet', 'curl.exe', 'route', 'ping', 'sftp', 'wsl'
$Tmp = "$env:TEMP\lab5\linea.cmd"
foreach ($c in Get-Content $Lista) {
  if (-not $c.Trim()) { continue }
  Write-Host -NoNewline "PS $($PWD.Path)> "; Write-Host $c
  if (($c -split '\s+')[0] -eq 'telnet') {
    # telnet necesita la consola real (no funciona con la salida redirigida)
    & "$env:SystemRoot\System32\telnet.exe" @(($c -split '\s+')[1..2])
  } elseif ($Nativos -contains ($c -split '\s+')[0]) {
    # Por cmd: PowerShell 5.1 pierde o deforma el stderr de los programas nativos
    Set-Content $Tmp "@echo off`r`n$c 2>&1" -Encoding ascii
    cmd /c $Tmp | Out-Host
  } else {
    Invoke-Expression $c | Out-Host
  }
}
New-Item -ItemType File "$Lista.listo" -Force | Out-Null
