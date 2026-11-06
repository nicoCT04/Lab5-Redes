#!/usr/bin/env bash
# Copia config/, scripts/ y secretos.env a ~/lab5 de la VM indicada.
# Uso: prototipo-mac/subir.sh web [puerto]   (puerto 22 antes de cambiarlo)
set -euo pipefail
cd "$(dirname "$0")/.."
H=$1; P=${2:-22022}
COPYFILE_DISABLE=1 tar --no-xattrs -czf - config scripts secretos.env | ssh -F prototipo-mac/ssh_config -p "$P" "$H" 'rm -rf ~/lab5 && mkdir -p ~/lab5 && tar xzf - -C ~/lab5 && chmod 600 ~/lab5/secretos.env'
