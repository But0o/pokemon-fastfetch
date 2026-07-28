#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAME="pokemon-fastfetch"
APP_VERSION="2.0.0"

SOURCE_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd
)"

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
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
CYAN=$'\033[36m'

usage() {
    cat <<EOF
Actualizador de Pokémon Fastfetch v1 → v${APP_VERSION}

Uso:
  ./upgrade-v1-to-v2.sh [opciones]

Opciones:
  --yes, -y                  Acepta automáticamente las preguntas.
  --no-autostart             No ejecuta Pokémon Fastfetch al abrir Kitty.
  --pokemon-dir RUTA         Indica manualmente la carpeta de imágenes.
  --help, -h                 Muestra esta ayuda.

Ejemplos:
  ./upgrade-v1-to-v2.sh
  ./upgrade-v1-to-v2.sh --yes
  ./upgrade-v1-to-v2.sh --pokemon-dir "\$HOME/pokimg/images"
EOF
}

info() {
    printf '%s%s[INFO]%s %s\n' "$BOLD" "$CYAN" "$RESET" "$*"
}

success() {
    printf '%s%s[OK]%s %s\n' "$BOLD" "$GREEN" "$RESET" "$*"
}

warn() {
    printf '%s%s[AVISO]%s %s\n' "$BOLD" "$YELLOW" "$RESET" "$*"
}

die() {
    printf '%s%s[ERROR]%s %s\n' "$BOLD" "$RED" "$RESET" "$*" >&2
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
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
    local value="$1"

    case "$value" in
        "~")
            printf '%s\n' "$HOME"
            ;;
        "~/"*)
            printf '%s/%s\n' "$HOME" "${value#~/}"
            ;;
        *)
            printf '%s\n' "$value"
            ;;
    esac
}

contains_images() {
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

    if [[ -r "$CONFIG_DIR/config" ]]; then
        # shellcheck disable=SC1090
        source "$CONFIG_DIR/config" 2>/dev/null || true
        [[ -n "${POKEMON_DIR:-}" ]] && candidates+=("$POKEMON_DIR")
    fi

    candidates+=(
        "$HOME/.local/share/pokimg/images"
        "$HOME/pokimg/images"
        "$HOME/.local/share/pokimg"
        "$HOME/pokimg"
    )

    for candidate in "${candidates[@]}"; do
        [[ -n "$candidate" ]] || continue

        if contains_images "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

check_source_files() {
    local required=(
        "random-fastfetch.sh"
        "render-pokemon.sh"
        "build-pokedex-cache.sh"
    )

    local file=""

    for file in "${required[@]}"; do
        [[ -f "$SOURCE_DIR/$file" ]] ||
            die "Falta '$file' en el repositorio."
        bash -n "$SOURCE_DIR/$file" ||
            die "Error de sintaxis en '$file'."
    done
}

detect_legacy_paths() {
    local candidates=(
        "$HOME/pokemon-fastfetch"
        "$HOME/Pokemon-FastFetch"
        "$HOME/Descargas/Script_pokemon"
        "$HOME/Downloads/Script_pokemon"
        "$HOME/.local/share/pokemon-fastfetch"
    )

    local candidate=""

    for candidate in "${candidates[@]}"; do
        if [[ -d "$candidate" ]]; then
            printf '%s\n' "$candidate"
        fi
    done
}

create_backup() {
    local timestamp=""
    local backup_dir=""
    local legacy_path=""

    timestamp="$(date +'%Y-%m-%d_%H-%M-%S')"
    backup_dir="$BACKUP_ROOT/$timestamp"
    mkdir -p "$backup_dir"

    while IFS= read -r legacy_path; do
        [[ -n "$legacy_path" ]] || continue

        case "$legacy_path" in
            "$SOURCE_DIR")
                continue
                ;;
        esac

        cp -a "$legacy_path" "$backup_dir/$(basename "$legacy_path")" 2>/dev/null || true
    done < <(detect_legacy_paths)

    if [[ -d "$INSTALL_DIR" ]]; then
        cp -a "$INSTALL_DIR" "$backup_dir/current-install" 2>/dev/null || true
    fi

    if [[ -d "$CONFIG_DIR" ]]; then
        cp -a "$CONFIG_DIR" "$backup_dir/current-config" 2>/dev/null || true
    fi

    if [[ -f "$FISH_CONFIG_FILE" ]]; then
        mkdir -p "$backup_dir/fish"
        cp -a "$FISH_CONFIG_FILE" "$backup_dir/fish/"
    fi

    if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish" ]]; then
        mkdir -p "$backup_dir/fish"
        cp -a "${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish" \
            "$backup_dir/fish/config.fish"
    fi

    success "Respaldo creado en: $backup_dir"
}

copy_v2_files() {
    mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$CACHE_DIR"

    install -m 0755 \
        "$SOURCE_DIR/random-fastfetch.sh" \
        "$INSTALL_DIR/random-fastfetch.sh"

    install -m 0755 \
        "$SOURCE_DIR/render-pokemon.sh" \
        "$INSTALL_DIR/render-pokemon.sh"

    install -m 0755 \
        "$SOURCE_DIR/build-pokedex-cache.sh" \
        "$INSTALL_DIR/build-pokedex-cache.sh"

    if [[ -f "$SOURCE_DIR/VERSION" ]]; then
        install -m 0644 "$SOURCE_DIR/VERSION" "$INSTALL_DIR/VERSION"
    else
        printf '%s\n' "$APP_VERSION" > "$INSTALL_DIR/VERSION"
    fi

    success "Archivos v2 instalados en: $INSTALL_DIR"
}

migrate_cache() {
    local destination="$CACHE_DIR/pokedex.json"
    local candidate=""
    local candidates=(
        "$CACHE_DIR/pokedex.json"
        "$HOME/.cache/pokemon-fastfetch/pokedex.json"
        "$SOURCE_DIR/cache/pokedex.json"
        "$SOURCE_DIR/pokedex.json"
        "$HOME/Descargas/Script_pokemon/pokedex.json"
        "$HOME/Downloads/Script_pokemon/pokedex.json"
    )

    for candidate in "${candidates[@]}"; do
        if [[ -s "$candidate" ]] && jq empty "$candidate" >/dev/null 2>&1; then
            if [[ "$candidate" != "$destination" ]]; then
                cp -f "$candidate" "$destination"
            fi

            success "Caché Pokédex conservada desde: $candidate"
            return 0
        fi
    done

    warn "No se encontró una caché Pokédex válida."
    warn "Ejecutá luego: $INSTALL_DIR/build-pokedex-cache.sh"
}

write_config() {
    local pokemon_dir="$1"

    cat > "$CONFIG_DIR/config" <<EOF
# Generado por el actualizador de Pokémon Fastfetch ${APP_VERSION}
POKEMON_DIR=$(printf '%q' "$pokemon_dir")
CACHE_DIR=$(printf '%q' "$CACHE_DIR")
INSTALL_DIR=$(printf '%q' "$INSTALL_DIR")
EOF

    chmod 0600 "$CONFIG_DIR/config"
    success "Configuración actualizada."
}

remove_legacy_fish_blocks() {
    local fish_main="${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"

    [[ -f "$fish_main" ]] || return 0

    cp -a "$fish_main" "${fish_main}.pokemon-fastfetch-v1.bak"

    sed -i \
        -e '/Script_pokemon.*random-fastfetch\.sh/d' \
        -e '/pokemon-fastfetch.*random-fastfetch\.sh/d' \
        -e '/set -g POKEMON_FASTFETCH_SCRIPT/d' \
        "$fish_main"

    success "Referencias antiguas eliminadas de config.fish."
}

write_fish_config() {
    mkdir -p "$FISH_CONFIG_DIR"

    {
        printf '# Pokémon Fastfetch %s\n' "$APP_VERSION"
        printf '# Generado por upgrade-v1-to-v2.sh\n\n'
        printf 'function fastfetch --description "Pokémon Fastfetch"\n'
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

    success "Configuración de Fish actualizada."
}

validate_upgrade() {
    local script=""

    for script in \
        "$INSTALL_DIR/random-fastfetch.sh" \
        "$INSTALL_DIR/render-pokemon.sh" \
        "$INSTALL_DIR/build-pokedex-cache.sh"
    do
        [[ -x "$script" ]] ||
            die "No quedó ejecutable: $script"

        bash -n "$script" ||
            die "Error de sintaxis después de actualizar: $script"
    done

    [[ -r "$CONFIG_DIR/config" ]] ||
        die "No se creó el archivo de configuración."

    [[ -r "$FISH_CONFIG_FILE" ]] ||
        die "No se creó la configuración de Fish."
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
                    die "Falta la ruta después de --pokemon-dir."
                POKEMON_DIR_OVERRIDE="$2"
                shift 2
                ;;

            --help|-h)
                usage
                exit 0
                ;;

            *)
                die "Opción desconocida: $1"
                ;;
        esac
    done
}

main() {
    local pokemon_dir=""
    local detected_legacy=""

    parse_arguments "$@"

    printf '%sActualización Pokémon Fastfetch → v%s%s\n\n' \
        "$BOLD" "$APP_VERSION" "$RESET"

    check_source_files

    if ! command_exists jq; then
        die "Falta jq."
    fi

    detected_legacy="$(detect_legacy_paths || true)"

    if [[ -z "$detected_legacy" && ! -d "$INSTALL_DIR" ]]; then
        warn "No se detectó una instalación anterior."
        warn "Este script puede continuar como instalación limpia."

        confirm "¿Continuar igualmente?" ||
            die "Actualización cancelada."
    else
        info "Se detectaron rutas compatibles con una instalación anterior."
    fi

    pokemon_dir="$(find_pokemon_dir || true)"

    if [[ -z "$pokemon_dir" ]]; then
        die 'No se encontró pokimg. Usá --pokemon-dir "/ruta/a/images".'
    fi

    success "Imágenes detectadas en: $pokemon_dir"

    confirm "¿Actualizar a Pokémon Fastfetch v${APP_VERSION}?" ||
        die "Actualización cancelada."

    create_backup
    copy_v2_files
    migrate_cache
    write_config "$pokemon_dir"
    remove_legacy_fish_blocks
    write_fish_config
    validate_upgrade

    printf '\n'
    success "Actualización completada."
    printf '\n'
    printf 'Reiniciá Kitty o ejecutá:\n\n'
    printf '  source %q\n' "$FISH_CONFIG_FILE"
    printf '  fastfetch\n\n'
}

main "$@"
