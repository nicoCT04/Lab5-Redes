#!/usr/bin/env bash
# [Fernando] Habilita UFW permitiendo SOLO los puertos que se usan.
# Uso:  sudo bash scripts/comun/02-ufw.sh web     (en la VM web)
#       sudo bash scripts/comun/02-ufw.sh db      (en la VM de base de datos)
set -euo pipefail
cd "$(dirname "$0")/../.."; source config/lab5.env
ROL="${1:?Indica el rol: web o db}"

apt-get install -y ufw >/dev/null
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# SSH/SFTP solo desde la red del laboratorio
ufw allow from "$RED_LAB" to any port "$SSH_PORT" proto tcp comment 'SSH/SFTP lab5'

case "$ROL" in
  web)
    ufw allow 80/tcp  comment 'HTTP (redirige a HTTPS)'
    ufw allow 443/tcp comment 'HTTPS WordPress'
    ;;
  db)
    # MySQL solo acepta conexiones desde el servidor web
    ufw allow from "$WEB_IP" to any port "$MYSQL_PORT" proto tcp comment 'MySQL desde web'
    ;;
  *) echo "Rol inválido: $ROL"; exit 1 ;;
esac

ufw --force enable
ufw status verbose
