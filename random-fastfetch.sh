#!/usr/bin/env bash

set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Pokémon Fastfetch
#
# Main application entry point.
#
# Responsibilities:
#   - Select a Pokémon
#   - Collect system information
#   - Render or reuse the cached Pokémon panel
#   - Display the final dashboard inside Kitty
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

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd
)"

COMMON_LIBRARY="$SCRIPT_DIR/lib/common.sh"

if [[ ! -r "$COMMON_LIBRARY" ]]; then
    printf '[ERROR] No se encontró la biblioteca común: %s\n' \
        "$COMMON_LIBRARY" >&2
    exit 1
fi

# shellcheck source=lib/common.sh
source "$COMMON_LIBRARY"

VERSION_FILE="$SCRIPT_DIR/VERSION"

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

CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/pokemon-fastfetch"
CONFIG_FILE="$CONFIG_ROOT/config"

if [[ -r "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

CACHE_ROOT="${CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/pokemon-fastfetch}"
POKEDEX_FILE="$CACHE_ROOT/pokedex.json"

FIXED_POKEMON_FILE="$CONFIG_ROOT/fixed-pokemon"

if [[ ! -d "$CONFIG_ROOT" ]]; then
    mkdir -p "$CONFIG_ROOT"
fi

RENDER_SCRIPT="$SCRIPT_DIR/render-pokemon.sh"

# ────────────────────────────────────────────────────────────────
# Configuración visual
# ────────────────────────────────────────────────────────────────

# Altura preferida del panel Pokémon, en filas de la terminal.
# El ancho siempre ocupa toda la terminal; si la terminal es angosta,
# el panel usa menos filas para que el contenido siga entrando.
POKEMON_PANEL_ROWS="${POKEMON_PANEL_ROWS:-20}"

if ! [[ "$POKEMON_PANEL_ROWS" =~ ^[0-9]+$ ]] || ((POKEMON_PANEL_ROWS < 5)); then
    POKEMON_PANEL_ROWS=20
fi

# Ancho máximo del contenido inferior. 0 = todo el ancho de la terminal.
SYSTEM_PANEL_MAX_WIDTH="${SYSTEM_PANEL_MAX_WIDTH:-0}"

if ! [[ "$SYSTEM_PANEL_MAX_WIDTH" =~ ^[0-9]+$ ]]; then
    SYSTEM_PANEL_MAX_WIDTH=0
fi

# Espacio entre las dos columnas inferiores.
COLUMN_GAP="${COLUMN_GAP:-6}"

SHOW_SYSTEM_INFO="${SHOW_SYSTEM_INFO:-true}"

# Pre-renderizar en segundo plano el próximo Pokémon aleatorio.
POKEMON_PREFETCH="${POKEMON_PREFETCH:-true}"
SHOW_COLOR_PALETTE="${SHOW_COLOR_PALETTE:-true}"

# ────────────────────────────────────────────────────────────────
# Colores ANSI
# ────────────────────────────────────────────────────────────────

RESET=$'\033[0m'


WHITE=$'\033[38;2;232;232;236m'
GRAY=$'\033[38;2;158;158;170m'
DARK_GRAY=$'\033[38;2;85;85;98m'

RED=$'\033[38;2;255;84;84m'
ORANGE=$'\033[38;2;255;145;44m'
YELLOW=$'\033[38;2;244;225;55m'
GREEN=$'\033[38;2;83;218;122m'
CYAN=$'\033[38;2;83;207;230m'
BLUE=$'\033[38;2;87;138;255m'
PURPLE=$'\033[38;2;149;103;255m'
MAGENTA=$'\033[38;2;224;84;214m'

# ────────────────────────────────────────────────────────────────
# Utilidades
# ────────────────────────────────────────────────────────────────

show_help() {
    cat <<EOF
Pokémon Fastfetch v${APP_VERSION}

Uso:

  random-fastfetch.sh
      Selecciona un Pokémon aleatorio.

  random-fastfetch.sh charizard
      Muestra un Pokémon por nombre.

  random-fastfetch.sh 6
      Muestra un Pokémon por número de Pokédex.

  random-fastfetch.sh --random
      Selecciona un Pokémon aleatorio.

  random-fastfetch.sh --rerender charizard
      Borra el panel cacheado y vuelve a generarlo.

  random-fastfetch.sh --help
      Muestra esta ayuda.

Ejemplos:

  random-fastfetch.sh pikachu
  random-fastfetch.sh charizard
  random-fastfetch.sh rayquaza
  random-fastfetch.sh 25
  random-fastfetch.sh 384
EOF
}

# Procesar opciones informativas antes de validar dependencias o caché.
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;

    --version|-v)
        printf 'Pokémon Fastfetch v%s\n' "$APP_VERSION"
        exit 0
        ;;
esac


# trim_text VARIABLE TEXTO MAXIMO
# Guarda el texto recortado en VARIABLE sin crear un subshell.
# shellcheck disable=SC2034  # trim_target se asigna a través del nameref
trim_text() {
    local -n trim_target="$1"
    local value="${2:-}"
    local maximum="${3:-40}"

    value="${value//$'\n'/ }"
    value="${value//$'\r'/ }"

    while [[ "$value" == *"  "* ]]; do
        value="${value//  / }"
    done

    if ((${#value} > maximum)); then
        trim_target="${value:0:$((maximum - 1))}…"
    else
        trim_target="$value"
    fi
}

safe_value() {
    local value="${1:-}"
    local fallback="${2:-No disponible}"

    if [[ -z "$value" || "$value" == "null" ]]; then
        printf '%s' "$fallback"
    else
        printf '%s' "$value"
    fi
}

format_bytes() {
    local bytes="${1:-0}"
    local units=(B KiB MiB GiB TiB)
    local unit_index=0
    local divisor=1
    local hundredths=0

    if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        bytes=0
    fi

    # Aritmética entera en centésimas: sin awk y sin procesos extra.
    # (La versión anterior usaba "index" como variable de awk, que es una
    # función incorporada, y awk fallaba en silencio.)
    while ((bytes >= divisor * 1024 && unit_index < 4)); do
        divisor=$((divisor * 1024))
        unit_index=$((unit_index + 1))
    done

    hundredths=$(((bytes * 100 + divisor / 2) / divisor))

    if ((unit_index <= 1)); then
        printf '%d %s' "$(((hundredths + 50) / 100))" "${units[unit_index]}"
    else
        printf '%d.%02d %s' \
            "$((hundredths / 100))" \
            "$((hundredths % 100))" \
            "${units[unit_index]}"
    fi
}

get_terminal_columns() {
    local columns

    columns="$(
        tput cols 2>/dev/null ||
            printf '120'
    )"

    if ! [[ "$columns" =~ ^[0-9]+$ ]]; then
        columns=120
    fi

    printf '%s' "$columns"
}

repeat_character() {
    local character="$1"
    local amount="$2"
    local line=""

    if ((amount <= 0)); then
        return
    fi

    # No usar tr: trabaja por bytes y rompe caracteres UTF-8 como '─'.
    printf -v line '%*s' "$amount" ''
    printf '%s' "${line// /$character}"
}

# Consulta el tamaño de celda directamente a la terminal.
query_cell_size() {
    local saved_tty=""
    local reply=""

    { exec 3<>/dev/tty; } 2>/dev/null || return 1

    saved_tty="$(stty -g <&3 2>/dev/null)" || {
        exec 3<&-
        return 1
    }

    stty -echo -icanon min 0 time 3 <&3 2>/dev/null
    printf '\033[16t' >&3
    IFS= read -r -d t -t 1 reply <&3 || true
    stty "$saved_tty" <&3 2>/dev/null
    exec 3<&-

    if [[ "$reply" =~ \[6\;([0-9]+)\;([0-9]+)$ ]]; then
        printf '%s %s' "${BASH_REMATCH[2]}" "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

# Imprime "ANCHO ALTO" de una celda en píxeles.
get_cell_size() {
    local columns="$1"
    local lines="$2"
    local window_size=""
    local cell_width=0
    local cell_height=0

    window_size="$(
        { kitten icat --print-window-size < /dev/tty; } 2>/dev/null ||
            true
    )"

    if [[ "$window_size" =~ ^([0-9]+)x([0-9]+)$ ]] &&
        [[ "$lines" =~ ^[0-9]+$ ]] &&
        ((columns > 0 && lines > 0)); then
        cell_width="$((BASH_REMATCH[1] / columns))"
        cell_height="$((BASH_REMATCH[2] / lines))"
    fi

    # Plan B: pedirle a la terminal el tamaño de celda (CSI 16 t).
    # Kitty responde ESC [ 6 ; ALTO ; ANCHO t
    if ((cell_width <= 0 || cell_height <= 0)); then
        read -r cell_width cell_height <<< "$(query_cell_size || printf '0 0')"
    fi

    # Valores razonables si Kitty no informa el tamaño.
    if ((cell_width <= 0 || cell_height <= 0)); then
        cell_width=10
        cell_height=22
    fi

    printf '%s %s' "$cell_width" "$cell_height"
}

# ────────────────────────────────────────────────────────────────
# Validaciones
# ────────────────────────────────────────────────────────────────
pf_require_commands \
    jq \
    kitten \
    tput \
    awk \
    sed \
    uname \
    hostname \
    df


# Solo se comprueba que exista; validar el JSON completo en cada arranque
# costaría una lectura extra. Si está roto, jq falla más adelante.
pf_require_nonempty_file "$POKEDEX_FILE" "La caché Pokédex"

# Índice de claves con imagen, para elegir al azar sin leer el JSON.
# Se regenera solo cuando la Pokédex es más nueva que el índice.
POKEDEX_INDEX_FILE="$CACHE_ROOT/pokedex-keys.txt"

pick_random_pokemon() {
    local keys=()

    if [[ ! -s "$POKEDEX_INDEX_FILE" || "$POKEDEX_FILE" -nt "$POKEDEX_INDEX_FILE" ]]; then
        if ! jq -r '
                to_entries[]
                | select((.value.image // "") | length > 0)
                | .key
            ' "$POKEDEX_FILE" > "$POKEDEX_INDEX_FILE.tmp" 2>/dev/null; then
            rm -f "$POKEDEX_INDEX_FILE.tmp"
            pf_die "La caché Pokédex contiene un JSON inválido: $POKEDEX_FILE"
        fi

        mv -f "$POKEDEX_INDEX_FILE.tmp" "$POKEDEX_INDEX_FILE"
    fi

    mapfile -t keys < "$POKEDEX_INDEX_FILE"

    if ((${#keys[@]} == 0)); then
        return 1
    fi

    printf '%s' "${keys[${SRANDOM:-$RANDOM} % ${#keys[@]}]}"
}

pf_require_executable "$RENDER_SCRIPT" "El renderizador Pokémon"

# ────────────────────────────────────────────────────────────────
# Procesar argumentos
# ────────────────────────────────────────────────────────────────

REQUEST=""
FORCE_RERENDER=false
RANDOM_SELECTION=false

case "${1:-}" in
    --set)
        FIXED_REQUEST="${2:-}"

        if [[ -z "$FIXED_REQUEST" ]]; then
            pf_error "Tenés que indicar un Pokémon por nombre o número."
            echo
            echo "Ejemplos:"
            echo "  fastfetch --set pikachu"
            echo "  fastfetch --set 25"
            exit 1
        fi

        # Comprobar que el Pokémon y su imagen existen, sin renderizar.
        # Se guarda la clave canónica (por ejemplo "25" -> "pikachu").
        FIXED_KEY="$("$RENDER_SCRIPT" --check "$FIXED_REQUEST" 2>/dev/null || true)"

        if [[ -z "$FIXED_KEY" ]]; then
            pf_die "No se encontró el Pokémon o su imagen: $FIXED_REQUEST"
        fi

        printf '%s\n' "$FIXED_KEY" > "$FIXED_POKEMON_FILE"

        echo "Pokémon fijo configurado: $FIXED_KEY"
        echo "Se mostrará al abrir nuevas terminales."
        exit 0
        ;;

    --random-mode)
        rm -f "$FIXED_POKEMON_FILE"

        echo "Modo aleatorio activado."
        echo "Se seleccionará un Pokémon diferente en cada terminal."
        exit 0
        ;;

    --rerender)
        FORCE_RERENDER=true
        REQUEST="${2:-}"

        if [[ -z "$REQUEST" ]]; then
            echo "Tenés que indicar un Pokémon."
            echo
            echo "Ejemplo:"
            echo "  $0 --rerender charizard"
            exit 1
        fi
        ;;

    --random|random)
        # Selección aleatoria solo para esta ejecución.
        RANDOM_SELECTION=true
        REQUEST="$(pick_random_pokemon || true)"
        ;;

    "")
        if [[ -s "$FIXED_POKEMON_FILE" ]]; then
            read -r REQUEST < "$FIXED_POKEMON_FILE" || true
        else
            RANDOM_SELECTION=true
            REQUEST="$(pick_random_pokemon || true)"
        fi
        ;;

    *)
        # Permite seguir usando:
        # fastfetch pikachu
        # fastfetch 25
        REQUEST="$1"
        ;;
esac

if [[ -z "$REQUEST" ]]; then
    pf_die "No se pudo seleccionar un Pokémon."
fi


# ────────────────────────────────────────────────────────────────
# Tamaño del panel Pokémon (responsive)
#
# El panel ocupa todo el ancho de la terminal. Se renderiza al tamaño
# exacto en píxeles de PANEL_COLUMNS x PANEL_ROWS celdas, así Kitty no lo
# reescala y no queda espacio vacío debajo.
#
# Estos umbrales tienen que coincidir con los de render-pokemon.sh:
# el diseño mide 450 unidades de alto, necesita 1400 de ancho para
# mostrar todas las columnas y 1000 para el modo compacto.
# ────────────────────────────────────────────────────────────────

DESIGN_HEIGHT=450
FULL_LAYOUT_MIN_WIDTH=1400
COMPACT_LAYOUT_MIN_WIDTH=1000

TERMINAL_COLUMNS="$(get_terminal_columns)"
PANEL_COLUMNS="$TERMINAL_COLUMNS"

TERMINAL_LINES="$(tput lines 2>/dev/null || printf '0')"

if ! [[ "$TERMINAL_LINES" =~ ^[0-9]+$ ]]; then
    TERMINAL_LINES=0
fi

read -r CELL_WIDTH CELL_HEIGHT <<< "$(get_cell_size "$PANEL_COLUMNS" "$TERMINAL_LINES")"

PANEL_PIXEL_WIDTH="$((PANEL_COLUMNS * CELL_WIDTH))"

# Filas máximas que permiten el diseño completo a este ancho.
FULL_LAYOUT_ROWS="$((
    PANEL_PIXEL_WIDTH * DESIGN_HEIGHT / (FULL_LAYOUT_MIN_WIDTH * CELL_HEIGHT)
))"

# Aceptamos achicar hasta un 70 % antes de pasar al modo compacto.
MINIMUM_FULL_ROWS="$(((POKEMON_PANEL_ROWS * 7 + 9) / 10))"

if ((FULL_LAYOUT_ROWS >= POKEMON_PANEL_ROWS)); then
    PANEL_ROWS="$POKEMON_PANEL_ROWS"
elif ((FULL_LAYOUT_ROWS >= MINIMUM_FULL_ROWS)); then
    PANEL_ROWS="$FULL_LAYOUT_ROWS"
else
    PANEL_ROWS="$((
        PANEL_PIXEL_WIDTH * DESIGN_HEIGHT / (COMPACT_LAYOUT_MIN_WIDTH * CELL_HEIGHT)
    ))"

    # Nunca más alto que el diseño completo: así el panel no crece
    # cuando la terminal se achica.
    if ((PANEL_ROWS > MINIMUM_FULL_ROWS)); then
        PANEL_ROWS="$MINIMUM_FULL_ROWS"
    fi
fi

# En terminales bajas, dejar lugar para el panel del sistema y el prompt:
# divisor + 8 filas + paleta (2) + prompt (1).
if [[ "$SHOW_SYSTEM_INFO" == "true" ]]; then
    RESERVED_ROWS=10

    if [[ "$SHOW_COLOR_PALETTE" == "true" ]]; then
        RESERVED_ROWS=12
    fi
else
    RESERVED_ROWS=1
fi

if ((TERMINAL_LINES > 0 && PANEL_ROWS > TERMINAL_LINES - RESERVED_ROWS)); then
    PANEL_ROWS="$((TERMINAL_LINES - RESERVED_ROWS))"
fi

if ((PANEL_ROWS < 5)); then
    PANEL_ROWS=5
fi

PANEL_PIXEL_HEIGHT="$((PANEL_ROWS * CELL_HEIGHT))"

# ────────────────────────────────────────────────────────────────
# Pokémon pre-renderizado (modo aleatorio)
#
# Después de mostrar el panel se renderiza en segundo plano el próximo
# Pokémon al azar para este tamaño de terminal. Así la siguiente
# terminal lo encuentra en caché y no espera a ImageMagick.
# ────────────────────────────────────────────────────────────────

NEXT_RANDOM_FILE="$CACHE_ROOT/next-random-${PANEL_PIXEL_WIDTH}x${PANEL_PIXEL_HEIGHT}"

if [[ "$RANDOM_SELECTION" == "true" && -s "$NEXT_RANDOM_FILE" ]]; then
    CLAIMED_FILE="$NEXT_RANDOM_FILE.claimed-$$"
    PREFETCHED_REQUEST=""

    # mv es atómico: si se abren dos terminales a la vez, solo una
    # se queda con el Pokémon pre-renderizado.
    if mv -f "$NEXT_RANDOM_FILE" "$CLAIMED_FILE" 2>/dev/null; then
        read -r PREFETCHED_REQUEST < "$CLAIMED_FILE" || true
        rm -f "$CLAIMED_FILE"
    fi

    if [[ -n "$PREFETCHED_REQUEST" ]]; then
        REQUEST="$PREFETCHED_REQUEST"
    fi
fi

start_random_prefetch() {
    local next_request=""

    if [[ "$POKEMON_PREFETCH" != "true" || -s "$NEXT_RANDOM_FILE" ]]; then
        return 0
    fi

    next_request="$(pick_random_pokemon || true)"

    if [[ -z "$next_request" || "$next_request" == "$REQUEST" ]]; then
        return 0
    fi

    (
        trap - EXIT

        low_priority=()

        if pf_command_exists nice; then
            low_priority=(nice -n 19)
        fi

        if PF_RENDER_WIDTH="$PANEL_PIXEL_WIDTH" \
            PF_RENDER_HEIGHT="$PANEL_PIXEL_HEIGHT" \
            "${low_priority[@]}" "$RENDER_SCRIPT" "$next_request"; then
            printf '%s\n' "$next_request" > "$NEXT_RANDOM_FILE.tmp-$BASHPID" &&
                mv -f "$NEXT_RANDOM_FILE.tmp-$BASHPID" "$NEXT_RANDOM_FILE"
        fi
    ) < /dev/null > /dev/null 2>&1 &

    disown 2>/dev/null || true
}

# ────────────────────────────────────────────────────────────────
# Obtener panel Pokémon
# ────────────────────────────────────────────────────────────────

# El renderer corre en segundo plano mientras se junta la información
# del sistema; se espera su resultado justo antes de dibujar.
RENDER_OUTPUT_FILE="$CACHE_ROOT/.render-output-$$"

cleanup_render_output() {
    rm -f "$RENDER_OUTPUT_FILE"
}

trap cleanup_render_output EXIT

# --rerender: el renderer resuelve el nombre o número y descarta los
# paneles cacheados de ese Pokémon antes de volver a generarlo.
FORCE_RENDER_FLAG=0

if [[ "$FORCE_RERENDER" == "true" ]]; then
    FORCE_RENDER_FLAG=1
fi

PF_RENDER_WIDTH="$PANEL_PIXEL_WIDTH" \
    PF_RENDER_HEIGHT="$PANEL_PIXEL_HEIGHT" \
    PF_FORCE_RENDER="$FORCE_RENDER_FLAG" \
    "$RENDER_SCRIPT" "$REQUEST" > "$RENDER_OUTPUT_FILE" &

RENDER_PID=$!

# ────────────────────────────────────────────────────────────────
# Recopilar información del sistema
# ────────────────────────────────────────────────────────────────

get_os() {
    local os_name=""
    local architecture=""

    if [[ -r /etc/os-release ]]; then
        os_name="$(
            (
                source /etc/os-release
                printf '%s' "${PRETTY_NAME:-${NAME:-Linux}}"
            )
        )"
    fi

    architecture="$(uname -m 2>/dev/null || true)"

    os_name="$(safe_value "$os_name" "Linux")"
    architecture="$(safe_value "$architecture" "Desconocida")"

    printf '%s %s' "$os_name" "$architecture"
}

get_kernel() {
    uname -r 2>/dev/null || printf 'No disponible'
}

get_uptime() {
    local uptime_seconds=""
    local days=0
    local hours=0
    local minutes=0
    local result=""

    # /proc/uptime se lee con builtins: sin uptime, sed ni awk.
    if ! read -r uptime_seconds _ < /proc/uptime 2>/dev/null; then
        printf 'No disponible'
        return
    fi

    uptime_seconds="${uptime_seconds%%.*}"

    days=$((uptime_seconds / 86400))
    hours=$((uptime_seconds % 86400 / 3600))
    minutes=$((uptime_seconds % 3600 / 60))

    if ((days > 0)); then
        result+="${days}d "
    fi

    if ((days > 0 || hours > 0)); then
        result+="${hours}h "
    fi

    printf '%s%dm' "$result" "$minutes"
}

get_packages() {
    local packages=""
    local entries=()

    # Cada paquete instalado es una carpeta en la base local de pacman.
    # Contarlas con un glob es mucho más rápido que "pacman -Qq".
    if [[ -d /var/lib/pacman/local ]]; then
        entries=(/var/lib/pacman/local/*/)
        printf '%s (pacman)' "${#entries[@]}"
        return
    fi

    if pf_command_exists flatpak; then
        packages="$(
            flatpak list --app 2>/dev/null |
                wc -l |
                tr -d ' '
        )"

        printf '%s (flatpak)' "$packages"
        return
    fi

    printf 'No disponible'
}

get_shell() {
    local shell_name=""
    local shell_version=""

    shell_name="$(basename "${SHELL:-fish}")"

    case "$shell_name" in
        fish)
            shell_version="$(
                fish --version 2>/dev/null |
                    awk '{print $3}' ||
                    true
            )"
            ;;

        bash)
            shell_version="${BASH_VERSION:-}"
            ;;

        zsh)
            shell_version="$(
                zsh --version 2>/dev/null |
                    awk '{print $2}' ||
                    true
            )"
            ;;

        *)
            shell_version=""
            ;;
    esac

    if [[ -n "$shell_version" ]]; then
        printf '%s %s' "$shell_name" "$shell_version"
    else
        printf '%s' "$shell_name"
    fi
}

get_display() {
    local display=""

    if pf_command_exists hyprctl; then
        display="$(
            hyprctl monitors -j 2>/dev/null |
                jq -r '
                    [
                        .[]
                        | select(
                            .focused == true
                        )
                    ][0]
                    //
                    .[0]
                    |
                    if . == null then
                        empty
                    else
                        "\(.width)x\(.height) @ \(
                            (
                                .refreshRate
                                // 0
                            )
                            | floor
                        ) Hz"
                    end
                ' 2>/dev/null ||
                true
        )"
    fi

    if [[ -z "$display" ]] && pf_command_exists xrandr; then
        display="$(
            xrandr --current 2>/dev/null |
                awk '
                    / connected primary / {
                        for (i = 1; i <= NF; i++) {
                            if ($i ~ /^[0-9]+x[0-9]+\+/) {
                                split($i, resolution, "+")
                                print resolution[1]
                                exit
                            }
                        }
                    }

                    / connected / && result == "" {
                        for (i = 1; i <= NF; i++) {
                            if ($i ~ /^[0-9]+x[0-9]+\+/) {
                                split($i, resolution, "+")
                                result = resolution[1]
                            }
                        }
                    }

                    END {
                        if (result != "") {
                            print result
                        }
                    }
                ' |
                head -n 1 ||
                true
        )"
    fi

    safe_value "$display"
}

get_window_manager() {
    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        local version=""

        version="$(
            hyprctl version -j 2>/dev/null |
                jq -r '
                    .tag
                    // .version
                    // empty
                ' 2>/dev/null ||
                true
        )"

        if [[ -n "$version" ]]; then
            printf 'Hyprland %s (Wayland)' "$version"
        else
            printf 'Hyprland (Wayland)'
        fi

        return
    fi

    safe_value "${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-}}"
}

get_terminal() {
    local version=""

    if [[ "${TERM:-}" == "xterm-kitty" ]] && pf_command_exists kitty; then
        version="$(
            kitty --version 2>/dev/null |
                awk '{print $2}' ||
                true
        )"

        if [[ -n "$version" ]]; then
            printf 'kitty %s' "$version"
        else
            printf 'kitty'
        fi

        return
    fi

    safe_value "${TERM_PROGRAM:-${TERM:-}}"
}

get_font() {
    local font_name=""

    font_name="$(
        fc-match \
            -f '%{family[0]} (%{size}pt)' \
            monospace \
            2>/dev/null ||
            true
    )"

    safe_value "$font_name"
}

get_cpu() {
    local cpu=""

    if pf_command_exists lscpu; then
        cpu="$(
            lscpu 2>/dev/null |
                awk -F: '
                    /^Model name:/ {
                        value = $2
                        sub(/^[ \t]+/, "", value)
                        print value
                        exit
                    }
                ' ||
                true
        )"
    fi

    if [[ -z "$cpu" && -r /proc/cpuinfo ]]; then
        cpu="$(
            awk -F: '
                /^model name/ {
                    value = $2
                    sub(/^[ \t]+/, "", value)
                    print value
                    exit
                }
            ' /proc/cpuinfo
        )"
    fi

    safe_value "$cpu"
}

get_gpu() {
    local gpu=""

    if pf_command_exists lspci; then
        gpu="$(
            lspci 2>/dev/null |
                awk -F': ' '
                    /VGA compatible controller|3D controller|Display controller/ {
                        value = $2
                        sub(/ \(rev [^)]+\)$/, "", value)
                        print value
                        exit
                    }
                ' ||
                true
        )"
    fi

    safe_value "$gpu"
}

get_memory() {
    if [[ ! -r /proc/meminfo ]]; then
        printf 'No disponible'
        return
    fi

    awk '
        /^MemTotal:/ {
            total = $2 * 1024
        }

        /^MemAvailable:/ {
            available = $2 * 1024
        }

        END {
            used = total - available
            percent = total > 0 ? int((used / total) * 100) : 0

            printf "%.2f GiB / %.2f GiB (%d%%)",
                used / 1073741824,
                total / 1073741824,
                percent
        }
    ' /proc/meminfo
}

get_disk() {
    local total=""
    local used=""
    local percent=""
    local filesystem=""

    {
        read -r _
        read -r total used percent filesystem
    } < <(
        df \
            --block-size=1 \
            --output=size,used,pcent,fstype \
            / \
            2>/dev/null
    ) || true

    if ! [[ "$total" =~ ^[0-9]+$ ]]; then
        printf 'No disponible'
        return
    fi

    printf '%s / %s (%s) - %s' \
        "$(format_bytes "$used")" \
        "$(format_bytes "$total")" \
        "$percent" \
        "$filesystem"
}

get_network() {
    local interface=""
    local destination=""
    local address=""
    local field=""
    local fields=()

    # La ruta por defecto (destino 00000000) sale de /proc, sin "ip route".
    if [[ -r /proc/net/route ]]; then
        while read -r field destination _; do
            if [[ "$destination" == "00000000" ]]; then
                interface="$field"
                break
            fi
        done < /proc/net/route
    fi

    if [[ -n "$interface" ]] && pf_command_exists ip; then
        read -r -a fields < <(
            ip -o -4 address show dev "$interface" 2>/dev/null
        ) || true

        address="${fields[3]:-}"
    fi

    if [[ -n "$interface" && -n "$address" ]]; then
        printf '%s %s' "$interface" "$address"
    elif [[ -n "$interface" ]]; then
        printf '%s' "$interface"
    else
        printf 'No disponible'
    fi
}

# Fecha de creación del sistema de archivos raíz (se cachea por arranque).
get_install_birth() {
    local timestamp=""

    timestamp="$(stat --format='%W' / 2>/dev/null || printf '0')"

    if [[ "$timestamp" =~ ^[0-9]+$ ]]; then
        printf '%s' "$timestamp"
    else
        printf '0'
    fi
}

get_install_age() {
    local birth="${1:-0}"
    local now=""
    local days=0

    if ! [[ "$birth" =~ ^[0-9]+$ ]] || ((birth <= 0)); then
        printf 'No disponible'
        return
    fi

    printf -v now '%(%s)T' -1
    days=$(((now - birth) / 86400))

    if ((days == 1)); then
        printf '1 día'
    else
        printf '%s días' "$days"
    fi
}

get_machine() {
    local product=""
    local vendor=""

    if [[ -r /sys/devices/virtual/dmi/id/product_name ]]; then
        product="$(
            tr -d '\n' < /sys/devices/virtual/dmi/id/product_name
        )"
    fi

    if [[ -r /sys/devices/virtual/dmi/id/sys_vendor ]]; then
        vendor="$(
            tr -d '\n' < /sys/devices/virtual/dmi/id/sys_vendor
        )"
    fi

    if [[ -n "$vendor" && -n "$product" ]]; then
        printf '%s %s' "$vendor" "$product"
    elif [[ -n "$product" ]]; then
        printf '%s' "$product"
    else
        hostname 2>/dev/null || printf 'No disponible'
    fi
}

# ────────────────────────────────────────────────────────────────
# Recopilar valores
# ────────────────────────────────────────────────────────────────

# Datos que no cambian hasta reiniciar (CPU, GPU, versiones, fuente...)
# se guardan en un archivo. La clave incluye el boot_id, así que cada
# arranque del sistema, o una sesión nueva de Hyprland, los recalcula.
STATIC_CACHE_FILE="$CACHE_ROOT/system-static.cache"
STATIC_FIELDS=(
    OS_VALUE KERNEL_VALUE SHELL_VALUE WM_VALUE TERMINAL_VALUE
    FONT_VALUE CPU_VALUE GPU_VALUE MACHINE_VALUE OS_BIRTH_VALUE
)

load_static_info() {
    local boot_id=""
    local cache_key=""
    local lines=()
    local index=0
    local field=""

    read -r boot_id < /proc/sys/kernel/random/boot_id 2>/dev/null || true

    cache_key="v1|$APP_VERSION|$boot_id|${TERM:-}|${SHELL:-}"
    cache_key+="|${HYPRLAND_INSTANCE_SIGNATURE:-}|${XDG_CURRENT_DESKTOP:-}"

    if [[ -n "$boot_id" && -r "$STATIC_CACHE_FILE" ]]; then
        mapfile -t lines < "$STATIC_CACHE_FILE"

        if [[ "${lines[0]:-}" == "$cache_key" ]] &&
            ((${#lines[@]} == ${#STATIC_FIELDS[@]} + 1)); then
            for field in "${STATIC_FIELDS[@]}"; do
                index=$((index + 1))
                printf -v "$field" '%s' "${lines[index]}"
            done

            return 0
        fi
    fi

    OS_VALUE="$(get_os)"
    KERNEL_VALUE="$(get_kernel)"
    SHELL_VALUE="$(get_shell)"
    WM_VALUE="$(get_window_manager)"
    TERMINAL_VALUE="$(get_terminal)"
    FONT_VALUE="$(get_font)"
    CPU_VALUE="$(get_cpu)"
    GPU_VALUE="$(get_gpu)"
    MACHINE_VALUE="$(get_machine)"
    OS_BIRTH_VALUE="$(get_install_birth)"

    if [[ -n "$boot_id" ]]; then
        if {
            printf '%s\n' "$cache_key"

            for field in "${STATIC_FIELDS[@]}"; do
                printf '%s\n' "${!field//$'\n'/ }"
            done
        } > "$STATIC_CACHE_FILE.tmp" 2>/dev/null; then
            mv -f "$STATIC_CACHE_FILE.tmp" "$STATIC_CACHE_FILE" 2>/dev/null || true
        else
            rm -f "$STATIC_CACHE_FILE.tmp"
        fi
    fi
}

if [[ "$SHOW_SYSTEM_INFO" == "true" ]]; then
    load_static_info

    UPTIME_VALUE="$(get_uptime)"
    PACKAGES_VALUE="$(get_packages)"
    DISPLAY_VALUE="$(get_display)"
    MEMORY_VALUE="$(get_memory)"
    DISK_VALUE="$(get_disk)"
    NETWORK_VALUE="$(get_network)"
    OS_AGE_VALUE="$(get_install_age "$OS_BIRTH_VALUE")"
fi

# ────────────────────────────────────────────────────────────────
# Esperar el panel Pokémon
# ────────────────────────────────────────────────────────────────

if ! wait "$RENDER_PID"; then
    pf_die "No se pudo obtener el panel Pokémon."
fi

PANEL_IMAGE=""
read -r PANEL_IMAGE < "$RENDER_OUTPUT_FILE" || true

if [[ -z "$PANEL_IMAGE" || ! -s "$PANEL_IMAGE" ]]; then
    pf_die "No se pudo obtener el panel Pokémon."
fi

# ────────────────────────────────────────────────────────────────
# Ajustar tamaños según terminal
# ────────────────────────────────────────────────────────────────

if ((SYSTEM_PANEL_MAX_WIDTH > 0 && TERMINAL_COLUMNS > SYSTEM_PANEL_MAX_WIDTH)); then
    CONTENT_WIDTH="$SYSTEM_PANEL_MAX_WIDTH"
else
    CONTENT_WIDTH="$TERMINAL_COLUMNS"
fi

if ((CONTENT_WIDTH < 90)); then
    CONTENT_WIDTH=90
fi

# Ícono + espacio + etiqueta de 10 + espacio.
LABEL_WIDTH=13

max_length() {
    local maximum=0
    local value=""

    for value in "$@"; do
        if ((${#value} > maximum)); then
            maximum="${#value}"
        fi
    done

    printf '%s' "$maximum"
}

LEFT_MAX_LENGTH="$(
    max_length \
        "$OS_VALUE" "$KERNEL_VALUE" "$UPTIME_VALUE" "$PACKAGES_VALUE" \
        "$SHELL_VALUE" "$DISPLAY_VALUE" "$WM_VALUE" "$TERMINAL_VALUE"
)"

RIGHT_MAX_LENGTH="$(
    max_length \
        "$CPU_VALUE" "$GPU_VALUE" "$MEMORY_VALUE" "$DISK_VALUE" \
        "$NETWORK_VALUE" "$OS_AGE_VALUE" "$MACHINE_VALUE" "$FONT_VALUE"
)"

# El separador va siempre en el centro de la terminal y cada columna
# mide lo justo para su texto más largo, a COLUMN_GAP del separador.
# Así el bloque completo queda centrado alrededor de la barra.
CENTER_COLUMN="$((CONTENT_WIDTH / 2))"

LEFT_BLOCK_WIDTH="$((LABEL_WIDTH + LEFT_MAX_LENGTH + COLUMN_GAP))"
RIGHT_BLOCK_WIDTH="$((COLUMN_GAP + LABEL_WIDTH + RIGHT_MAX_LENGTH))"

if ((LEFT_BLOCK_WIDTH <= CENTER_COLUMN)) &&
    ((RIGHT_BLOCK_WIDTH <= CONTENT_WIDTH - CENTER_COLUMN - 1)); then
    LEFT_INDENT="$((CENTER_COLUMN - LEFT_BLOCK_WIDTH))"
    LEFT_VALUE_WIDTH="$LEFT_MAX_LENGTH"
    RIGHT_VALUE_WIDTH="$RIGHT_MAX_LENGTH"
    LEFT_PAD_WIDTH="$((LEFT_MAX_LENGTH + COLUMN_GAP))"
    SEPARATOR_GAP="$COLUMN_GAP"
else
    # No entra: dos mitades iguales y se recortan los textos largos.
    LEFT_INDENT=0
    LEFT_VALUE_WIDTH="$((
        (CONTENT_WIDTH - 1 - 2 * LABEL_WIDTH - 2 * COLUMN_GAP) / 2
    ))"
    RIGHT_VALUE_WIDTH="$((
        CONTENT_WIDTH - 1 - 2 * LABEL_WIDTH - 2 * COLUMN_GAP - LEFT_VALUE_WIDTH
    ))"
    LEFT_PAD_WIDTH="$((LEFT_VALUE_WIDTH + COLUMN_GAP))"
    SEPARATOR_GAP="$COLUMN_GAP"
fi

# ────────────────────────────────────────────────────────────────
# Mostrar panel Pokémon
# ────────────────────────────────────────────────────────────────

clear

# El PNG ya tiene el tamaño exacto de la zona, así que ocupa todo el
# ancho sin reescalar. Después el cursor va justo debajo del panel.
kitten icat \
    --transfer-mode file \
    --align left \
    --scale-up \
    --place "${PANEL_COLUMNS}x${PANEL_ROWS}@0x0" \
    "$PANEL_IMAGE"

tput cup "$PANEL_ROWS" 0

if [[ "$RANDOM_SELECTION" == "true" ]]; then
    start_random_prefetch
fi

if [[ "$SHOW_SYSTEM_INFO" != "true" ]]; then
    exit 0
fi

# ────────────────────────────────────────────────────────────────
# Renderizar información inferior
# ────────────────────────────────────────────────────────────────

print_divider() {
    printf '%s' "$DARK_GRAY"
    repeat_character '─' "$CONTENT_WIDTH"
    printf '%s\n' "$RESET"
}

print_two_columns() {
    local left_color="$1"
    local left_icon="$2"
    local left_label="$3"
    local left_value="$4"

    local right_color="$5"
    local right_icon="$6"
    local right_label="$7"
    local right_value="$8"

    trim_text left_value "$left_value" "$LEFT_VALUE_WIDTH"
    trim_text right_value "$right_value" "$RIGHT_VALUE_WIDTH"

    printf '%*s' "$LEFT_INDENT" ''

    printf '%s%s %-10s%s ' \
        "$left_color" \
        "$left_icon" \
        "$left_label" \
        "$RESET"

    # Relleno manual: printf de Bash cuenta bytes, no caracteres, y
    # desalinea textos con tildes o símbolos UTF-8.
    printf '%s%*s' \
        "$left_value" \
        "$((LEFT_PAD_WIDTH - ${#left_value}))" ''

    printf '%s│%s' "$DARK_GRAY" "$RESET"

    printf '%*s' "$SEPARATOR_GAP" ''

    printf '%s%s %-10s%s ' \
        "$right_color" \
        "$right_icon" \
        "$right_label" \
        "$RESET"

    printf '%s\n' "$right_value"
}

print_divider

print_two_columns \
    "$RED" "󰣇" "OS" "$OS_VALUE" \
    "$PURPLE" "" "CPU" "$CPU_VALUE"

print_two_columns \
    "$RED" "󰘳" "Kernel" "$KERNEL_VALUE" \
    "$PURPLE" "󰢮" "GPU" "$GPU_VALUE"

print_two_columns \
    "$RED" "󰔟" "Uptime" "$UPTIME_VALUE" \
    "$PURPLE" "󰍛" "Memory" "$MEMORY_VALUE"

print_two_columns \
    "$GREEN" "󰏖" "Packages" "$PACKAGES_VALUE" \
    "$MAGENTA" "󰋊" "Disk" "$DISK_VALUE"

print_two_columns \
    "$PURPLE" "󰆍" "Shell" "$SHELL_VALUE" \
    "$MAGENTA" "󰛳" "Network" "$NETWORK_VALUE"

print_two_columns \
    "$GREEN" "󰍹" "Display" "$DISPLAY_VALUE" \
    "$ORANGE" "󰔚" "OS Age" "$OS_AGE_VALUE"

print_two_columns \
    "$YELLOW" "" "WM" "$WM_VALUE" \
    "$RED" "󰌢" "Machine" "$MACHINE_VALUE"

print_two_columns \
    "$YELLOW" "" "Terminal" "$TERMINAL_VALUE" \
    "$CYAN" "" "Font" "$FONT_VALUE"

# ────────────────────────────────────────────────────────────────
# Paleta inferior
# ────────────────────────────────────────────────────────────────

if [[ "$SHOW_COLOR_PALETTE" == "true" ]]; then
    printf '\n'

    PALETTE_LENGTH=22
    PALETTE_PADDING="$(((CONTENT_WIDTH - PALETTE_LENGTH) / 2))"

    if ((PALETTE_PADDING < 0)); then
        PALETTE_PADDING=0
    fi

    printf '%*s' "$PALETTE_PADDING" ''

    printf '%s●%s  ' "$WHITE" "$RESET"
    printf '%s●%s  ' "$GRAY" "$RESET"
    printf '%s●%s  ' "$BLUE" "$RESET"
    printf '%s●%s  ' "$PURPLE" "$RESET"
    printf '%s●%s  ' "$MAGENTA" "$RESET"
    printf '%s●%s  ' "$GREEN" "$RESET"
    printf '%s●%s  ' "$YELLOW" "$RESET"
    printf '%s●%s\n' "$RED" "$RESET"
fi