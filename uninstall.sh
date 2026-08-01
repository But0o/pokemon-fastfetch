#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Pokémon Fastfetch
#
# Project uninstaller.
#
# Responsibilities:
#   - Remove installed scripts
#   - Remove Fish integration
#   - Optionally remove cache
#   - Optionally remove backups
#
# Copyright (c) 2026 But0o
# Licensed under the MIT License.
#
# Shell:
#   Bash 5.0+
#
# Repository:
#   https://github.com/But0o/pokemon-fastfetch
# -----------------------------------------------------------------------------

APP_NAME="pokemon-fastfetch"
INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/$APP_NAME"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$APP_NAME"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/$APP_NAME"
BACKUP_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/${APP_NAME}-backups"
FISH_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/${APP_NAME}.fish"

ASSUME_YES=false
REMOVE_CACHE=false
REMOVE_BACKUPS=false

confirm() {
  if [[ "$ASSUME_YES" == true ]]; then return 0; fi
  read -r -p "$1 [S/n]: " a
  case "${a:-S}" in s|S|si|SI|sí|Sí|y|Y|yes|YES) return 0;; *) return 1;; esac
}

usage() {
cat <<EOF
Uso: ./uninstall.sh [opciones]

  --yes              No pedir confirmación
  --remove-cache     Eliminar la caché
  --remove-backups   Eliminar respaldos
  -h,--help          Ayuda
EOF
}

while (($#)); do
 case "$1" in
   --yes|-y) ASSUME_YES=true;;
   --remove-cache) REMOVE_CACHE=true;;
   --remove-backups) REMOVE_BACKUPS=true;;
   -h|--help) usage; exit 0;;
   *) echo "Opción desconocida: $1"; exit 1;;
 esac
 shift
done

confirm "¿Desinstalar Pokémon Fastfetch?" || exit 0

rm -rf "$INSTALL_DIR"
rm -rf "$CONFIG_DIR"
rm -f "$FISH_CONFIG_FILE"

if [[ "$REMOVE_CACHE" == true ]]; then
  rm -rf "$CACHE_DIR"
fi

if [[ "$REMOVE_BACKUPS" == true ]]; then
  rm -rf "$BACKUP_ROOT"
fi

echo
echo "Desinstalación completada."
echo
echo "Se eliminaron:"
echo "  $INSTALL_DIR"
echo "  $CONFIG_DIR"
echo "  $FISH_CONFIG_FILE"

[[ "$REMOVE_CACHE" == true ]] && echo "  $CACHE_DIR"
[[ "$REMOVE_BACKUPS" == true ]] && echo "  $BACKUP_ROOT"

echo
echo "Abrí una nueva terminal para aplicar los cambios."
