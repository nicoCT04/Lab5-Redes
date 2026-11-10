# Guion de demostración — Lab 5 sobre QEMU/KVM

Duración objetivo: 12–15 min. Equipo: Windows 11 + WSL2 (Ubuntu 24.04) con QEMU 8.2.2 y KVM.
Todo se hace por SSH desde PowerShell o WSL; las VM no tienen pantalla.

## Antes de entrar a clase (10 min)

1. En WSL, desde la raíz del repositorio:
   ```bash
   just -f infra-qemu/justfile vms        # arranca lab5-web y lab5-db (si ya corren, no hace nada)
   ssh web hostname && ssh db hostname
   ```
2. En Windows, PowerShell **como administrador** (la IP de WSL cambia en cada arranque):
   ```powershell
   powershell -ExecutionPolicy Bypass -File infra-qemu\windows.ps1
   ```
   Debe terminar con `TcpTestSucceeded : True`.
3. Comprobar desde PowerShell normal:
   ```powershell
   ssh web hostname; ssh db hostname
   curl.exe -sI https://redes-lab5-wp.duckdns.org | Select-Object -First 1   # HTTP/1.1 200 OK
   ```
4. Dejar abiertas: PowerShell normal, PowerShell como administrador (telnet), una terminal de WSL,
   FileZilla (`%LOCALAPPDATA%\Programs\FileZilla-3.71.1\filezilla.exe`) y Edge.
5. Crear un `prueba-demo.html` nuevo para subirlo en vivo.

## Recorrido

| # | Min | Qué se muestra | Comando / acción | Qué debe verse |
|---|---|---|---|---|
| 1 | 1 | Arquitectura | Figura 3 del informe | Windows → WSL2 (KVM) → 2 VM; br-lab5 192.168.56.0/24 |
| 2 | 1 | Hipervisor | WSL: `qemu-system-x86_64 --version`; `pgrep -a qemu-system \| cut -c1-120`; `ip -br link show master br-lab5` | QEMU 8.2.2; 2 procesos con `accel=kvm`; tap-web y tap-db en el puente |
| 3 | 1 | SO y red de las VM | `ssh web "lsb_release -d; ip -4 -br addr"`; `ssh db "lsb_release -d; ip -4 -br addr"` | Ubuntu 26.04.1 LTS; enp0s3 10.0.2.15 (NAT) y enp0s8 .10 / .20 |
| 4 | 1 | Resolución local | `(Select-String C:\Windows\System32\drivers\etc\hosts -Pattern duckdns).Line`; `ping -n 2 redes-lab5-wp.duckdns.org` | 192.168.56.10 |
| 5 | 1 | SSH no conocido | `ssh web hostname`; `ssh -p 22 -o ConnectTimeout=5 sysadmin@192.168.56.10` | Entra por 22022; el 22 *timed out* |
| 6 | 1 | Firewall | `ssh web "sudo ufw status verbose"`; `ssh db "sudo ufw status verbose"` | deny por defecto; 22022/80/443 y 22022/33306 (.10) |
| 7 | 2 | BD por SSH | `ssh db "sudo mysql -e 'SHOW DATABASES; SELECT user,host,plugin FROM mysql.user;'"`; `ssh db "sudo ss -tlnp \| grep mysqld"` | wordpress_db; wp_user@192.168.56.10; 192.168.56.20:33306 |
| 8 | 2 | 2 capas | `ssh web "ping -c 3 192.168.56.20"`; `ssh web "nc -zv -w3 192.168.56.20 33306"`; `ssh web "nc -zv -w3 192.168.56.20 3306"`; `ssh web "sleep 3 \| telnet 192.168.56.20 33306"` | 0 % pérdida; 33306 abre; 3306 no; saludo `8.4.11` |
| 9 | 1 | Telnet desde el host (admin) | `telnet 192.168.56.10 443` (Ctrl+] y `quit`); `telnet 192.168.56.20 33306` | 443 conecta (negro); 33306 *Connect failed* |
| 10 | 2 | Permisos | `ssh web "ls -ld /var/www /var/www/wordpress"`; `ssh web "sudo -u www-data touch /var/www/wordpress/x"`; `ssh web "touch /var/www/wordpress/x"` | 755 root; 2750 wpadmin:www-data; *Permission denied* ×2 |
| 11 | 2 | SFTP + FileZilla (en vivo) | FileZilla: host `sftp://192.168.56.10`, puerto 22022, usuario `wpadmin` → subir `prueba-demo.html` a `/wordpress` | Solo se ve `/wordpress`; *File transfer successful* |
| 12 | 1 | Archivo servido | Edge: `https://redes-lab5-wp.duckdns.org/prueba-demo.html` | Se abre con candado |
| 13 | 1 | HTTPS | Edge: candado → certificado; `curl.exe -sI http://redes-lab5-wp.duckdns.org` | Emisor Let's Encrypt; 301 a https |
| 14 | 1 | Pruebas completas | `powershell -ExecutionPolicy Bypass -File scripts\pruebas\pruebas-host-windows.ps1 -Dominio redes-lab5-wp.duckdns.org` | True en 22022/443; False en 22 y 33306 |

Si algo no responde desde Windows, volver a correr `infra-qemu\windows.ps1` como administrador (cambió la IP de WSL).
Si una VM no responde, `just -f infra-qemu/justfile vms` desde WSL.

## Preguntas probables y respuesta corta

**¿Por qué QEMU/KVM?** KVM convierte al kernel de Linux en hipervisor y usa VT-x del CPU; QEMU crea cada VM como proceso y emula dispositivos virtio. Convive con WSL2/Hyper-V (VirtualBox se congelaba en este equipo), se automatiza por completo y es la base de Proxmox y OpenStack.

**¿Es tipo 1 o tipo 2?** KVM suele considerarse tipo 1 porque el hipervisor es el propio kernel. Aquí ese kernel es el de WSL2, que corre sobre Hyper-V de Windows con virtualización anidada: las VM están en un segundo nivel, con aceleración por hardware en ambos.

**¿Cómo se arma la red "host-only"?** Un puente Linux `br-lab5` con 192.168.56.1/24; cada VM se conecta con una interfaz tap. Para Internet, cada VM usa la NAT de QEMU (10.0.2.15, solo saliente). Las NIC van en las ranuras PCI 3 y 8 para que se llamen enp0s3 y enp0s8.

**¿Cómo llega Windows a las VM?** Una ruta 192.168.56.0/24 vía la IP de WSL; WSL reenvía y aplica MASQUERADE, así el tráfico entra a las VM como 192.168.56.1 y UFW lo permite.

**¿Cómo se instalan las VM sin instalador?** Imagen cloud oficial de Ubuntu Server 26.04 + cloud-init (NoCloud): hostname, usuario, llave y red se declaran en archivos; arranca en ~1 min.

**¿Por qué dos VM?** Separar aplicación y datos: la BD solo es alcanzable desde el servidor web (UFW + `bind-address`) y una falla en WordPress no da acceso directo al motor.

**¿Por qué 22022 y 33306?** Reducen escaneos automatizados; es oscuridad que complementa a llave, firewall y mínimo privilegio.

**¿Por qué el 22 da *timed out* y no *refused*?** UFW descarta (DROP) los paquetes a puertos no permitidos; *refused* solo se ve antes de activar UFW.

**¿Cómo obtuvieron un certificado válido sin exponer la VM?** Reto DNS-01: Let's Encrypt verifica un TXT en el DNS público de DuckDNS y nunca se conecta a la VM.

**¿Por qué el navegador acepta el certificado si el dominio apunta a una IP privada?** Valida el nombre y la cadena hasta ISRG Root X1, no la IP. El archivo hosts solo decide a qué IP conectarse.

**Explique 2750 y 640.** 2 = setgid (lo nuevo hereda www-data); 7 = rwx wpadmin; 5 = r-x www-data; 0 = nada otros. 640: rw- dueño, r-- grupo, nada otros.

**¿Qué es el chroot de SFTP?** wpadmin queda encerrado en /var/www (solo ve /wordpress); OpenSSH exige que la jaula pertenezca a root.

**¿Quién es cliente y quién servidor?** Aplicación: Edge→Nginx, FileZilla→sshd, PHP/mysql→mysqld, QEMU→KVM. Ordenador: el host es cliente de ambas VM y lab5-web es cliente de lab5-db.

**¿Por qué zz-lab5.cnf y por qué reiniciar ssh.socket?** MySQL lee la configuración en orden alfabético y gana el último valor. Desde Ubuntu 24.04 el puerto de SSH lo abre systemd por activación de socket.
