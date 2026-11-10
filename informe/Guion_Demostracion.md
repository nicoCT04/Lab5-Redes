# Demostración (VirtualBox)

## Antes de empezar

VMs encendidas (`infra-windows\arrancar-vms.ps1` si están apagadas) y comprobar:
```powershell
ssh web hostname; ssh db hostname
```

## Recorrido

1. VirtualBox: versión y las dos VM en ejecución
2. VMs: `ssh web lsb_release -d` y `ssh db lsb_release -d`
3. Resolución local: archivo hosts y `ping redes-lab5-wp.duckdns.org`
4. SSH: `ssh web hostname` y `ssh -p 22 -o ConnectTimeout=5 sysadmin@192.168.56.10`
5. UFW: `ssh web "sudo ufw status verbose"` y `ssh db "sudo ufw status verbose"`
6. MySQL por SSH: `ssh db "sudo mysql -e 'SHOW DATABASES; SELECT user,host,plugin FROM mysql.user;'"`
7. Dos capas desde web: `ping -c 3 192.168.56.20`, `nc -zv -w3 192.168.56.20 33306`, `nc -zv -w3 192.168.56.20 3306`
8. telnet desde Windows: `telnet 192.168.56.10 443` (conecta) y `telnet 192.168.56.20 33306` (no conecta)
9. Permisos: `ls -ld /var/www /var/www/wordpress`, `touch` como www-data y como sysadmin
10. FileZilla: subir un HTML a `/wordpress` como `wpadmin`
11. Navegador: el archivo subido y el sitio por HTTPS, ver el certificado
12. `scripts\pruebas\pruebas-host-windows.ps1 -Dominio redes-lab5-wp.duckdns.org`
