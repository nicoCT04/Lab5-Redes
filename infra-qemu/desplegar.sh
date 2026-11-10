#!/usr/bin/env bash
# Despliegue completo del laboratorio sobre las VM de QEMU, en el mismo orden que la
# tabla "Orden de ejecución" del README. Todo por SSH desde el host (WSL); cada salida
# queda en evidencias/qemu/ con el mismo nombre que las evidencias de la demo.
#
# Uso:  infra-qemu/desplegar.sh                 todo, con certificado de staging (no gasta límite)
#       infra-qemu/desplegar.sh --certificado   además emite el certificado real de Let's Encrypt
#       infra-qemu/desplegar.sh --solo-pruebas  solo el paso 10 (pruebas)
set -uo pipefail
cd "$(dirname "$0")/.."
source config/lab5.env
EV=evidencias/qemu; mkdir -p "$EV"
CFG=infra-qemu/build/ssh_config
MODO="${1:-}"

paso () { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
# Ejecuta un comando en la VM y guarda la salida (sin códigos de color ni \r)
en () { local VM=$1 ARCH=$2; shift 2
  ssh "$VM" "cd ~/lab5 && $*" 2>&1 | sed 's/\r$//' | tee "$EV/$ARCH.txt"; return "${PIPESTATUS[0]}"; }
falla () { echo "ERROR: $*"; exit 1; }

if [ "$MODO" != --solo-pruebas ]; then
  PUERTO="$(awk '/^ *Port /{print $2}' "$CFG")"

  paso "1. Copiar config/, scripts/ y secretos.env a las VM (puerto $PUERTO)"
  infra-windows/subir.sh web "$PUERTO" && infra-windows/subir.sh db "$PUERTO" || falla "no se pudo copiar"

  paso "Paso 0 (guía Fernando): acceso por SSH"
  { ssh web "hostname; ls ~/lab5"; ssh db "hostname; ls ~/lab5"; } 2>&1 | tee "$EV/00-acceso-ssh.txt"

  paso "2. SSH al puerto $SSH_PORT en ambas VM"
  en web web-01-ssh-puerto "sudo bash scripts/comun/01-ssh-puerto.sh" || falla "ssh web"
  en db  db-01-ssh-puerto  "sudo bash scripts/comun/01-ssh-puerto.sh" || falla "ssh db"
  sed -i -E "s/^( *Port) 22\$/\1 $SSH_PORT/" "$CFG"
  { echo "\$ ssh web hostname"; ssh web hostname
    echo "\$ ssh db hostname";  ssh db hostname
    for IP in "$WEB_IP" "$DB_IP"; do
      echo "\$ ssh -p 22 $SYSADMIN_USER@$IP"
      ssh -p 22 -o ConnectTimeout=5 -o BatchMode=yes "$SYSADMIN_USER@$IP" true 2>&1 || true
    done; } | tee "$EV/01-puerto-22-cerrado.txt"

  paso "3. Firewall UFW"
  en web web-02-ufw "sudo bash scripts/comun/02-ufw.sh web" || falla "ufw web"
  en db  db-02-ufw  "sudo bash scripts/comun/02-ufw.sh db"  || falla "ufw db"

  paso "4. MySQL en la VM db"
  en db db-03-mysql "sudo bash scripts/bd/01-mysql.sh" || falla "mysql"
  en db db-04-gestion-bd "sudo mysql -e 'SHOW DATABASES; SELECT user,host,plugin FROM mysql.user;'"

  paso "5-7. Capa web: stack, WordPress con permisos, SFTP"
  en web web-03-stack              "sudo bash scripts/web/01-stack-web.sh"          || falla "stack web"
  en web web-04-wordpress-permisos "sudo bash scripts/web/02-wordpress-permisos.sh" || falla "wordpress"
  en web web-05-sftp               "sudo bash scripts/web/03-sftp.sh"               || falla "sftp"

  paso "8. HTTPS (staging primero)"
  en web web-06-https-prueba "sudo bash scripts/web/04-https.sh --prueba" || falla "https staging"
  if [ "$MODO" = --certificado ]; then
    en web web-07-https "sudo bash scripts/web/04-https.sh" || falla "https"
  fi
fi

paso "10. Pruebas (guía Fernando, paso 5)"
en web pruebas-servidor-web "sudo bash scripts/pruebas/pruebas-servidor.sh web"
en db  pruebas-servidor-db  "sudo bash scripts/pruebas/pruebas-servidor.sh db"
# La prueba desde el host usa la llave y los puertos del laboratorio
bash scripts/pruebas/pruebas-host-mac-linux.sh 2>&1 | tee "$EV/pruebas-host-wsl.txt"

paso "telnet desde el host (443 abre; 33306 lo bloquea UFW)"
{ echo "\$ telnet $WEB_IP 443";        timeout 5 stdbuf -o0 telnet "$WEB_IP" 443        </dev/null 2>&1
  echo "\$ telnet $DB_IP $MYSQL_PORT"; timeout 8 stdbuf -o0 telnet "$DB_IP" "$MYSQL_PORT" </dev/null 2>&1
  [ $? -eq 124 ] && echo "(sin respuesta: bloqueado por el firewall)"; } | tee "$EV/telnet-host.txt"

paso "Versiones"
for VM in web db; do
  ssh "$VM" 'echo "== $(hostname)"; lsb_release -d; uname -r; sudo ufw version | head -1; ssh -V 2>&1; mysql --version 2>/dev/null'
done 2>&1 | tee "$EV/versiones.txt"
echo
echo "Evidencias en $EV/"
