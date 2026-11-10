# Sube con FileZilla el archivo seleccionado en el panel local (Enter = transferir).
. "$PSScriptRoot\clic.ps1" -Dialogo "__no__" -Botones "x" | Out-Null
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class K {
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
"@
$v = Get-Process filezilla | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$listas = [U]::Hijos($v.MainWindowHandle) | Where-Object { $c = New-Object Text.StringBuilder 64; [U]::GetClassName($_, $c, 64) | Out-Null; "$c" -eq "SysListView32" }
foreach ($l in $listas) { "lista $l : $([K]::SendMessage($l, 0x1004, [IntPtr]::Zero, [IntPtr]::Zero)) elementos" }   # LVM_GETITEMCOUNT
$local = $listas | Where-Object { [K]::SendMessage($_, 0x1004, [IntPtr]::Zero, [IntPtr]::Zero) -eq 2 } | Select-Object -First 1
if (-not $local) { "No identifiqué la lista local"; exit 1 }
foreach ($vk in 0x24, 0x28) {   # Inicio, Flecha abajo -> segundo elemento (prueba-sftp.html)
  [K]::PostMessage($local, 0x100, [IntPtr]$vk, [IntPtr]::Zero) | Out-Null
  [K]::PostMessage($local, 0x101, [IntPtr]$vk, [IntPtr]::Zero) | Out-Null
  Start-Sleep -Milliseconds 400
}
$sel = [K]::SendMessage($local, 0x100C, [IntPtr](-1), [IntPtr]2)   # LVM_GETNEXTITEM, LVNI_SELECTED
"seleccionado: índice $sel"
if ($sel -ne 1) { "La selección no es el archivo; no subo"; exit 1 }
[K]::PostMessage($local, 0x100, [IntPtr]0x0D, [IntPtr]::Zero) | Out-Null
[K]::PostMessage($local, 0x101, [IntPtr]0x0D, [IntPtr]::Zero) | Out-Null
"Enter enviado"
