#!/usr/bin/env python3
"""
Sincroniza cambios del vault Obsidian con la Knowledge Base de OpenWebUI/OpenClaw.
Variables de entorno (típicamente vía systemd EnvironmentFile):
  VAULT_PATH, OPENWEBUI_URL, OPENWEBUI_API_KEY, KNOWLEDGE_ID

Mejoras respecto a v1:
- Estado persistente en .vault-watcher-state.json (evita re-indexar archivos no cambiados)
- La sincronización inicial solo sube archivos nuevos o modificados desde el último run
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import requests

VAULT_PATH = os.environ.get("VAULT_PATH", "/opt/nexus-brain/vault")
OPENWEBUI_URL = os.environ.get("OPENWEBUI_URL", "http://127.0.0.1:3000").rstrip("/")
API_KEY = os.environ.get("OPENWEBUI_API_KEY", "")
KNOWLEDGE_ID = os.environ.get("KNOWLEDGE_ID", "")
HEADERS = {"Authorization": f"Bearer {API_KEY}"} if API_KEY else {}

# Archivo de estado: guarda {ruta_absoluta: mtime} para detectar cambios entre reinicios
STATE_FILE = Path(VAULT_PATH).parent / ".vault-watcher-state.json"


def log(msg: str) -> None:
    print(f"[vault-watcher] {msg}", flush=True)


def _is_excluded(path: Path) -> bool:
    """Devuelve True si el archivo debe ignorarse."""
    return ".obsidian" in path.parts or path.suffix.lower() != ".md"


# ── Estado persistente ──────────────────────────────────────────────────────


def load_state() -> dict[str, float]:
    """Carga el estado previo de mtime desde disco."""
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text())
        except Exception:
            return {}
    return {}


def save_state(state: dict[str, float]) -> None:
    """Persiste el estado de mtime en disco."""
    try:
        STATE_FILE.write_text(json.dumps(state))
    except Exception as e:
        log(f"No se pudo guardar estado: {e}")


# ── Subida a OpenWebUI ──────────────────────────────────────────────────────


def upload_file(filepath: str) -> bool:
    """
    Sube un archivo .md a la Knowledge Base.
    Devuelve True si tuvo éxito.
    """
    path = Path(filepath)
    if not path.is_file() or _is_excluded(path):
        return False
    if not API_KEY or not KNOWLEDGE_ID:
        log("Falta OPENWEBUI_API_KEY o KNOWLEDGE_ID; no se sube nada.")
        return False

    log(f"Indexando: {path.name}")
    try:
        with path.open("rb") as f:
            files = {"file": (path.name, f, "text/markdown")}
            r = requests.post(
                f"{OPENWEBUI_URL}/api/v1/knowledge/{KNOWLEDGE_ID}/file/add",
                headers=HEADERS,
                files=files,
                timeout=120,
            )
    except requests.RequestException as e:
        log(f"Error de red: {e}")
        return False

    if r.status_code == 200:
        log(f"OK {path.name}")
        return True
    else:
        log(f"HTTP {r.status_code}: {r.text[:500]}")
        return False


# ── Sincronización inicial (incremental) ────────────────────────────────────


def initial_sync() -> None:
    """
    Recorre el vault e indexa solo los archivos nuevos o modificados desde
    el último run (comparando mtime). Evita duplicados en la Knowledge Base.
    """
    root = Path(VAULT_PATH)
    if not root.is_dir():
        log(f"No existe el vault: {root}")
        return

    state = load_state()
    new_state: dict[str, float] = {}
    uploaded = skipped = errors = 0

    log("Sincronización inicial (incremental)…")
    for md in root.rglob("*.md"):
        if _is_excluded(md):
            continue

        key = str(md)
        try:
            mtime = md.stat().st_mtime
        except OSError:
            continue

        if state.get(key) == mtime:
            skipped += 1
            new_state[key] = mtime
            continue

        if upload_file(key):
            new_state[key] = mtime
            uploaded += 1
        else:
            # Conservar mtime anterior para no perder el estado de archivos que ya estaban OK
            if key in state:
                new_state[key] = state[key]
            errors += 1

    # Actualizar estado (unir el anterior con el nuevo para conservar entradas no vistas)
    merged = {**state, **new_state}
    save_state(merged)

    log(f"Sincronización inicial terminada — subidos: {uploaded}, sin cambios: {skipped}, errores: {errors}")


# ── Watcher de cambios en tiempo real ───────────────────────────────────────


def watch() -> None:
    cmd = [
        "inotifywait",
        "-m",
        "-r",
        "-e",
        "close_write,moved_to,create",
        "--format",
        "%w%f",
        VAULT_PATH,
    ]
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True)
    except FileNotFoundError:
        log("inotifywait no encontrado. Instalá: apt install inotify-tools")
        sys.exit(1)

    log(f"Observando: {VAULT_PATH}")
    assert proc.stdout is not None

    state = load_state()

    for line in proc.stdout:
        fp = line.strip()
        path = Path(fp)
        if _is_excluded(path):
            continue

        if upload_file(fp):
            try:
                state[fp] = path.stat().st_mtime
                save_state(state)
            except OSError:
                pass


# ── Entrypoint ───────────────────────────────────────────────────────────────


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] == "--once":
        initial_sync()
        return
    initial_sync()
    watch()


if __name__ == "__main__":
    main()
