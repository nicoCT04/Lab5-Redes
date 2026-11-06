#!/usr/bin/env bash
# Hook de certbot: publica el valor del reto DNS-01 como registro TXT en DuckDNS.
# certbot define CERTBOT_VALIDATION. Se instala en /etc/letsencrypt/duckdns/.
set -euo pipefail
source /etc/letsencrypt/duckdns/credenciales
R=$(curl -fsS "https://www.duckdns.org/update?domains=$SUB&token=$TOKEN&txt=$CERTBOT_VALIDATION&verbose=true")
echo "DuckDNS: $R"
[[ "$R" == OK* ]] || exit 1
sleep 60   # tiempo para que el TXT se propague antes de que Let's Encrypt lo consulte
