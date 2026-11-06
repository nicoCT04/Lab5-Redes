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
| Fernando Mendoza | SSH en 22022, UFW, MySQL, pruebas de conectividad | guía enviada por separado |
| Nicolás Concuá | Capa web, WordPress, permisos chown/chmod, SFTP, HTTPS Let's Encrypt | este README (abajo) |

## Orden de ejecución en la laptop de la demo

| # | Quién | Dónde | Comando / acción |
|---|---|---|---|
| 1 | C1 | VirtualBox | Crear VMs, instalar Ubuntu, llaves SSH, copiar `config/ scripts/ secretos.env` a `~/lab5` |
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
prototipo-mac/             automatización del prototipo en macOS (Apple Silicon); no se usa en la demo
informe/                   informe del laboratorio (.docx)
```

`secretos.env` tiene estas variables: `SYSADMIN_PASS`, `DB_PASS`, `WPADMIN_SFTP_PASS`,
`WP_ADMIN_USER`, `WP_ADMIN_PASS`, `WP_ADMIN_EMAIL`, `DUCKDNS_TOKEN`.

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
| Cambiar `Port` en sshd no bastaba | Ubuntu 24.04+ usa `ssh.socket` | `systemctl daemon-reload` + reiniciar `ssh.socket` |
