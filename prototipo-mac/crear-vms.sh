#!/usr/bin/env bash
# Prototipo en macOS (Apple Silicon): crea las 2 VM con VirtualBox e instala
# Ubuntu Server 26.04.1 de forma desatendida (autoinstall).
# Uso: ./crear-vms.sh   (requiere xorriso y la ISO arm64 descargada)
set -euo pipefail
cd "$(dirname "$0")"
source ../config/lab5.env
source ../secretos.env

ISO_DIR="$HOME/VirtualBox VMs/lab5-iso"
ISO="$ISO_DIR/ubuntu-26.04.1-live-server-arm64.iso"
BUILD="build"; mkdir -p "$BUILD"
PUBKEY="$(cat ~/.ssh/lab5_ed25519.pub)"
PASS_HASH="$(openssl passwd -6 "$SYSADMIN_PASS")"

# 1) ISO con 'autoinstall' en el kernel (evita la confirmación interactiva)
AUTO_ISO="$ISO_DIR/ubuntu-26.04.1-autoinstall-arm64.iso"
if [ ! -f "$AUTO_ISO" ]; then
  xorriso -osirrox on -indev "$ISO" -extract /boot/grub/grub.cfg "$BUILD/grub.cfg" 2>/dev/null
  chmod u+w "$BUILD/grub.cfg"
  sed -i '' -e 's|---| autoinstall ---|g' -e 's/^set timeout=.*/set timeout=3/' "$BUILD/grub.cfg"
  xorriso -indev "$ISO" -outdev "$AUTO_ISO" -map "$BUILD/grub.cfg" /boot/grub/grub.cfg \
          -boot_image any replay 2>&1 | tail -1
fi

crear_vm () {
  local NAME=$1 HOST=$2 IP=$3 MAC_NAT=$4 MAC_LAN=$5
  local SEED="$BUILD/$NAME-seed"; mkdir -p "$SEED"
  fmt () { echo "$1" | sed 's/../&:/g;s/:$//' | tr 'A-F' 'a-f'; }
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
        set-name: enp-nat
        dhcp4: true
        dhcp4-overrides: {use-dns: false}
        nameservers: {addresses: [1.1.1.1, 8.8.8.8]}
      lan:
        match: {macaddress: '$(fmt $MAC_LAN)'}
        set-name: enp-lan
        dhcp4: false
        addresses: [$IP/24]
  storage: {layout: {name: direct}}
  late-commands:
    - echo '$SYSADMIN_USER ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/90-prototipo
    - chmod 440 /target/etc/sudoers.d/90-prototipo
  shutdown: poweroff
EOF
  echo "instance-id: $NAME" > "$SEED/meta-data"
  rm -f "$BUILD/$NAME-seed.iso"
  xorriso -as mkisofs -quiet -V CIDATA -J -r -o "$BUILD/$NAME-seed.iso" "$SEED" 2>/dev/null

  VBoxManage createvm --name "$NAME" --platform-architecture arm --ostype Ubuntu_arm64 --register
  VBoxManage modifyvm "$NAME" --cpus 2 --memory 2048 --firmware efi --graphicscontroller qemuramfb \
    --nic1 nat --mac-address1 "$MAC_NAT" --nat-dns-host-resolver1 on \
    --nic2 hostonlynet --host-only-net2 lab5net --mac-address2 "$MAC_LAN" \
    --audio-enabled off --usb-xhci on --mouse usb --keyboard usb
  VBoxManage storagectl "$NAME" --name VirtIO --add virtio-scsi --bootable on
  local DISK="$HOME/VirtualBox VMs/$NAME/$NAME.vdi"
  VBoxManage createmedium disk --filename "$DISK" --size 15360 --format VDI
  VBoxManage storageattach "$NAME" --storagectl VirtIO --port 0 --type hdd --medium "$DISK"
  VBoxManage storageattach "$NAME" --storagectl VirtIO --port 1 --type dvddrive --medium "$AUTO_ISO"
  VBoxManage storageattach "$NAME" --storagectl VirtIO --port 2 --type dvddrive --medium "$PWD/$BUILD/$NAME-seed.iso"
  VBoxManage startvm "$NAME" --type headless
}

crear_vm lab5-web "$WEB_HOSTNAME" "$WEB_IP" 0800275A0010 0800275A0110
crear_vm lab5-db  "$DB_HOSTNAME"  "$DB_IP"  0800275A0020 0800275A0120
echo "Instalando... las VM se apagan solas al terminar."
