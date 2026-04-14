#!/usr/bin/env bash
# Configura OpenClaw/OpenWebUI vía API REST:
#   - Conexión Ollama (modelo gemma4 como primario)
#   - Conexión Gemini Flash como fallback (OpenAI-compatible)
#   - System prompt especializado en PKM / estudio / agenda
#
# Uso: sudo ./scripts/configure-openclaw.sh /opt/nexus-brain
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

NEXUS_ROOT="$(nexus_root_from_arg "${1:-}")"
load_env_file "$NEXUS_ROOT/.env"

require_cmd curl
require_cmd jq

BASE_URL="${OPENWEBUI_URL:-http://127.0.0.1:${OPENCLAW_PORT:-3000}}"
ADMIN_EMAIL="${OPENCLAW_ADMIN_EMAIL:-}"
ADMIN_PASS="${OPENCLAW_ADMIN_PASSWORD:-}"
PRIMARY_MODEL="${PRIMARY_MODEL:-gemma4}"
GEMINI_API_KEY="${GEMINI_API_KEY:-}"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-2.5-flash-preview}"
OLLAMA_URL="${OLLAMA_BASE_URL:-http://127.0.0.1:11434}"

[[ -n "$ADMIN_EMAIL" ]] || die "Definí OPENCLAW_ADMIN_EMAIL en ${NEXUS_ROOT}/.env"
[[ -n "$ADMIN_PASS" ]]  || die "Definí OPENCLAW_ADMIN_PASSWORD en ${NEXUS_ROOT}/.env"

# ── Helpers ───────────────────────────────────────────────────────────────────
api() {
  local method="$1"; local endpoint="$2"; shift 2
  curl -sf -X "$method" "${BASE_URL}${endpoint}" \
    -H "Authorization: Bearer ${TOKEN:-}" \
    -H "Content-Type: application/json" \
    "$@"
}

wait_for_openclaw() {
  echo "[config] Esperando que OpenClaw responda en ${BASE_URL}..."
  local max=60
  for ((i=1; i<=max; i++)); do
    if curl -sf "${BASE_URL}/health" >/dev/null 2>&1 || \
       curl -sf "${BASE_URL}/" >/dev/null 2>&1; then
      echo "[config] OpenClaw OK"
      return 0
    fi
    sleep 3
  done
  die "OpenClaw no respondió en ${BASE_URL} tras $((max*3))s — ¿está instalado y corriendo?"
}

# ── 1. Login para obtener token de admin ──────────────────────────────────────
wait_for_openclaw

echo "[config] Autenticando como $ADMIN_EMAIL ..."
AUTH_RESP=$(curl -sf -X POST "${BASE_URL}/api/v1/auths/signin" \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"${ADMIN_EMAIL}\", \"password\": \"${ADMIN_PASS}\"}" 2>&1) \
  || die "Login fallido. Verificá OPENCLAW_ADMIN_EMAIL y OPENCLAW_ADMIN_PASSWORD"

TOKEN=$(echo "$AUTH_RESP" | jq -r '.token // empty')
[[ -n "$TOKEN" ]] || die "No se obtuvo token de autenticación. Respuesta: $AUTH_RESP"
echo "[config] Token obtenido"

# ── 2. Configurar URL de Ollama ───────────────────────────────────────────────
echo "[config] Configurando conexión Ollama: $OLLAMA_URL ..."
OLLAMA_RESP=$(api POST "/ollama/config/update" \
  -d "{\"OLLAMA_BASE_URLS\": [\"${OLLAMA_URL}\"]}" 2>&1) \
  || { echo "[config] WARN: endpoint /ollama/config/update no disponible — configura manualmente en Settings → Connections"; OLLAMA_RESP=""; }

if [[ -n "$OLLAMA_RESP" ]]; then
  echo "[config] Ollama configurado: $OLLAMA_URL"
fi

# ── 3. Registrar Gemini como endpoint OpenAI-compatible (si hay API Key) ─────
if [[ -n "$GEMINI_API_KEY" ]]; then
  echo "[config] Registrando Gemini Flash como endpoint OpenAI-compatible..."
  GEMINI_BASE="https://generativelanguage.googleapis.com/v1beta/openai/"

  OPENAI_RESP=$(api POST "/openai/config/update" \
    -d "{
      \"OPENAI_API_BASE_URLS\": [\"${GEMINI_BASE}\"],
      \"OPENAI_API_KEYS\": [\"${GEMINI_API_KEY}\"]
    }" 2>&1) \
    || { echo "[config] WARN: endpoint /openai/config/update no disponible — configura manualmente"; OPENAI_RESP=""; }

  if [[ -n "$OPENAI_RESP" ]]; then
    echo "[config] Gemini Flash registrado como provider OpenAI-compatible"
    echo "[config] Modelo disponible en OpenClaw: ${GEMINI_MODEL}"
    echo "[config] URL: ${GEMINI_BASE}"
  fi
else
  echo "[config] GEMINI_API_KEY no definida — fallback a Gemini omitido"
fi

# ── 4. Crear / actualizar preset "Nexus PKM" con el system prompt ─────────────
echo "[config] Aplicando system prompt especializado (PKM + Estudio + Agenda)..."

# System prompt del agente Nexus — especializado en conocimiento personal
SYSTEM_PROMPT=$(cat <<'PROMPT_EOF'
Sos Nexus, un asistente de conocimiento personal especializado en tres dominios clave:

## 🎓 Asistencia de Estudio
- Explicás conceptos desde primeros principios, no solo definiciones
- Generás resúmenes densos en información, no paja
- Creás ejercicios de práctica y preguntas de autoevaluación
- Conectás conceptos nuevos con lo que ya sabés (basado en tus notas)

## 📅 Orquestación de Agenda Diaria
- Ayudás a planificar el día con bloques de tiempo realistas
- Priorizás tareas usando criterios de impacto/urgencia
- Recordás compromisos y deadlines basados en tus notas de Daily Notes
- Sugerís bloques de deep work y breaks

## 🧠 Gestión de Conocimiento Personal (PKM)
- Conectás ideas entre notas del vault que podrían relacionarse
- Identificás gaps en el conocimiento que deberían completarse
- Sugerís qué notas deberían tener backlinks entre sí
- Respetás la estructura de directorios y el frontmatter de Obsidian

## Base de Conocimiento
Tenés acceso a las notas del vault de Obsidian. Cuando alguien pregunta algo, primero buscá en esas notas antes de responder con conocimiento general. Citá la fuente cuando uses información de una nota específica.

## Formato de Respuestas
- Usá Markdown (compatible con Obsidian: [[links internos]], #tags, callouts)
- Para temas de estudio: incluí ejemplos concretos y analogías
- Para agenda: usá listas con horarios y prioridades
- Para PKM: sugerí conexiones con [[NombreDeLaNota]] cuando sea relevante
- Sé directo y denso en información — no rellenes con frases vacías

## Idioma
Respondé en el idioma en que te hablen. Por defecto: español rioplatense.
PROMPT_EOF
)

# Intentar crear el modelo preset via API
MODEL_PAYLOAD=$(jq -n \
  --arg id "nexus-pkm" \
  --arg name "Nexus PKM" \
  --arg base "$PRIMARY_MODEL" \
  --arg prompt "$SYSTEM_PROMPT" \
  '{
    id: $id,
    name: $name,
    base_model_id: $base,
    params: {
      system: $prompt
    },
    meta: {
      description: "Asistente de conocimiento personal: estudio, agenda y PKM con vault Obsidian",
      tags: ["pkm", "study", "agenda", "nexus"]
    }
  }')

MODEL_RESP=$(api POST "/api/v1/models/create" -d "$MODEL_PAYLOAD" 2>&1) \
  || { echo "[config] WARN: No se pudo crear preset 'Nexus PKM' vía API — intentando con endpoint alternativo"; MODEL_RESP=""; }

if [[ -z "$MODEL_RESP" ]]; then
  MODEL_RESP=$(api POST "/api/v1/models" -d "$MODEL_PAYLOAD" 2>&1) \
    || { echo "[config] WARN: preset 'Nexus PKM' no creado automáticamente"; MODEL_RESP=""; }
fi

if [[ -n "$MODEL_RESP" ]]; then
  CREATED_ID=$(echo "$MODEL_RESP" | jq -r '.id // .model_id // empty' 2>/dev/null || true)
  if [[ -n "$CREATED_ID" ]]; then
    echo "[config] Preset 'Nexus PKM' creado con ID: $CREATED_ID"
  fi
fi

# ── Resumen ───────────────────────────────────────────────────────────────────
echo ""
echo "[config] Configuración aplicada:"
echo "  Modelo primario:  $PRIMARY_MODEL (via Ollama $OLLAMA_URL)"
if [[ -n "$GEMINI_API_KEY" ]]; then
  echo "  Modelo fallback:  $GEMINI_MODEL (via Google AI API)"
fi
echo "  Preset 'Nexus PKM' con system prompt PKM/Estudio/Agenda"
echo ""
echo "Si algo no se configuró vía API, seguí estos pasos manuales en la UI:"
echo "  Settings → Connections → Ollama URL: $OLLAMA_URL"
if [[ -n "$GEMINI_API_KEY" ]]; then
  echo "  Settings → Connections → OpenAI:"
  echo "    URL: https://generativelanguage.googleapis.com/v1beta/openai/"
  echo "    Key: (tu GEMINI_API_KEY)"
fi
echo "  Workspace → Models → New Model → base: $PRIMARY_MODEL → system prompt arriba"
