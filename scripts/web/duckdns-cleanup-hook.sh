#!/usr/bin/env bash
# Hook de certbot: borra el registro TXT del reto en DuckDNS.
set -euo pipefail
source /etc/letsencrypt/duckdns/credenciales
curl -fsS "https://www.duckdns.org/update?domains=$SUB&token=$TOKEN&txt=borrado&clear=true" >/dev/null
