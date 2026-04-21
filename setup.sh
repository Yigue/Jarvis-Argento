#!/usr/bin/env bash
# =============================================================================
# Nexus Brain — Zero-Touch Provisioning
# Levanta el stack completo en un servidor Ubuntu/Debian desde cero.
#
# USO (2 comandos desde un servidor limpio):
#   git clone <repo> && cd Jarvis-Argento
#   cp .env.example .env && nano .env          # editar una sola vez
#   sudo ./setup.sh                             # hace TODO lo demás
#
# Variables de entorno opcionales:
#   NEXUS_ROOT=/opt/nexus-brain   (default)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEXUS_ROOT="${NEXUS_ROOT:-/opt/nexus-brain}"
export NEXUS_ROOT

# ── Colores ───────────────────────────────────────────────────────────────────
C_OK="\033[0;32m"
C_WARN="\033[1;33m"
C_ERR="\033[0;31m"
C_BOLD="\033[1m"
C_RESET="\033[0m"

step() { echo -e "\n${C_BOLD}▶ $*${C_RESET}"; }
ok()   { echo -e "${C_OK}✔ $*${C_RESET}"; }
warn() { echo -e "${C_WARN}⚠ $*${C_RESET}"; }
die()  { echo -e "${C_ERR}✘ $*${C_RESET}" >&2; exit 1; }

[[ "${EUID:-0}" -eq 0 ]] || die "Ejecutá con sudo: sudo $0"

echo -e "${C_BOLD}"
echo "╔══════════════════════════════════════════════╗"
echo "║      NEXUS BRAIN — ZERO-TOUCH SETUP         ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${C_RESET}"

# ── PASO 1: Verificar / crear .env ────────────────────────────────────────────
step "Verificando configuración"

ENV_REPO="$SCRIPT_DIR/.env"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"

if [[ ! -f "$ENV_REPO" ]]; then
  cp "$ENV_EXAMPLE" "$ENV_REPO"
  warn "Se creó .env desde .env.example en $(pwd)"
  echo ""
  echo "Editá el archivo con tus valores reales:"
  echo "  nano $ENV_REPO"
  echo ""
  echo "Variables mínimas requeridas:"
  echo "  DOMAIN_CLAW       → dominio para OpenClaw  (ej: brain.mi-vps.com)"
  echo "  DOMAIN_SYNC       → dominio para CouchDB   (ej: sync.mi-vps.com)"
  echo "  COUCHDB_PASSWORD  → contraseña segura"
  echo ""
  echo "Variables opcionales para automatización completa:"
  echo "  VAULT_GIT_URL        → repo Git de tu vault Obsidian"
  echo "  GEMINI_API_KEY       → Google AI API key para modelo fallback"
  echo "  OPENCLAW_ADMIN_EMAIL → email admin de OpenClaw"
  echo "  OPENCLAW_ADMIN_PASSWORD"
  echo ""
  echo "Luego volvé a ejecutar: sudo $0"
  exit 2
fi

# Cargar .env y validar variables críticas
# shellcheck source=/dev/null
set -a; source "$ENV_REPO"; set +a

MISSING=()
for v in DOMAIN_CLAW DOMAIN_SYNC COUCHDB_PASSWORD; do
  [[ -n "${!v:-}" ]] || MISSING+=("$v")
done
[[ ${#MISSING[@]} -eq 0 ]] || die "Faltan estas variables en .env: ${MISSING[*]}"

ok "Configuración validada"

# ── PASO 2: Pre-copiar .env a NEXUS_ROOT para que install.sh no salga con exit 2
step "Preparando directorio base: $NEXUS_ROOT"
install -d -m 0755 "$NEXUS_ROOT"
install -m 0600 "$ENV_REPO" "$NEXUS_ROOT/.env"
ok ".env copiado a $NEXUS_ROOT/.env"

# ── PASO 3: Stack base (Docker + CouchDB + Qdrant + Ollama + Caddy) ──────────
step "Instalando stack base (deps del sistema + Docker + servicios)"
bash "$SCRIPT_DIR/scripts/install.sh" --install-deps
ok "Stack base instalado y corriendo"

# ── PASO 3.5: Instalar OpenClaw via Docker ─────────────────────────────────────
step "Lanzando OpenClaw en Docker..."
bash "$SCRIPT_DIR/scripts/setup-openclaw.sh" "$NEXUS_ROOT"
ok "OpenClaw container inicializado"

# ── PASO 4: Preparar directorio del vault (LiveSync vía CouchDB) ──────────────
step "Preparando directorio del vault Obsidian"
VAULT_DIR="${VAULT_PATH:-$NEXUS_ROOT/vault}"
install -d -m 0755 "$VAULT_DIR"
if [[ -n "${SUDO_USER:-}" ]]; then
  chown -R "${SUDO_USER}:${SUDO_USER}" "$VAULT_DIR" 2>/dev/null || true
fi
ok "Directorio del vault listo: $VAULT_DIR"
echo "  El vault se pobla vía Self-hosted LiveSync desde tu Obsidian."
echo "  Configurá el plugin en Obsidian → sync.${DOMAIN_SYNC:-tudominio.com}"

# ── PASO 5: Descargar modelos Ollama (gemma4 + cualquier otro en OLLAMA_MODELS)
step "Descargando modelos Ollama"
bash "$SCRIPT_DIR/scripts/pull-ollama-models.sh" "$NEXUS_ROOT" \
  || warn "Algunos modelos no descargaron — revisá logs de Ollama"

# ── PASO 6: Configurar OpenClaw (Ollama URL + Gemini fallback + system prompt)
if [[ -n "${OPENCLAW_ADMIN_PASSWORD:-}" ]]; then
  step "Configurando OpenClaw (modelos, Gemini fallback, system prompt PKM)"
  bash "$SCRIPT_DIR/scripts/configure-openclaw.sh" "$NEXUS_ROOT" \
    || warn "Configuración automática de OpenClaw falló — revisar configure-openclaw.sh"
else
  warn "OPENCLAW_ADMIN_PASSWORD no definida → configuración manual de OpenClaw necesaria"
  echo "  1. En OpenClaw UI: Settings → Connections → Ollama URL → http://127.0.0.1:11434"
  echo "  2. Modelo por defecto: ${PRIMARY_MODEL:-gemma4}"
  if [[ -n "${GEMINI_API_KEY:-}" ]]; then
    echo "  3. Settings → Connections → OpenAI → URL: https://generativelanguage.googleapis.com/v1beta/openai/"
    echo "     Key: \$GEMINI_API_KEY"
  fi
fi

# ── PASO 6.5: Inyectar Tools/Skills personalizados a OpenClaw ─────────────────
if [[ -n "${OPENCLAW_ADMIN_PASSWORD:-}" ]]; then
  step "Inyectando skills Python en WebUI (Crear Notas, etc...)"
  bash "$SCRIPT_DIR/scripts/inject-skills.sh" "$NEXUS_ROOT" || warn "Fallo inyeccion de skills. Podes cargarlas a mano."
fi

# ── PASO 7: (LiveSync) CouchDB sincroniza el vault en tiempo real — no se necesita timer Git

# ── PASO 8: Watcher vault → Knowledge Base (requiere API Key + Knowledge ID)
if [[ -n "${KNOWLEDGE_ID:-}" && -n "${OPENWEBUI_API_KEY:-}" ]]; then
  step "Instalando watcher (vault Markdown → Knowledge Base)"
  bash "$SCRIPT_DIR/scripts/install-watcher-service.sh" "$NEXUS_ROOT"
  ok "Watcher instalado y activo"
else
  warn "Watcher no instalado aún (KNOWLEDGE_ID o OPENWEBUI_API_KEY vacíos)"
  echo "  Cuando OpenClaw esté corriendo:"
  echo "  1. Settings → Account → API Keys → generá una key → OPENWEBUI_API_KEY"
  echo "  2. sudo ./scripts/create-knowledge-base.sh $NEXUS_ROOT → copiá KNOWLEDGE_ID"
  echo "  3. Actualizá .env con ambos valores"
  echo "  4. sudo ./scripts/install-watcher-service.sh $NEXUS_ROOT"
fi

# ── PASO 9: Health check ──────────────────────────────────────────────────────
step "Verificando servicios"
"$SCRIPT_DIR/scripts/health-check.sh" "$NEXUS_ROOT" || true

# ── Resumen ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${C_BOLD}╔══════════════════════════════════════════════════════╗"
echo -e "║          NEXUS BRAIN — STACK OPERATIVO              ║"
echo -e "╚══════════════════════════════════════════════════════╝${C_RESET}"
echo -e "  OpenClaw (UI):      ${C_OK}https://${DOMAIN_CLAW}${C_RESET}"
echo -e "  CouchDB LiveSync:   ${C_OK}https://${DOMAIN_SYNC}${C_RESET}"
echo -e "  Ollama API:         http://127.0.0.1:11434"
echo -e "  Qdrant:             http://127.0.0.1:6333"
echo ""
echo -e "  Modelo primario:    ${C_BOLD}${PRIMARY_MODEL:-gemma4:7b}${C_RESET} (Ollama local)"
if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  echo -e "  Modelo fallback:    ${C_BOLD}${GEMINI_MODEL:-gemini-2.5-flash-preview}${C_RESET} (Google AI)"
fi
echo -e "  Vault:              ${VAULT_PATH:-$NEXUS_ROOT/vault}  ← se puebla via LiveSync"
echo ""
echo -e "  Obsidian LiveSync:  https://${DOMAIN_SYNC:-tudominio.com}"
echo -e "  Logs del watcher:   journalctl -u nexus-vault-watcher -f"
echo -e "  Health check:       $SCRIPT_DIR/scripts/health-check.sh $NEXUS_ROOT"
echo ""
