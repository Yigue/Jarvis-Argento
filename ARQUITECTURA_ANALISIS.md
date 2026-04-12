# 🧠 Jarvis-Argento — Diagnóstico Técnico y Hoja de Ruta
> Análisis por: Claude (Experto en DevOps / RAG / Arquitectura de sistemas)
> Fecha: Abril 2026

---

## 🚨 TL;DR — Los 3 bugs que bloquean todo hoy

Antes de cualquier hoja de ruta, estas son las razones exactas por las que Ollama no conecta con OpenWebUI:

| # | Bug | Severidad | Fix |
|---|-----|-----------|-----|
| 1 | Ollama en Docker **sin `ports` expuestos al host** | 🔴 CRÍTICO | Agregar `ports: ["11434:11434"]` |
| 2 | **Sin GPU passthrough** en Docker → timeout en modelos 7B+ | 🔴 CRÍTICO | Agregar `deploy.resources` o correr Ollama nativo |
| 3 | Modelo `qwen2.5-coder:14b` sugerido en el script es **inviable en VPS sin GPU** | 🟠 ALTO | Usar `llama3.2:3b` o `qwen2.5:7b-q4` primero |

---

## 1. Validación de la Arquitectura

### ✅ Lo que está bien planteado

**CouchDB para LiveSync** → correcto. Es el único backend que soporta el plugin oficial Self-hosted LiveSync de Obsidian. Sin alternativas reales aquí.

**Qdrant como vector DB** → excelente elección. En 2025-2026 sigue siendo el líder en performance para búsqueda semántica en markdown chunking. Buena decisión.

**Caddy v2** → sigue siendo la mejor opción para TLS automático en setups personales. Mucho menos fricción que nginx.

**OpenWebUI (llamado "OpenClaw" en tu README) nativo** → tiene sentido si ya lo tenés instalado. Acceso directo al filesystem facilita el pipeline RAG.

---

### ⚠️ Lo que hay que corregir

#### Bug #1 — Ollama sin puerto expuesto (ROOT CAUSE del error de conexión)

Tu docker-compose actual:

```yaml
ollama:
    image: ollama/ollama:latest
    container_name: nexus-ollama
    volumes:
      - ./ollama:/root/.ollama
    networks:
      - nexus_net
    # ❌ No hay "ports:" → el host no puede llegar a Ollama
```

OpenWebUI corre **nativamente en el host**. Ollama corre **dentro de Docker**. Sin `ports: ["11434:11434"]`, el proceso nativo en el host no tiene forma de llegar a `localhost:11434` porque ese puerto no existe en el host — existe solo dentro de la red Docker interna `nexus_net`.

**Fix inmediato:**

```yaml
ollama:
    image: ollama/ollama:latest
    container_name: nexus-ollama
    restart: unless-stopped
    ports:
      - "127.0.0.1:11434:11434"   # expone solo a loopback, no a internet
    volumes:
      - ./ollama:/root/.ollama
    networks:
      - nexus_net
```

Luego en OpenWebUI → Settings → Connections → Ollama URL: `http://localhost:11434`

---

#### Bug #2 — Sin GPU passthrough → modelos 7B+ en CPU puro = timeout

Cuando Ollama corre en Docker sin acceso a GPU, genera tokens a ~2-5 tokens/segundo en CPU. OpenWebUI tiene un timeout de respuesta (por defecto 30-60s). Un modelo 9B en CPU puro puede tardar 3-5 minutos en responder → OpenWebUI lo marca como error aunque el modelo SÍ está corriendo.

Esto explica exactamente tu síntoma: "funcionan en la CLI de Ollama pero no en OpenWebUI".

**Opciones según tu hardware:**

**Opción A — VPS con GPU NVIDIA (recomendada si disponible):**
```yaml
ollama:
    image: ollama/ollama:latest
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    ports:
      - "127.0.0.1:11434:11434"
    volumes:
      - ./ollama:/root/.ollama
    networks:
      - nexus_net
```
Requiere: `nvidia-container-toolkit` instalado en el host.

**Opción B — VPS CPU-only (más común):** Correr Ollama **nativo en el host** en lugar de en Docker. Rendimiento similar pero sin la capa de Docker.

```bash
# Instalar Ollama nativo
curl -fsSL https://ollama.com/install.sh | sh

# Verificar que corre en el host
systemctl status ollama
```

Luego eliminar el servicio ollama del docker-compose y usarlo desde el host directamente.

---

#### Bug #3 — Modelo incorrecto para el hardware

El script sugiere `qwen2.5-coder:14b`. Para un VPS estándar (sin GPU dedicada):

| Modelo | RAM necesaria | Velocidad CPU | Recomendación |
|--------|--------------|---------------|---------------|
| llama3.2:3b | ~2.5 GB | ✅ Usable | Para testing rápido |
| qwen2.5:7b (q4_K_M) | ~4.5 GB | ⚠️ Lento | Para producción CPU |
| gemma2:9b | ~6 GB | 🐌 Muy lento en CPU | Solo con GPU |
| qwen2.5-coder:14b | ~10 GB | ❌ Timeout | Solo con GPU 12GB+ |

**Recomendación para arrancar:**
```bash
ollama pull llama3.2:3b          # testing inmediato
ollama pull qwen2.5:7b-q4_K_M   # producción en CPU
```

---

## 2. Diagnóstico Ollama + OpenWebUI — Paso a paso

### Verificación del problema

Desde el host de tu VPS, ejecuta esto y compará los resultados:

```bash
# Test 1: ¿Ollama responde desde el host?
curl http://localhost:11434/api/tags

# Test 2: ¿OpenWebUI puede llegar a Ollama?
# (Si OpenWebUI está en Docker)
docker exec -it <nombre_openwebui_container> curl http://host.docker.internal:11434/api/tags

# Test 3: ¿El modelo existe?
ollama list

# Test 4: ¿Cuánto RAM tiene el VPS?
free -h

# Test 5: ¿Cuánto tarda el modelo en responder?
time ollama run llama3.2:3b "responde con una sola palabra: hola"
```

### Checklist de configuración en OpenWebUI

1. **Settings → Admin → Connections**
   - Si Ollama es nativo en host y OpenWebUI también es nativo: `http://localhost:11434`
   - Si Ollama es nativo pero OpenWebUI está en Docker: `http://host.docker.internal:11434`
   - Si ambos están en Docker en la misma red: `http://nexus-ollama:11434`

2. **Settings → Admin → Models** → Verificar que aparecen los modelos descargados

3. **Settings → Admin → General → Request Timeout** → Aumentar a 300 segundos si usás CPU

---

## 3. Pipeline RAG: Obsidian → OpenWebUI

Esta es la parte más interesante de tu arquitectura. OpenWebUI (desde v0.4+) tiene un sistema de **Knowledge Bases** con RAG nativo. El flujo completo es:

```
Obsidian Vault (/opt/nexus-brain/vault)
    ↓ [inotifywait watcher]
    ↓ detecta cambio en .md
    ↓ [Python script]
    ↓ llama API OpenWebUI /api/v1/knowledge/{id}/file/add
    ↓
OpenWebUI ingesta el archivo
    ↓ chunkea markdown
    ↓ genera embeddings (con modelo local)
    ↓ guarda en Chroma (built-in) o Qdrant (externo)
    ↓
Al chatear: RAG automático desde el vault
```

### Paso 1 — Crear Knowledge Base en OpenWebUI

Desde la UI de OpenWebUI:
1. Ir a **Workspace → Knowledge**
2. Crear una colección: `Obsidian Vault`
3. Anotar el `ID` de la colección (lo necesitás para la API)

O via API:
```bash
curl -X POST http://localhost:3000/api/v1/knowledge \
  -H "Authorization: Bearer TU_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "Obsidian Vault", "description": "Nexus Brain personal vault"}'
```

### Paso 2 — Script watcher de sincronización

Guardá esto como `/opt/nexus-brain/vault-watcher.py`:

```python
#!/usr/bin/env python3
"""
Vault Watcher — sincroniza cambios del vault de Obsidian con OpenWebUI RAG
"""
import subprocess
import requests
import os
import time
from pathlib import Path

# ── Configuración ──────────────────────────────────────────────
VAULT_PATH = "/opt/nexus-brain/vault"
OPENWEBUI_URL = "http://localhost:3000"   # puerto real de OpenWebUI
OPENWEBUI_API_KEY = "TU_API_KEY_AQUI"    # Settings → Account → API Key
KNOWLEDGE_ID = "TU_KNOWLEDGE_ID_AQUI"    # ID de la colección creada

HEADERS = {"Authorization": f"Bearer {OPENWEBUI_API_KEY}"}
# ──────────────────────────────────────────────────────────────


def upload_file(filepath: str):
    """Sube o actualiza un archivo markdown en la Knowledge Base."""
    path = Path(filepath)
    if not path.exists() or path.suffix != ".md":
        return

    print(f"[vault-watcher] Indexando: {path.name}")

    with open(filepath, "rb") as f:
        files = {"file": (path.name, f, "text/markdown")}
        response = requests.post(
            f"{OPENWEBUI_URL}/api/v1/knowledge/{KNOWLEDGE_ID}/file/add",
            headers=HEADERS,
            files=files,
        )

    if response.status_code == 200:
        print(f"[vault-watcher] ✅ Indexado: {path.name}")
    else:
        print(f"[vault-watcher] ❌ Error {response.status_code}: {response.text}")


def initial_sync():
    """Indexa todos los archivos .md del vault al inicio."""
    print("[vault-watcher] Sincronización inicial del vault...")
    for md_file in Path(VAULT_PATH).rglob("*.md"):
        # Excluir carpetas de sistema de Obsidian
        if ".obsidian" in str(md_file):
            continue
        upload_file(str(md_file))
    print("[vault-watcher] ✅ Sincronización inicial completada")


def watch():
    """Observa cambios en el vault con inotifywait."""
    cmd = [
        "inotifywait",
        "-m", "-r",
        "-e", "close_write,moved_to,create",
        "--format", "%w%f",
        VAULT_PATH,
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True)
    print(f"[vault-watcher] Observando: {VAULT_PATH}")

    for line in proc.stdout:
        filepath = line.strip()
        if filepath.endswith(".md") and ".obsidian" not in filepath:
            upload_file(filepath)


if __name__ == "__main__":
    initial_sync()
    watch()
```

### Paso 3 — Systemd service para el watcher

```bash
# Instalar dependencia
pip install requests --break-system-packages
sudo apt install inotify-tools -y

# Crear service
sudo tee /etc/systemd/system/vault-watcher.service > /dev/null <<EOF
[Unit]
Description=Obsidian Vault RAG Watcher
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /opt/nexus-brain/vault-watcher.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable vault-watcher
sudo systemctl start vault-watcher

# Verificar
sudo systemctl status vault-watcher
```

### Paso 4 — Activar RAG en el chat de OpenWebUI

Al chatear en OpenWebUI:
1. Hacer clic en el ícono `+` debajo del campo de texto
2. Seleccionar **Knowledge** → `Obsidian Vault`
3. Preguntar sobre tus notas → OpenWebUI buscará en el vault semánticamente

O crear un **Model Preset** con el vault adjunto por defecto para no tener que seleccionarlo cada vez.

---

## 4. ¿Qdrant externo o Chroma built-in?

Tu README menciona Qdrant. OpenWebUI tiene dos modos de RAG:

| Backend | Pros | Contras | Cuándo usarlo |
|---------|------|---------|---------------|
| **Chroma** (built-in) | Zero config, ya está | Menos performance a escala | ✅ Ahora, para arrancar |
| **Qdrant** (externo) | Performance superior, persistencia robusta, multi-colección | Requiere config extra en OpenWebUI | Cuando tengas >5000 notas |

**Recomendación**: Empezá con Chroma built-in de OpenWebUI (no necesitás configurar nada extra). Cuando el vault crezca, migrás a Qdrant cambiando una variable de entorno en OpenWebUI:

```bash
# En el .env de OpenWebUI cuando quieras migrar
VECTOR_DB=qdrant
QDRANT_URI=http://localhost:6333
```

---

## 5. Clean Slate vs. Fix Actual

**Veredicto: Fix, no Clean Slate.**

Las razones para hacer Clean Slate (reescribir todo desde cero) serían: configuraciones corruptas no recuperables, deuda técnica acumulada severa, o cambio de stack tecnológico completo. Ninguno aplica aquí.

Tu arquitectura es **conceptualmente sólida**. Los problemas son de configuración puntual, no de diseño:

| Problema | Solución | Tiempo estimado |
|----------|----------|-----------------|
| Ollama sin puerto expuesto | Agregar `ports` en docker-compose + `docker compose up -d` | 5 minutos |
| Sin GPU / timeout | Correr Ollama nativo O aumentar timeout en OpenWebUI | 15 minutos |
| Modelo muy pesado | `ollama pull llama3.2:3b` | 5 minutos + descarga |
| RAG no configurado | Script watcher + Knowledge Base en OpenWebUI | 1-2 horas |

**Cuándo sí tiene sentido Clean Slate**: cuando estés listo para pasar a producción seria (multi-usuario, SaaS Jarvis), ahí sí conviene un despliegue limpio con Ansible/Terraform o al menos un repositorio con variables de entorno versionadas.

---

## 6. docker-compose.yml corregido y completo

Este reemplaza al del README con todos los fixes aplicados:

```yaml
# /opt/nexus-brain/docker-compose.yml
# Nexus Brain — Stack corregido (Abril 2026)

services:

  # ── CouchDB — Backend LiveSync de Obsidian ──────────────────
  couchdb:
    image: couchdb:3
    container_name: nexus-couchdb
    restart: unless-stopped
    environment:
      COUCHDB_USER: admin
      COUCHDB_PASSWORD: ${COUCHDB_PASSWORD}   # usar .env, nunca hardcoded
    volumes:
      - ./couchdb:/opt/couchdb/data
    networks:
      - nexus_net

  # ── Qdrant — Vector DB (para producción futura) ──────────────
  qdrant:
    image: qdrant/qdrant:latest
    container_name: nexus-qdrant
    restart: unless-stopped
    ports:
      - "127.0.0.1:6333:6333"   # solo loopback, no expuesto a internet
    volumes:
      - ./qdrant:/qdrant/storage
    networks:
      - nexus_net

  # ── Ollama — Inferencia local ────────────────────────────────
  # OPCIÓN A: Ollama en Docker (si tenés GPU NVIDIA)
  # OPCIÓN B: Comentar este bloque y correr Ollama nativo en el host
  ollama:
    image: ollama/ollama:latest
    container_name: nexus-ollama
    restart: unless-stopped
    ports:
      - "127.0.0.1:11434:11434"   # ← FIX: expuesto al host (solo loopback)
    volumes:
      - ./ollama:/root/.ollama
    # Descomentar si tenés GPU NVIDIA + nvidia-container-toolkit:
    # deploy:
    #   resources:
    #     reservations:
    #       devices:
    #         - driver: nvidia
    #           count: all
    #           capabilities: [gpu]
    networks:
      - nexus_net

  # ── Caddy — Reverse proxy con TLS automático ─────────────────
  caddy:
    image: caddy:2
    container_name: nexus-caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./caddy/Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    extra_hosts:
      - "host.docker.internal:host-gateway"   # permite llegar al host nativo
    networks:
      - nexus_net

networks:
  nexus_net:
    driver: bridge

volumes:
  caddy_data:
  caddy_config:
```

### Archivo `.env` (nunca commitear esto)

```bash
# /opt/nexus-brain/.env
COUCHDB_PASSWORD=cambia_esto_por_una_password_segura_larga
```

---

## 7. Configuración de Obsidian LiveSync

Una vez CouchDB esté corriendo:

1. **Inicializar CouchDB** (solo una vez):
```bash
# Crear la base de datos
curl -X PUT http://admin:TU_PASSWORD@sync.tudominio.com/obsidian-livesync

# Configurar CORS (requerido por el plugin)
curl -X PUT http://admin:TU_PASSWORD@sync.tudominio.com/_node/_local/_config/httpd/enable_cors \
  -d '"true"'
curl -X PUT http://admin:TU_PASSWORD@sync.tudominio.com/_node/_local/_config/cors/origins \
  -d '"app://obsidian.md,capacitor://localhost,http://localhost"'
curl -X PUT http://admin:TU_PASSWORD@sync.tudominio.com/_node/_local/_config/cors/credentials \
  -d '"true"'
curl -X PUT http://admin:TU_PASSWORD@sync.tudominio.com/_node/_local/_config/cors/methods \
  -d '"GET, PUT, POST, HEAD, DELETE"'
curl -X PUT http://admin:TU_PASSWORD@sync.tudominio.com/_node/_local/_config/cors/headers \
  -d '"accept, authorization, content-type, origin, referer"'
```

2. **En Obsidian** → Instalar plugin **Self-hosted LiveSync** → Configurar:
   - URI: `https://sync.tudominio.com`
   - Database: `obsidian-livesync`
   - Username: `admin`
   - Password: tu password de CouchDB

---

## 8. Estructura de vault recomendada (para RAG óptimo)

Para maximizar la calidad del retrieval en RAG, cada nota debería tener frontmatter consistente:

```markdown
---
domain: architecture       # o: devops, career, product, research
type: note                 # o: meeting, decision, reference, inbox
status: active             # o: draft, archived, someday
tags: [rag, obsidian, vps]
created: 2026-04-12
---

# Título de la nota

Contenido...
```

Estructura de carpetas sugerida para Jarvis:
```
00 Inbox/          ← notas sin procesar
01 Daily/          ← agenda diaria
02 Architecture/   ← decisiones técnicas
03 RAG Research/   ← notas sobre IA/ML
04 Product/        ← estrategia Jarvis SaaS
05 DevOps/         ← runbooks, configs
06 Career/         ← objetivos personales
99 Archive/        ← notas viejas
```

---

## 9. Hoja de ruta por fases

### Fase 0 — Hoy (1-2 horas)
- [ ] Agregar `ports: ["127.0.0.1:11434:11434"]` al servicio ollama en docker-compose
- [ ] `docker compose up -d ollama`
- [ ] En OpenWebUI → Settings → Connections → Ollama URL: `http://localhost:11434`
- [ ] `ollama pull llama3.2:3b` → probar en OpenWebUI
- [ ] Verificar que modelos aparecen en OpenWebUI

### Fase 1 — Esta semana
- [ ] Levantar CouchDB y configurar LiveSync desde Obsidian
- [ ] Instalar `inotify-tools` y deployar el vault-watcher como systemd service
- [ ] Crear Knowledge Base en OpenWebUI y probar RAG con algunas notas
- [ ] Configurar Caddy con tus dominios reales

### Fase 2 — Mes 1
- [ ] Migrar de Chroma built-in a Qdrant externo (cuando el vault crezca)
- [ ] Agregar modelo de embeddings dedicado (nomic-embed-text via Ollama)
- [ ] Sistema de agenda diaria: nota en Obsidian → RAG context en conversación matutina
- [ ] Backups diarios del vault y CouchDB a Backblaze B2

### Fase 3 — Mes 2-3 (Jarvis SaaS)
- [ ] API propia sobre OpenWebUI para Jarvis
- [ ] Webhooks para notificaciones (Telegram bot o similar)
- [ ] Multi-vault (Personal + Nexus + Career)
- [ ] Dashboard de métricas del vault

---

## 10. Validación de herramientas (¿siguen siendo las mejores en 2026?)

| Herramienta | Estado | Alternativa a considerar |
|-------------|--------|--------------------------|
| **OpenWebUI** | ✅ Sigue siendo el mejor frontend para Ollama. Versión 0.5+ tiene mejoras sustanciales en RAG y Knowledge Bases. | - |
| **Ollama** | ✅ Estándar de facto para inferencia local en 2026. Soporte de modelos excelente. | LM Studio (solo desktop) |
| **CouchDB + LiveSync** | ✅ Sin alternativas reales para Obsidian sync self-hosted. | - |
| **Qdrant** | ✅ Sigue siendo top 3 en benchmarks. Muy activo en desarrollo. | Weaviate (más complejo), pgvector (si ya usás PG) |
| **Caddy** | ✅ Mejor opción para setups personales en 2026. | Traefik (si usás Swarm/K8s) |
| **gemma2:9b** | ⚠️ Buen modelo pero pesado para CPU. | `qwen2.5:7b-q4_K_M` (mejor ratio calidad/peso) |

---

## Resumen ejecutivo

**¿Es viable la arquitectura?** Sí, completamente. El diseño es correcto y las herramientas son las adecuadas para 2026.

**¿Por qué no funciona hoy?** Por un solo bug de configuración: Ollama en Docker no tiene el puerto expuesto al host donde corre OpenWebUI. Eso explica el 100% del problema de conexión.

**¿Clean Slate o Fix?** Fix. Son 3 cambios puntuales en el docker-compose y 15 minutos de trabajo.

**¿Cuándo escalar?** Cuando el vault supere las 2000-3000 notas o cuando empieces a construir el SaaS Jarvis para otros usuarios. Hasta entonces, la arquitectura actual es más que suficiente.
