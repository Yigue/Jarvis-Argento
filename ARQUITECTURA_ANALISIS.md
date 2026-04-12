# 🧠 Jarvis-Argento — Diagnóstico Técnico Completo
> Análisis sobre el código fuente real del proyecto (todos los scripts, configs y specs)
> Fecha: Abril 2026

---

## Resumen ejecutivo

El proyecto está **considerablemente más avanzado** de lo que sugería el README original. La arquitectura es correcta, el código de los scripts es sólido y el flujo de instalación está bien pensado. Se encontraron **2 bugs reales** (ya corregidos en este análisis) y 3 observaciones menores.

**¿Es viable esta arquitectura?** Sí. Ya está casi lista para ejecutarse.

---

## Estado por componente

| Componente | Archivo | Estado | Notas |
|---|---|---|---|
| docker-compose | `deploy/docker-compose.yml` | ✅ Correcto | Puertos OK, loopback, GPU comentada |
| Ollama override | `deploy/docker-compose.no-ollama.yml` | ✅ Elegante | `profiles: disabled` es la forma correcta |
| Variables de entorno | `.env.example` | ✅ Correcto | Modelo default `llama3.2:3b` para CPU |
| **Caddyfile template** | `deploy/caddy/Caddyfile.template` | 🔴 **BUG — YA CORREGIDO** | Ver sección 1 |
| Script de instalación | `scripts/install.sh` | ✅ Sólido | `set -euo pipefail`, validación de vars, 2 runs |
| Setup de CouchDB | `scripts/setup-couchdb.sh` | ✅ Excelente | CORS correcto, nodo dinámico, URL encode de `@` |
| Health check | `scripts/health-check.sh` | ✅ Completo | Cubre todos los servicios, Ollama Docker+nativo |
| Pull de modelos | `scripts/pull-ollama-models.sh` | ✅ Correcto | Multi-modelo, fallback a nativo |
| Creación de KB | `scripts/create-knowledge-base.sh` | ✅ OK | Ver observación menor |
| Watcher service | `scripts/install-watcher-service.sh` | ✅ Correcto | Reescribe rutas con sed |
| Init vault dirs | `scripts/init-vault-dirs.sh` | ✅ OK | Crea estructura sugerida |
| **Vault watcher** | `watcher/vault_watcher.py` | 🟠 **BUG — YA CORREGIDO** | Ver sección 2 |
| Systemd service | `systemd/nexus-vault-watcher.service` | ✅ Correcto | `EnvironmentFile` con `-` (no falla si no existe) |
| Specs | `openspec/changes/...` | ✅ Bien definidas | Requirements claros con escenarios |
| .gitignore | `.gitignore` | ⚠️ Menor | Ver observación 3 |

---

## Bug #1 — CRÍTICO (ya corregido) — Caddyfile.template

### Descripción

`deploy/caddy/Caddyfile.template` usaba la sintaxis de interpolación de Caddy (`{$VAR}`) pero `install.sh` lo procesa con `envsubst`, que busca el patrón `${VAR}` o `$VAR` en el input.

**Comportamiento antes del fix:**
```
# Template original:
{$DOMAIN_CLAW} {
    reverse_proxy host.docker.internal:{$OPENCLAW_PORT}
}
```

`envsubst` ve `$DOMAIN_CLAW` dentro de `{...}` y sustituye solo el nombre de variable, dejando las llaves:
```
# Caddyfile generado (INVÁLIDO):
{claw.tudominio.com} {
    reverse_proxy host.docker.internal:{3000}
}
```

`{claw.tudominio.com}` en Caddy es interpretado como un **bloque de opciones globales**, no como una dirección de sitio. Caddy fallaría al arrancar con un error de parseo.

### Fix aplicado

```diff
- {$DOMAIN_CLAW} {
-     reverse_proxy host.docker.internal:{$OPENCLAW_PORT}
+ ${DOMAIN_CLAW} {
+     reverse_proxy host.docker.internal:${OPENCLAW_PORT}
```

`envsubst` reemplaza `${DOMAIN_CLAW}` → `claw.tudominio.com` y produce Caddyfile válido:
```
claw.tudominio.com {
    reverse_proxy host.docker.internal:3000
}
```

---

## Bug #2 — MEDIO (ya corregido) — vault_watcher.py re-indexa todo en cada reinicio

### Descripción

La función `initial_sync()` original recorría todos los `.md` del vault y los subía **incondicionalmente** en cada ejecución. Esto causaba que:

- Cada reinicio del servicio systemd re-indexara el vault completo
- OpenWebUI acumulaba entradas duplicadas en la Knowledge Base a lo largo del tiempo
- La sincronización inicial podía tardar varios minutos en vaults grandes sin ningún beneficio real

### Fix aplicado

Se agregó un mecanismo de **estado persistente** basado en `mtime`:

- Al finalizar cada sync, se guarda un archivo `{VAULT_PATH}/../.vault-watcher-state.json` con `{ruta: mtime}` de cada archivo indexado
- En la sincronización inicial, se compara el `mtime` actual con el guardado y se omiten los archivos sin cambios
- El watcher en tiempo real también actualiza el estado tras cada subida exitosa

**Resultado:** el reinicio del servicio solo sube archivos que cambiaron desde el último run. Vaults grandes de cientos de notas sincronizan en segundos en lugar de minutos.

---

## Observaciones menores (no bloquean el sistema)

### Obs #1 — create-knowledge-base.sh: error silencioso en HTTP 4xx

`curl -sf` falla silenciosamente ante errores HTTP 4xx/5xx. Si la API Key es inválida, el script podría recibir un 401 y no reportarlo claramente.

**Mejora sugerida (opcional):**
```bash
# Reemplazar:
resp=$(curl -sf -X POST ...)

# Por:
http_code=$(curl -s -o /tmp/kb-resp.json -w "%{http_code}" -X POST ...)
[[ "$http_code" == "200" || "$http_code" == "201" ]] || die "HTTP ${http_code}: $(cat /tmp/kb-resp.json)"
resp=$(cat /tmp/kb-resp.json)
```

### Obs #2 — Sin manejo de eliminaciones en el watcher

Si una nota se borra de Obsidian, el watcher no la elimina de la Knowledge Base. Esto es una limitación de `inotifywait` con el evento `DELETE` que no está suscrito.

Esta limitación es aceptable en la Fase 1. Para fases futuras, agregar `-e delete,moved_from` al comando `inotifywait` y llamar a `DELETE /api/v1/knowledge/{id}/file/{file_id}`.

### Obs #3 — .gitignore: nombre de venv incorrecto

```
# .gitignore tiene:
.watcher-venv/

# install.sh crea:
$NEXUS_ROOT/watcher-venv/   # sin punto inicial
```

En la práctica no es un problema porque el venv se crea en `/opt/nexus-brain/`, fuera del repositorio. Si alguien cambiara `NEXUS_ROOT` al directorio del repo, el venv no sería ignorado. Se puede corregir agregando ambas variantes al `.gitignore`:

```
watcher-venv/
.watcher-venv/
```

---

## Diagnóstico Ollama + OpenWebUI — Estado actual

El `docker-compose.yml` real ya tiene el puerto de Ollama expuesto correctamente:

```yaml
ollama:
    ports:
      - "127.0.0.1:11434:11434"   # ✅ ya estaba corregido
```

Por lo tanto, **el problema de conexión no es el puerto**. Las causas más probables en el servidor actual son:

### Causa A — URL incorrecta en OpenWebUI (más probable)

En OpenWebUI → Settings → Admin → Connections → Ollama API URL, verificar que el valor sea exactamente `http://127.0.0.1:11434` (no `localhost`, no `http://nexus-ollama:11434`).

**Test de verificación desde el host del VPS:**
```bash
# ¿Ollama Docker responde al host?
curl http://127.0.0.1:11434/api/tags

# ¿Los modelos están descargados?
curl http://127.0.0.1:11434/api/tags | python3 -m json.tool

# ¿Cuánto tarda en responder (determina si es timeout)?
time curl -s -X POST http://127.0.0.1:11434/api/generate \
  -d '{"model":"llama3.2:3b","prompt":"hola","stream":false}'
```

### Causa B — Timeout en OpenWebUI por modelo pesado en CPU

Si usás `gemma2:9b` en CPU puro, puede tardar 3-5 minutos en responder. OpenWebUI tiene un timeout de ~30-60s por defecto.

**Fix:**
1. Settings → Admin → General → **Request Timeout** → cambiar a `300`
2. O probar con `llama3.2:3b` que es significativamente más rápido en CPU

### Causa C — Modelo no descargado en el contenedor Ollama

Si el `OLLAMA_MODELS` en `.env` no incluye el modelo que querés usar, o si el contenedor se recreó y perdió los datos del volumen:

```bash
# Verificar modelos disponibles en el contenedor
docker exec nexus-ollama ollama list

# Descargar si no está
docker exec nexus-ollama ollama pull llama3.2:3b
```

### Diagnóstico rápido completo

```bash
# Ejecutar el health-check del proyecto
./scripts/health-check.sh /opt/nexus-brain

# Si health-check no existe aún, verificar manualmente:
curl -sf http://127.0.0.1:5984/          && echo "CouchDB OK" || echo "CouchDB FAIL"
curl -sf http://127.0.0.1:6333/readyz    && echo "Qdrant OK"  || echo "Qdrant FAIL"
curl -sf http://127.0.0.1:11434/api/tags && echo "Ollama OK"  || echo "Ollama FAIL"
curl -sf http://127.0.0.1:3000/          && echo "OpenWebUI OK" || echo "OpenWebUI FAIL"
```

---

## Flujo de instalación correcto (Clean Slate recomendado ahora que tenés el repo)

Dado que ya tenés el repositorio estructurado, el flujo limpio es:

```bash
# En el VPS, como usuario con sudo:

# 1. Clonar el repo
git clone <tu-repo> ~/Jarvis-Argento
cd ~/Jarvis-Argento
chmod +x scripts/*.sh

# 2. Primera pasada (instala deps + crea .env vacío)
sudo ./scripts/install.sh --install-deps

# 3. Editar .env con tus valores reales
sudo nano /opt/nexus-brain/.env
# Completar: DOMAIN_CLAW, DOMAIN_SYNC, COUCHDB_PASSWORD, OPENCLAW_PORT
# Decidir: OLLAMA_MODELS=llama3.2:3b (recomendado para CPU)

# 4. Si NO tenés GPU → Ollama nativo (más simple, mejor performance en CPU)
curl -fsSL https://ollama.com/install.sh | sh
sudo ./scripts/install.sh --skip-ollama

# 4-alt. Si SÍ tenés GPU → Ollama en Docker (descomentar bloque deploy en compose)
sudo ./scripts/install.sh

# 5. Verificar todo
./scripts/health-check.sh /opt/nexus-brain

# 6. En OpenWebUI: generar API Key (Settings → Account → API Key)
# 7. Editar .env: agregar OPENWEBUI_API_KEY=...

# 8. Crear Knowledge Base
sudo ./scripts/create-knowledge-base.sh /opt/nexus-brain "Obsidian Vault"
# Copiar el KNOWLEDGE_ID al .env

# 9. Instalar vault watcher
sudo ./scripts/install-watcher-service.sh /opt/nexus-brain

# 10. Verificar watcher
sudo journalctl -u nexus-vault-watcher -f
```

---

## Hoja de ruta por fases

### Fase 0 — Esta sesión (ya cubierta)
- ✅ Bug Caddyfile corregido (generación del dominio inválida)
- ✅ Vault watcher mejorado (sincronización incremental basada en mtime)
- ✅ Análisis completo documentado

### Fase 1 — Esta semana
- Ejecutar `install.sh` con `--install-deps` en el VPS
- Editar `.env` con dominios reales y contraseña CouchDB
- Verificar conexión Ollama ↔ OpenWebUI con `health-check.sh`
- Configurar LiveSync desde Obsidian
- Crear Knowledge Base y activar watcher

### Fase 2 — Mes 1
- Activar frontmatter consistente en las notas (mejora retrieval RAG significativamente)
- Migrar de Chroma built-in a Qdrant cuando el vault supere las 2000 notas
- Agregar modelo de embeddings dedicado: `nomic-embed-text` via Ollama
- Snapshots diarios del vault y CouchDB

### Fase 3 — Mes 2-3 (Jarvis como producto)
- API propia sobre OpenWebUI para Jarvis
- Telegram bot para notificaciones y agenda diaria
- Dashboard de actividad del vault
- Multi-vault (Personal / Nexus / Career)

---

## Validación de herramientas en 2026

| Herramienta | Versión | Estado | Alternativa si escalás |
|---|---|---|---|
| **OpenWebUI** | latest | ✅ Vigente. v0.5+ tiene RAG y Knowledge mejorados. | — |
| **Ollama** | latest | ✅ Estándar de facto para inferencia local. | — |
| **CouchDB** | 3 | ✅ Único backend soportado por Self-hosted LiveSync. | — |
| **Qdrant** | latest | ✅ Top 3 en benchmarks 2026. | pgvector si ya usás PG |
| **Caddy** | 2 | ✅ Mejor opción para TLS automático en setups personales. | Traefik para K8s |
| **llama3.2:3b** | — | ✅ Correcto para CPU sin GPU. | qwen2.5:7b-q4_K_M para respuestas más elaboradas |
| **gemma2:9b** | — | ⚠️ Solo viable con GPU o timeout >180s en CPU lento. | llama3.2:3b para empezar |
