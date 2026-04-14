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

# ── Infraestructura Docker ────────────────────────────────────────────────────
curl -sf -u "${COUCHDB_USER:-admin}:${COUCHDB_PASSWORD}" "http://127.0.0.1:5984/" >/dev/null \
  && ok "CouchDB :5984" || fail "CouchDB :5984"

curl -sf "http://127.0.0.1:6333/readyz" >/dev/null \
  && ok "Qdrant :6333" || fail "Qdrant :6333"

# ── Ollama + modelo primario ──────────────────────────────────────────────────
OLLAMA_OK=false
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'nexus-ollama'; then
  curl -sf "http://127.0.0.1:11434/api/tags" >/dev/null && ok "Ollama Docker :11434" || fail "Ollama Docker :11434"
  OLLAMA_OK=true
elif curl -sf "http://127.0.0.1:11434/api/tags" >/dev/null 2>&1; then
  ok "Ollama nativo :11434"
  OLLAMA_OK=true
else
  fail "Ollama :11434 (ni Docker ni nativo responde)"
fi

# Verificar que el modelo primario esté disponible
PRIMARY="${PRIMARY_MODEL:-gemma4}"
if [[ "$OLLAMA_OK" == true ]]; then
  if curl -sf "http://127.0.0.1:11434/api/tags" 2>/dev/null | grep -q "\"$PRIMARY\"" ; then
    ok "Modelo primario '$PRIMARY' disponible en Ollama"
  else
    warn() { echo "WARN $*"; }
    warn "Modelo '$PRIMARY' no encontrado en Ollama (puede estar descargando)"
  fi
fi

# ── OpenClaw/OpenWebUI ────────────────────────────────────────────────────────
PORT="${OPENCLAW_PORT:-3000}"
curl -sf "http://127.0.0.1:${PORT}/" >/dev/null \
  && ok "OpenClaw/OpenWebUI host :${PORT}" || fail "OpenClaw/OpenWebUI host :${PORT}"

# ── Caddy (TLS) ───────────────────────────────────────────────────────────────
if [[ -n "${DOMAIN_CLAW:-}" ]]; then
  curl -sfI "https://${DOMAIN_CLAW}/" >/dev/null \
    && ok "Caddy → ${DOMAIN_CLAW}" || fail "Caddy → ${DOMAIN_CLAW} (¿DNS ya propagado?)"
fi

# ── Vault Git ─────────────────────────────────────────────────────────────────
VAULT_PATH="${VAULT_PATH:-$NEXUS_ROOT/vault}"
if [[ -d "$VAULT_PATH/.git" ]]; then
  MD_COUNT=$(find "$VAULT_PATH" -name "*.md" ! -path "*/.obsidian/*" 2>/dev/null | wc -l)
  ok "Vault Git en $VAULT_PATH ($MD_COUNT notas .md)"
elif [[ -d "$VAULT_PATH" ]]; then
  echo "INFO Vault sin Git en $VAULT_PATH (sync manual)"
else
  fail "Vault no encontrado en $VAULT_PATH"
fi

# ── Servicios systemd ─────────────────────────────────────────────────────────
for svc in nexus-vault-watcher nexus-vault-sync.timer; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    ok "systemd: $svc activo"
  elif systemctl list-unit-files --quiet "$svc" 2>/dev/null | grep -q "$svc"; then
    echo "INFO systemd: $svc instalado pero no activo"
  fi
done

# ── Gemini fallback (si está configurado) ─────────────────────────────────────
if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  GEMINI_MODEL="${GEMINI_MODEL:-gemini-2.5-flash-preview}"
  if curl -sf \
    "https://generativelanguage.googleapis.com/v1beta/openai/models" \
    -H "Authorization: Bearer ${GEMINI_API_KEY}" >/dev/null 2>&1; then
    ok "Gemini API key válida (modelo fallback: $GEMINI_MODEL)"
  else
    echo "WARN Gemini API no alcanzable (¿red o key incorrecta?)"
  fi
fi

exit "$RC"
