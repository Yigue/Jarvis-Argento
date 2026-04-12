#!/usr/bin/env bash
# Descarga modelos Ollama (Docker o binario nativo).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

NEXUS_ROOT="$(nexus_root_from_arg "${1:-}")"
load_env_file "$NEXUS_ROOT/.env"

MODELS="${OLLAMA_MODELS:-llama3.2:3b}"
IFS=',' read -ra ARR <<< "${MODELS// /}"

pull_docker() {
  local name="$1"
  echo "[ollama] docker pull ${name}..."
  docker exec nexus-ollama ollama pull "$name"
}

pull_native() {
  local name="$1"
  echo "[ollama] nativo pull ${name}..."
  ollama pull "$name"
}

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'nexus-ollama'; then
  for m in "${ARR[@]}"; do
    [[ -n "$m" ]] || continue
    pull_docker "$m"
  done
elif command -v ollama >/dev/null 2>&1; then
  for m in "${ARR[@]}"; do
    [[ -n "$m" ]] || continue
    pull_native "$m"
  done
else
  echo "[ollama] No hay contenedor nexus-ollama ni comando ollama; omitiendo descarga de modelos."
  exit 0
fi

echo "[ollama] Modelos solicitados procesados. En OpenClaw: URL http://127.0.0.1:11434 (o el puerto que uses)."
