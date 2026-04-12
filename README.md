# 🧠 Plan de implementación — Obsidian + LiveSync + OpenClaw nativo en VPS

**Instalación automatizada en el VPS (scripts + Docker + Caddy + CouchDB + Qdrant + Ollama):** [INSTALACION.md](INSTALACION.md)

Objetivo: dejar tu VPS como **second brain productivo**, con OpenClaw ya instalado **fuera de Docker**, y usar contenedores solo para servicios de soporte.

---

# 🎯 Arquitectura final

```text
Host VPS (Ubuntu 24.04)
├── OpenClaw (nativo, ya instalado)
├── /opt/nexus-brain/vault
├── Caddy (Docker)
├── CouchDB (Docker)
├── Qdrant (Docker)
└── Ollama (Docker)
```

## 🔍 Por qué esta arquitectura

### ✅ OpenClaw nativo

**Por qué:**

* ya lo tenés instalado
* evita doble mantenimiento
* acceso directo al filesystem
* mejor performance I/O sobre el vault
* más simple para MCP/filesystem

### ✅ CouchDB

**Por qué:**

* es el backend oficial de facto para plugin **Self-hosted LiveSync**
* sincroniza móvil, notebook, desktop
* resuelve conflictos por documento
* replicación continua

### ✅ Qdrant

**Por qué:**

* vector DB rápida
* ideal para búsquedas semánticas del vault
* muy buena con markdown chunking
* excelente para RAG con notas técnicas

### ✅ Ollama

**Por qué:**

* inferencia local
* sin costo por token
* privacidad total
* ideal para tu SaaS Jarvis

### ✅ Caddy

**Por qué:**

* TLS automático
* menos configuración que nginx
* renovación SSL automática
* ideal para exponer OpenClaw sin tocar su proceso nativo

---

# 📋 Plan paso a paso

## 1) Crear estructura persistente

```bash
sudo mkdir -p /opt/nexus-brain/{vault,couchdb,qdrant,ollama,caddy}
cd /opt/nexus-brain
```

**Por qué:** separa datos por servicio y simplifica backups.

---

## 2) Levantar soporte en Docker

Solo estos servicios:

* couchdb
* qdrant
* ollama
* caddy

**Por qué:** son stateless o fácilmente persistibles.

---

## 3) Apuntar OpenClaw al vault host

Vault recomendado:

```bash
/opt/nexus-brain/vault
```

**Por qué:**

* Obsidian LiveSync termina escribiendo acá
* OpenClaw consume markdown real
* Qdrant indexa chunks

---

## 4) Reverse proxy a OpenClaw nativo

Caddy publica:

```text
https://claw.tudominio.com
```

proxy a:

```text
http://host.docker.internal:3000
```

(reemplazá 3000 por el puerto real de OpenClaw)

**Por qué:**

* no exponés puertos del host directo
* TLS
* autenticación futura
* rate limiting posible

---

## 5) Configurar LiveSync

Desde Obsidian plugin:

```text
https://sync.tudominio.com
```

DB:

```text
obsidian-livesync
```

---

## 6) Integración OpenClaw + Qdrant

OpenClaw debe:

* leer `/opt/nexus-brain/vault`
* chunkear markdown
* indexar en Qdrant
* consultar Ollama

**Por qué:** esta capa convierte notas en memoria semántica real.

---

# 🛠️ Script Bash comentado (Ubuntu 24.04)

```bash
#!/usr/bin/env bash
set -e

# =========================================================
# Nexus Brain Bootstrap
# OpenClaw nativo + Docker support stack
# Ubuntu 24.04
# =========================================================

BASE_DIR="/opt/nexus-brain"
OPENCLAW_PORT="3000"   # CAMBIAR por tu puerto real
DOMAIN_CLAW="claw.tudominio.com"
DOMAIN_SYNC="sync.tudominio.com"

echo "[1/7] Creando estructura..."
sudo mkdir -p ${BASE_DIR}/{vault,couchdb,qdrant,ollama,caddy}
cd ${BASE_DIR}


echo "[2/7] Creando docker-compose..."
cat > docker-compose.yml <<'EOF'
services:
  couchdb:
    image: couchdb:3
    container_name: nexus-couchdb
    restart: unless-stopped
    environment:
      COUCHDB_USER: admin
      COUCHDB_PASSWORD: CHANGE_THIS_ULTRA_SECURE
    volumes:
      - ./couchdb:/opt/couchdb/data
    networks:
      - nexus_net

  qdrant:
    image: qdrant/qdrant:latest
    container_name: nexus-qdrant
    restart: unless-stopped
    volumes:
      - ./qdrant:/qdrant/storage
    networks:
      - nexus_net

  ollama:
    image: ollama/ollama:latest
    container_name: nexus-ollama
    restart: unless-stopped
    volumes:
      - ./ollama:/root/.ollama
    networks:
      - nexus_net

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
      - "host.docker.internal:host-gateway"
    networks:
      - nexus_net

networks:
  nexus_net:
    driver: bridge

volumes:
  caddy_data:
  caddy_config:
EOF


echo "[3/7] Creando Caddyfile..."
cat > caddy/Caddyfile <<EOF
${DOMAIN_CLAW} {
    reverse_proxy host.docker.internal:${OPENCLAW_PORT}
}

${DOMAIN_SYNC} {
    reverse_proxy couchdb:5984
}
EOF


echo "[4/7] Levantando servicios..."
docker compose up -d


echo "[5/7] Descargando modelo Ollama recomendado..."
docker exec -it nexus-ollama ollama pull qwen2.5-coder:14b || true


echo "[6/7] Mostrando endpoints..."
echo "OpenClaw: https://${DOMAIN_CLAW}"
echo "LiveSync: https://${DOMAIN_SYNC}"


echo "[7/7] Finalizado."
echo "Ahora configurá OpenClaw para leer: ${BASE_DIR}/vault"
```

---

# 🔥 Qué sigue después

## Fase 2 — producción seria

Siguiente mejora recomendada:

* systemd service para indexador del vault
* watcher con inotify
* embeddings automáticos al guardar notas
* snapshots diarios
* backup a S3/Backblaze
* multi-vault (Personal + Nexus + Career)

---

# 💡 Mi recomendación técnica para vos

Para tu proyecto **Jarvis**, este vault debería tener:

```text
00 Inbox

02 Architecture
03 RAG Research
04 Product Strategy
05 DevOps
06 Career
99 Archive
```

Y usar frontmatter:

```md
---
domain: nexus
type: architecture
status: active
---
```

Esto mejora muchísimo retrieval en Qdrant + OpenClaw.
