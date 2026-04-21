# 🧠 Jarvis-Argento — Deployment & Setup Status

> **Analysis Date:** April 2026
> **Focus:** LiveSync, OpenClaw (OpenWebUI), Obsidian Vault, Production Readiness

## 1. Executive Summary & Stack Readiness

The entire stack is **production-ready** for deployment on a VPS. The infrastructure is orchestrated through a combination of Docker Compose (for supporting services) and native/systemd services (for OpenWebUI and the Vault Watcher). 

### Current State of the Stack
- **Obsidian LiveSync:** Fully configured via `CouchDB`. The `.env` template handles the `COUCHDB_PASSWORD` and `Caddy` provides automatic HTTPS via `DOMAIN_SYNC`.
- **OpenWebUI (OpenClaw):** Designed to run on the host via `pip install open-webui` (or uvicorn/Docker). It's listening on port `3000` locally, proxied to the internet via Caddy at HTTPS `DOMAIN_CLAW`.
- **Obsidian Vault (RAG):** The connection between Obsidian (LiveSync) and OpenWebUI's RAG system is handled by a custom `watcher/vault_watcher.py` script. It monitors the vault filesystem (`/opt/nexus-brain/vault/`), does incremental syncs based on `mtime`, and automatically pushes Markdown updates to the OpenWebUI Knowledge Base using the `OPENWEBUI_API_KEY` and `KNOWLEDGE_ID`.

---

## 2. Endpoints & Required Credentials Tracker

Before running the final setup, you MUST populate the `.env` file from the `.env.example`. Here is the required tracker for your deployment:

### 🌐 Endpoints
| Service | Internal | Public URL | Purpose |
|---------|----------|------------|---------|
| **OpenClaw (UI)** | `http://127.0.0.1:3000` | `https://claw.tudominio.com` | RAG Chat Interface |
| **LiveSync (CouchDB)** | `http://127.0.0.1:5984` | `https://sync.tudominio.com` | Obsidian Sync Target |
| **Ollama** | `http://127.0.0.1:11434` | *Not Exposed* | Local LLM inference |
| **Qdrant** | `http://127.0.0.1:6333` | *Not Exposed* | Vector Database |

### 🔐 Credentials Checklist (to add in `/opt/nexus-brain/.env`)
- [ ] `DOMAIN_CLAW`: e.g., `brain.mivps.com`
- [ ] `DOMAIN_SYNC`: e.g., `sync.mivps.com`
- [ ] `COUCHDB_PASSWORD`: (Generate a secure 16+ char password)
- [ ] `OPENCLAW_ADMIN_EMAIL`: Your login email for OpenWebUI.
- [ ] `OPENCLAW_ADMIN_PASSWORD`: Your login password for OpenWebUI.
- [ ] `OPENWEBUI_API_KEY`: (Generated inside OpenWebUI after step 3 below).
- [ ] `KNOWLEDGE_ID`: (Generated automatically via `create-knowledge-base.sh`).

---

## 3. Step-by-Step Production Deployment Guide

Follow these steps strictly to bring the system online.

### Step 1: Initialize Dependencies
Clone your repo on the VPS, then run the preparation script to install Docker, curl, jq, and OS packages:
```bash
git clone https://github.com/Yigue/Jarvis-Argento.git /root/Jarvis-Argento
cd /root/Jarvis-Argento
sudo ./scripts/install.sh --install-deps
```

### Step 2: Configure Environment and Boot Support Services
Copy `.env.example` to `/opt/nexus-brain/.env` and edit it:
```bash
sudo cp .env.example /opt/nexus-brain/.env
sudo nano /opt/nexus-brain/.env
```
Start the base stack (Caddy, CouchDB, Ollama, Qdrant):
```bash
sudo ./scripts/install.sh --skip-ollama # if using native Ollama
# OR
sudo ./scripts/install.sh # if using Dockerized Ollama
```

### Step 3: Install & Configure OpenWebUI (OpenClaw)
Since OpenWebUI runs on the host to access `host.docker.internal` easily:
```bash
pip install open-webui
# Setup the systemd service as detailed in SERVIDOR-SETUP.md
sudo systemctl enable --now nexus-openclaw
```
1. Go to `https://claw.tudominio.com`.
2. Click **Sign up** using the exact credentials specified in your `.env` (`OPENCLAW_ADMIN_EMAIL`).
3. Generate an API Key under Settings -> Account -> API Keys.
4. Save the key in `/opt/nexus-brain/.env` as `OPENWEBUI_API_KEY`.

### Step 4: Vault & RAG Integration Setup
With OpenWebUI running and your API Key stored, create the Knowledge Base:
```bash
sudo ./scripts/create-knowledge-base.sh /opt/nexus-brain "Obsidian Vault"
```
*Note the output `KNOWLEDGE_ID` and save it to your `.env`.*

Finally, install and start the Python watcher that pipes Markdown files to openwebui:
```bash
sudo ./scripts/install-watcher-service.sh /opt/nexus-brain
sudo systemctl status nexus-vault-watcher
```

### Step 5: Connect Obsidian
In your local Obsidian client:
1. Install plugin: **Self-hosted LiveSync**.
2. Remote URI: `https://sync.tudominio.com`
3. Username: `admin`
4. Password: `<COUCHDB_PASSWORD>`
5. DB: `obsidian-livesync`
6. Click **Check and Fix** to verify the connection.

---
> **Status:** ✅ VERIFIED. The Caddyfile templates, environment loading routines, and vault indexer scripts have been audited. The environment is safe to deploy.
