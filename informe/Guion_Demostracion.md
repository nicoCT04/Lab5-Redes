# Guion de demostración — Lab 5

Duración objetivo: 12–15 min. Se presenta en la laptop de Daniela (Windows 11 + VirtualBox 7.2).
Todo se hace desde **PowerShell** y apps del host; la consola de VirtualBox no se abre.

## Antes de entrar a clase (10 min)

1. VirtualBox abierto, `lab5-web` y `lab5-db` en *Running* (`infra-windows\arrancar-vms.ps1` si están apagadas).
2. Comprobar en PowerShell:
   ```powershell
   ssh web hostname; ssh db hostname
   curl.exe -sI https://redes-lab5-wp.duckdns.org | Select-Object -First 1   # HTTP/1.1 200 OK
   ```
3. Abrir y dejar listas: una ventana de PowerShell **normal**, una **como administrador** (telnet),
   FileZilla (sitio guardado `Lab5 WordPress`, sin conectar) y el navegador en una pestaña vacía.
4. Tener un `prueba-demo.html` nuevo en el escritorio para subirlo en vivo.
5. Telnet habilitado: `dism /online /Enable-Feature /FeatureName:TelnetClient` (una sola vez).

## Recorrido

| # | Min | Quién | Qué se muestra | Comando / acción | Qué debe verse |
|---|---|---|---|---|---|
| 1 | 1 | Daniela | Arquitectura | Diagrama (Fig. 2 del informe) | 2 VM, red 192.168.56.0/24, puertos |
| 2 | 1 | Daniela | Hipervisor y SO | VirtualBox → Ayuda → Acerca de; `ssh web lsb_release -d`; `ssh db lsb_release -d` | VirtualBox 7.2.0; Ubuntu 26.04.1 LTS en ambas |
| 3 | 1 | Daniela | Resolución local | `Get-Content C:\Windows\System32\drivers\etc\hosts \| Select-String duckdns`; `ping redes-lab5-wp.duckdns.org` | Responde 192.168.56.10 |
| 4 | 1 | Fernando | SSH no conocido | `ssh web hostname`; `ssh -p 22 -o ConnectTimeout=5 sysadmin@192.168.56.10` | Entra por 22022; el 22 no responde |
| 5 | 1 | Fernando | Firewall | `ssh web "sudo ufw status verbose"`; `ssh db "sudo ufw status verbose"` | deny por defecto; solo 22022/80/443 y 22022/33306(.10) |
| 6 | 2 | Fernando | BD por SSH | `ssh db "sudo mysql -e 'SHOW DATABASES; SELECT user,host,plugin FROM mysql.user;'"`; `ssh db "sudo ss -tlnp \| grep mysqld"` | wordpress_db, wp_user@192.168.56.10; escucha en 192.168.56.20:33306 |
| 7 | 2 | Fernando | 2 capas | `ssh web "ping -c 3 192.168.56.20"`; `ssh web "nc -zv -w3 192.168.56.20 33306"`; `ssh web "nc -zv -w3 192.168.56.20 3306"`; `ssh web "sleep 3 \| telnet 192.168.56.20 33306"` | 0 % pérdida; 33306 abre; 3306 no; saludo `8.4.11` |
| 8 | 1 | Fernando | Telnet desde el host (PowerShell admin) | `telnet 192.168.56.10 443` (Ctrl+] y `quit`); `telnet 192.168.56.20 33306` | 443 conecta (negro); 33306 *Connect failed* |
| 9 | 2 | Nicolás | Permisos | `ssh web "ls -ld /var/www /var/www/wordpress"`; `ssh web "sudo -u www-data touch /var/www/wordpress/x"`; `ssh web "touch /var/www/wordpress/x"` | 755 root, 2750 wpadmin:www-data; *Permission denied* ×2 |
| 10 | 2 | Nicolás | SFTP + FileZilla (rúbrica en vivo) | Conectar sitio `Lab5 WordPress` → arrastrar `prueba-demo.html` a `/wordpress` | Solo se ve `/wordpress`; *File transfer successful* |
| 11 | 1 | Nicolás | Archivo servido | Navegador: `https://redes-lab5-wp.duckdns.org/prueba-demo.html` | Se abre con candado |
| 12 | 1 | Nicolás | HTTPS | Navegador: sitio → candado → certificado; `curl.exe -sI http://redes-lab5-wp.duckdns.org` | Emisor Let's Encrypt; 301 a https |
| 13 | 1 | Cualquiera | Pruebas completas | `powershell -ExecutionPolicy Bypass -File scripts\pruebas\pruebas-host-windows.ps1 -Dominio redes-lab5-wp.duckdns.org` | True en 22022/443; False en 22 y 33306 |

Si algo falla, no improvisar cambios: mostrar la evidencia equivalente del informe y explicar la causa.

## Preguntas probables y respuesta corta

**¿Por qué dos VM?** Separar aplicación y datos: la BD no es alcanzable más que desde el servidor web (UFW + `bind-address`), y una falla en WordPress no da acceso directo al motor.

**¿Por qué puertos 22022 y 33306?** Reducen escaneos automatizados que buscan 22 y 3306. Es oscuridad: complementa a la llave, al firewall y al mínimo privilegio; no los reemplaza.

**¿Cómo obtuvieron un certificado válido si la VM no está en Internet?** Reto DNS-01: Let's Encrypt verifica un TXT en el DNS público de DuckDNS; nunca se conecta a la VM. HTTP-01 y TLS-ALPN-01 necesitarían que la VM fuera accesible.

**¿Por qué el navegador acepta el certificado si el dominio apunta a una IP privada?** El navegador valida el nombre (CN/SAN) y la cadena hasta una raíz de confianza (ISRG Root X1), no la IP. El archivo hosts solo decide a qué IP se conecta.

**¿Qué hace el archivo hosts frente al DNS?** El resolver del SO lo consulta primero; si encuentra el nombre, no pregunta al DNS.

**Explique 2750 y 640.** 2 = setgid (lo nuevo hereda el grupo www-data); 7 = rwx para wpadmin; 5 = r-x para www-data; 0 = nada para otros. 640: rw- dueño, r-- grupo, nada otros.

**¿Por qué www-data no puede escribir?** Si se explota WordPress, el atacante corre como www-data; sin escritura no puede modificar el sitio ni dejar código persistente. Por eso `DISALLOW_FILE_MODS`.

**¿Qué es el chroot de SFTP y por qué /var/www es de root?** wpadmin queda encerrado en /var/www (solo ve /wordpress). OpenSSH exige que la jaula y sus padres pertenezcan a root y no sean escribibles por otros.

**¿Quién es cliente y quién servidor?** Como aplicación: navegador→Nginx, FileZilla→sshd, PHP/mysql→mysqld. Como ordenador: el host es cliente de ambas VM y lab5-web es cliente de lab5-db.

**¿Por qué root de MySQL usa auth_socket?** Solo entra quien ya es root en la VM (`sudo mysql`); no hay contraseña que robar y no acepta conexiones remotas.

**¿Por qué zz-lab5.cnf?** MySQL lee `mysql.conf.d` en orden alfabético y gana el último valor; con `99-` lo sobrescribía `mysqld.cnf` y quedaba en 127.0.0.1.

**¿Por qué reiniciar ssh.socket?** Desde Ubuntu 24.04 el puerto lo abre systemd (activación por socket); reiniciar solo `ssh` no cambia el puerto.

**Tipo 1 vs tipo 2.** Tipo 1 corre sobre el hardware (ESXi, Proxmox); tipo 2 corre como aplicación sobre un SO (VirtualBox). Para 2 VM pequeñas en una laptop, tipo 2 es suficiente.
