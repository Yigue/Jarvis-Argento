#!/usr/bin/env bash
# Instala la unidad systemd del vault-watcher (tras definir KNOWLEDGE_ID y OPENWEBUI_API_KEY en .env).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
require_cmd systemctl

NEXUS_ROOT="$(nexus_root_from_arg "${1:-}")"
load_env_file "$NEXUS_ROOT/.env"

[[ -n "${KNOWLEDGE_ID:-}" ]] || die "Definí KNOWLEDGE_ID en $NEXUS_ROOT/.env"
[[ -n "${OPENWEBUI_API_KEY:-}" ]] || die "Definí OPENWEBUI_API_KEY en $NEXUS_ROOT/.env"

UNIT_SRC="$REPO_ROOT/systemd/nexus-vault-watcher.service"
[[ -f "$UNIT_SRC" ]] || die "No existe $UNIT_SRC"

tmp_unit="$(mktemp)"
sed "s|/opt/nexus-brain|${NEXUS_ROOT}|g" "$UNIT_SRC" >"$tmp_unit"
install -m 0644 "$tmp_unit" /etc/systemd/system/nexus-vault-watcher.service
rm -f "$tmp_unit"
systemctl daemon-reload
systemctl enable nexus-vault-watcher.service
systemctl restart nexus-vault-watcher.service
systemctl --no-pager status nexus-vault-watcher.service || true
echo "Servicio nexus-vault-watcher activo. Logs: journalctl -u nexus-vault-watcher -f"
