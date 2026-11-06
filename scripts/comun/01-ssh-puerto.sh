#!/usr/bin/env bash
# [Fernando] Cambia SSH al puerto no conocido y endurece la configuración.
# Se corre en AMBAS VM:  sudo bash scripts/comun/01-ssh-puerto.sh
# IMPORTANTE: correr ANTES 02-ufw.sh abre el puerto nuevo; si UFW aún no está
# activo no hay problema. No cierres la sesión actual hasta probar la nueva.
set -euo pipefail
cd "$(dirname "$0")/../.."; source config/lab5.env

cat > /etc/ssh/sshd_config.d/10-lab5.conf <<EOF
# Lab 5 - SSH en puerto no conocido
Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
X11Forwarding no
EOF

sshd -t   # valida la sintaxis antes de reiniciar
# Ubuntu 24.04+ usa activación por socket: el puerto lo toma ssh.socket
systemctl daemon-reload
systemctl restart ssh.socket 2>/dev/null || true
systemctl restart ssh
sleep 1
ss -tlnp | grep -E ":$SSH_PORT\b" && echo "OK: SSH escuchando en $SSH_PORT"
