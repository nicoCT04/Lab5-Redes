#!/usr/bin/env bash
# [Nicolás] Usuario SFTP administrador, descarga de WordPress, conexión a la BD
# remota y permisos (chown/chmod) para que SOLO wpadmin pueda escribir.
# Requiere: capa BD lista (01-mysql.sh) y 01-stack-web.sh.
# Uso (en la VM web):  sudo bash scripts/web/02-wordpress-permisos.sh
set -euo pipefail
cd "$(dirname "$0")/../.."; source config/lab5.env; source secretos.env
WP="sudo -u $SFTP_USER wp --path=$WP_DIR"

# 1) Prueba de conexión al MySQL remoto con el usuario de WordPress
mysql -h "$DB_IP" -P "$MYSQL_PORT" -u "$DB_USER" -p"$DB_PASS" -e "SELECT 'OK conexión a BD remota' AS estado;"

# 2) Usuario administrador del sitio (único con escritura). Grupo propio.
if ! id "$SFTP_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /usr/sbin/nologin "$SFTP_USER"
fi
echo "$SFTP_USER:$WPADMIN_SFTP_PASS" | chpasswd

# 3) /var/www debe ser de root y no escribible por otros (requisito del chroot SFTP)
mkdir -p "$WP_DIR"; chown root:root /var/www; chmod 755 /var/www
chown "$SFTP_USER:www-data" "$WP_DIR"

# 4) WordPress descargado y configurado COMO wpadmin (él es el dueño)
export HOME=/tmp
if [ ! -f "$WP_DIR/wp-load.php" ]; then
  $WP core download
fi
if [ ! -f "$WP_DIR/wp-config.php" ]; then
  $WP config create --dbname="$DB_NAME" --dbuser="$DB_USER" --dbpass="$DB_PASS" \
      --dbhost="$DB_IP:$MYSQL_PORT" --dbcharset=utf8mb4
  # El servidor web no puede escribir: los cambios de archivos se hacen por SFTP
  $WP config set DISALLOW_FILE_EDIT true --raw
  $WP config set DISALLOW_FILE_MODS true --raw
  $WP config set FORCE_SSL_ADMIN true --raw
fi
if ! $WP core is-installed 2>/dev/null; then
  $WP core install --url="https://$DOMINIO" --title="$WP_TITULO" \
      --admin_user="$WP_ADMIN_USER" --admin_password="$WP_ADMIN_PASS" \
      --admin_email="$WP_ADMIN_EMAIL" --skip-email
fi
# Idioma español si ya hay traducción para esta versión (si no, queda en inglés)
$WP language core install es_ES --activate 2>/dev/null || echo "Aviso: sin traducción es_ES, se queda en inglés"

# 5) Permisos:  dueño = wpadmin (rw), grupo = www-data (solo lectura), otros = nada
#    - directorios 2750: el bit setgid hace que lo que suba wpadmin herede el grupo www-data
#    - archivos 640; wp-config.php 640 (contiene la contraseña de la BD)
chown -R "$SFTP_USER:www-data" "$WP_DIR"
find "$WP_DIR" -type d -exec chmod 2750 {} +
find "$WP_DIR" -type f -exec chmod 640 {} +

echo "== Permisos resultantes"
ls -ld /var/www "$WP_DIR"; ls -l "$WP_DIR" | head -8
