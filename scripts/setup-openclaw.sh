#!/usr/bin/env bash
# Instala y ejecuta OpenClaw (OpenWebUI) utilizando Docker.
# Se conecta a la red de 'nexus_net' creada por docker-compose para que
# alcance a Ollama y a las bases de datos.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
NEXUS_ROOT="$(nexus_root_from_arg "${1:-}")"
load_env_file "$NEXUS_ROOT/.env"

PORT=${OPENCLAW_PORT:-3000}
CONTAINER_NAME="nexus-openclaw"
DATA_DIR="${NEXUS_ROOT}/openwebui_data"

echo "[setup] Creando directorio persistente de OpenWebUI: $DATA_DIR"
mkdir -p "$DATA_DIR"

echo "[setup] Verificando si el contenedor $CONTAINER_NAME ya existe..."
if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
    echo "[setup] Removiendo contenedor anterior..."
    docker rm -f "$CONTAINER_NAME"
fi

echo "[setup] Lanzando OpenWebUI (OpenClaw) en el puerto $PORT..."
docker run -d -p "$PORT:8080" \
  -e OLLAMA_BASE_URL=http://nexus-ollama:11434 \
  -v "$DATA_DIR:/app/backend/data" \
  --name "$CONTAINER_NAME" \
  --network nexus_net \
  --restart unless-stopped \
  ghcr.io/open-webui/open-webui:main

echo "[setup] Esperando que la interfaz inicie en http://127.0.0.1:$PORT ..."
sleep 5

echo "✅ OpenClaw instalado exitosamente!"
echo ""
echo "👉 1. Entrá a http://127.0.0.1:$PORT (o vía tu dominio Caddy)"
echo "👉 2. Creá tu cuenta de administrador."
echo "👉 3. Ejecutá sudo ./scripts/configure-openclaw.sh /opt/nexus-brain para inyectar la configuración del RAG."
