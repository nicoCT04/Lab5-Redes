#!/usr/bin/env bash
# [Nicolás] Certificado de Let's Encrypt por validación DNS-01 (DuckDNS) y
# Nginx sirviendo WordPress solo por HTTPS.
#
# Por qué DNS-01: la VM no es accesible desde Internet (red host-only y nombre
# resuelto con /etc/hosts), así que HTTP-01 / TLS-ALPN-01 no pueden validarse.
# DNS-01 solo exige publicar un registro TXT en el DNS público del dominio,
# cosa que DuckDNS permite por su API. El certificado sirve igual aunque el
# nombre se resuelva localmente a 192.168.56.10.
#
# Uso (en la VM web):  sudo bash scripts/web/04-https.sh            (certificado real)
#                      sudo bash scripts/web/04-https.sh --prueba   (solo staging, no gasta límite)
set -euo pipefail
cd "$(dirname "$0")/../.."; source config/lab5.env; source secretos.env
[ -n "${DUCKDNS_TOKEN:-}" ] || { echo "Falta DUCKDNS_TOKEN en secretos.env"; exit 1; }
SUB="${DOMINIO%.duckdns.org}"

apt-get install -y certbot >/dev/null

# Token guardado solo para root (lo usan los hooks también en las renovaciones)
install -d -m 700 /etc/letsencrypt/duckdns
printf 'SUB=%s\nTOKEN=%s\n' "$SUB" "$DUCKDNS_TOKEN" > /etc/letsencrypt/duckdns/credenciales
chmod 600 /etc/letsencrypt/duckdns/credenciales
install -m 700 scripts/web/duckdns-auth-hook.sh    /etc/letsencrypt/duckdns/auth-hook.sh
install -m 700 scripts/web/duckdns-cleanup-hook.sh /etc/letsencrypt/duckdns/cleanup-hook.sh

ARGS=(certonly --manual --preferred-challenges dns
      --manual-auth-hook /etc/letsencrypt/duckdns/auth-hook.sh
      --manual-cleanup-hook /etc/letsencrypt/duckdns/cleanup-hook.sh
      --non-interactive --agree-tos --register-unsafely-without-email
      --keep-until-expiring -d "$DOMINIO")
if [ "${1:-}" = "--prueba" ]; then
  certbot "${ARGS[@]}" --dry-run; exit 0
fi
certbot "${ARGS[@]}"

PHPV="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
cat > /etc/nginx/sites-available/wordpress <<EOF
# HTTP: solo redirige a HTTPS
server {
    listen 80;
    server_name $DOMINIO;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name $DOMINIO;
    root $WP_DIR;
    index index.php;

    ssl_certificate     /etc/letsencrypt/live/$DOMINIO/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMINIO/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    add_header Strict-Transport-Security "max-age=31536000" always;

    client_max_body_size 64M;

    location / { try_files \$uri \$uri/ /index.php?\$args; }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$PHPV-fpm.sock;
    }

    # No exponer archivos sensibles
    location ~ /\.(?!well-known) { deny all; }
    location = /wp-config.php    { deny all; }
    location = /xmlrpc.php       { deny all; }
}
EOF
ln -sf /etc/nginx/sites-available/wordpress /etc/nginx/sites-enabled/wordpress
nginx -t && systemctl reload nginx

echo "== Certificado"
openssl x509 -in "/etc/letsencrypt/live/$DOMINIO/cert.pem" -noout -issuer -subject -dates
systemctl list-timers certbot.timer --no-pager | head -3
