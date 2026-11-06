#!/usr/bin/env bash
# [Fernando] Capa de base de datos: MySQL en puerto no conocido, escuchando
# solo en la red del lab, con BD y usuario propios de WordPress (no root).
# Uso (en la VM db):  sudo bash scripts/bd/01-mysql.sh
set -euo pipefail
cd "$(dirname "$0")/../.."; source config/lab5.env; source secretos.env

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y mysql-server >/dev/null

# "zz-" para que se lea DESPUÉS de mysqld.cnf (orden alfabético) y lo sobrescriba
rm -f /etc/mysql/mysql.conf.d/99-lab5.cnf
cat > /etc/mysql/mysql.conf.d/zz-lab5.cnf <<EOF
[mysqld]
# Escucha solo en la interfaz de la red del laboratorio
bind-address = $DB_IP
port         = $MYSQL_PORT
# Desactiva el protocolo X (puerto 33060): no se usa
mysqlx       = 0
EOF

systemctl restart mysql

# root del motor sigue con auth_socket: solo "sudo mysql" desde la propia VM.
mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'$WEB_IP' IDENTIFIED BY '$DB_PASS';
ALTER USER '$DB_USER'@'$WEB_IP' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'$WEB_IP';
FLUSH PRIVILEGES;
SQL

mysql -e "SELECT user, host, plugin FROM mysql.user WHERE user='$DB_USER';
          SHOW GRANTS FOR '$DB_USER'@'$WEB_IP';"
mysql --version
ss -tlnp | grep mysqld
