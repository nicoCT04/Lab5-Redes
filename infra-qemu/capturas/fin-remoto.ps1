param([int]$Bajar = 0)
. "$PSScriptRoot\clic.ps1" -Dialogo "__no__" -Botones "x" | Out-Null
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class K2 {
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
"@
$v = Get-Process filezilla | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$listas = [U]::Hijos($v.MainWindowHandle) | Where-Object { $c = New-Object Text.StringBuilder 64; [U]::GetClassName($_, $c, 64) | Out-Null; "$c" -eq "SysListView32" }
$remota = $listas | Sort-Object { [int][K2]::SendMessage($_, 0x1004, [IntPtr]::Zero, [IntPtr]::Zero) } -Descending | Select-Object -First 1
"remota: $([K2]::SendMessage($remota, 0x1004, [IntPtr]::Zero, [IntPtr]::Zero)) elementos"
foreach ($vk in @(0x24) + @(0x28) * $Bajar) { [K2]::PostMessage($remota, 0x100, [IntPtr]$vk, [IntPtr]::Zero) | Out-Null; [K2]::PostMessage($remota, 0x101, [IntPtr]$vk, [IntPtr]::Zero) | Out-Null; Start-Sleep -Milliseconds 200 }
