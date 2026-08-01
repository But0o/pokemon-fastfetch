#!/usr/bin/env bash

set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Pokémon Fastfetch
#
# Project installer.
#
# Responsibilities:
#   - Validate the repository layout
#   - Check runtime dependencies
#   - Install scripts and shared libraries
#   - Generate the user configuration
#   - Install the bundled Pokédex
#   - Configure Fish shell integration
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

if [[ ! -r "$COMMON_LIBRARY" ]]; then
    printf '[ERROR] No se encontró la biblioteca común: %s\n' \
        "$COMMON_LIBRARY" >&2
    exit 1
fi

# shellcheck source=lib/common.sh
source "$COMMON_LIBRARY"

VERSION_FILE="$SOURCE_DIR/VERSION"

if [[ -r "$VERSION_FILE" ]]; then
    APP_VERSION="$(
        tr -d '[:space:]' < "$VERSION_FILE"
    )"
else
    APP_VERSION="0.0.0-unknown"
fi

if [[ -z "$APP_VERSION" ]]; then
    APP_VERSION="0.0.0-unknown"
fi

INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/$APP_NAME"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$APP_NAME"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/$APP_NAME"
BACKUP_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/${APP_NAME}-backups"

FISH_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d"
FISH_CONFIG_FILE="$FISH_CONFIG_DIR/${APP_NAME}.fish"

POKEMON_DIR_OVERRIDE=""
ASSUME_YES=false
ENABLE_AUTOSTART=true

RESET=$'\033[0m'
BOLD=$'\033[1m'


usage() {
    cat <<EOF
Pokémon Fastfetch installer v${APP_VERSION}

Uso:
  ./install.sh [opciones]

Opciones:
  --yes, -y                  Acepta automáticamente las preguntas.
  --no-autostart             No ejecuta Pokémon Fastfetch al abrir Kitty.
  --pokemon-dir RUTA         Indica manualmente la carpeta de imágenes.
  --help, -h                 Muestra esta ayuda.

Ejemplos:
  ./install.sh
  ./install.sh --yes
  ./install.sh --pokemon-dir "\$HOME/pokimg/images"
  ./install.sh --no-autostart
EOF
}


confirm() {
    local prompt="$1"
    local reply=""

    if [[ "$ASSUME_YES" == "true" ]]; then
        return 0
    fi

    read -r -p "$prompt [S/n]: " reply
    case "${reply:-S}" in
        s|S|si|SI|sí|Sí|y|Y|yes|YES)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

expand_path() {
    local value="${1:-}"

    # shellcheck disable=SC2088
    case "$value" in
        "~")
            printf '%s\n' "$HOME"
            ;;
        "~/"*)
            printf '%s/%s\n' "$HOME" "${value#\~/}"
            ;;
        *)
            printf '%s\n' "$value"
            ;;
    esac
}
contains_image_files() {
    local directory="$1"

    [[ -d "$directory" ]] || return 1

    find "$directory" \
        -maxdepth 3 \
        -type f \
        \( -iname '*.png' -o -iname '*.webp' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' \) \
        -print -quit 2>/dev/null |
        grep -q .
}

find_pokemon_dir() {
    local candidate=""
    local candidates=()

    if [[ -n "$POKEMON_DIR_OVERRIDE" ]]; then
        candidates+=("$(expand_path "$POKEMON_DIR_OVERRIDE")")
    fi

    candidates+=(
        "$HOME/.local/share/pokimg/images"
        "$HOME/pokimg/images"
        "$HOME/.local/share/pokimg"
        "$HOME/pokimg"
    )

    for candidate in "${candidates[@]}"; do
        [[ -n "$candidate" ]] || continue

        if contains_image_files "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

check_project_files() {
    local required_files=(
        "random-fastfetch.sh"
        "render-pokemon.sh"
        "build-pokedex-cache.sh"
        "config/pokedex.json"
        "lib/common.sh"
        "VERSION"
    )

    local file=""

    for file in "${required_files[@]}"; do
        [[ -f "$SOURCE_DIR/$file" ]] ||
            pf_die "Falta '$file' en el repositorio: $SOURCE_DIR"
    done
}

check_script_syntax() {
    local scripts=(
        "$SOURCE_DIR/random-fastfetch.sh"
        "$SOURCE_DIR/render-pokemon.sh"
        "$SOURCE_DIR/build-pokedex-cache.sh"
        "$SOURCE_DIR/lib/common.sh"
    )

    local script=""

    for script in "${scripts[@]}"; do
        bash -n "$script" ||
            pf_die "Error de sintaxis en: $script"
    done
}

check_pokedex_file() {
    local pokedex_file="$SOURCE_DIR/config/pokedex.json"

    [[ -s "$pokedex_file" ]] ||
        pf_die "La Pokédex del repositorio está vacía: $pokedex_file"

    jq empty "$pokedex_file" >/dev/null 2>&1 ||
        pf_die "La Pokédex del repositorio contiene un JSON inválido: $pokedex_file"

    pf_success "Pokédex del repositorio validada."
}

check_dependencies() {
    local required=(
        bash
        jq
        awk
        sed
        grep
        find
        shuf
        tput
        df
        uname
        hostname
        stat
        date
        tr
        mv
        fc-match
        kitten
    )

    local optional=(
        magick
        convert
        hyprctl
        ip
        lspci
        lscpu
        pacman
        fish
    )

    local missing=()
    local command=""

    for command in "${required[@]}"; do
        if ! pf_command_exists "$command"; then
            missing+=("$command")
        fi
    done

    if ! pf_command_exists magick && ! pf_command_exists convert; then
        missing+=("imagemagick")
    fi

    if ((${#missing[@]} > 0)); then
        printf '\n'
        pf_warn "Faltan dependencias obligatorias:"
        printf '  - %s\n' "${missing[@]}"
        printf '\n'

        if pf_command_exists pacman; then
            printf 'En Arch/CachyOS podés instalar las principales con:\n\n'
            printf '  sudo pacman -S --needed jq imagemagick kitty fish fontconfig pciutils iproute2\n\n'
        fi

        pf_die "Instalá las dependencias faltantes y ejecutá nuevamente el instalador."
    fi

    for command in "${optional[@]}"; do
        if ! pf_command_exists "$command"; then
            pf_warn "Dependencia opcional no encontrada: $command"
        fi
    done
}

backup_existing_installation() {
    local timestamp=""
    local backup_dir=""

    if [[ ! -e "$INSTALL_DIR" && ! -e "$CONFIG_DIR" && ! -e "$FISH_CONFIG_FILE" ]]; then
        return 0
    fi

    if ! confirm "Se encontró una instalación existente. ¿Crear respaldo y continuar?"; then
        pf_die "Instalación cancelada."
    fi

    timestamp="$(date +'%Y-%m-%d_%H-%M-%S')"
    backup_dir="$BACKUP_ROOT/$timestamp"

    mkdir -p "$backup_dir"

    if [[ -e "$INSTALL_DIR" ]]; then
        cp -a "$INSTALL_DIR" "$backup_dir/install"
    fi

    if [[ -e "$CONFIG_DIR" ]]; then
        cp -a "$CONFIG_DIR" "$backup_dir/config"
    fi

    if [[ -e "$FISH_CONFIG_FILE" ]]; then
        mkdir -p "$backup_dir/fish"
        cp -a "$FISH_CONFIG_FILE" "$backup_dir/fish/"
    fi

    pf_success "Respaldo creado en: $backup_dir"
}

copy_project_files() {
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/lib"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$CACHE_DIR"

    install -m 0755 \
        "$SOURCE_DIR/random-fastfetch.sh" \
        "$INSTALL_DIR/random-fastfetch.sh"

    install -m 0755 \
        "$SOURCE_DIR/render-pokemon.sh" \
        "$INSTALL_DIR/render-pokemon.sh"

    install -m 0755 \
        "$SOURCE_DIR/build-pokedex-cache.sh" \
        "$INSTALL_DIR/build-pokedex-cache.sh"

    install -m 0755 \
        "$SOURCE_DIR/uninstall.sh" \
        "$INSTALL_DIR/uninstall.sh"

    install -m 0644 \
        "$SOURCE_DIR/lib/common.sh" \
        "$INSTALL_DIR/lib/common.sh"

    install -m 0644 \
        "$SOURCE_DIR/VERSION" \
        "$INSTALL_DIR/VERSION"

    if [[ -f "$SOURCE_DIR/LICENSE" ]]; then
        install -m 0644 \
            "$SOURCE_DIR/LICENSE" \
            "$INSTALL_DIR/LICENSE"
    fi

    pf_success "Scripts instalados en: $INSTALL_DIR"
}

write_config() {
    local pokemon_dir="$1"
    local config_file="$CONFIG_DIR/config"
    local temporary_file="$CONFIG_DIR/config.tmp"

    local panel_width="1580"
    local panel_height="470"
    local panel_rows="22"
    local system_max_width="150"
    local column_gap="6"
    local show_system_info="true"
    local show_color_palette="true"

    if [[ -r "$config_file" ]]; then
        # Leemos únicamente las opciones visuales conocidas.
        # Las rutas se regeneran siempre para evitar valores antiguos.
        panel_width="$(
            awk -F= '
                $1 == "POKEMON_PANEL_WIDTH" {
                    print substr($0, index($0, "=") + 1)
                    exit
                }
            ' "$config_file"
        )"

        panel_height="$(
            awk -F= '
                $1 == "POKEMON_PANEL_HEIGHT" {
                    print substr($0, index($0, "=") + 1)
                    exit
                }
            ' "$config_file"
        )"

        panel_rows="$(
            awk -F= '
                $1 == "POKEMON_PANEL_ROWS" {
                    print substr($0, index($0, "=") + 1)
                    exit
                }
            ' "$config_file"
        )"

        system_max_width="$(
            awk -F= '
                $1 == "SYSTEM_PANEL_MAX_WIDTH" {
                    print substr($0, index($0, "=") + 1)
                    exit
                }
            ' "$config_file"
        )"

        column_gap="$(
            awk -F= '
                $1 == "COLUMN_GAP" {
                    print substr($0, index($0, "=") + 1)
                    exit
                }
            ' "$config_file"
        )"

        show_system_info="$(
            awk -F= '
                $1 == "SHOW_SYSTEM_INFO" {
                    print substr($0, index($0, "=") + 1)
                    exit
                }
            ' "$config_file"
        )"

        show_color_palette="$(
            awk -F= '
                $1 == "SHOW_COLOR_PALETTE" {
                    print substr($0, index($0, "=") + 1)
                    exit
                }
            ' "$config_file"
        )"

        panel_width="${panel_width:-1580}"
        panel_height="${panel_height:-470}"
        panel_rows="${panel_rows:-22}"
        system_max_width="${system_max_width:-150}"
        column_gap="${column_gap:-6}"
        show_system_info="${show_system_info:-true}"
        show_color_palette="${show_color_palette:-true}"
    fi

    cat > "$temporary_file" <<EOF
# Pokémon Fastfetch ${APP_VERSION}
# Archivo administrado por install.sh

# Rutas
POKEMON_DIR=$(printf '%q' "$pokemon_dir")
CACHE_DIR=$(printf '%q' "$CACHE_DIR")
INSTALL_DIR=$(printf '%q' "$INSTALL_DIR")

# Panel Pokémon
POKEMON_PANEL_WIDTH=$panel_width
POKEMON_PANEL_HEIGHT=$panel_height
POKEMON_PANEL_ROWS=$panel_rows

# Panel del sistema
SYSTEM_PANEL_MAX_WIDTH=$system_max_width
COLUMN_GAP=$column_gap

# Opciones visuales
SHOW_SYSTEM_INFO=$show_system_info
SHOW_COLOR_PALETTE=$show_color_palette
EOF

    chmod 0600 "$temporary_file"
    mv -f "$temporary_file" "$config_file"

    pf_success "Configuración actualizada: $config_file"
}

ensure_pokedex_cache() {
    local source_cache=""
    local destination_cache="$CACHE_DIR/pokedex.json"

    local cache_candidates=(
        "$CACHE_DIR/pokedex.json"
        "$SOURCE_DIR/config/pokedex.json"
        "$SOURCE_DIR/cache/pokedex.json"
        "$SOURCE_DIR/pokedex.json"
    )
  

    local candidate=""

    for candidate in "${cache_candidates[@]}"; do
        if [[ -s "$candidate" ]] && jq empty "$candidate" >/dev/null 2>&1; then
            source_cache="$candidate"
            break
        fi
    done

    if [[ -n "$source_cache" && "$source_cache" != "$destination_cache" ]]; then
        cp -f "$source_cache" "$destination_cache"
        pf_success "Caché Pokédex copiada desde: $source_cache"
        return 0
    fi

    if [[ -s "$destination_cache" ]] && jq empty "$destination_cache" >/dev/null 2>&1; then
        pf_success "Caché Pokédex existente conservada."
        return 0
    fi

    pf_warn "No se encontró una caché Pokédex válida."
    pf_warn "Después de instalar, ejecutá:"
    printf '\n  %q\n\n' "$INSTALL_DIR/build-pokedex-cache.sh"
}

write_fish_config() {
    mkdir -p "$FISH_CONFIG_DIR"

    {
        printf '# Pokémon Fastfetch %s\n' "$APP_VERSION"
        printf '# Generado automáticamente por install.sh\n\n'
        printf 'function fastfetch --description "Pokémon Fastfetch"\n'
        # shellcheck disable=SC2016
        printf '    "%s/random-fastfetch.sh" $argv\n' "$INSTALL_DIR"
        printf 'end\n'

        if [[ "$ENABLE_AUTOSTART" == "true" ]]; then
            cat <<EOF

if status is-interactive
    if test "\$TERM" = "xterm-kitty"
        if not set -q POKEMON_FASTFETCH_SHOWN
            set -g POKEMON_FASTFETCH_SHOWN 1
            "$INSTALL_DIR/random-fastfetch.sh"
        end
    end
end
EOF
        fi
    } > "$FISH_CONFIG_FILE"

    pf_success "Integración de Fish creada en: $FISH_CONFIG_FILE"
}

validate_installation() {
    local installed_scripts=(
        "$INSTALL_DIR/random-fastfetch.sh"
        "$INSTALL_DIR/render-pokemon.sh"
        "$INSTALL_DIR/build-pokedex-cache.sh"
        "$INSTALL_DIR/uninstall.sh"
    )

    local script=""

    for script in "${installed_scripts[@]}"; do
        [[ -x "$script" ]] ||
            pf_die "El archivo no quedó ejecutable: $script"

        bash -n "$script" ||
            pf_die "Error de sintaxis después de instalar: $script"
    done

    local installed_library="$INSTALL_DIR/lib/common.sh"

    [[ -r "$installed_library" ]] ||
        pf_die "No se instaló correctamente la biblioteca común."

    bash -n "$installed_library" ||
        pf_die "La biblioteca común instalada contiene errores de sintaxis."

    # NUEVO BLOQUE
    pf_require_nonempty_file \
        "$INSTALL_DIR/VERSION" \
        "El archivo VERSION instalado"

    [[ -r "$CONFIG_DIR/config" ]] ||
        pf_die "No se creó el archivo de configuración."

    [[ -r "$FISH_CONFIG_FILE" ]] ||
        pf_die "No se creó la configuración de Fish."
}

parse_arguments() {
    while (($# > 0)); do
        case "$1" in
            --yes|-y)
                ASSUME_YES=true
                shift
                ;;

            --no-autostart)
                ENABLE_AUTOSTART=false
                shift
                ;;

            --pokemon-dir)
                (($# >= 2)) ||
                    pf_die "Falta la ruta después de --pokemon-dir."

                POKEMON_DIR_OVERRIDE="$2"
                shift 2
                ;;

            --help|-h)
                usage
                exit 0
                ;;

            *)
                pf_die "Opción desconocida: $1"
                ;;
        esac
    done
}

main() {
    local pokemon_dir=""

    parse_arguments "$@"

    printf '%sPokémon Fastfetch v%s%s\n\n' "$BOLD" "$APP_VERSION" "$RESET"

    check_project_files
    check_script_syntax
    check_dependencies

    pokemon_dir="$(find_pokemon_dir || true)"

    if [[ -z "$pokemon_dir" ]]; then
        printf '\n'
        pf_warn "No se encontró automáticamente la carpeta de imágenes de pokimg."
        printf 'Ubicaciones revisadas:\n'
        printf '  - %s\n' \
            "$HOME/.local/share/pokimg/images" \
            "$HOME/pokimg/images" \
            "$HOME/.local/share/pokimg" \
            "$HOME/pokimg"
        printf '\n'
        pf_die "Indicá la ruta manualmente con: ./install.sh --pokemon-dir \"/ruta/a/imagenes\""
    fi

    pf_success "Imágenes detectadas en: $pokemon_dir"

    backup_existing_installation
    copy_project_files
    write_config "$pokemon_dir"
    ensure_pokedex_cache
    write_fish_config
    validate_installation

    printf '\n'
    pf_success "Instalación completada."
    printf '\n'
    printf 'Abrí una terminal Kitty nueva o ejecutá:\n\n'
    printf '  source %q\n' "$FISH_CONFIG_FILE"
    printf '  fastfetch\n\n'

    if [[ "$ENABLE_AUTOSTART" == "false" ]]; then
        pf_info "El inicio automático quedó desactivado."
    fi
}

main "$@"
