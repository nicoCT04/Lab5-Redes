# Demostración

## Antes de empezar

```bash
just -f infra-qemu/justfile vms
```
```powershell
# PowerShell como administrador
powershell -ExecutionPolicy Bypass -File infra-qemu\windows.ps1
```

## Recorrido

1. Anfitrión: `qemu-system-x86_64 --version`, `pgrep -a qemu-system`, `ip -br link show master br-lab5`
2. VMs: `ssh web "lsb_release -d; ip -4 -br addr"` y lo mismo con `db`
3. Resolución local: archivo hosts y `ping redes-lab5-wp.duckdns.org`
4. SSH: `ssh web hostname` y `ssh -p 22 -o ConnectTimeout=5 sysadmin@192.168.56.10`
5. UFW: `ssh web "sudo ufw status verbose"` y `ssh db "sudo ufw status verbose"`
6. MySQL por SSH: `ssh db "sudo mysql -e 'SHOW DATABASES; SELECT user,host,plugin FROM mysql.user;'"`
7. Dos capas desde web: `ping -c 3 192.168.56.20`, `nc -zv -w3 192.168.56.20 33306`, `nc -zv -w3 192.168.56.20 3306`,
   `sleep 3 | telnet 192.168.56.20 33306`
8. telnet desde Windows: `telnet 192.168.56.10 443` (conecta) y `telnet 192.168.56.20 33306` (no conecta)
9. Permisos: `ls -ld /var/www /var/www/wordpress`, `touch` como www-data y como sysadmin
10. FileZilla: `sftp://192.168.56.10`, puerto 22022, usuario `wpadmin`; subir un HTML a `/wordpress`
11. Navegador: el archivo subido y el sitio por HTTPS, ver el certificado
12. `scripts\pruebas\pruebas-host-windows.ps1 -Dominio redes-lab5-wp.duckdns.org`
