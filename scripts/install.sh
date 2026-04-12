#!/usr/bin/env bash
# Instala el stack Nexus Brain en el VPS (Docker + Caddy + CouchDB + Qdrant + Ollama opcional).
# Uso (desde el repo clonado):
#   sudo ./scripts/install.sh
#   sudo NEXUS_ROOT=/opt/nexus-brain ./scripts/install.sh --install-deps
#   sudo ./scripts/install.sh --skip-ollama    # Ollama nativo en el host
#   sudo ./scripts/install.sh --force-docker-ollama  # ignorar detección (requiere 11434 libre)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

NEXUS_ROOT="${NEXUS_ROOT:-/opt/nexus-brain}"
INSTALL_DEPS=false
SKIP_OLLAMA=false
FORCE_DOCKER_OLLAMA=false

usage() {
  sed -n '1,20p' "$0" | tail -n +2
}

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --nexus-root)
      NEXUS_ROOT="${2:?}"
      shift 2
      ;;
    --install-deps)
      INSTALL_DEPS=true
      shift
      ;;
    --skip-ollama)
      SKIP_OLLAMA=true
      shift
      ;;
    --force-docker-ollama)
      FORCE_DOCKER_OLLAMA=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "Opción desconocida: $1"
      ;;
  esac
done

require_root

if [[ "$INSTALL_DEPS" == true ]]; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates curl jq gettext-base inotify-tools python3 python3-venv python3-pip
  if ! command -v docker >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-plugin
  fi
fi

require_cmd docker
docker compose version >/dev/null 2>&1 || die "Necesitás Docker Compose v2 (plugin docker compose)."
require_cmd curl
command -v jq >/dev/null 2>&1 || die "Instalá jq: apt install -y jq (o ejecutá con --install-deps)."
command -v envsubst >/dev/null 2>&1 || die "Instalá envsubst: apt install -y gettext-base (o --install-deps)."
command -v python3 >/dev/null 2>&1 || die "Falta python3."

install -d -m 0755 "$NEXUS_ROOT"/{vault,couchdb,qdrant,ollama,caddy,scripts}

cp -f "$REPO_ROOT/deploy/docker-compose.yml" "$NEXUS_ROOT/"
cp -f "$REPO_ROOT/deploy/docker-compose.no-ollama.yml" "$NEXUS_ROOT/"
cp -f "$REPO_ROOT/deploy/caddy/Caddyfile.template" "$NEXUS_ROOT/caddy/Caddyfile.template"

if [[ ! -f "$NEXUS_ROOT/.env" ]]; then
  install -m 0600 "$REPO_ROOT/.env.example" "$NEXUS_ROOT/.env"
  echo ""
  echo "Se creó $NEXUS_ROOT/.env"
  echo "Editá al menos: DOMAIN_CLAW, DOMAIN_SYNC, COUCHDB_PASSWORD, OPENCLAW_PORT"
  echo "Luego volvé a ejecutar: sudo $0"
  echo ""
  exit 2
fi

chmod 0600 "$NEXUS_ROOT/.env"
set -a
# shellcheck source=/dev/null
source "$NEXUS_ROOT/.env"
set +a

for v in DOMAIN_CLAW DOMAIN_SYNC COUCHDB_PASSWORD OPENCLAW_PORT; do
  if [[ -z "${!v:-}" ]]; then
    die "Completá la variable $v en $NEXUS_ROOT/.env"
  fi
done

export DOMAIN_CLAW DOMAIN_SYNC OPENCLAW_PORT
envsubst '${DOMAIN_CLAW} ${DOMAIN_SYNC} ${OPENCLAW_PORT}' \
  <"$NEXUS_ROOT/caddy/Caddyfile.template" >"$NEXUS_ROOT/caddy/Caddyfile"

cp -f "$REPO_ROOT/watcher/vault_watcher.py" "$NEXUS_ROOT/scripts/"
cp -f "$REPO_ROOT/watcher/requirements.txt" "$NEXUS_ROOT/scripts/"

if [[ ! -d "$NEXUS_ROOT/watcher-venv" ]]; then
  python3 -m venv "$NEXUS_ROOT/watcher-venv"
fi
"$NEXUS_ROOT/watcher-venv/bin/pip" install -q -r "$NEXUS_ROOT/scripts/requirements.txt"

cp -f "$REPO_ROOT/systemd/nexus-vault-watcher.service" "$NEXUS_ROOT/scripts/nexus-vault-watcher.service.example"

# Puerto 11434 ocupado → típicamente Ollama nativo; Docker no puede mapear el mismo puerto.
port_11434_in_use() {
  if command -v ss >/dev/null 2>&1; then
    ss -tln 2>/dev/null | grep -q ':11434'
    return $?
  fi
  curl -sf --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1
}

if [[ "$SKIP_OLLAMA" != true && "$FORCE_DOCKER_OLLAMA" != true ]]; then
  if port_11434_in_use; then
    echo ""
    echo "[install] El puerto 11434 ya está en uso (casi seguro Ollama nativo en el host)."
    echo "[install] Se omite el contenedor nexus-ollama; OpenClaw debe usar: http://127.0.0.1:11434"
    echo "[install] (Para forzar Ollama en Docker: detené el servicio nativo y usá --force-docker-ollama)"
    echo ""
    SKIP_OLLAMA=true
  fi
fi

if [[ "$FORCE_DOCKER_OLLAMA" == true ]]; then
  if port_11434_in_use; then
    die "11434 está ocupado. Detené Ollama nativo (p. ej. systemctl stop ollama) o ejecutá sin --force-docker-ollama para usar solo el nativo."
  fi
fi

cd "$NEXUS_ROOT"
if [[ "$SKIP_OLLAMA" == true ]]; then
  docker compose -f docker-compose.yml -f docker-compose.no-ollama.yml up -d
else
  docker compose up -d
fi

echo "[install] Esperando a CouchDB..."
for _ in $(seq 1 45); do
  if curl -sf "http://127.0.0.1:5984/" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

"$SCRIPT_DIR/setup-couchdb.sh" "$NEXUS_ROOT"

"$SCRIPT_DIR/pull-ollama-models.sh" "$NEXUS_ROOT" || true

"$SCRIPT_DIR/init-vault-dirs.sh" "$NEXUS_ROOT/vault" "${SUDO_USER:-}"

if [[ -n "${SUDO_USER:-}" ]]; then
  chown -R "$SUDO_USER:$SUDO_USER" "$NEXUS_ROOT/vault" 2>/dev/null || true
fi

echo ""
echo "=== Instalación base lista ==="
echo "OpenClaw (UI):     https://${DOMAIN_CLAW}"
echo "CouchDB LiveSync:  https://${DOMAIN_SYNC}"
echo "Ollama API (host): http://127.0.0.1:11434  (omití Ollama Docker con --skip-ollama + ollama nativo)"
echo "Qdrant:            http://127.0.0.1:6333"
echo ""
echo "En OpenClaw: Settings → Connections → Ollama URL → http://127.0.0.1:11434"
echo "Si usás CPU sin GPU: subí Request Timeout (p. ej. 300s) en la UI."
echo ""
echo "RAG: generá API Key, ejecutá sudo $SCRIPT_DIR/create-knowledge-base.sh $NEXUS_ROOT"
echo "     copiá KNOWLEDGE_ID al .env y: sudo $SCRIPT_DIR/install-watcher-service.sh $NEXUS_ROOT"
echo ""
echo "Chequeo: $SCRIPT_DIR/health-check.sh $NEXUS_ROOT"
