#!/usr/bin/env bash
# Crea la base LiveSync y aplica CORS en CouchDB (API local 127.0.0.1:5984).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

NEXUS_ROOT="$(nexus_root_from_arg "${1:-}")"
load_env_file "$NEXUS_ROOT/.env"

require_cmd curl
require_cmd jq

COUCHDB_USER="${COUCHDB_USER:-admin}"
COUCHDB_DATABASE="${COUCHDB_DATABASE:-obsidian-livesync}"
BASE="http://127.0.0.1:5984"

echo "[couchdb] Comprobando API en ${BASE}..."
curl -sf -u "${COUCHDB_USER}:${COUCHDB_PASSWORD}" "${BASE}/" >/dev/null || die "CouchDB no responde en ${BASE}. ¿Está levantado el contenedor?"

MEM=$(curl -sf -u "${COUCHDB_USER}:${COUCHDB_PASSWORD}" "${BASE}/_membership")
if command -v jq >/dev/null 2>&1; then
  NODE=$(echo "$MEM" | jq -r '.cluster_nodes[0] // empty')
else
  NODE=$(echo "$MEM" | sed -n 's/.*"cluster_nodes":\["\([^"]*\)"\].*/\1/p')
fi
[[ -n "$NODE" ]] || NODE="nonode@nohost"
echo "[couchdb] Nodo de configuración: ${NODE}"
NODE_ENC="${NODE//@/%40}"

put_cfg() {
  local section="$1"
  local key="$2"
  local val="$3"
  local url="${BASE}/_node/${NODE_ENC}/_config/${section}/${key}"
  code=$(curl -s -o /tmp/couch-cfg.out -w "%{http_code}" -u "${COUCHDB_USER}:${COUCHDB_PASSWORD}" -X PUT "$url" -H "Content-Type: application/json" -d "$val")
  if [[ "$code" != "200" && "$code" != "201" ]]; then
    echo "[couchdb] Advertencia ${section}/${key} → HTTP ${code} $(cat /tmp/couch-cfg.out 2>/dev/null || true)"
  else
    echo "[couchdb] OK ${section}/${key}"
  fi
}

echo "[couchdb] Creando base ${COUCHDB_DATABASE} (si no existe)..."
code=$(curl -s -o /tmp/couch-db.out -w "%{http_code}" -u "${COUCHDB_USER}:${COUCHDB_PASSWORD}" -X PUT "${BASE}/${COUCHDB_DATABASE}")
if [[ "$code" == "201" || "$code" == "200" ]]; then
  echo "[couchdb] Base lista (HTTP ${code})"
else
  echo "[couchdb] PUT base → HTTP ${code} $(cat /tmp/couch-db.out 2>/dev/null || true)"
fi

put_cfg "httpd" "enable_cors" '"true"'
ORIGINS='app://obsidian.md,capacitor://localhost,http://localhost,https://localhost'
if [[ -n "${DOMAIN_SYNC:-}" ]]; then
  ORIGINS="${ORIGINS},https://${DOMAIN_SYNC}"
fi
ORIGINS_JSON=$(jq -cn --arg o "$ORIGINS" '$o')
put_cfg "cors" "origins" "$ORIGINS_JSON"
put_cfg "cors" "credentials" '"true"'
put_cfg "cors" "methods" '"GET, PUT, POST, HEAD, DELETE"'
put_cfg "cors" "headers" '"accept, authorization, content-type, origin, referer"'

echo "[couchdb] Listo. En Obsidian LiveSync usá https://${DOMAIN_SYNC:-tu-dominio} y la base ${COUCHDB_DATABASE}."
