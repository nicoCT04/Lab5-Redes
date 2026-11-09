#!/usr/bin/env bash
# Crea las 2 VM e instala Ubuntu 26.04.1 con autoinstall. Uso: crear-vms.sh [iso] | crear-vms.sh --terminar
set -euo pipefail
cd "$(dirname "$0")"
source ../config/lab5.env
source <(sed 's/\r$//' ../secretos.env)

VBM="/c/Program Files/Oracle/VirtualBox/VBoxManage.exe"
OPENSSL="/c/Program Files/Git/usr/bin/openssl.exe"
[ -x "$OPENSSL" ] || OPENSSL=openssl
HOSTONLY_IF="VirtualBox Host-Only Ethernet Adapter"
VMS_DIR="$(cygpath -u "$USERPROFILE")/VirtualBox VMs"
BUILD="build"; mkdir -p "$BUILD"

win () { cygpath -w "$1"; }

terminar () {
  local INFO
  for NAME in lab5-web lab5-db; do
    INFO="$("$VBM" showvminfo "$NAME" --machinereadable)"
    if ! grep -q '^"SATA-1-0"=".*\.iso"' <<<"$INFO"; then echo "$NAME ya estaba lista"; continue; fi
    until grep -q '^VMState="poweroff"' <<<"$INFO"; do
      echo "Esperando a que $NAME termine de instalar y se apague..."; sleep 30
      INFO="$("$VBM" showvminfo "$NAME" --machinereadable)"
    done
    "$VBM" storageattach "$NAME" --storagectl SATA --port 1 --type dvddrive --medium none
    "$VBM" storageattach "$NAME" --storagectl SATA --port 2 --type dvddrive --medium none
    "$VBM" startvm "$NAME" --type headless
  done
  echo "Listo. En ~1 min: ssh web hostname  /  ssh db hostname"
}

if [ "${1:-}" = "--terminar" ]; then terminar; exit 0; fi

ISO="${1:-$(cygpath -u "$USERPROFILE")/Downloads/ubuntu-26.04.1-live-server-amd64.iso}"
[ -f "$ISO" ] || { echo "No encuentro la ISO: $ISO"; exit 1; }
PUBKEY="$(cat ~/.ssh/lab5_ed25519.pub)"
PASS_HASH="$("$OPENSSL" passwd -6 "$SYSADMIN_PASS")"

# --- Red host-only: 192.168.56.1/24 en el host, sin DHCP (IPs fijas) ---
"$VBM" list hostonlyifs | grep -q "^Name: *$HOSTONLY_IF\$" || {
  echo "Falta el adaptador '$HOSTONLY_IF' (Archivo > Herramientas > Network Manager > Crear)"; exit 1; }
"$VBM" list hostonlyifs | grep -A4 "^Name: *$HOSTONLY_IF\$" | grep -q "IPAddress: *$HOST_IP" || \
  "$VBM" hostonlyif ipconfig "$HOSTONLY_IF" --ip "$HOST_IP" --netmask 255.255.255.0
"$VBM" dhcpserver modify --interface="$HOSTONLY_IF" --disable 2>/dev/null || true

crear_vm () {
  local NAME=$1 HOST=$2 IP=$3 MAC_NAT=$4 MAC_LAN=$5
  local SEED="$BUILD/$NAME-seed"; mkdir -p "$SEED"
  fmt () { echo "$1" | sed 's/../&:/g;s/:$//' | tr 'A-F' 'a-f'; }

  if "$VBM" list vms | grep -q "\"$NAME\""; then echo "$NAME ya existe, la salto"; return; fi

  cat > "$SEED/user-data" <<EOF
#cloud-config
autoinstall:
  version: 1
  refresh-installer: {update: false}
  locale: en_US.UTF-8
  keyboard: {layout: latam}
  timezone: America/Guatemala
  identity:
    hostname: $HOST
    realname: $SYSADMIN_USER
    username: $SYSADMIN_USER
    password: '$PASS_HASH'
  ssh:
    install-server: true
    allow-pw: false
    authorized-keys: ['$PUBKEY']
  network:
    version: 2
    ethernets:
      nat:
        match: {macaddress: '$(fmt $MAC_NAT)'}
        dhcp4: true
        dhcp4-overrides: {use-dns: false}
        nameservers: {addresses: [1.1.1.1, 8.8.8.8]}
      lan:
        match: {macaddress: '$(fmt $MAC_LAN)'}
        dhcp4: false
        addresses: [$IP/24]
  storage: {layout: {name: direct}}
  late-commands:
    # sudo sin contraseña para sysadmin: permite lanzar los scripts por ssh sin TTY.
    - echo '$SYSADMIN_USER ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/90-lab5
    - chmod 440 /target/etc/sudoers.d/90-lab5
  shutdown: poweroff
EOF
  echo "instance-id: $NAME" > "$SEED/meta-data"
  rm -f "$BUILD/$NAME-seed.iso"
  python hacer-seed.py "$SEED" "$BUILD/$NAME-seed.iso"

  "$VBM" createvm --name "$NAME" --ostype Ubuntu_64 --register
  "$VBM" modifyvm "$NAME" --cpus 2 --memory 2048 --vram 16 --graphicscontroller vmsvga \
    --nic1 nat --mac-address1 "$MAC_NAT" \
    --nic2 hostonly --hostonlyadapter2 "$HOSTONLY_IF" --mac-address2 "$MAC_LAN" \
    --audio-enabled off --boot1 disk --boot2 dvd --boot3 none --boot4 none
  "$VBM" storagectl "$NAME" --name SATA --add sata --controller IntelAhci --portcount 3 --bootable on
  local DISK="$VMS_DIR/$NAME/$NAME.vdi"
  "$VBM" createmedium disk --filename "$(win "$DISK")" --size 15360 --format VDI
  "$VBM" storageattach "$NAME" --storagectl SATA --port 0 --type hdd --medium "$(win "$DISK")"
  "$VBM" storageattach "$NAME" --storagectl SATA --port 1 --type dvddrive --medium "$(win "$ISO")"
  "$VBM" storageattach "$NAME" --storagectl SATA --port 2 --type dvddrive --medium "$(win "$PWD/$BUILD/$NAME-seed.iso")"
  "$VBM" startvm "$NAME" --type headless
}

crear_vm lab5-web "$WEB_HOSTNAME" "$WEB_IP" 0800275A0010 0800275A0110
crear_vm lab5-db  "$DB_HOSTNAME"  "$DB_IP"  0800275A0020 0800275A0120
echo "Instalando (10-20 min). Luego: infra-windows/crear-vms.sh --terminar"
