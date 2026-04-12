#!/usr/bin/env bash
# Crea una Knowledge Base en OpenWebUI/OpenClaw vía API e imprime el id.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

NEXUS_ROOT="$(nexus_root_from_arg "${1:-}")"
load_env_file "$NEXUS_ROOT/.env"

NAME="${2:-Obsidian Vault}"
require_cmd curl
require_cmd jq

BASE_URL="${OPENWEBUI_URL:-http://127.0.0.1:${OPENCLAW_PORT:-3000}}"
API_KEY="${OPENWEBUI_API_KEY:-}"

[[ -n "$API_KEY" ]] || die "Definí OPENWEBUI_API_KEY en ${NEXUS_ROOT}/.env (Settings → Account → API Key en la UI)."

echo "[kb] POST ${BASE_URL}/api/v1/knowledge ..."
resp=$(curl -sf -X POST "${BASE_URL}/api/v1/knowledge" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"${NAME}\", \"description\": \"Vault Nexus Brain\"}")

id=$(echo "$resp" | jq -r '.id // .knowledge_id // .data.id // empty')
[[ -n "$id" && "$id" != null ]] || die "Respuesta inesperada: $resp"

echo "[kb] KNOWLEDGE_ID=${id}"
echo "Agregá a ${NEXUS_ROOT}/.env:"
echo "KNOWLEDGE_ID=${id}"
