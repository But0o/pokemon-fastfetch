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
    )

    local file=""

    for file in "${required_files[@]}"; do
        [[ -f "$SOURCE_DIR/$file" ]] ||
            die "Falta '$file' en el repositorio: $SOURCE_DIR"
    done
}

check_script_syntax() {
    local scripts=(
        "$SOURCE_DIR/random-fastfetch.sh"
        "$SOURCE_DIR/render-pokemon.sh"
        "$SOURCE_DIR/build-pokedex-cache.sh"
    )

    local script=""

    for script in "${scripts[@]}"; do
        bash -n "$script" ||
            die "Error de sintaxis en: $script"
    done
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
        if ! command_exists "$command"; then
            missing+=("$command")
        fi
    done

    if ! command_exists magick && ! command_exists convert; then
        missing+=("imagemagick")
    fi

    if ((${#missing[@]} > 0)); then
        printf '\n'
        warn "Faltan dependencias obligatorias:"
        printf '  - %s\n' "${missing[@]}"
        printf '\n'

        if command_exists pacman; then
            printf 'En Arch/CachyOS podés instalar las principales con:\n\n'
            printf '  sudo pacman -S --needed jq imagemagick kitty fish fontconfig pciutils iproute2\n\n'
        fi

        die "Instalá las dependencias faltantes y ejecutá nuevamente el instalador."
    fi

    for command in "${optional[@]}"; do
        if ! command_exists "$command"; then
            warn "Dependencia opcional no encontrada: $command"
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
        die "Instalación cancelada."
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

    success "Respaldo creado en: $backup_dir"
}

copy_project_files() {
    mkdir -p "$INSTALL_DIR"
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

    if [[ -f "$SOURCE_DIR/VERSION" ]]; then
        install -m 0644 "$SOURCE_DIR/VERSION" "$INSTALL_DIR/VERSION"
    else
        printf '%s\n' "$APP_VERSION" > "$INSTALL_DIR/VERSION"
    fi

    if [[ -f "$SOURCE_DIR/LICENSE" ]]; then
        install -m 0644 "$SOURCE_DIR/LICENSE" "$INSTALL_DIR/LICENSE"
    fi

    success "Scripts instalados en: $INSTALL_DIR"
}

write_config() {
    local pokemon_dir="$1"

    cat > "$CONFIG_DIR/config" <<EOF
# Generado por Pokémon Fastfetch ${APP_VERSION}
POKEMON_DIR=$(printf '%q' "$pokemon_dir")
CACHE_DIR=$(printf '%q' "$CACHE_DIR")
INSTALL_DIR=$(printf '%q' "$INSTALL_DIR")
EOF

    chmod 0600 "$CONFIG_DIR/config"

    success "Configuración guardada en: $CONFIG_DIR/config"
}

ensure_pokedex_cache() {
    local source_cache=""
    local destination_cache="$CACHE_DIR/pokedex.json"

    local cache_candidates=(
        "$CACHE_DIR/pokedex.json"
        "$HOME/.cache/pokemon-fastfetch/pokedex.json"
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
        success "Caché Pokédex copiada desde: $source_cache"
        return 0
    fi

    if [[ -s "$destination_cache" ]] && jq empty "$destination_cache" >/dev/null 2>&1; then
        success "Caché Pokédex existente conservada."
        return 0
    fi

    warn "No se encontró una caché Pokédex válida."
    warn "Después de instalar, ejecutá:"
    printf '\n  %q\n\n' "$INSTALL_DIR/build-pokedex-cache.sh"
}

write_fish_config() {
    mkdir -p "$FISH_CONFIG_DIR"

    {
        printf '# Pokémon Fastfetch %s\n' "$APP_VERSION"
        printf '# Generado automáticamente por install.sh\n\n'
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

    success "Integración de Fish creada en: $FISH_CONFIG_FILE"
}

validate_installation() {
    local installed_scripts=(
        "$INSTALL_DIR/random-fastfetch.sh"
        "$INSTALL_DIR/render-pokemon.sh"
        "$INSTALL_DIR/build-pokedex-cache.sh"
    )

    local script=""

    for script in "${installed_scripts[@]}"; do
        [[ -x "$script" ]] ||
            die "El archivo no quedó ejecutable: $script"

        bash -n "$script" ||
            die "Error de sintaxis después de instalar: $script"
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

    parse_arguments "$@"

    printf '%sPokémon Fastfetch v%s%s\n\n' "$BOLD" "$APP_VERSION" "$RESET"

    check_project_files
    check_script_syntax
    check_dependencies

    pokemon_dir="$(find_pokemon_dir || true)"

    if [[ -z "$pokemon_dir" ]]; then
        printf '\n'
        warn "No se encontró automáticamente la carpeta de imágenes de pokimg."
        printf 'Ubicaciones revisadas:\n'
        printf '  - %s\n' \
            "$HOME/.local/share/pokimg/images" \
            "$HOME/pokimg/images" \
            "$HOME/.local/share/pokimg" \
            "$HOME/pokimg"
        printf '\n'
        die 'Indicá la ruta manualmente con: ./install.sh --pokemon-dir "/ruta/a/images"'
    fi

    success "Imágenes detectadas en: $pokemon_dir"

    backup_existing_installation
    copy_project_files
    write_config "$pokemon_dir"
    ensure_pokedex_cache
    write_fish_config
    validate_installation

    printf '\n'
    success "Instalación completada."
    printf '\n'
    printf 'Abrí una terminal Kitty nueva o ejecutá:\n\n'
    printf '  source %q\n' "$FISH_CONFIG_FILE"
    printf '  fastfetch\n\n'

    if [[ "$ENABLE_AUTOSTART" == "false" ]]; then
        info "El inicio automático quedó desactivado."
    fi
}

main "$@"
