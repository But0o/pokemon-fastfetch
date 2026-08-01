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

mkdir -p "$CONFIG_ROOT"

RENDER_SCRIPT="$SCRIPT_DIR/render-pokemon.sh"

# ────────────────────────────────────────────────────────────────
# Configuración visual
# ────────────────────────────────────────────────────────────────

# Cantidad de filas que ocupará el panel Pokémon en Kitty.
POKEMON_PANEL_ROWS="${POKEMON_PANEL_ROWS:-22}"

# Ancho máximo del contenido inferior.
SYSTEM_PANEL_MAX_WIDTH="${SYSTEM_PANEL_MAX_WIDTH:-150}"

# Espacio entre las dos columnas inferiores.
COLUMN_GAP="${COLUMN_GAP:-6}"

SHOW_SYSTEM_INFO="${SHOW_SYSTEM_INFO:-true}"
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


trim_text() {
    local value="${1:-}"
    local maximum="${2:-40}"

    value="${value//$'\n'/ }"
    value="${value//$'\r'/ }"

    while [[ "$value" == *"  "* ]]; do
        value="${value//  / }"
    done

    if ((${#value} > maximum)); then
        printf '%s…' "${value:0:$((maximum - 1))}"
    else
        printf '%s' "$value"
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

    if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        bytes=0
    fi

    awk \
        -v bytes="$bytes" \
        'BEGIN {
            split("B KiB MiB GiB TiB", units, " ")
            index = 1
            value = bytes

            while (value >= 1024 && index < 5) {
                value /= 1024
                index++
            }

            if (index <= 2) {
                printf "%.0f %s", value, units[index]
            } else {
                printf "%.2f %s", value, units[index]
            }
        }'
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

    if ((amount <= 0)); then
        return
    fi

    printf '%*s' "$amount" '' |
        tr ' ' "$character"
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


pf_require_json "$POKEDEX_FILE" "La caché Pokédex"

pf_require_executable "$RENDER_SCRIPT" "El renderizador Pokémon"

# ────────────────────────────────────────────────────────────────
# Procesar argumentos
# ────────────────────────────────────────────────────────────────

REQUEST=""
FORCE_RERENDER=false

case "${1:-}" in
    --set)
        FIXED_REQUEST="${2:-}"

        if [[ -z "$FIXED_REQUEST" ]]; then
            pf_error "Tenés que indicar un Pokémon por nombre o número."
            echo
            echo "Ejemplos:"
            echo "  pokemon-set pikachu"
            echo "  pokemon-set 25"
            exit 1
        fi

        # Comprobar que el Pokémon existe.
        TEST_PANEL="$("$RENDER_SCRIPT" "$FIXED_REQUEST" 2>/dev/null || true)"

        if [[ -z "$TEST_PANEL" || ! -s "$TEST_PANEL" ]]; then
            pf_die "No se encontró el Pokémon: $FIXED_REQUEST"
        fi

        printf '%s\n' "$FIXED_REQUEST" > "$FIXED_POKEMON_FILE"

        echo "Pokémon fijo configurado: $FIXED_REQUEST"
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
        REQUEST="$(
            jq -r '
                to_entries
                | map(
                    select(
                        (
                            .value.image
                            // ""
                        )
                        | length > 0
                    )
                )
                | .[].key
            ' "$POKEDEX_FILE" |
                shuf --head-count=1
        )"
        ;;

    "")
        if [[ -s "$FIXED_POKEMON_FILE" ]]; then
            REQUEST="$(head -n 1 "$FIXED_POKEMON_FILE")"
        else
            REQUEST="$(
                jq -r '
                    to_entries
                    | map(
                        select(
                            (
                                .value.image
                                // ""
                            )
                            | length > 0
                        )
                    )
                    | .[].key
                ' "$POKEDEX_FILE" |
                    shuf --head-count=1
            )"
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
# Forzar regeneración opcional
# ────────────────────────────────────────────────────────────────

if [[ "$FORCE_RERENDER" == "true" ]]; then
    SAFE_REQUEST="$(
        printf '%s' "$REQUEST" |
            tr '[:upper:]' '[:lower:]' |
            sed \
                -e 's/[[:space:]_]/-/g' \
                -e 's/[^a-z0-9.-]/-/g'
    )"

    rm -f \
        "$CACHE_ROOT/panels-v2/${SAFE_REQUEST}.png" \
        "$CACHE_ROOT/panels-v2/${SAFE_REQUEST}-"*.png \
        2>/dev/null ||
        true
fi

# ────────────────────────────────────────────────────────────────
# Obtener panel Pokémon
# ────────────────────────────────────────────────────────────────

PANEL_IMAGE="$(
    "$RENDER_SCRIPT" "$REQUEST"
)"

if [[ -z "$PANEL_IMAGE" || ! -s "$PANEL_IMAGE" ]]; then
    pf_die "No se pudo obtener el panel Pokémon."
fi

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
    local uptime_value=""

    if pf_command_exists uptime; then
        uptime_value="$(
            uptime -p 2>/dev/null |
                sed \
                    -e 's/^up //' \
                    -e 's/ days\?/d/g' \
                    -e 's/ hours\?/h/g' \
                    -e 's/ minutes\?/m/g' \
                    -e 's/,//g' ||
                true
        )"
    fi

    if [[ -z "$uptime_value" && -r /proc/uptime ]]; then
        uptime_value="$(
            awk '
                {
                    seconds = int($1)
                    days = int(seconds / 86400)
                    hours = int((seconds % 86400) / 3600)
                    minutes = int((seconds % 3600) / 60)

                    if (days > 0) {
                        printf "%dd ", days
                    }

                    if (hours > 0 || days > 0) {
                        printf "%dh ", hours
                    }

                    printf "%dm", minutes
                }
            ' /proc/uptime
        )"
    fi

    safe_value "$uptime_value"
}

get_packages() {
    local packages=""

    if pf_command_exists pacman; then
        packages="$(
            pacman -Qq 2>/dev/null |
                wc -l |
                tr -d ' '
        )"

        printf '%s (pacman)' "$packages"
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
    local disk_line=""
    local total=""
    local used=""
    local percent=""
    local filesystem=""

    disk_line="$(
        df \
            --block-size=1 \
            --output=size,used,pcent,fstype \
            / \
            2>/dev/null |
            tail -n 1 |
            awk '{$1=$1; print}' ||
            true
    )"

    if [[ -z "$disk_line" ]]; then
        printf 'No disponible'
        return
    fi

    read -r total used percent filesystem <<< "$disk_line"

    printf '%s / %s (%s) - %s' \
        "$(format_bytes "$used")" \
        "$(format_bytes "$total")" \
        "$percent" \
        "$filesystem"
}

get_network() {
    local interface=""
    local address=""

    if pf_command_exists ip; then
        interface="$(
            ip route show default 2>/dev/null |
                awk '
                    {
                        for (i = 1; i <= NF; i++) {
                            if ($i == "dev") {
                                print $(i + 1)
                                exit
                            }
                        }
                    }
                ' ||
                true
        )"

        if [[ -n "$interface" ]]; then
            address="$(
                ip \
                    -o \
                    -4 \
                    address \
                    show \
                    dev "$interface" \
                    2>/dev/null |
                    awk '{print $4; exit}' ||
                    true
            )"
        fi
    fi

    if [[ -n "$interface" && -n "$address" ]]; then
        printf '%s %s' "$interface" "$address"
    elif [[ -n "$interface" ]]; then
        printf '%s' "$interface"
    else
        printf 'No disponible'
    fi
}

get_install_age() {
    local timestamp=""
    local current=""
    local days=""

    if [[ -e / ]]; then
        timestamp="$(
            stat \
                --format='%W' \
                / \
                2>/dev/null ||
                printf '0'
        )"
    fi

    if [[ "$timestamp" =~ ^[0-9]+$ ]] && ((timestamp > 0)); then
        current="$(date +%s)"
        days="$(((current - timestamp) / 86400))"

        printf '%s días' "$days"
        return
    fi

    if pf_command_exists tune2fs; then
        printf 'No disponible'
        return
    fi

    printf 'No disponible'
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

OS_VALUE="$(get_os)"
KERNEL_VALUE="$(get_kernel)"
UPTIME_VALUE="$(get_uptime)"
PACKAGES_VALUE="$(get_packages)"
SHELL_VALUE="$(get_shell)"
DISPLAY_VALUE="$(get_display)"
WM_VALUE="$(get_window_manager)"
TERMINAL_VALUE="$(get_terminal)"
FONT_VALUE="$(get_font)"

CPU_VALUE="$(get_cpu)"
GPU_VALUE="$(get_gpu)"
MEMORY_VALUE="$(get_memory)"
DISK_VALUE="$(get_disk)"
NETWORK_VALUE="$(get_network)"
OS_AGE_VALUE="$(get_install_age)"
MACHINE_VALUE="$(get_machine)"

# ────────────────────────────────────────────────────────────────
# Ajustar tamaños según terminal
# ────────────────────────────────────────────────────────────────

TERMINAL_COLUMNS="$(get_terminal_columns)"

if ((TERMINAL_COLUMNS > SYSTEM_PANEL_MAX_WIDTH)); then
    CONTENT_WIDTH="$SYSTEM_PANEL_MAX_WIDTH"
else
    CONTENT_WIDTH="$TERMINAL_COLUMNS"
fi

if ((CONTENT_WIDTH < 90)); then
    CONTENT_WIDTH=90
fi

LEFT_COLUMN_WIDTH="$(((CONTENT_WIDTH - COLUMN_GAP - 1) / 2))"
RIGHT_COLUMN_WIDTH="$((CONTENT_WIDTH - LEFT_COLUMN_WIDTH - COLUMN_GAP - 1))"

LEFT_LABEL_WIDTH=13
RIGHT_LABEL_WIDTH=13

LEFT_VALUE_WIDTH="$((LEFT_COLUMN_WIDTH - LEFT_LABEL_WIDTH - 2))"
RIGHT_VALUE_WIDTH="$((RIGHT_COLUMN_WIDTH - RIGHT_LABEL_WIDTH - 2))"

# ────────────────────────────────────────────────────────────────
# Mostrar panel Pokémon
# ────────────────────────────────────────────────────────────────

clear

# El protocolo gráfico de Kitty coloca la imagen en una zona fija.
# Después posicionamos el cursor debajo del panel.
kitten icat \
    --transfer-mode file \
    --align left \
    --scale-up \
    --place "${CONTENT_WIDTH}x${POKEMON_PANEL_ROWS}@0x0" \
    "$PANEL_IMAGE"

tput cup "$POKEMON_PANEL_ROWS" 0

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

    left_value="$(trim_text "$left_value" "$LEFT_VALUE_WIDTH")"
    right_value="$(trim_text "$right_value" "$RIGHT_VALUE_WIDTH")"

    printf '%s%s %-10s%s ' \
        "$left_color" \
        "$left_icon" \
        "$left_label" \
        "$RESET"

    printf '%-*s' \
        "$LEFT_VALUE_WIDTH" \
        "$left_value"

    printf '%s│%s' "$DARK_GRAY" "$RESET"

    printf '%*s' "$COLUMN_GAP" ''

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
