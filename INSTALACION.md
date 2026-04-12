# Instalación en VPS (Ubuntu 24.04)

Esta guía asume **OpenClaw / OpenWebUI ya instalado en el host** y un VPS donde vas a clonar este repo.

## 1. Prerrequisitos

- DNS: registros `A` (o `AAAA`) para `DOMAIN_CLAW` y `DOMAIN_SYNC` apuntando a la VPS.
- Puertos 80 y 443 libres (Caddy obtiene certificados Let’s Encrypt).
- Usuario con `sudo`.

## 2. Clonar e instalar dependencias del sistema (opcional)

```bash
git clone <tu-repo> Jarvis-Argento
cd Jarvis-Argento
chmod +x scripts/*.sh
sudo ./scripts/install.sh --install-deps
```

Si ya tenés Docker, `curl`, `jq`, `gettext-base` (envsubst), `python3-venv` e `inotify-tools`, podés omitir `--install-deps`.

## 3. Primera ejecución (genera `/opt/nexus-brain/.env`)

```bash
sudo ./scripts/install.sh
```

Editá el archivo indicado y completá como mínimo:

- `DOMAIN_CLAW`, `DOMAIN_SYNC`
- `COUCHDB_PASSWORD`
- `OPENCLAW_PORT` (puerto real donde escucha OpenClaw en el host)

Volvé a ejecutar:

```bash
sudo ./scripts/install.sh
```

### Ollama nativo (recomendado en VPS sin GPU)

```bash
curl -fsSL https://ollama.com/install.sh | sh
sudo ./scripts/install.sh --skip-ollama
```

En OpenClaw: **Ollama URL** → `http://127.0.0.1:11434`. Subí el **Request Timeout** (p. ej. 300 s) si usás CPU.

Si **ya tenés Ollama nativo**, no hace falta `--skip-ollama`: el instalador detecta el puerto 11434 ocupado y **no levanta** el contenedor `nexus-ollama` automáticamente.

### Error: `address already in use` en `127.0.0.1:11434`

Significa que Ollama (u otro proceso) ya escucha en ese puerto. **No apagues Ollama nativo** si querés seguir usándolo: levantá el stack **sin** Ollama en Docker:

```bash
cd /opt/nexus-brain
# ajustá la ruta si usaste --nexus-root distinto
docker compose down
docker compose -f docker-compose.yml -f docker-compose.no-ollama.yml up -d
```

Luego volvé a ejecutar `sudo ./scripts/install.sh` desde el repo (idempotente) o solo el `docker compose` de arriba si el resto ya está bien.

**Alternativa** (solo si querés Ollama **solo** en Docker): `systemctl stop ollama` (y opcional `systemctl disable ollama`), liberá 11434 y ejecutá `sudo ./scripts/install.sh --force-docker-ollama`.

### Otro directorio de datos

```bash
sudo ./scripts/install.sh --nexus-root /srv/nexus-brain
```

(`install-watcher-service.sh` reescribe las rutas en la unidad systemd según ese directorio.)

## 4. OpenClaw y Qdrant

- **Ollama** (Docker): ya queda en `127.0.0.1:11434` para el proceso nativo en el host.
- **Qdrant**: `http://127.0.0.1:6333` — en OpenClaw, cuando quieras migrar desde Chroma: variables tipo `VECTOR_DB=qdrant` y `QDRANT_URI` según la documentación de tu versión de OpenWebUI.
- Apuntá el vault de Obsidian / herramientas a `VAULT_PATH` (por defecto `/opt/nexus-brain/vault`).

## 5. RAG: Knowledge Base + watcher

1. En la UI: generá una **API Key**.
2. Creá la colección (o usá el script):

   ```bash
   sudo ./scripts/create-knowledge-base.sh /opt/nexus-brain "Obsidian Vault"
   ```

3. Pegá `KNOWLEDGE_ID` y la API key en `/opt/nexus-brain/.env`.
4. Instalá el servicio:

   ```bash
   sudo ./scripts/install-watcher-service.sh /opt/nexus-brain
   ```

## 6. Obsidian LiveSync

Tras el instalador, CouchDB queda detrás de `https://DOMAIN_SYNC`. En el plugin usá esa URL, usuario `admin` y la contraseña del `.env`, base `obsidian-livesync` (o la que definiste en `COUCHDB_DATABASE`).

## 7. Comprobaciones

```bash
./scripts/health-check.sh /opt/nexus-brain
curl -s http://127.0.0.1:11434/api/tags
```

## 8. GPU con Ollama en Docker

En `deploy/docker-compose.yml`, descomentá el bloque `deploy.resources` bajo `ollama` e instalá [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) en el host.
