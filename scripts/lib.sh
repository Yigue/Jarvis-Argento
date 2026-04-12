#!/usr/bin/env bash
# shellcheck disable=SC2034
# Funciones comunes para scripts de Nexus Brain

die() {
  echo "Error: $*" >&2
  exit 1
}

require_root() {
  [[ "${EUID:-0}" -eq 0 ]] || die "Ejecutá este script con sudo o como root."
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Falta el comando: $1"
}

load_env_file() {
  local f="$1"
  [[ -f "$f" ]] || die "No existe el archivo de entorno: $f"
  set -a
  # shellcheck source=/dev/null
  source "$f"
  set +a
}

nexus_root_from_arg() {
  local r="${1:-}"
  [[ -n "$r" ]] || die "Indicá el directorio de despliegue (p. ej. /opt/nexus-brain)."
  [[ -d "$r" ]] || die "No existe el directorio: $r"
  echo "$r"
}
