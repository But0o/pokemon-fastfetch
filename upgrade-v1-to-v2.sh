#!/usr/bin/env bash

set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Pokémon Fastfetch
#
# Migration utility.
#
# Responsibilities:
#   - Detect previous installations
#   - Create safety backups
#   - Preserve user data
#   - Delegate installation to install.sh
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

SOURCE_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd
)"

COMMON_LIBRARY="$SOURCE_DIR/lib/common.sh"
INSTALLER="$SOURCE_DIR/install.sh"

INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/$APP_NAME"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$APP_NAME"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/$APP_NAME"
BACKUP_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/${APP_NAME}-backups"

FISH_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fish"
FISH_MAIN_CONFIG="$FISH_CONFIG_DIR/config.fish"
FISH_INTEGRATION_FILE="$FISH_CONFIG_DIR/conf.d/${APP_NAME}.fish"

ASSUME_YES=false

# ────────────────────────────────────────────────────────────────
# Cargar biblioteca común
# ────────────────────────────────────────────────────────────────

if [[ ! -r "$COMMON_LIBRARY" ]]; then
    printf '[ERROR] No se encontró la biblioteca común: %s\n' \
        "$COMMON_LIBRARY" >&2
    exit 1
fi

# shellcheck source=lib/common.sh
source "$COMMON_LIBRARY"

# ────────────────────────────────────────────────────────────────
# Versión
# ────────────────────────────────────────────────────────────────

if [[ -r "$SOURCE_DIR/VERSION" ]]; then
    APP_VERSION="$(
        tr -d '[:space:]' < "$SOURCE_DIR/VERSION"
    )"
else
    APP_VERSION="0.0.0-unknown"
fi

if [[ -z "$APP_VERSION" ]]; then
    APP_VERSION="0.0.0-unknown"
fi

# ────────────────────────────────────────────────────────────────
# Ayuda
# ────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Actualizador de Pokémon Fastfetch → v${APP_VERSION}

Uso:
  ./upgrade-v1-to-v2.sh [opciones]

Opciones:
  --yes, -y
      Acepta automáticamente las confirmaciones.

  --no-autostart
      No ejecuta Pokémon Fastfetch al abrir Kitty.

  --pokemon-dir RUTA
      Indica manualmente la carpeta de imágenes.

  --help, -h
      Muestra esta ayuda.

Ejemplos:
  ./upgrade-v1-to-v2.sh
  ./upgrade-v1-to-v2.sh --yes
  ./upgrade-v1-to-v2.sh --pokemon-dir "\$HOME/pokimg/images"
EOF
}

# ────────────────────────────────────────────────────────────────
# Argumentos propios
# ────────────────────────────────────────────────────────────────

inspect_arguments() {
    local argument=""

    for argument in "$@"; do
        case "$argument" in
            --yes|-y)
                ASSUME_YES=true
                ;;

            --help|-h)
                usage
                exit 0
                ;;
        esac
    done
}

confirm_upgrade() {
    local reply=""

    if [[ "$ASSUME_YES" == "true" ]]; then
        return 0
    fi

    read -r -p \
        "¿Actualizar Pokémon Fastfetch a v${APP_VERSION}? [S/n]: " \
        reply

    case "${reply:-S}" in
        s|S|si|SI|sí|Sí|y|Y|yes|YES)
            return 0
            ;;

        *)
            return 1
            ;;
    esac
}

# ────────────────────────────────────────────────────────────────
# Instalaciones antiguas
# ────────────────────────────────────────────────────────────────

legacy_paths() {
    local candidates=(
        "$HOME/Pokemon-FastFetch"
        "$HOME/Descargas/Script_pokemon"
        "$HOME/Downloads/Script_pokemon"
        "$HOME/.local/share/pokemon-fastfetch"
    )

    local candidate=""

    for candidate in "${candidates[@]}"; do
        [[ -d "$candidate" ]] || continue

        if [[ "$candidate" == "$SOURCE_DIR" ]]; then
            continue
        fi

        printf '%s\n' "$candidate"
    done
}

has_previous_installation() {
    [[ -d "$INSTALL_DIR" ]] ||
        [[ -d "$CONFIG_DIR" ]] ||
        [[ -f "$FISH_INTEGRATION_FILE" ]] ||
        [[ -n "$(legacy_paths)" ]]
}

# ────────────────────────────────────────────────────────────────
# Respaldo
# ────────────────────────────────────────────────────────────────

create_backup() {
    local timestamp=""
    local backup_dir=""
    local legacy_path=""
    local copied_anything=false
    local legacy_number=0

    timestamp="$(date +'%Y-%m-%d_%H-%M-%S')"
    backup_dir="$BACKUP_ROOT/$timestamp"

    mkdir -p "$backup_dir"

    while IFS= read -r legacy_path; do
        [[ -n "$legacy_path" ]] || continue

        legacy_number=$((legacy_number + 1))

        cp -a \
            "$legacy_path" \
            "$backup_dir/legacy-${legacy_number}-$(basename "$legacy_path")"

        copied_anything=true
    done < <(legacy_paths)

    if [[ -d "$INSTALL_DIR" && "$INSTALL_DIR" != "$SOURCE_DIR" ]]; then
        cp -a "$INSTALL_DIR" "$backup_dir/current-install"
        copied_anything=true
    fi

    if [[ -d "$CONFIG_DIR" ]]; then
        cp -a "$CONFIG_DIR" "$backup_dir/current-config"
        copied_anything=true
    fi

    if [[ -f "$FISH_INTEGRATION_FILE" ]]; then
        mkdir -p "$backup_dir/fish"
        cp -a "$FISH_INTEGRATION_FILE" "$backup_dir/fish/"
        copied_anything=true
    fi

    if [[ -f "$FISH_MAIN_CONFIG" ]]; then
        mkdir -p "$backup_dir/fish"
        cp -a "$FISH_MAIN_CONFIG" "$backup_dir/fish/config.fish"
        copied_anything=true
    fi

    if [[ "$copied_anything" == "true" ]]; then
        pf_success "Respaldo creado en: $backup_dir"
    else
        rmdir "$backup_dir" 2>/dev/null || true
        pf_info "No había archivos anteriores para respaldar."
    fi
}

# ────────────────────────────────────────────────────────────────
# Migración de la Pokédex
# ────────────────────────────────────────────────────────────────

migrate_legacy_cache() {
    local destination="$CACHE_DIR/pokedex.json"
    local candidate=""
    local candidates=(
        "$CACHE_DIR/pokedex.json"
        "$HOME/.cache/pokemon-fastfetch/pokedex.json"
        "$HOME/Descargas/Script_pokemon/pokedex.json"
        "$HOME/Downloads/Script_pokemon/pokedex.json"
        "$HOME/Pokemon-FastFetch/pokedex.json"
        "$HOME/Pokemon-FastFetch/cache/pokedex.json"
    )

    mkdir -p "$CACHE_DIR"

    for candidate in "${candidates[@]}"; do
        [[ -s "$candidate" ]] || continue

        if ! jq empty "$candidate" >/dev/null 2>&1; then
            pf_warn "Se ignoró una Pokédex inválida: $candidate"
            continue
        fi

        if [[ "$candidate" != "$destination" ]]; then
            cp -f "$candidate" "$destination"
        fi

        pf_success "Pokédex anterior conservada desde: $candidate"
        return 0
    done

    pf_info "No se encontró una Pokédex anterior válida."
    pf_info "El instalador utilizará config/pokedex.json."
}

# ────────────────────────────────────────────────────────────────
# Limpiar configuración antigua de Fish
# ────────────────────────────────────────────────────────────────

remove_legacy_fish_blocks() {
    [[ -f "$FISH_MAIN_CONFIG" ]] || return 0

    sed -i \
        -e '/Script_pokemon.*random-fastfetch\.sh/d' \
        -e '/Pokemon-FastFetch.*random-fastfetch\.sh/d' \
        -e '/pokemon-fastfetch.*random-fastfetch\.sh/d' \
        -e '/set -g POKEMON_FASTFETCH_SCRIPT/d' \
        "$FISH_MAIN_CONFIG"

    pf_success "Referencias antiguas eliminadas de config.fish."
}

# ────────────────────────────────────────────────────────────────
# Validaciones
# ────────────────────────────────────────────────────────────────

validate_source() {
    pf_require_file "$INSTALLER" "El instalador"
    pf_require_executable "$INSTALLER" "El instalador"

    pf_require_json \
        "$SOURCE_DIR/config/pokedex.json" \
        "La Pokédex incluida"

    pf_require_commands \
        bash \
        jq \
        cp \
        date \
        mkdir \
        sed \
        tr

    bash -n "$INSTALLER" ||
        pf_die "El instalador contiene errores de sintaxis."

    bash -n "$COMMON_LIBRARY" ||
        pf_die "La biblioteca común contiene errores de sintaxis."
}

# ────────────────────────────────────────────────────────────────
# Ejecución
# ────────────────────────────────────────────────────────────────

main() {
    inspect_arguments "$@"
    validate_source

    printf 'Actualización Pokémon Fastfetch → v%s\n\n' \
        "$APP_VERSION"

    if has_previous_installation; then
        pf_info "Se detectó una instalación anterior."
    else
        pf_warn "No se detectó una instalación anterior."
        pf_warn "El proceso continuará como una instalación limpia."
    fi

    confirm_upgrade ||
        pf_die "Actualización cancelada."

    create_backup
    migrate_legacy_cache
    remove_legacy_fish_blocks

    pf_info "Ejecutando el instalador actual..."

    bash "$INSTALLER" "$@"

    printf '\n'
    pf_success "Migración completada correctamente."
}

main "$@"