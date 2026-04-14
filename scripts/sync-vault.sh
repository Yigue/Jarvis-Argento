#!/usr/bin/env bash
# Clona o sincroniza el Obsidian Vault desde el repositorio Git configurado.
# Uso: sudo ./scripts/sync-vault.sh /opt/nexus-brain
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

NEXUS_ROOT="$(nexus_root_from_arg "${1:-}")"
load_env_file "$NEXUS_ROOT/.env"

VAULT_GIT_URL="${VAULT_GIT_URL:-}"
VAULT_GIT_BRANCH="${VAULT_GIT_BRANCH:-main}"
VAULT_PATH="${VAULT_PATH:-$NEXUS_ROOT/vault}"

[[ -n "$VAULT_GIT_URL" ]] || die "Definí VAULT_GIT_URL en ${NEXUS_ROOT}/.env (ej: https://github.com/user/Obsidian-Vault.git)"

require_cmd git

echo "[vault-sync] URL: $VAULT_GIT_URL"
echo "[vault-sync] Branch: $VAULT_GIT_BRANCH"
echo "[vault-sync] Destino: $VAULT_PATH"

if [[ ! -d "$VAULT_PATH/.git" ]]; then
  echo "[vault-sync] Clonando por primera vez..."
  # Si el directorio existe pero no es un repo git, lo limpiamos primero
  if [[ -d "$VAULT_PATH" ]] && [[ -n "$(ls -A "$VAULT_PATH" 2>/dev/null)" ]]; then
    echo "[vault-sync] Directorio no vacío sin .git — respaldando en ${VAULT_PATH}.bak"
    mv "$VAULT_PATH" "${VAULT_PATH}.bak.$(date +%Y%m%d%H%M%S)"
  fi
  git clone \
    --branch "$VAULT_GIT_BRANCH" \
    --depth 1 \
    "$VAULT_GIT_URL" \
    "$VAULT_PATH"
  echo "[vault-sync] Clone completo"
else
  echo "[vault-sync] Repo ya existe, actualizando (git pull --ff-only)..."
  git -C "$VAULT_PATH" fetch origin "$VAULT_GIT_BRANCH" --depth 1
  git -C "$VAULT_PATH" reset --hard "origin/$VAULT_GIT_BRANCH"
  echo "[vault-sync] Pull completo"
fi

# Ajustar permisos si se ejecuta como root (heredar el usuario sudo)
if [[ "${EUID:-0}" -eq 0 && -n "${SUDO_USER:-}" ]]; then
  chown -R "${SUDO_USER}:${SUDO_USER}" "$VAULT_PATH" 2>/dev/null || true
fi

# Conteo de notas como diagnóstico rápido
MD_COUNT=$(find "$VAULT_PATH" -name "*.md" ! -path "*/.obsidian/*" 2>/dev/null | wc -l)
echo "[vault-sync] Notas Markdown en el vault: $MD_COUNT"
echo "[vault-sync] Vault listo en: $VAULT_PATH"
