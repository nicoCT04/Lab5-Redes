#!/usr/bin/env bash
# [Nicolás] SFTP para wpadmin: enjaulado (chroot) en /var/www, sin shell,
# con contraseña (para FileZilla) y umask 027 para que lo subido quede 640/750.
# Requiere 01-ssh-puerto.sh (puerto) y 02-wordpress-permisos.sh.
# Uso (en la VM web):  sudo bash scripts/web/03-sftp.sh
set -euo pipefail
cd "$(dirname "$0")/../.."; source config/lab5.env

cat > /etc/ssh/sshd_config.d/20-sftp-wpadmin.conf <<EOF
# Lab 5 - wpadmin solo puede usar SFTP, encerrado en /var/www
Match User $SFTP_USER
    ChrootDirectory /var/www
    ForceCommand internal-sftp -u 0027
    PasswordAuthentication yes
    AllowTcpForwarding no
    X11Forwarding no
    PermitTunnel no
EOF

sshd -t
systemctl reload ssh
echo "== Config efectiva para $SFTP_USER"
sshd -T -C user="$SFTP_USER",host=x,addr="$HOST_IP" | grep -Ei '^(port|chrootdirectory|forcecommand|passwordauthentication) '
echo "== Config efectiva para $SYSADMIN_USER"
sshd -T -C user="$SYSADMIN_USER",host=x,addr="$HOST_IP" | grep -Ei '^(port|chrootdirectory|forcecommand|passwordauthentication) '
