#!/usr/bin/env bash
# Copia config/, scripts/ y secretos.env a ~/lab5 de la VM. Uso: subir.sh web|db [puerto]
set -euo pipefail
cd "$(dirname "$0")/.."
H=$1; P=${2:-22022}
tar -czf - config scripts secretos.env | ssh -p "$P" "$H" \
  'rm -rf ~/lab5 && mkdir -p ~/lab5 && tar xzf - -C ~/lab5 && chmod 600 ~/lab5/secretos.env &&
   sed -i "s/\r$//" ~/lab5/scripts/*/*.sh ~/lab5/config/lab5.env ~/lab5/secretos.env && echo "OK: $(hostname):~/lab5"'
