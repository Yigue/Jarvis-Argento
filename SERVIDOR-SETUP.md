# Nexus Brain — Guía de Configuración en el Servidor

> **Estado del proyecto:** El servidor ya tiene el stack corriendo (o lo tendrá tras el setup).
> Este documento describe qué tenés que hacer VOS en el servidor y en Obsidian para que todo funcione.

---

## Lo que hace el script automáticamente (no necesitás hacer nada de esto)

- Instala Docker, curl, jq, python3, inotify-tools
- Levanta CouchDB + Qdrant + Caddy + Ollama en Docker
- Descarga el modelo `gemma4:7b` via Ollama
- Configura CouchDB con CORS para LiveSync
- Crea estructura de directorios del vault
- Configura OpenClaw con el modelo primario y el system prompt PKM

---

## Lo que SÍ necesitás hacer vos

### PASO 1 — Prerrequisitos en el servidor (antes del primer `./setup.sh`)

```bash
# El servidor debe tener abiertos los puertos:
# 22    → SSH
# 80    → HTTP (Caddy / Let's Encrypt challenge)
# 443   → HTTPS (OpenClaw + LiveSync)

# Los dominios deben apuntar a la IP del servidor ANTES de correr el script.
# Caddy necesita hacer el challenge HTTP para obtener el certificado TLS.
# Si los DNS no están propagados, Caddy va a fallar.

# Verificar propagación DNS (hacé esto desde tu PC):
nslookup claw.tudominio.com
nslookup sync.tudominio.com
# Ambos deben resolver a la IP del servidor
```

### PASO 2 — Instalar OpenWebUI (OpenClaw) en el servidor

El script **no instala OpenWebUI** — lo instala el usuario por separado porque se puede instalar de distintas formas según el hardware.

```bash
# Opción A: Instalación con pip (recomendada para VPS sin GPU)
pip install open-webui
# Luego correlo como servicio systemd (ver abajo)

# Opción B: Con uvicorn directamente (para probar)
DATA_DIR=/opt/nexus-brain/openwebui open-webui serve --host 0.0.0.0 --port 3000

# Opción C: Docker (si querés todo en contenedores — ajustar OPENCLAW_PORT en .env)
docker run -d -p 3000:8080 \
  -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
  -v /opt/nexus-brain/openwebui:/app/backend/data \
  --name nexus-openclaw \
  --restart always \
  ghcr.io/open-webui/open-webui:main
```

#### Servicio systemd para OpenWebUI (Opción A)

```bash
sudo tee /etc/systemd/system/nexus-openclaw.service > /dev/null <<'EOF'
[Unit]
Description=Nexus Brain — OpenClaw (OpenWebUI)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Environment=DATA_DIR=/opt/nexus-brain/openwebui
Environment=PORT=3000
Environment=HOST=0.0.0.0
ExecStart=/usr/local/bin/open-webui serve --host 0.0.0.0 --port 3000
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable nexus-openclaw
sudo systemctl start nexus-openclaw
sudo systemctl status nexus-openclaw
```

### PASO 3 — Primer arranque del stack

```bash
# 1. Clonar el repositorio
git clone https://github.com/Yigue/Jarvis-Argento.git
cd Jarvis-Argento

# 2. Configurar el .env (una sola vez)
cp .env.example .env
nano .env
```

Valores mínimos a completar en `.env`:

| Variable | Valor | Ejemplo |
|---|---|---|
| `DOMAIN_CLAW` | Dominio para OpenClaw | `brain.mivps.com` |
| `DOMAIN_SYNC` | Dominio para LiveSync | `sync.mivps.com` |
| `COUCHDB_PASSWORD` | Contraseña segura (mín 16 chars) | `MiPass_Segura_2024!` |
| `OPENCLAW_ADMIN_EMAIL` | Email del admin en OpenClaw | `admin@mivps.com` |
| `OPENCLAW_ADMIN_PASSWORD` | Contraseña del admin | `la que pusiste en la UI` |
| `GEMINI_API_KEY` | Google AI API key (opcional, para fallback) | `AIza...` |

```bash
# 3. Correr el setup (hace TODO lo demás)
sudo ./setup.sh
```

---

### PASO 4 — Crear cuenta admin en OpenClaw (primera vez)

Antes de correr `configure-openclaw.sh` o de que el script intente configurar modelos:

```
1. Abrí https://claw.tudominio.com en el browser
2. Hacé click en "Sign up"
3. Creá la cuenta con el email y password que pusiste en .env
   (OPENCLAW_ADMIN_EMAIL / OPENCLAW_ADMIN_PASSWORD)
4. El primer usuario creado es automáticamente administrador
```

Si ya corriste `setup.sh` antes de crear la cuenta, podés volver a ejecutar solo la configuración:

```bash
sudo ./scripts/configure-openclaw.sh /opt/nexus-brain
```

---

### PASO 5 — Configurar Obsidian Self-hosted LiveSync

Este es el único paso que se hace desde tu **dispositivo con Obsidian** (no en el servidor).

```
1. En Obsidian: Configuración → Community plugins → Browser → buscar "Self-hosted LiveSync"
2. Instalar y activar el plugin
3. En la configuración del plugin:

   Remote Database:
     URI:      https://sync.tudominio.com
     Username: admin
     Password: (valor de COUCHDB_PASSWORD en .env)
     Database: obsidian-livesync

4. Hacé click en "Check and fix" → debería decir "Connected"
5. Elegí "Copy setup URI" para compartir la config con otros dispositivos
6. Activá "Sync on startup" y "Sync on file change"
```

> **Importante:** Obsidian escribe los archivos `.md` en CouchDB. El servidor tiene configurado
> un watcher que lee `/opt/nexus-brain/vault/` y lo indexa en la Knowledge Base de OpenClaw.
> Para que funcione el RAG, necesitás que LiveSync esté replicando al filesystem del servidor.

#### Activar replicación filesystem (CouchDB → disco)

LiveSync por defecto solo sincroniza entre dispositivos Obsidian. Para que el watcher de RAG pueda leer las notas, necesitamos que CouchDB replique al filesystem:

```bash
# Instalar obsidian-livesync-bridge (herramienta que escucha cambios en CouchDB y los escribe al disco)
pip install obsidian-livesync-bridge  # si existe en pip

# Alternativa manual: usar el plugin de OpenWebUI con acceso directo a CouchDB
# o apuntar VAULT_PATH directamente al directorio de Obsidian en el servidor
# si sincronizás el vault con un cliente Obsidian corriendo en la VPS
```

> **Nota:** Si no querés complicarte con la bridge, la alternativa más simple es
> configurar un cliente Obsidian en la VPS (via Flatpak o AppImage) y dejar que
> LiveSync sincronice el directorio local. El watcher indexa ese directorio.

---

### PASO 6 — Configurar RAG (Knowledge Base)

Una vez que OpenClaw esté corriendo y el vault tenga notas:

```bash
# 1. Generar API Key en OpenClaw:
#    Settings → Account → API Keys → New API Key → copiá el valor

# 2. Editar .env y agregar la key:
nano /opt/nexus-brain/.env
# Agregar: OPENWEBUI_API_KEY=tu-api-key

# 3. Crear la Knowledge Base:
sudo ./scripts/create-knowledge-base.sh /opt/nexus-brain "Obsidian Vault"
# → Te imprime KNOWLEDGE_ID=xxxxxxxx

# 4. Agregar el KNOWLEDGE_ID al .env:
nano /opt/nexus-brain/.env
# Agregar: KNOWLEDGE_ID=xxxxxxxx

# 5. Instalar el watcher:
sudo ./scripts/install-watcher-service.sh /opt/nexus-brain

# 6. Verificar que esté corriendo:
sudo journalctl -u nexus-vault-watcher -f
```

---

### PASO 7 — Verificar que todo funciona

```bash
# Health check completo
./scripts/health-check.sh /opt/nexus-brain

# Resultado esperado:
# ✔ CouchDB :5984
# ✔ Qdrant :6333
# ✔ Ollama (nativo o Docker) :11434
# ✔ Modelo primario 'gemma4:7b' disponible en Ollama
# ✔ OpenClaw/OpenWebUI host :3000
# ✔ Caddy → claw.tudominio.com
# ✔ Vault en /opt/nexus-brain/vault
# ✔ systemd: nexus-vault-watcher activo
```

---

## Operación del día a día

### Comandos útiles

```bash
# Ver logs del watcher (indexación de notas)
journalctl -u nexus-vault-watcher -f

# Reiniciar el watcher manualmente
systemctl restart nexus-vault-watcher

# Ver estado de todos los servicios Docker
docker compose -f /opt/nexus-brain/docker-compose.yml ps

# Actualizar el proyecto (nuevas features)
cd ~/Jarvis-Argento
git pull
sudo ./setup.sh   # idempotente — aplica cambios sin romper estado

# Indexar el vault manualmente (sin el watcher)
VAULT_PATH=/opt/nexus-brain/vault \
OPENWEBUI_URL=http://127.0.0.1:3000 \
OPENWEBUI_API_KEY=tu-key \
KNOWLEDGE_ID=tu-id \
/opt/nexus-brain/watcher-venv/bin/python /opt/nexus-brain/scripts/vault_watcher.py --once
```

### Puertos y servicios

| Servicio | Puerto | Acceso |
|---|---|---|
| OpenClaw (OpenWebUI) | 3000 | Host → Caddy → HTTPS |
| CouchDB (LiveSync) | 5984 | Host → Caddy → HTTPS |
| Ollama | 11434 | Solo localhost |
| Qdrant | 6333 | Solo localhost |
| Caddy | 80/443 | Público |

---

## Troubleshooting

### Caddy no consigue TLS
```bash
docker logs nexus-caddy
# Si dice "certificate obtained successfully" → OK
# Si dice "timeout" → el DNS todavía no propagó o el puerto 80 está bloqueado
```

### Ollama no descarga gemma4:7b
```bash
# Manual:
docker exec nexus-ollama ollama pull gemma4:7b
# o si Ollama es nativo:
ollama pull gemma4:7b
# La descarga es ~4.5GB — puede tardar según el ancho de banda
```

### LiveSync no conecta
```bash
# Verificar CouchDB desde la PC:
curl https://sync.tudominio.com/
# Debería retornar: {"couchdb":"Welcome","version":"3.x.x",...}

# Verificar CORS (debe estar configurado por setup-couchdb.sh):
curl -v -X OPTIONS https://sync.tudominio.com/obsidian-livesync
# Headers de respuesta deben incluir: Access-Control-Allow-Origin: *
```

### OpenClaw no encuentra Ollama
```bash
# En OpenClaw UI: Settings → Connections → Ollama URL
# Asegurarse que dice: http://127.0.0.1:11434
# Hacé click en "Verify connection" → debería decir "Connected"
```

---

## Variables sensibles — resumen

| Variable | Dónde la obtenés |
|---|---|
| `COUCHDB_PASSWORD` | La inventás vos (mín 16 chars, alfanumérica+símbolos) |
| `GEMINI_API_KEY` | https://aistudio.google.com/apikey → Create API Key |
| `OPENWEBUI_API_KEY` | OpenClaw UI → Settings → Account → API Keys |
| `OPENCLAW_ADMIN_PASSWORD` | La que usaste al crear la cuenta admin en OpenClaw |
| `KNOWLEDGE_ID` | Output del script `create-knowledge-base.sh` |

---

*Generado automáticamente por Nexus Brain setup — $(date +%Y-%m-%d)*
