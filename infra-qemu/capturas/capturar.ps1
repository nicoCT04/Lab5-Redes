# Utilidades para capturar UNA ventana concreta (no la pantalla completa).
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class Win {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool r);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int s);
  public static void Capturar(IntPtr h, string ruta) {
    RECT w; GetWindowRect(h, out w);
    RECT d; if (DwmGetWindowAttribute(h, 9, out d, 16) != 0) d = w;
    using (var bmp = new Bitmap(w.R - w.L, w.B - w.T)) {
      using (var g = Graphics.FromImage(bmp)) {
        IntPtr dc = g.GetHdc(); PrintWindow(h, dc, 2); g.ReleaseHdc(dc);
      }
      var recorte = new Rectangle(d.L - w.L, d.T - w.T, d.R - d.L, d.B - d.T);
      using (var c = bmp.Clone(recorte, bmp.PixelFormat)) c.Save(ruta, ImageFormat.Png);
    }
  }
}
"@
[Win]::SetProcessDPIAware() | Out-Null

# Espera la ventana principal de un proceso (o de cualquier proceso con ese nombre y título)
function Esperar-Ventana([string]$Nombre, [string]$Titulo = "", [int]$Seg = 30) {
  for ($i = 0; $i -lt $Seg * 2; $i++) {
    $p = Get-Process -Name $Nombre -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$Titulo*" } | Select-Object -First 1
    if ($p) { return $p }
    Start-Sleep -Milliseconds 500
  }
  throw "No apareció la ventana $Nombre '$Titulo'"
}
