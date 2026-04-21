#!/usr/bin/env bash
# Inyecta Skills automáticas (Tools en Python) a OpenWebUI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
NEXUS_ROOT="$(nexus_root_from_arg "${1:-}")"
load_env_file "$NEXUS_ROOT/.env"

BASE_URL="${OPENWEBUI_URL:-http://127.0.0.1:${OPENCLAW_PORT:-3000}}"
ADMIN_EMAIL="${OPENCLAW_ADMIN_EMAIL:-}"
ADMIN_PASS="${OPENCLAW_ADMIN_PASSWORD:-}"

[[ -n "$ADMIN_EMAIL" ]] || die "Definí OPENCLAW_ADMIN_EMAIL en .env"

# 1. Login para sacar el token
AUTH_RESP=$(curl -sf -X POST "${BASE_URL}/api/v1/auths/signin" \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"${ADMIN_EMAIL}\", \"password\": \"${ADMIN_PASS}\"}") || die "Fallo login en inject-skills"
TOKEN=$(echo "$AUTH_RESP" | jq -r '.token')

echo "[skills] Inyectando skill: crear_nota_obsidian"

SKILL_1_PAYLOAD=$(jq -n \
  --arg id "crear_nota_obsidian" \
  --arg name "Crear Nota Obsidian" \
  --arg content "$(cat <<'EOF'
import requests
import datetime
from pydantic import BaseModel, Field

class Tools:
    class Valves(BaseModel):
        couchdb_url: str = Field(default="http://nexus-couchdb:5984")
        couchdb_user: str = Field(default="admin")
        couchdb_pass: str = Field(default="admin")

    def __init__(self):
        self.valves = self.Valves()

    def crear_nota_obsidian(self, titulo: str, contenido: str) -> str:
        """
        Crea una nota nueva dentro de la bandeja de entrada del Vault de Obsidian.
        :param titulo: El titulo del archivo sin la extension .md.
        :param contenido: El contenido markdown de la nota. 
        """
        timestamp = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
        file_name = f"{titulo}_{timestamp}.md"
        full_content = f"---\ncreated: {timestamp}\ntags: ['ai-generated']\n---\n\n{contenido}"
        doc_id = f"file_index_{file_name}"
        
        payload = {
            "_id": doc_id,
            "type": "file",
            "name": file_name,
            "content": full_content
        }
        try:
            url = f"{self.valves.couchdb_url}/obsidian-livesync/{doc_id}"
            res = requests.put(url, json=payload, auth=(self.valves.couchdb_user, self.valves.couchdb_pass))
            if res.status_code in [201, 200]:
                return f"Nota '{file_name}' creada en el vault."
            return f"Fallo en insercion de BD: {res.text}"
        except Exception as e:
            return f"Error: {e}"
EOF
)" \
  --arg meta_desc "Permite crear notas directamente en Obsidian" \
  '{
    id: $id,
    name: $name,
    content: $content,
    meta: {
      description: $meta_desc
    }
  }')

curl -s -X POST "${BASE_URL}/api/v1/tools/create" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$SKILL_1_PAYLOAD" > /dev/null

echo "[skills] Skills insertadas exitosamente. Acordate de asignar el couchdb_pass en las válvulas de WebUI."
