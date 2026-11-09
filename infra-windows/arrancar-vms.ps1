# Uso (PowerShell normal, desde la raíz del repo):
#   powershell -ExecutionPolicy Bypass -File infra-windows\arrancar-vms.ps1
# Para apagarlas limpio:  ssh web "sudo poweroff"; ssh db "sudo poweroff"
$VBM = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

foreach ($vm in 'lab5-db', 'lab5-web') {   # primero la BD: WordPress la necesita
    $estado = (& $VBM showvminfo $vm --machinereadable | Select-String '^VMState=').ToString()
    if ($estado -notmatch '"running"') { & $VBM startvm $vm --type headless | Out-Null; "$vm encendida" }
    else { "$vm ya estaba encendida" }
}

foreach ($h in 'web', 'db') {
    for ($i = 0; $i -lt 30; $i++) {
        ssh -o ConnectTimeout=5 -o BatchMode=yes $h "true" 2>$null
        if ($LASTEXITCODE -eq 0) { break }
        Start-Sleep 5
    }
    ssh -o BatchMode=yes $h "echo `$(hostname): SSH OK"
}
