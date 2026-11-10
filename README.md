# Lab 5 — Mini Datacenter Virtualizado: WordPress en 2 capas

Redes Sec. 10 · UVG · Entrega 10/11/2026 · Sin puntos extra (hipervisor tipo 2: VirtualBox)

Sitio: **https://redes-lab5-wp.duckdns.org** (resuelto localmente con el archivo hosts)

## Arquitectura

```
 Equipo host (Windows en la demo)                       red host-only 192.168.56.0/24
 ├─ PowerShell / ssh  ──────── SSH 22022 ───────────┬─────────────────────────────────┐
 ├─ FileZilla        ──────── SFTP 22022 (wpadmin) ─┤                                 │
 ├─ Navegador        ──────── HTTPS 443 ────────────┤                                 │
 └─ hosts: redes-lab5-wp.duckdns.org → 192.168.56.10│                                 │
                                                    ▼                                 ▼
                                   lab5-web  192.168.56.10            lab5-db  192.168.56.20
                                   Nginx 1.28 + PHP-FPM 8.5           MySQL 8.4 LTS
                                   WordPress 7.1 + WP-CLI   ─ 33306 ─► wordpress_db / wp_user
                                   certbot (Let's Encrypt DNS-01)
                                   UFW: 22022 (lab), 80, 443          UFW: 22022 (lab), 33306 (solo .10)
 Cada VM: adaptador 1 NAT (Internet: apt, Let's Encrypt) + adaptador 2 host-only (IP fija).
```

## Reparto

| Quién | Qué | Guía |
|---|---|---|
| Daniela Ramirez | VirtualBox, VMs Ubuntu 26.04, red, llaves SSH, archivo hosts, FileZilla (su laptop es la de la demo) | guía enviada por separado |
| Fernando Mendoza | SSH en 22022, UFW, MySQL, pruebas de conectividad | este README (abajo) |
| Nicolás Concuá | Capa web, WordPress, permisos chown/chmod, SFTP, HTTPS Let's Encrypt | este README (abajo) |

## Orden de ejecución en la laptop de la demo

| # | Quién | Dónde | Comando / acción |
|---|---|---|---|
| 1 | C1 | Git Bash (host) | `infra-windows/crear-vms.sh` → `infra-windows/crear-vms.sh --terminar` → `infra-windows/subir.sh web 22` y `... db 22` |
| 2 | C2 | web y db | `sudo bash scripts/comun/01-ssh-puerto.sh` |
| 3 | C2 | web / db | `sudo bash scripts/comun/02-ufw.sh web` · `... db` |
| 4 | C2 | db | `sudo bash scripts/bd/01-mysql.sh` |
| 5 | Nicolás | web | `sudo bash scripts/web/01-stack-web.sh` |
| 6 | Nicolás | web | `sudo bash scripts/web/02-wordpress-permisos.sh` |
| 7 | Nicolás | web | `sudo bash scripts/web/03-sftp.sh` |
| 8 | Nicolás | web | `sudo bash scripts/web/04-https.sh --prueba` y luego `sudo bash scripts/web/04-https.sh` |
| 9 | C1 | host | Línea en hosts + FileZilla |
| 10 | C2 | host y VMs | `scripts/pruebas/*` y capturas |

Desde Windows cada comando se lanza así (ejemplo): `ssh -t web "cd ~/lab5 && sudo bash scripts/web/01-stack-web.sh"`

## Archivos

```
config/lab5.env            IPs, puertos, usuarios, dominio (sin secretos, va al repo)
secretos.env               contraseñas + token DuckDNS (NO va al repo; se pasa por privado). Plantilla: secretos.env.example
scripts/comun/             01-ssh-puerto.sh, 02-ufw.sh            (ambas VM)
scripts/bd/                01-mysql.sh                            (VM db)
scripts/web/               01-stack-web.sh, 02-wordpress-permisos.sh, 03-sftp.sh,
                           04-https.sh + hooks de DuckDNS         (VM web)
scripts/pruebas/           pruebas-servidor.sh, pruebas-host-windows.ps1, pruebas-host-mac-linux.sh
infra-windows/             creación de las VM en la laptop de la demo (Windows, VirtualBox 7.2, autoinstall)
                           crear-vms.sh, hacer-seed.py (ISO CIDATA con pycdlib), subir.sh
infra-qemu/                réplica del laboratorio con QEMU/KVM en WSL2 (validación); no se usa en la demo
prototipo-mac/             automatización del prototipo en macOS (Apple Silicon); no se usa en la demo
informe/                   informe (.docx y .pdf), diagramas fuente (SVG) y guion de la demostración
```

`secretos.env` tiene estas variables: `SYSADMIN_PASS`, `DB_PASS`, `WPADMIN_SFTP_PASS`,
`WP_ADMIN_USER`, `WP_ADMIN_PASS`, `WP_ADMIN_EMAIL`, `DUCKDNS_TOKEN`.

---

## Parte de Fernando: SSH, firewall, base de datos y pruebas

### 01-ssh-puerto.sh (ambas VM)
`/etc/ssh/sshd_config.d/10-lab5.conf`: `Port 22022`, `PermitRootLogin no`, `PasswordAuthentication no`
(solo llave), sin X11. Valida con `sshd -t` antes de reiniciar para no perder el acceso. En Ubuntu
24.04+ el puerto lo abre `ssh.socket`, por eso hace `daemon-reload` y reinicia el socket.
Después se cambia `Port 22` → `Port 22022` en los alias `web` y `db` del `~/.ssh/config` del host.

| Servicio | Puerto por defecto | Puerto usado |
|---|---|---|
| SSH / SFTP | 22 | 22022 |
| MySQL | 3306 | 33306 |
| MySQL X Protocol | 33060 | desactivado |

*Por qué puertos no conocidos:* los bots y escáneres automáticos prueban 22 y 3306; moverlos reduce
ruido en los logs e intentos de acceso. Es seguridad por oscuridad: complementa a las llaves y al
firewall, no los reemplaza.

### 02-ufw.sh (ambas VM)
Política por defecto: denegar entrante, permitir saliente. Solo se abre lo que se usa:

| VM | Puerto | Origen | Motivo |
|---|---|---|---|
| web | 22022/tcp | 192.168.56.0/24 | SSH/SFTP solo desde la red del lab |
| web | 80/tcp | cualquiera | únicamente redirige a HTTPS |
| web | 443/tcp | cualquiera | WordPress por HTTPS |
| db | 22022/tcp | 192.168.56.0/24 | SSH solo desde la red del lab |
| db | 33306/tcp | 192.168.56.10 | MySQL solo desde la VM web (el host tampoco llega) |

La regla del 33306 y el `bind-address` de MySQL se cubren entre sí: si una falla, la base sigue sin quedar expuesta.

### 01-mysql.sh (VM db)
- MySQL **8.4 LTS**, el que trae el repositorio oficial de Ubuntu 26.04; no hace falta agregar repositorios de Oracle.
- `/etc/mysql/mysql.conf.d/zz-lab5.cnf`: `bind-address = 192.168.56.20`, `port = 33306`, `mysqlx = 0`.
  Se llama `zz-` para que se lea después de `mysqld.cnf`; con `99-lab5.cnf` MySQL seguía en 127.0.0.1.
- BD `wordpress_db` (utf8mb4) y usuario `wp_user@192.168.56.10` con privilegios **solo** sobre esa base:
  pertenecen a WordPress y no son el administrador del motor.
- `root` de MySQL se queda con `auth_socket`: solo entra quien ya es root en la VM (`sudo mysql`); no tiene
  contraseña que robar ni acepta conexiones remotas.
- Es idempotente: si cambia `DB_PASS` en `secretos.env`, se vuelve a correr y actualiza la contraseña.

Gestión de la base por SSH desde el host:
```
ssh -t db "sudo mysql -e 'SHOW DATABASES; SELECT user,host,plugin FROM mysql.user;'"
```

*Cliente y servidor:* `mysqld` (lab5-db) es la aplicación servidor; PHP y el cliente `mysql` de lab5-web son
las aplicaciones cliente. En esa conexión la VM web es el ordenador cliente, aunque para el navegador sea servidor.

### Pruebas
| Prueba | Comando | Resultado esperado |
|---|---|---|
| ping web ↔ db | `pruebas-servidor.sh web` / `db` | 0% packet loss |
| MySQL abierto desde web | `nc -zv 192.168.56.20 33306` | `succeeded!` |
| 3306 cerrado | `nc -zv 192.168.56.20 3306` | timed out |
| Login remoto | `mysql -h 192.168.56.20 -P 33306 -u wp_user -p` | `wp_user@192.168.56.10  lab5-db  33306` y tablas `wp_*` |
| Puertos desde el host | `pruebas-host-windows.ps1` | 22022 y 443 `True`; 22 y 33306 `False` |
| SSH sin consola | `ssh web` / `ssh db` | hostname y `Ubuntu 26.04.1 LTS` |
| telnet desde el host | `telnet 192.168.56.10 443` / `telnet 192.168.56.20 33306` | conecta / no conecta (firewall) |
| telnet desde web | `telnet 192.168.56.20 33306` | saludo de MySQL con `8.4.11` |

`telnet` no viene activo en Windows: `dism /online /Enable-Feature /FeatureName:TelnetClient` (PowerShell como administrador).
En la VM web: `sudo apt-get install -y telnet`.

Salidas de la demo (09/11/2026) en `evidencias/` (`*-01-ssh-puerto.txt`, `*-02-ufw.txt`, `db-03-mysql.txt`, `pruebas-*.txt`).

---

## Réplica con QEMU/KVM en WSL2 (Fernando)

Réplica completa del laboratorio en una laptop con Windows + WSL2, donde VirtualBox no es
estable (WSL2 activa Hyper-V; es el mismo problema que congelaba las VMs en la laptop de la
demo). Sirve para validar los scripts de punta a punta y practicar; **la demo oficial sigue
siendo la de VirtualBox**. Se usan los mismos `config/` y `scripts/` sin ningún cambio.

| VirtualBox (demo) | Réplica QEMU/KVM |
|---|---|
| Adaptador host-only 192.168.56.1/24 | Puente `br-lab5` 192.168.56.1/24 en WSL (servicio `lab5-red`) |
| Adaptador 1 NAT (10.0.2.15) | NAT de QEMU (10.0.2.15), DNS 1.1.1.1 / 8.8.8.8 |
| `enp0s3` / `enp0s8` | Igual: las NIC van en las ranuras PCI 3 y 8 |
| ISO + autoinstall | Imagen cloud oficial de Ubuntu Server 26.04 + cloud-init |
| Host = Windows | Host = WSL (`/etc/hosts`, `ssh web`) y también Windows (ruta a 192.168.56.0/24 vía WSL) |

```
just -f infra-qemu/justfile requisitos   # una vez, pide sudo: QEMU, grupo kvm, red y /etc/hosts
just -f infra-qemu/justfile vms          # crea y arranca lab5-web y lab5-db (sin pantalla)
just -f infra-qemu/justfile desplegar --certificado   # todo el orden de la tabla de arriba
just -f infra-qemu/justfile pruebas      # solo pruebas
```
En Windows (PowerShell como administrador): `infra-qemu\windows.ps1` agrega la ruta, la línea
en `hosts`, los alias `web`/`db` y el cliente telnet. Hay que volver a correrlo si se reinicia
Windows, porque cambia la IP de WSL.

Detalles:
- Windows llega a las VMs a través de WSL; WSL hace MASQUERADE, así que el tráfico entra a
  las VMs desde 192.168.56.1 y UFW lo trata igual que al host de VirtualBox.
- QEMU corre como usuario normal: las interfaces `tap-web`/`tap-db` son de ese usuario.
- No se usa la consola: la salida serie queda en `infra-qemu/build/<vm>-serial.log`.
- Evidencias en `evidencias/qemu/` (salidas en texto) y `evidencias/qemu/capturas/` (17 capturas).
- FileZilla 3.71.1 portable (zip oficial, SHA-512 verificado) en `%LOCALAPPDATA%\Programs`.

Las capturas se tomaron con `infra-qemu/capturas/`: cada una abre una consola, Edge o FileZilla
en Windows, corre los comandos de `capturas/comandos/<n>.txt` y captura **solo esa ventana**.
Para repetirlas, copiar la carpeta a `%TEMP%\lab5` (junto con `scripts\pruebas\pruebas-host-windows.ps1`) y:
```
powershell -ExecutionPolicy Bypass -File $env:TEMP\lab5\tomar.ps1 -Lista $env:TEMP\lab5\comandos\11-ufw-ambas.txt -Png $env:TEMP\lab5\11.png
```
En FileZilla la llave del servidor se aceptó después de comparar la huella con
`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` en lab5-web (`SHA256:XX4MpdWZ...`).

| Requisito | Captura (`evidencias/qemu/capturas/`) |
|---|---|
| Hipervisor y VMs | `01-qemu-vms` |
| SSH 22022, 22 cerrado | `02-ssh-puerto-22022` |
| UFW en ambas VM | `03-ufw-ambas` |
| BD: gestión por SSH, 33306 | `04-mysql-gestion-ssh` |
| 2 capas: ping, nc, login remoto | `05-dos-capas-web-a-db`, `06-telnet-web-a-mysql` |
| Permisos chown/chmod | `07-permisos-wordpress` |
| SFTP con FileZilla | `08-filezilla-conectado-chroot`, `09-filezilla-subida`, `10-filezilla-archivo-remoto`, `11-archivo-sftp-navegador` |
| HTTPS Let's Encrypt | `12-sitio-https`, `13-hosts-y-certificado` |
| Resolución local | `13-hosts-y-certificado` |
| Pruebas desde el host | `14-pruebas-host-windows`, `15-telnet-host-33306`, `16-telnet-host-443` |
| Versiones | `17-versiones` |

| Problema | Causa | Solución |
|---|---|---|
| La NIC NAT quedó como `enp0s2` | cloud-init no puede renombrar una interfaz ya activa en el primer arranque | Fijar las NIC en las ranuras PCI 3 y 8 |
| `ssh` rechazado con "System is booting up" | El puerto abre antes de que termine el arranque (`pam_nologin`) | Esperar a que el login funcione, no solo a que abra el puerto |
| `route add` fallaba desde PowerShell | PowerShell 5.1 altera las comillas al llamar a `wsl.exe` | Obtener la IP de WSL con `hostname -I` |
| FileZilla no se instala con winget | No está en el catálogo de winget | Zip portable oficial, verificado con su SHA-512 |
| Con UFW activo, `ssh -p 22` da *timed out* y no *refused* | UFW descarta (DROP) en vez de rechazar | Es lo esperado: *refused* solo se ve antes de activar UFW (`evidencias/qemu/01-puerto-22-cerrado.txt`) |

---

## Parte de Nicolás: capa web

### 01-stack-web.sh
Nginx 1.28 + PHP-FPM 8.5 (+ extensiones `mysql, curl, gd, mbstring, xml, zip, intl, imagick`),
cliente `mysql` (requisito: la capa web tiene cliente MySQL), WP-CLI. Quita el sitio por
defecto y oculta la versión de Nginx (`server_tokens off`).
*Por qué Nginx + PHP-FPM y no Apache:* menor consumo de RAM con VMs de 2 GB, PHP corre en
un proceso separado (`www-data`) con su propio pool, configuración de un solo archivo.

### 02-wordpress-permisos.sh — permisos (chown/chmod)
1. Prueba la conexión a MySQL remoto con `wp_user` (evidencia de 2 capas).
2. Crea `wpadmin` sin shell (`/usr/sbin/nologin`): **único** usuario con escritura.
3. Descarga e instala WordPress **como `wpadmin`** con WP-CLI, `DB_HOST=192.168.56.20:33306`.
4. Permisos finales:

| Ruta | Dueño:grupo | Modo | Significado |
|---|---|---|---|
| `/var/www` | `root:root` | `755` | Requisito de la jaula SFTP (chroot debe ser de root) |
| `/var/www/wordpress` y subcarpetas | `wpadmin:www-data` | `2750` | dueño rwx, grupo r-x, otros nada; **setgid** (`2`) → todo lo nuevo hereda el grupo `www-data` |
| archivos | `wpadmin:www-data` | `640` | dueño rw, grupo r, otros nada |

- `www-data` (Nginx/PHP) **solo lee** vía grupo → si alguien explota WordPress no puede modificar archivos.
- `sysadmin` y cualquier otro usuario: **ni leen** (otros = 0). Solo root (sudo) podría.
- `wp-config.php` tiene `DISALLOW_FILE_MODS` y `DISALLOW_FILE_EDIT`: el panel de WordPress no intenta escribir; plugins/temas/archivos se gestionan **por SFTP**. `FORCE_SSL_ADMIN` obliga HTTPS en el panel.

### 03-sftp.sh
`/etc/ssh/sshd_config.d/20-sftp-wpadmin.conf` con `Match User wpadmin`:
`ChrootDirectory /var/www`, `ForceCommand internal-sftp -u 0027`, contraseña permitida
solo para él (FileZilla), sin túneles. `umask 027` hace que lo que sube quede 640/750.
`sysadmin` sigue solo con llave. El script muestra la config efectiva de ambos (`sshd -T`).

### 04-https.sh — Let's Encrypt con dominio resuelto localmente
- **Problema:** Let's Encrypt debe comprobar que controlamos el dominio. HTTP-01 y TLS-ALPN-01 requieren que *sus* servidores lleguen a nuestra VM por Internet en 80/443, imposible con red host-only.
- **Solución:** reto **DNS-01**: certbot pide publicar un registro TXT `_acme-challenge.<dominio>` y Let's Encrypt lo consulta en el DNS público. **DuckDNS** (gratis) tiene API para poner ese TXT.
- Así el dominio es público (para validar) pero se resuelve **localmente** a 192.168.56.10 vía hosts (requisito de resolución local). El certificado es válido porque el nombre coincide, sin importar a qué IP apunte.
- Hooks `duckdns-auth-hook.sh` / `duckdns-cleanup-hook.sh` en `/etc/letsencrypt/duckdns/` (token con permisos 600). `certbot.timer` renueva solo cada ~60 días con los mismos hooks.
- Nginx: 80 → 301 a HTTPS; 443 con TLS 1.2/1.3, HTTP/2, HSTS; bloquea `wp-config.php`, `xmlrpc.php` y archivos ocultos.
- `--prueba` usa el entorno *staging* (no gasta límite). **Límite de Let's Encrypt:** 5 certificados iguales por semana; en el prototipo ya se usó 1.

### Resultado del prototipo (macOS, 06/11/2026)
- Ubuntu 26.04.1 LTS en ambas VM, SSH 22022 (22 cerrado), UFW activo.
- `wp_user@192.168.56.10` → `lab5-db:33306`, tablas `wp_*` creadas.
- `www-data` y `sysadmin`: *Permission denied*; `wpadmin`: escribe. SFTP enjaulado, no ve `/etc`.
- `https://redes-lab5-wp.duckdns.org` → `HTTP/2 200`, certificado `Let's Encrypt (YE1)`, válido hasta 04/02/2027, verificación TLS OK desde el host.

### Problemas encontrados en el prototipo (para el informe)
| Problema | Causa | Solución |
|---|---|---|
| `apt` no resolvía nombres | VirtualBox pasaba a la VM los DNS de la red de la universidad, que fallaban intermitentemente | DNS públicos fijos (1.1.1.1, 8.8.8.8) en netplan para la interfaz NAT |
| MySQL escuchaba en 127.0.0.1 | Orden alfabético: `99-lab5.cnf` se leía antes que `mysqld.cnf` | Renombrar a `zz-lab5.cnf` |
| `wp core download --locale=es_ES` fallaba | Aún no existe traducción de WordPress 7.1.4 | Descargar en inglés e intentar activar español después |
| `server_tokens off` no se aplicaba | En Nginx 1.28 de Ubuntu la línea es `server_tokens build;`, no comentada | `sed` con expresión regular más general |
| VMs congeladas en la laptop Windows ("Guest seems to be unresponsive") | Windows tenía activo su hipervisor (WSL2, Integridad de memoria, VBS); VirtualBox no puede usar AMD-V y corre sobre Hyper-V (NEM) | Desactivar WSL/Hyper-V, Integridad de memoria y VBS; con eso las VMs quedaron estables. VBS sigue bloqueado por UEFI pero ya no congela las VMs |
| El instalador pedía "Continue with autoinstall?" | Sin el parámetro `autoinstall` en el kernel, Ubuntu pide confirmación | Responder `yes` con `VBoxManage controlvm <vm> keyboardputstring`, sin abrir la consola |
| Cambiar `Port` en sshd no bastaba | Ubuntu 24.04+ usa `ssh.socket` | `systemctl daemon-reload` + reiniciar `ssh.socket` |
