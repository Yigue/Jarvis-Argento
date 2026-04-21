#!/usr/bin/env bash
# Configura nginx como reverse proxy para OpenClaw y CouchDB LiveSync.
# Se usa cuando el servidor ya tiene nginx instalado (ej: VPS con panel de hosting).
# nginx maneja TLS con Let's Encrypt ya existente.
#
# Arquitectura:
#   puerto 443 (HTTPS) → OpenClaw gateway (:18789 o $OPENCLAW_PORT)
#   puerto 5985 (HTTPS) → CouchDB (:5984) para Obsidian LiveSync
#
# Uso: sudo ./scripts/configure-nginx.sh /opt/nexus-brain
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
require_cmd nginx

NEXUS_ROOT="$(nexus_root_from_arg "${1:-}")"
load_env_file "$NEXUS_ROOT/.env"

DOMAIN="${DOMAIN_CLAW:-}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

[[ -n "$DOMAIN" ]] || die "Definí DOMAIN_CLAW en $NEXUS_ROOT/.env"

# Si no hay cert de Let's Encrypt, intentar con snakeoil
if [[ ! -f "$CERT" ]]; then
  echo "[nginx] AVISO: No hay cert Let's Encrypt para $DOMAIN"
  echo "[nginx] Buscando certificados alternativos..."
  CERT=$(find /etc/letsencrypt/live -name "fullchain.pem" 2>/dev/null | head -1)
  KEY=$(find /etc/letsencrypt/live -name "privkey.pem" 2>/dev/null | head -1)
  if [[ -z "$CERT" ]]; then
    die "No hay certificados TLS disponibles. Ejecuta: certbot certonly --nginx -d $DOMAIN"
  fi
  echo "[nginx] Usando cert: $CERT"
fi

NGINX_CONF="/etc/nginx/sites-enabled/nexus-brain.conf"

cat > "$NGINX_CONF" << NGINXEOF
# Nexus Brain — OpenClaw + CouchDB LiveSync via nginx
# Generado por configure-nginx.sh

upstream openclaw_upstream {
    server 127.0.0.1:${OPENCLAW_PORT};
}

server {
    listen 80;
    server_name ${DOMAIN};
    location /.well-known/acme-challenge { root /var/www/html; }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${DOMAIN};

    ssl_certificate ${CERT};
    ssl_certificate_key ${KEY};

    access_log /var/log/nginx/openclaw.access.log;
    error_log  /var/log/nginx/openclaw.error.log;

    client_max_body_size 100M;

    location / {
        proxy_pass http://openclaw_upstream;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}

# CouchDB para Obsidian Self-hosted LiveSync
# URI en Obsidian: https://${DOMAIN}:5985
server {
    listen 5985 ssl;
    listen [::]:5985 ssl;
    server_name ${DOMAIN};

    ssl_certificate ${CERT};
    ssl_certificate_key ${KEY};

    access_log /var/log/nginx/couchdb.access.log;
    error_log  /var/log/nginx/couchdb.error.log;

    client_max_body_size 50M;

    location / {
        proxy_pass http://127.0.0.1:5984;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        # CORS para LiveSync
        add_header Access-Control-Allow-Origin  "*" always;
        add_header Access-Control-Allow-Methods "GET, PUT, POST, HEAD, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type, Authorization, X-Requested-With" always;
        add_header Access-Control-Max-Age 3600 always;

        if (\$request_method = OPTIONS) { return 204; }
    }
}
NGINXEOF

echo "[nginx] Configuracion escrita en $NGINX_CONF"
nginx -t && systemctl reload nginx && echo "[nginx] Recargado OK"
echo "[nginx] OpenClaw:  https://${DOMAIN}"
echo "[nginx] LiveSync:  https://${DOMAIN}:5985"
