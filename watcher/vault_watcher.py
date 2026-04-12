#!/usr/bin/env python3
"""
Sincroniza cambios del vault Obsidian con la Knowledge Base de OpenWebUI/OpenClaw.
Variables de entorno (típicamente vía systemd EnvironmentFile):
  VAULT_PATH, OPENWEBUI_URL, OPENWEBUI_API_KEY, KNOWLEDGE_ID
"""
from __future__ import annotations

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


def log(msg: str) -> None:
    print(f"[vault-watcher] {msg}", flush=True)


def upload_file(filepath: str) -> None:
    path = Path(filepath)
    if not path.is_file() or path.suffix.lower() != ".md":
        return
    if ".obsidian" in path.parts:
        return
    if not API_KEY or not KNOWLEDGE_ID:
        log("Falta OPENWEBUI_API_KEY o KNOWLEDGE_ID; no se sube nada.")
        return

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
        return

    if r.status_code == 200:
        log(f"OK {path.name}")
    else:
        log(f"HTTP {r.status_code}: {r.text[:500]}")


def initial_sync() -> None:
    root = Path(VAULT_PATH)
    if not root.is_dir():
        log(f"No existe el vault: {root}")
        return
    log("Sincronización inicial…")
    for md in root.rglob("*.md"):
        if ".obsidian" in md.parts:
            continue
        upload_file(str(md))
    log("Sincronización inicial terminada.")


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
    for line in proc.stdout:
        fp = line.strip()
        if fp.endswith(".md") and ".obsidian" not in fp:
            upload_file(fp)


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] == "--once":
        initial_sync()
        return
    initial_sync()
    watch()


if __name__ == "__main__":
    main()
