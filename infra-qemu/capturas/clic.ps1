# Pulsa botones/casillas de un diálogo de FileZilla por mensaje BM_CLICK (no requiere foco).
param([string]$Dialogo, [string]$Botones)
Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class U {
  public delegate bool P(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(P p, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr w, P p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  public static string Texto(IntPtr h) { var s = new StringBuilder(512); GetWindowText(h, s, 512); return s.ToString(); }
  public static List<IntPtr> Superiores(uint pid) { var r = new List<IntPtr>();
    EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid) r.Add(h); return true; }, IntPtr.Zero); return r; }
  public static List<IntPtr> Hijos(IntPtr w) { var r = new List<IntPtr>();
    EnumChildWindows(w, (h, l) => { r.Add(h); return true; }, IntPtr.Zero); return r; }
}
"@
$pid_ = (Get-Process filezilla).Id
$d = [U]::Superiores($pid_) | Where-Object { [U]::Texto($_) -eq $Dialogo } | Select-Object -First 1
if (-not $d) { "No encontré el diálogo '$Dialogo'"; exit 1 }
if (-not $Botones) { foreach ($h in [U]::Hijos($d)) { $c = New-Object Text.StringBuilder 128; [U]::GetClassName($h, $c, 128) | Out-Null; "$c [$([U]::Texto($h))]" }; exit 0 }
foreach ($b in ($Botones -split "\|")) {
  $h = [U]::Hijos($d) | Where-Object { ([U]::Texto($_) -replace '&', '') -eq $b } | Select-Object -First 1
  if ($h) { [U]::SendMessage($h, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null; "pulsado: $b"; Start-Sleep -Milliseconds 300 }
  else { "no encontrado: $b" }
}
