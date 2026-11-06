#!/usr/bin/env bash
# Pruebas desde un host macOS/Linux (equivalente al .ps1 de Windows).
set -uo pipefail
cd "$(dirname "$0")/../.."; source config/lab5.env
t () { echo; echo "===== $* ====="; }
K="-i $HOME/.ssh/lab5_ed25519 -o IdentitiesOnly=yes -o UserKnownHostsFile=$HOME/.ssh/known_hosts_lab5 -o StrictHostKeyChecking=accept-new"
# nc con tiempo límite de conexión (en macOS -w no limita el connect; se usa -G)
NC="nc -zv -w3"; [ "$(uname)" = Darwin ] && NC="nc -zv -G3 -w3"

t "ping a ambas VM";            ping -c 2 "$WEB_IP"; ping -c 2 "$DB_IP"
t "Resolución local (/etc/hosts)"; grep "$DOMINIO" /etc/hosts; dscacheutil -q host -a name "$DOMINIO" 2>/dev/null || getent hosts "$DOMINIO"
t "Puertos abiertos";           for p in "$WEB_IP $SSH_PORT" "$WEB_IP 443" "$DB_IP $SSH_PORT"; do $NC $p; done
t "Puertos CERRADOS";           $NC "$WEB_IP" 22; $NC "$DB_IP" 22; $NC "$DB_IP" "$MYSQL_PORT"
t "SSH a ambas VM";             ssh $K -p "$SSH_PORT" "$SYSADMIN_USER@$WEB_IP" 'hostname; lsb_release -d'
                                ssh $K -p "$SSH_PORT" "$SYSADMIN_USER@$DB_IP"  'hostname; lsb_release -d'
t "HTTPS (sin -k: el certificado debe ser válido)"; curl -sSI "https://$DOMINIO" | head -5
t "HTTP redirige a HTTPS";      curl -sSI "http://$DOMINIO" | head -3
