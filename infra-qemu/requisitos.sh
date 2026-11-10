#!/usr/bin/env bash
# Prepara WSL2 para correr las VM con QEMU/KVM. Es lo único que necesita root.
# Uso:  sudo bash infra-qemu/requisitos.sh
set -euo pipefail
cd "$(dirname "$0")"
USUARIO="${SUDO_USER:?corre este script con sudo desde tu usuario}"

[ -e /dev/kvm ] || { echo "No existe /dev/kvm: activa la virtualización anidada de WSL2"; exit 1; }

echo "== Paquetes"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  qemu-system-x86 qemu-utils cloud-image-utils iptables telnet netcat-openbsd >/dev/null
qemu-system-x86_64 --version | head -1

echo "== Acceso a KVM para $USUARIO"
usermod -aG kvm "$USUARIO"

echo "== Red del laboratorio (servicio lab5-red)"
install -m 755 red.sh /usr/local/sbin/lab5-red
cat > /etc/systemd/system/lab5-red.service <<EOF
[Unit]
Description=Lab 5 - red host-only 192.168.56.0/24 para las VM de QEMU
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=USUARIO=$USUARIO
ExecStart=/usr/local/sbin/lab5-red up
ExecStop=/usr/local/sbin/lab5-red down

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable lab5-red.service >/dev/null
systemctl restart lab5-red.service
systemctl is-active lab5-red.service
echo "Listo."
