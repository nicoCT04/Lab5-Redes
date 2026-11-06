#!/usr/bin/env bash
# [Nicolás] Capa web: Nginx + PHP-FPM + extensiones de WordPress + cliente MySQL + WP-CLI.
# Uso (en la VM web):  sudo bash scripts/web/01-stack-web.sh
set -euo pipefail
cd "$(dirname "$0")/../.."; source config/lab5.env

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y nginx php-fpm php-mysql php-curl php-gd php-mbstring php-xml \
  php-zip php-intl php-imagick mysql-client curl unzip >/dev/null

# WP-CLI: herramienta oficial de línea de comandos de WordPress (gestión sin GUI)
if ! command -v wp >/dev/null; then
  curl -fsSL -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
  chmod 755 /usr/local/bin/wp
fi

# Nginx no anuncia su versión
sed -i -E 's/^(\s*)#?\s*server_tokens [a-z]+;/\1server_tokens off;/' /etc/nginx/nginx.conf
rm -f /etc/nginx/sites-enabled/default
rm -rf /var/www/html   # página de ejemplo de Nginx, no se usa
systemctl enable --now nginx "php$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')-fpm"

echo "== Versiones"; nginx -v; php -v | head -1; mysql --version; wp --version --allow-root
