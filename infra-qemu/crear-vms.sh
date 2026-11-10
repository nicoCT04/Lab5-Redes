#!/usr/bin/env bash
# Crea y arranca lab5-web y lab5-db con QEMU/KVM en WSL2, sin pantalla.
# Mismo diseño que infra-windows/ (VirtualBox): 2 CPU, 2 GB, 15 GB, Ubuntu Server 26.04,
# adaptador 1 NAT (Internet) + adaptador 2 en la red host-only (IP fija), usuario sysadmin
# solo con llave. En lugar del instalador se usa la imagen cloud oficial + cloud-init.
#
# Uso:  infra-qemu/crear-vms.sh            crea (si no existen) y arranca las 2 VM
#       infra-qemu/crear-vms.sh --apagar   apaga ambas
#       infra-qemu/crear-vms.sh --borrar   apaga y elimina discos (la imagen base se conserva)
# Requiere haber corrido una vez:  sudo bash infra-qemu/requisitos.sh
set -euo pipefail
cd "$(dirname "$0")"
source ../config/lab5.env
source <(sed 's/\r$//' ../secretos.env)

BUILD="$PWD/build"; mkdir -p "$BUILD"
IMG_URL="https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-amd64.img"
BASE="$BUILD/ubuntu-26.04-server-cloudimg-amd64.img"
LLAVE="$HOME/.ssh/lab5_ed25519"

#        nombre    hostname         ip         mac NAT            mac host-only      tap
VMS=("lab5-web $WEB_HOSTNAME $WEB_IP 08:00:27:5a:00:10 08:00:27:5a:01:10 tap-web"
     "lab5-db  $DB_HOSTNAME  $DB_IP  08:00:27:5a:00:20 08:00:27:5a:01:20 tap-db")

pid_de () { local P="$BUILD/$1.pid"; [ -f "$P" ] && kill -0 "$(cat "$P")" 2>/dev/null && cat "$P"; }

apagar () {
  for V in "${VMS[@]}"; do
    read -r NAME _ <<<"$V"
    local PID; PID="$(pid_de "$NAME")" || { echo "$NAME ya estaba apagada"; continue; }
    # Apagado ordenado por QMP (equivale a presionar el botón de encendido)
    python3 - "$BUILD/$NAME.qmp" <<'PY' || kill "$PID"
import json, socket, sys
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); f = s.makefile("rw")
f.readline()
for cmd in ("qmp_capabilities", "system_powerdown"):
    f.write(json.dumps({"execute": cmd}) + "\n"); f.flush(); f.readline()
PY
    for _ in $(seq 60); do kill -0 "$PID" 2>/dev/null || break; sleep 1; done
    kill -0 "$PID" 2>/dev/null && kill "$PID"
    echo "$NAME apagada"
  done
}

case "${1:-}" in
  --apagar) apagar; exit 0 ;;
  --borrar) apagar; rm -rf "$BUILD"/lab5-*; echo "Discos eliminados"; exit 0 ;;
  "") ;;
  *) echo "Opción desconocida: $1"; exit 1 ;;
esac

# --- Comprobaciones ---
ip link show br-lab5 >/dev/null 2>&1 || { echo "Falta la red br-lab5: sudo bash infra-qemu/requisitos.sh"; exit 1; }
command -v qemu-system-x86_64 >/dev/null || { echo "Falta QEMU: sudo bash infra-qemu/requisitos.sh"; exit 1; }
# Si el grupo kvm se agregó en esta sesión, se usa con sg sin reiniciar WSL
QEMU=(qemu-system-x86_64)
id -nG | grep -qw kvm || QEMU=(sg kvm -c)

# --- Llave del laboratorio e imagen base ---
[ -f "$LLAVE" ] || ssh-keygen -q -t ed25519 -N "" -C "lab5" -f "$LLAVE"
if [ ! -f "$BASE" ]; then
  echo "Descargando Ubuntu Server 26.04 (imagen cloud, ~820 MB)..."
  curl -fL --progress-bar -o "$BASE.part" "$IMG_URL" && mv "$BASE.part" "$BASE"
fi
PASS_HASH="$(openssl passwd -6 "$SYSADMIN_PASS")"

crear_y_arrancar () {
  local NAME=$1 HOST=$2 IP=$3 MAC_NAT=$4 MAC_LAN=$5 TAP=$6
  local DISK="$BUILD/$NAME.qcow2" SEED="$BUILD/$NAME-seed.img" D="$BUILD/$NAME-cidata"

  if pid_de "$NAME" >/dev/null; then echo "$NAME ya está corriendo"; return; fi

  if [ ! -f "$DISK" ]; then
    mkdir -p "$D"
    cat > "$D/user-data" <<EOF
#cloud-config
hostname: $HOST
manage_etc_hosts: true
timezone: America/Guatemala
locale: en_US.UTF-8
ssh_pwauth: false
users:
  - name: $SYSADMIN_USER
    gecos: $SYSADMIN_USER
    groups: [sudo]
    shell: /bin/bash
    lock_passwd: false
    passwd: '$PASS_HASH'
    # sudo sin contraseña: permite lanzar los scripts por ssh sin TTY (igual que en VirtualBox)
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys: ['$(cat "$LLAVE.pub")']
EOF
    echo "instance-id: $NAME" > "$D/meta-data"
    # Las NIC van en las ranuras PCI 3 y 8 (ver ARGS), así Ubuntu las nombra enp0s3 (NAT) y enp0s8
    # (host-only), igual que en VirtualBox; set-name solo lo confirma
    cat > "$D/network-config" <<EOF
version: 2
ethernets:
  enp0s3:
    match: {macaddress: '$MAC_NAT'}
    set-name: enp0s3
    dhcp4: true
    dhcp4-overrides: {use-dns: false}
    nameservers: {addresses: [1.1.1.1, 8.8.8.8]}
  enp0s8:
    match: {macaddress: '$MAC_LAN'}
    set-name: enp0s8
    dhcp4: false
    addresses: [$IP/24]
EOF
    cloud-localds --network-config="$D/network-config" "$SEED" "$D/user-data" "$D/meta-data"
    qemu-img create -q -f qcow2 -F qcow2 -b "$BASE" "$DISK" 15G
  fi

  local ARGS=(-name "$NAME" -machine q35,accel=kvm -cpu host -smp 2 -m 2048
    -drive "if=virtio,file=$DISK"
    -drive "if=virtio,format=raw,file=$SEED,readonly=on"
    -netdev user,id=nat -device "virtio-net-pci,netdev=nat,mac=$MAC_NAT,addr=0x3"
    -netdev "tap,id=lan,ifname=$TAP,script=no,downscript=no" -device "virtio-net-pci,netdev=lan,mac=$MAC_LAN,addr=0x8"
    -display none -serial "file:$BUILD/$NAME-serial.log"
    -qmp "unix:$BUILD/$NAME.qmp,server=on,wait=off"
    -pidfile "$BUILD/$NAME.pid" -daemonize)
  if [ "${QEMU[0]}" = sg ]; then
    sg kvm -c "qemu-system-x86_64 $(printf '%q ' "${ARGS[@]}")"
  else
    qemu-system-x86_64 "${ARGS[@]}"
  fi
  echo "$NAME arrancada ($IP)"
}

for V in "${VMS[@]}"; do crear_y_arrancar $V; done

# --- Alias ssh web / ssh db (como el ~/.ssh/config de la guía) ---
CFG="$BUILD/ssh_config"
if [ ! -f "$CFG" ]; then
  cat > "$CFG" <<EOF
# Generado por infra-qemu/crear-vms.sh. Paso 1 de la guía: cambiar Port 22 -> $SSH_PORT
Host web
    HostName $WEB_IP
Host db
    HostName $DB_IP
Host web db
    User $SYSADMIN_USER
    Port 22
    IdentityFile $LLAVE
    IdentitiesOnly yes
    UserKnownHostsFile ~/.ssh/known_hosts_lab5
    StrictHostKeyChecking accept-new
EOF
fi
# El Include debe ir al inicio del archivo para que aplique a todos los hosts
touch "$HOME/.ssh/config"
if ! grep -qF "Include $CFG" "$HOME/.ssh/config"; then
  { printf 'Include %s\n\n' "$CFG"; cat "$HOME/.ssh/config"; } > "$HOME/.ssh/config.tmp"
  mv "$HOME/.ssh/config.tmp" "$HOME/.ssh/config"
fi
chmod 600 "$HOME/.ssh/config"

echo "Esperando a que SSH responda (primer arranque ~1 min)..."
# No basta con que el puerto abra: hasta que termina el arranque, pam_nologin rechaza el login
for VM in web db; do
  for _ in $(seq 90); do ssh -o BatchMode=yes -o ConnectTimeout=3 "$VM" true 2>/dev/null && break; sleep 2; done
done
ssh web hostname && ssh db hostname
