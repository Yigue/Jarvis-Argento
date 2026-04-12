#!/usr/bin/env bash
# Comprueba servicios locales del stack Nexus Brain.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

NEXUS_ROOT="$(nexus_root_from_arg "${1:-}")"
load_env_file "$NEXUS_ROOT/.env"

ok() { echo "OK  $*"; }
fail() { echo "FALLO $*" >&2; RC=1; }

RC=0

curl -sf -u "${COUCHDB_USER:-admin}:${COUCHDB_PASSWORD}" "http://127.0.0.1:5984/" >/dev/null && ok "CouchDB :5984" || fail "CouchDB :5984"

curl -sf "http://127.0.0.1:6333/readyz" >/dev/null && ok "Qdrant :6333" || fail "Qdrant :6333"

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'nexus-ollama'; then
  curl -sf "http://127.0.0.1:11434/api/tags" >/dev/null && ok "Ollama Docker :11434" || fail "Ollama Docker :11434"
elif curl -sf "http://127.0.0.1:11434/api/tags" >/dev/null; then
  ok "Ollama nativo :11434"
else
  fail "Ollama :11434 (ni Docker ni nativo responde)"
fi

PORT="${OPENCLAW_PORT:-3000}"
curl -sf "http://127.0.0.1:${PORT}/" >/dev/null && ok "OpenClaw/OpenWebUI host :${PORT}" || fail "OpenClaw/OpenWebUI host :${PORT}"

if [[ -n "${DOMAIN_CLAW:-}" ]]; then
  curl -sfI "https://${DOMAIN_CLAW}/" >/dev/null && ok "Caddy → ${DOMAIN_CLAW}" || fail "Caddy → ${DOMAIN_CLAW} (¿DNS ya propagado?)"
fi

exit "$RC"
