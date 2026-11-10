#!/usr/bin/env bash
# Red del laboratorio: puente br-lab5 (192.168.56.1/24, sin DHCP) con tap-web y tap-db.
# El tráfico que llega de otra red (cliente Windows) entra a las VM como 192.168.56.1.
# La instala requisitos.sh como servicio lab5-red. Uso manual: red.sh up|down
set -euo pipefail
USUARIO="${USUARIO:?falta USUARIO (dueño de las interfaces tap)}"
BR=br-lab5; RED=192.168.56.0/24; IP_HOST=192.168.56.1/24
# Dominio en /etc/hosts del anfitrión (el archivo se regenera al iniciar)
HOSTS_LINEA="192.168.56.10    redes-lab5-wp.duckdns.org"

up () {
  ip link show "$BR" >/dev/null 2>&1 || ip link add "$BR" type bridge
  ip addr replace "$IP_HOST" dev "$BR"
  sysctl -qw "net.ipv6.conf.$BR.disable_ipv6=1"
  ip link set "$BR" up
  for T in tap-web tap-db; do
    ip link show "$T" >/dev/null 2>&1 || ip tuntap add dev "$T" mode tap user "$USUARIO"
    ip link set "$T" master "$BR" up
  done
  sysctl -qw net.ipv4.ip_forward=1
  iptables -t nat -C POSTROUTING -o "$BR" ! -s "$RED" -j MASQUERADE 2>/dev/null ||
    iptables -t nat -A POSTROUTING -o "$BR" ! -s "$RED" -j MASQUERADE
  iptables -C FORWARD -o "$BR" -j ACCEPT 2>/dev/null || iptables -A FORWARD -o "$BR" -j ACCEPT
  iptables -C FORWARD -i "$BR" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null ||
    iptables -A FORWARD -i "$BR" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  grep -qxF "$HOSTS_LINEA" /etc/hosts || echo "$HOSTS_LINEA" >> /etc/hosts
  ip -br addr show "$BR"
}

down () {
  for T in tap-web tap-db; do ip link del "$T" 2>/dev/null || true; done
  ip link del "$BR" 2>/dev/null || true
  iptables -t nat -D POSTROUTING -o "$BR" ! -s "$RED" -j MASQUERADE 2>/dev/null || true
  iptables -D FORWARD -o "$BR" -j ACCEPT 2>/dev/null || true
  iptables -D FORWARD -i "$BR" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
  sed -i "/redes-lab5-wp.duckdns.org/d" /etc/hosts
}

"${1:-up}"
