#!/usr/bin/env bash
# [Fernando] Pruebas de funcionamiento DENTRO de cada VM (evidencia para el informe).
# Uso:  sudo bash scripts/pruebas/pruebas-servidor.sh web   |   ... db
set -uo pipefail
cd "$(dirname "$0")/../.."; source config/lab5.env; source secretos.env
ROL="${1:?web o db}"
t () { echo; echo "===== $* ====="; }

t "Sistema operativo";      lsb_release -d; uname -r
t "IP de la red del lab";   ip -4 -br addr
t "Puertos escuchando";     ss -tlnp
t "Firewall UFW";           ufw status verbose

if [ "$ROL" = web ]; then
  t "ping a la BD";                     ping -c 3 "$DB_IP"
  t "Puerto MySQL abierto en la BD (nc)"; nc -zv -w3 "$DB_IP" "$MYSQL_PORT"
  t "telnet al puerto MySQL (saludo del servidor)"
                                        command -v telnet >/dev/null || apt-get install -y telnet >/dev/null
                                        sleep 2 | telnet "$DB_IP" "$MYSQL_PORT" 2>&1 | tr -cd "[:print:]\n" | head -4
  t "Puerto 3306 por defecto CERRADO";  nc -zv -w3 "$DB_IP" 3306 || echo "-> correcto: 3306 no responde"
  t "Login MySQL remoto con wp_user";   mysql -h "$DB_IP" -P "$MYSQL_PORT" -u "$DB_USER" -p"$DB_PASS" \
                                          -e "SELECT CURRENT_USER(), @@hostname, @@port; SHOW TABLES FROM $DB_NAME;"
  t "Permisos de WordPress";            ls -ld /var/www "$WP_DIR"; ls -l "$WP_DIR" | head -6
  t "www-data NO puede escribir";       sudo -u www-data touch "$WP_DIR/prueba" 2>&1 || true
  t "sysadmin NO puede escribir";       sudo -u "$SYSADMIN_USER" touch "$WP_DIR/prueba" 2>&1 || true
  t "wpadmin SÍ puede escribir";        sudo -u "$SFTP_USER" touch "$WP_DIR/prueba" && ls -l "$WP_DIR/prueba" && sudo -u "$SFTP_USER" rm "$WP_DIR/prueba"
  t "HTTPS local";                      curl -sI --resolve "$DOMINIO:443:127.0.0.1" "https://$DOMINIO" | head -5
  t "Certificado";                      openssl x509 -in "/etc/letsencrypt/live/$DOMINIO/cert.pem" -noout -issuer -subject -dates
else
  t "ping al servidor web";             ping -c 3 "$WEB_IP"
  t "Usuarios de MySQL";                mysql -e "SELECT user, host, plugin FROM mysql.user;"
  t "Privilegios de wp_user";           mysql -e "SHOW GRANTS FOR '$DB_USER'@'$WEB_IP';"
  t "Tablas de WordPress";              mysql -e "SHOW TABLES FROM $DB_NAME;"
fi
