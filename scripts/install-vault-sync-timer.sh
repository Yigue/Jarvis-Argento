#!/usr/bin/env bash
# Instala el servicio + timer systemd para sincronizar el vault Obsidian desde Git cada 30 minutos.
# Uso: sudo ./scripts/install-vault-sync-timer.sh /opt/nexus-brain
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
require_cmd systemctl

NEXUS_ROOT="$(nexus_root_from_arg "${1:-}")"
load_env_file "$NEXUS_ROOT/.env"

[[ -n "${VAULT_GIT_URL:-}" ]] || die "Definí VAULT_GIT_URL en $NEXUS_ROOT/.env"

SERVICE_SRC="$REPO_ROOT/systemd/nexus-vault-sync.service"
TIMER_SRC="$REPO_ROOT/systemd/nexus-vault-sync.timer"

[[ -f "$SERVICE_SRC" ]] || die "No existe $SERVICE_SRC"
[[ -f "$TIMER_SRC" ]]   || die "No existe $TIMER_SRC"

# Reemplazar /opt/nexus-brain con el NEXUS_ROOT real si es diferente
tmp_service="$(mktemp)"
tmp_timer="$(mktemp)"
sed "s|/opt/nexus-brain|${NEXUS_ROOT}|g" "$SERVICE_SRC" >"$tmp_service"
sed "s|/opt/nexus-brain|${NEXUS_ROOT}|g" "$TIMER_SRC"   >"$tmp_timer"

install -m 0644 "$tmp_service" /etc/systemd/system/nexus-vault-sync.service
install -m 0644 "$tmp_timer"   /etc/systemd/system/nexus-vault-sync.timer
rm -f "$tmp_service" "$tmp_timer"

systemctl daemon-reload
systemctl enable nexus-vault-sync.timer
systemctl start nexus-vault-sync.timer

echo "[vault-sync-timer] Timer nexus-vault-sync activo (cada 30 min)"
echo "[vault-sync-timer] Para sync manual: systemctl start nexus-vault-sync.service"
echo "[vault-sync-timer] Logs: journalctl -u nexus-vault-sync -f"
systemctl --no-pager status nexus-vault-sync.timer || true
