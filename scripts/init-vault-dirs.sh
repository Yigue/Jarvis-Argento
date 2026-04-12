#!/usr/bin/env bash
# Crea la estructura de carpetas sugerida para el vault Obsidian.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

VAULT="${1:-}"
OWNER="${2:-}"

[[ -n "$VAULT" ]] || die "Uso: $0 /ruta/al/vault [usuario_propietario]"

install -d -m 0755 "$VAULT"/{"00 Inbox","01 Daily","02 Architecture","03 RAG Research","04 Product","05 DevOps","06 Career","99 Archive"}

if [[ -n "$OWNER" && "$OWNER" != root ]]; then
  chown -R "$OWNER:$OWNER" "$VAULT" 2>/dev/null || true
fi

echo "Estructura de vault creada en: $VAULT"
