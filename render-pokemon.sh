#!/usr/bin/env bash

set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Pokémon Fastfetch
#
# Pokémon panel renderer.
#
# Responsibilities:
#   - Resolve local Pokédex data
#   - Locate Pokémon artwork
#   - Generate SVG assets
#   - Render PNG panels
#   - Manage the render cache
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

PANELS_DIR="$CACHE_ROOT/panels-v2"
TEMP_DIR="$CACHE_ROOT/render-temp"

POKEMON_DIR="${POKEMON_DIR:-$HOME/.local/share/pokimg/images}"

PANEL_WIDTH="${POKEMON_PANEL_WIDTH:-1580}"
PANEL_HEIGHT="${POKEMON_PANEL_HEIGHT:-470}"

mkdir -p "$PANELS_DIR"
mkdir -p "$TEMP_DIR"

# ────────────────────────────────────────────────────────────────
# Dependencias
# ────────────────────────────────────────────────────────────────

pf_require_commands \
    jq \
    magick \
    sha256sum \
    fc-match \
    sed \
    awk \
    find

pf_require_json "$POKEDEX_FILE" "La caché Pokédex"
pf_require_directory "$POKEMON_DIR" "El directorio de imágenes"

# ────────────────────────────────────────────────────────────────
# Ayuda
# ────────────────────────────────────────────────────────────────

show_help() {
    cat <<EOF

Pokémon Fastfetch renderer v${APP_VERSION}

Uso:

  render-pokemon.sh charizard
  render-pokemon.sh pikachu
  render-pokemon.sh 6
  render-pokemon.sh 25

El script genera un panel PNG y muestra su ruta absoluta.

Variables opcionales:

  POKEMON_DIR
      Carpeta que contiene las imágenes.

  POKEMON_PANEL_WIDTH
      Ancho del panel. Predeterminado: 1580.

  POKEMON_PANEL_HEIGHT
      Alto del panel. Predeterminado: 470.
EOF
}

# Procesar opciones informativas antes de validar dependencias o caché.
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;

    --version|-v)
        printf 'Pokémon Fastfetch renderer v%s\n' "$APP_VERSION"
        exit 0
        ;;
esac

REQUEST="${1:-}"

case "$REQUEST" in
    "")
        pf_error "Tenés que indicar un Pokémon."
        echo "Ejemplo:" >&2
        echo "  $0 charizard" >&2
        exit 1
        ;;
esac

# ────────────────────────────────────────────────────────────────
# Utilidades
# ────────────────────────────────────────────────────────────────

normalize_name() {
    local VALUE="$1"

    VALUE="${VALUE,,}"

    VALUE="$(
        printf '%s' "$VALUE" |
            sed \
                -e 's/[[:space:]_]/-/g' \
                -e "s/'//g" \
                -e 's/\.//g' \
                -e 's/♀/-f/g' \
                -e 's/♂/-m/g' \
                -e 's/--*/-/g' \
                -e 's/^-//' \
                -e 's/-$//'
    )"

    case "$VALUE" in
        mrmime | mr-mime)
            VALUE="mr-mime"
            ;;

        mimejr | mime-jr)
            VALUE="mime-jr"
            ;;

        mrrime | mr-rime)
            VALUE="mr-rime"
            ;;

        nidoranf | nidoran-f)
            VALUE="nidoran-f"
            ;;

        nidoranm | nidoran-m)
            VALUE="nidoran-m"
            ;;

        farfetchd | farfetch-d)
            VALUE="farfetchd"
            ;;

        sirfetchd | sirfetch-d)
            VALUE="sirfetchd"
            ;;

        hooh | ho-oh)
            VALUE="ho-oh"
            ;;

        porygonz | porygon-z)
            VALUE="porygon-z"
            ;;

        typenull | type-null)
            VALUE="type-null"
            ;;

        jangmoo | jangmo-o)
            VALUE="jangmo-o"
            ;;

        hakamoo | hakamo-o)
            VALUE="hakamo-o"
            ;;

        kommoo | kommo-o)
            VALUE="kommo-o"
            ;;
    esac

    printf '%s' "$VALUE"
}

title_case() {
    local VALUE="$1"

    printf '%s' "$VALUE" |
        sed 's/-/ /g' |
        awk '
            {
                for (i = 1; i <= NF; i++) {
                    $i = toupper(substr($i, 1, 1)) substr($i, 2)
                }

                print
            }
        '
}

escape_xml() {
    local VALUE="$1"

    VALUE="${VALUE//&/&amp;}"
    VALUE="${VALUE//</&lt;}"
    VALUE="${VALUE//>/&gt;}"
    VALUE="${VALUE//\"/&quot;}"
    VALUE="${VALUE//\'/&apos;}"

    printf '%s' "$VALUE"
}

truncate_text() {
    local VALUE="$1"
    local MAX_LENGTH="$2"

    if ((${#VALUE} > MAX_LENGTH)); then
        printf '%s…' "${VALUE:0:$((MAX_LENGTH - 1))}"
    else
        printf '%s' "$VALUE"
    fi
}

type_color() {
    case "$1" in
        normal)   printf '#A8A77A' ;;
        fire)     printf '#FF5A4F' ;;
        water)    printf '#6390F0' ;;
        electric) printf '#F7D02C' ;;
        grass)    printf '#59D578' ;;
        ice)      printf '#78D8D5' ;;
        fighting) printf '#D13A34' ;;
        poison)   printf '#B65DCC' ;;
        ground)   printf '#DDBD62' ;;
        flying)   printf '#63D5E8' ;;
        psychic)  printf '#F95587' ;;
        bug)      printf '#A6B91A' ;;
        rock)     printf '#B6A136' ;;
        ghost)    printf '#8B6AB1' ;;
        dragon)   printf '#7950F2' ;;
        dark)     printf '#80675A' ;;
        steel)    printf '#B7B7CE' ;;
        fairy)    printf '#E28FB1' ;;
        *)        printf '#A9A9B5' ;;
    esac
}

type_icon() {
    case "$1" in
        fire)     printf '󰈸' ;;
        water)    printf '󰖌' ;;
        electric) printf '󰖂' ;;
        grass)    printf '󰌪' ;;
        ice)      printf '󰼶' ;;
        fighting) printf '󰓥' ;;
        poison)   printf '󰟻' ;;
        ground)   printf '󰏐' ;;
        flying)   printf '󰳆' ;;
        psychic)  printf '󰯙' ;;
        bug)      printf '󰨭' ;;
        rock)     printf '󰠤' ;;
        ghost)    printf '󰊠' ;;
        dragon)   printf '󰩃' ;;
        dark)     printf '󰽥' ;;
        steel)    printf '󰷛' ;;
        fairy)    printf '󰔱' ;;
        normal)   printf '●' ;;
        *)        printf '●' ;;
    esac
}

generation_roman() {
    case "$1" in
        1) printf 'I' ;;
        2) printf 'II' ;;
        3) printf 'III' ;;
        4) printf 'IV' ;;
        5) printf 'V' ;;
        6) printf 'VI' ;;
        7) printf 'VII' ;;
        8) printf 'VIII' ;;
        9) printf 'IX' ;;
        *) printf '?' ;;
    esac
}

calculate_bar_width() {
    local VALUE="$1"
    local MAX_WIDTH=285
    local MAX_STAT=180
    local RESULT

    if ! [[ "$VALUE" =~ ^[0-9]+$ ]]; then
        VALUE=0
    fi

    RESULT=$((VALUE * MAX_WIDTH / MAX_STAT))

    if ((RESULT < 4)); then
        RESULT=4
    fi

    if ((RESULT > MAX_WIDTH)); then
        RESULT="$MAX_WIDTH"
    fi

    printf '%s' "$RESULT"
}

# ────────────────────────────────────────────────────────────────
# Seleccionar entrada
# ────────────────────────────────────────────────────────────────

if [[ "$REQUEST" =~ ^[0-9]+$ ]]; then
    REQUEST_ID="$((10#$REQUEST))"

    POKEMON_KEY="$(
        jq -r \
            --argjson requested_id "$REQUEST_ID" \
            '
                to_entries
                | map(
                    select(
                        (.value.id // 0) == $requested_id
                    )
                )
                | .[0].key // empty
            ' \
            "$POKEDEX_FILE"
    )"
else
    NORMALIZED_REQUEST="$(normalize_name "$REQUEST")"

    POKEMON_KEY="$(
        jq -r \
            --arg requested_name "$NORMALIZED_REQUEST" \
            '
                if has($requested_name) then
                    $requested_name
                else
                    (
                        to_entries
                        | map(
                            select(
                                (
                                    .value.api_name
                                    // ""
                                ) == $requested_name
                            )
                        )
                        | .[0].key // empty
                    )
                end
            ' \
            "$POKEDEX_FILE"
    )"
fi

if [[ -z "$POKEMON_KEY" ]]; then
    pf_die "No se encontró el Pokémon: $REQUEST"
fi

POKEMON_DATA="$(
    jq -c \
        --arg key "$POKEMON_KEY" \
        '.[$key]' \
        "$POKEDEX_FILE"
)"

if [[ -z "$POKEMON_DATA" || "$POKEMON_DATA" == "null" ]]; then
    pf_die "No se pudo leer la información de: $POKEMON_KEY"
fi

# ────────────────────────────────────────────────────────────────
# Leer información
# ────────────────────────────────────────────────────────────────

ID="$(jq -r '.id // 0' <<< "$POKEMON_DATA")"
NUMBER="$(printf '%03d' "$ID")"

NAME="$(
    jq -r '
        .name
        // .api_name
        // "Desconocido"
    ' <<< "$POKEMON_DATA"
)"

API_NAME="$(
    jq -r '
        .api_name
        // empty
    ' <<< "$POKEMON_DATA"
)"

IMAGE_VALUE="$(
    jq -r '
        .image
        // empty
    ' <<< "$POKEMON_DATA"
)"

PRIMARY_TYPE="$(
    jq -r '
        .types[0]
        // "normal"
    ' <<< "$POKEMON_DATA"
)"

SECONDARY_TYPE="$(
    jq -r '
        .types[1]
        // empty
    ' <<< "$POKEMON_DATA"
)"

REGION="$(
    jq -r '
        .region
        // "Desconocida"
    ' <<< "$POKEMON_DATA"
)"

GENERATION="$(
    jq -r '
        .generation
        // 0
    ' <<< "$POKEMON_DATA"
)"

HEIGHT="$(
    jq -r '
        .height_m
        // 0
    ' <<< "$POKEMON_DATA"
)"

WEIGHT="$(
    jq -r '
        .weight_kg
        // 0
    ' <<< "$POKEMON_DATA"
)"

IS_LEGENDARY="$(
    jq -r '
        .legendary
        // false
    ' <<< "$POKEMON_DATA"
)"

IS_MYTHICAL="$(
    jq -r '
        .mythical
        // false
    ' <<< "$POKEMON_DATA"
)"

IS_BABY="$(
    jq -r '
        .baby
        // false
    ' <<< "$POKEMON_DATA"
)"

HP="$(jq -r '.stats.hp // 0' <<< "$POKEMON_DATA")"
ATK="$(jq -r '.stats.attack // 0' <<< "$POKEMON_DATA")"
DEF="$(jq -r '.stats.defense // 0' <<< "$POKEMON_DATA")"
SPATK="$(jq -r '.stats.special_attack // 0' <<< "$POKEMON_DATA")"
SPDEF="$(jq -r '.stats.special_defense // 0' <<< "$POKEMON_DATA")"
SPEED="$(jq -r '.stats.speed // 0' <<< "$POKEMON_DATA")"

TOTAL="$((HP + ATK + DEF + SPATK + SPDEF + SPEED))"

ABILITIES="$(
    jq -r '
        (
            .abilities
            // []
        )
        | map(
            gsub("-"; " ")
            | split(" ")
            | map(
                if length > 0 then
                    (
                        .[0:1]
                        | ascii_upcase
                    ) + .[1:]
                else
                    .
                end
            )
            | join(" ")
        )
        | join(", ")
    ' <<< "$POKEMON_DATA"
)"

if [[ -z "$ABILITIES" ]]; then
    ABILITIES="Desconocidas"
fi

if [[ "$IS_MYTHICAL" == "true" ]]; then
    CATEGORY="Mítico"
elif [[ "$IS_LEGENDARY" == "true" ]]; then
    CATEGORY="Legendario"
elif [[ "$IS_BABY" == "true" ]]; then
    CATEGORY="Bebé"
else
    CATEGORY="Normal"
fi

GENERATION_ROMAN="$(generation_roman "$GENERATION")"

PRIMARY_TYPE_NAME="$(title_case "$PRIMARY_TYPE")"
PRIMARY_TYPE_COLOR="$(type_color "$PRIMARY_TYPE")"
PRIMARY_TYPE_ICON="$(type_icon "$PRIMARY_TYPE")"

if [[ -n "$SECONDARY_TYPE" ]]; then
    SECONDARY_TYPE_NAME="$(title_case "$SECONDARY_TYPE")"
    SECONDARY_TYPE_COLOR="$(type_color "$SECONDARY_TYPE")"
    SECONDARY_TYPE_ICON="$(type_icon "$SECONDARY_TYPE")"
else
    SECONDARY_TYPE_NAME=""
    SECONDARY_TYPE_COLOR="$PRIMARY_TYPE_COLOR"
    SECONDARY_TYPE_ICON=""
fi

# Limitar textos para evitar que se salgan del panel.
NAME="$(truncate_text "$NAME" 22)"
ABILITIES="$(truncate_text "$ABILITIES" 32)"
REGION="$(truncate_text "$REGION" 18)"
CATEGORY="$(truncate_text "$CATEGORY" 18)"

# Escapar valores antes de insertarlos en SVG.
SVG_NAME="$(escape_xml "$NAME")"
SVG_ABILITIES="$(escape_xml "$ABILITIES")"
SVG_REGION="$(escape_xml "$REGION")"
SVG_CATEGORY="$(escape_xml "$CATEGORY")"

SVG_PRIMARY_NAME="$(escape_xml "$PRIMARY_TYPE_NAME")"
SVG_PRIMARY_ICON="$(escape_xml "$PRIMARY_TYPE_ICON")"

SVG_SECONDARY_NAME="$(escape_xml "$SECONDARY_TYPE_NAME")"
SVG_SECONDARY_ICON="$(escape_xml "$SECONDARY_TYPE_ICON")"

# ────────────────────────────────────────────────────────────────
# Encontrar imagen
# ────────────────────────────────────────────────────────────────

SELECTED_IMAGE=""

if [[ -n "$IMAGE_VALUE" ]]; then
    if [[ "$IMAGE_VALUE" = /* && -f "$IMAGE_VALUE" ]]; then
        SELECTED_IMAGE="$IMAGE_VALUE"
    elif [[ -f "$POKEMON_DIR/$IMAGE_VALUE" ]]; then
        SELECTED_IMAGE="$POKEMON_DIR/$IMAGE_VALUE"
    fi
fi

if [[ -z "$SELECTED_IMAGE" && -n "$API_NAME" ]]; then
    SELECTED_IMAGE="$(
        find "$POKEMON_DIR" \
            -type f \
            \( \
                -iname "$API_NAME.png" \
                -o -iname "$API_NAME.webp" \
                -o -iname "$API_NAME.gif" \
            \) \
            2>/dev/null |
            head -n 1
    )"
fi

if [[ -z "$SELECTED_IMAGE" ]]; then
    SELECTED_IMAGE="$(
        find "$POKEMON_DIR" \
            -type f \
            \( \
                -iname "$POKEMON_KEY.png" \
                -o -iname "$POKEMON_KEY.webp" \
                -o -iname "$POKEMON_KEY.gif" \
            \) \
            2>/dev/null |
            head -n 1
    )"
fi

if [[ -z "$SELECTED_IMAGE" || ! -f "$SELECTED_IMAGE" ]]; then
    pf_error "No se encontró la imagen de $NAME."
    pf_error "Directorio consultado: $POKEMON_DIR"
    exit 1
fi

# ────────────────────────────────────────────────────────────────
# Fuente
# ────────────────────────────────────────────────────────────────

find_font() {
    local FONT_PATH=""

    for FONT_NAME in \
        "JetBrainsMono Nerd Font" \
        "JetBrains Mono Nerd Font" \
        "JetBrainsMonoNL Nerd Font" \
        "JetBrains Mono"
    do
        FONT_PATH="$(
            fc-match \
                -f '%{file}\n' \
                "$FONT_NAME" \
                2>/dev/null |
                head -n 1
        )"

        if [[ -n "$FONT_PATH" && -f "$FONT_PATH" ]]; then
            printf '%s' "$FONT_PATH"
            return 0
        fi
    done

    return 1
}

FONT_FILE="$(find_font || true)"

if [[ -z "$FONT_FILE" ]]; then
    pf_die "No se encontró JetBrains Mono Nerd Font."
fi

# ────────────────────────────────────────────────────────────────
# Caché del panel
# ────────────────────────────────────────────────────────────────

IMAGE_MTIME="$(
    stat \
        --format='%Y' \
        "$SELECTED_IMAGE" \
        2>/dev/null ||
        printf '0'
)"

RENDER_VERSION="pokemon-fastfetch-v2-render-4"

CACHE_HASH="$(
    {
        printf '%s' "$RENDER_VERSION"
        printf '%s' "$PANEL_WIDTH"
        printf '%s' "$PANEL_HEIGHT"
        printf '%s' "$IMAGE_MTIME"
        printf '%s' "$POKEMON_DATA"
    } |
        sha256sum |
        awk '{print substr($1, 1, 16)}'
)"

SAFE_KEY="$(
    printf '%s' "$POKEMON_KEY" |
        sed 's/[^a-zA-Z0-9._-]/-/g'
)"

FINAL_PANEL="$PANELS_DIR/${SAFE_KEY}-${CACHE_HASH}.png"
CURRENT_PANEL="$PANELS_DIR/${SAFE_KEY}.png"

if [[ -s "$FINAL_PANEL" ]]; then
    ln -sfn "$(basename "$FINAL_PANEL")" "$CURRENT_PANEL"

    printf '%s\n' "$FINAL_PANEL"
    exit 0
fi

# ────────────────────────────────────────────────────────────────
# Medidas del diseño
# ────────────────────────────────────────────────────────────────

SPRITE_X=20
SPRITE_Y=25
SPRITE_WIDTH=465
SPRITE_HEIGHT=415

STATS_X=520
RIGHT_COLUMN_X=1110

HP_BAR="$(calculate_bar_width "$HP")"
ATK_BAR="$(calculate_bar_width "$ATK")"
DEF_BAR="$(calculate_bar_width "$DEF")"
SPATK_BAR="$(calculate_bar_width "$SPATK")"
SPDEF_BAR="$(calculate_bar_width "$SPDEF")"
SPEED_BAR="$(calculate_bar_width "$SPEED")"

SVG_FILE="$TEMP_DIR/${SAFE_KEY}-${CACHE_HASH}.svg"
SPRITE_FILE="$TEMP_DIR/${SAFE_KEY}-${CACHE_HASH}-sprite.png"
BASE_FILE="$TEMP_DIR/${SAFE_KEY}-${CACHE_HASH}-base.png"

# ────────────────────────────────────────────────────────────────
# Generar SVG
# ────────────────────────────────────────────────────────────────

cat > "$SVG_FILE" <<EOF
<svg
    xmlns="http://www.w3.org/2000/svg"
    width="$PANEL_WIDTH"
    height="$PANEL_HEIGHT"
    viewBox="0 0 $PANEL_WIDTH $PANEL_HEIGHT"
>
    <rect
        x="0"
        y="0"
        width="$PANEL_WIDTH"
        height="$PANEL_HEIGHT"
        fill="none"
    />

    <style>
        .text {
            font-family: "JetBrainsMono Nerd Font", "JetBrains Mono", monospace;
            fill: #E8E8EC;
        }

        .muted {
            font-family: "JetBrainsMono Nerd Font", "JetBrains Mono", monospace;
            fill: #9B9BA8;
        }

        .label {
            font-family: "JetBrainsMono Nerd Font", "JetBrains Mono", monospace;
            fill: #DADAE0;
            font-weight: 700;
        }

        .value {
            font-family: "JetBrainsMono Nerd Font", "JetBrains Mono", monospace;
            fill: #F0F0F3;
        }

        .divider {
            stroke: #555562;
            stroke-width: 1.5;
        }

        .bar-background {
            fill: #30303C;
        }
    </style>

    <!-- Nombre y número -->
    <text
        x="$STATS_X"
        y="55"
        class="text"
        font-size="31"
        font-weight="700"
    >$SVG_NAME</text>

    <text
        x="755"
        y="55"
        class="muted"
        font-size="25"
    >#$NUMBER</text>

    <!-- Tipo -->
    <text
        x="$STATS_X"
        y="98"
        class="muted"
        font-size="22"
    >Tipo</text>

    <rect
        x="665"
        y="68"
        width="145"
        height="39"
        rx="7"
        fill="none"
        stroke="$PRIMARY_TYPE_COLOR"
        stroke-width="1.5"
    />

    <text
        x="680"
        y="95"
        font-family="JetBrainsMono Nerd Font, JetBrains Mono, monospace"
        font-size="21"
        font-weight="700"
        fill="$PRIMARY_TYPE_COLOR"
    >$SVG_PRIMARY_ICON $SVG_PRIMARY_NAME</text>
EOF

if [[ -n "$SECONDARY_TYPE" ]]; then
    cat >> "$SVG_FILE" <<EOF
    <text
        x="820"
        y="96"
        class="muted"
        font-size="23"
    >/</text>

    <rect
        x="845"
        y="68"
        width="165"
        height="39"
        rx="7"
        fill="none"
        stroke="$SECONDARY_TYPE_COLOR"
        stroke-width="1.5"
    />

    <text
        x="860"
        y="95"
        font-family="JetBrainsMono Nerd Font, JetBrains Mono, monospace"
        font-size="21"
        font-weight="700"
        fill="$SECONDARY_TYPE_COLOR"
    >$SVG_SECONDARY_ICON $SVG_SECONDARY_NAME</text>
EOF
fi

cat >> "$SVG_FILE" <<EOF
    <!-- Estadísticas -->
    <text x="$STATS_X" y="151" class="label" font-size="21">HP</text>
    <text x="$STATS_X" y="194" class="label" font-size="21">ATK</text>
    <text x="$STATS_X" y="237" class="label" font-size="21">DEF</text>
    <text x="$STATS_X" y="280" class="label" font-size="21">SPATK</text>
    <text x="$STATS_X" y="323" class="label" font-size="21">SPDEF</text>
    <text x="$STATS_X" y="366" class="label" font-size="21">SPD</text>

    <text x="615" y="151" class="text" font-size="20">♥</text>
    <text x="615" y="194" class="text" font-size="20">×</text>
    <text x="615" y="237" class="text" font-size="20">●</text>
    <text x="615" y="280" class="text" font-size="20">★</text>
    <text x="615" y="323" class="text" font-size="20">◆</text>
    <text x="615" y="366" class="text" font-size="20">↦</text>

    <!-- Fondos de barra -->
    <rect x="660" y="131" width="285" height="23" rx="2" class="bar-background" />
    <rect x="660" y="174" width="285" height="23" rx="2" class="bar-background" />
    <rect x="660" y="217" width="285" height="23" rx="2" class="bar-background" />
    <rect x="660" y="260" width="285" height="23" rx="2" class="bar-background" />
    <rect x="660" y="303" width="285" height="23" rx="2" class="bar-background" />
    <rect x="660" y="346" width="285" height="23" rx="2" class="bar-background" />

    <!-- Barras -->
    <rect x="660" y="131" width="$HP_BAR" height="23" rx="2" fill="#FF575F" />
    <rect x="660" y="174" width="$ATK_BAR" height="23" rx="2" fill="#FF922B" />
    <rect x="660" y="217" width="$DEF_BAR" height="23" rx="2" fill="#F4EA68" />
    <rect x="660" y="260" width="$SPATK_BAR" height="23" rx="2" fill="#B477ED" />
    <rect x="660" y="303" width="$SPDEF_BAR" height="23" rx="2" fill="#51DA7B" />
    <rect x="660" y="346" width="$SPEED_BAR" height="23" rx="2" fill="#64CFE4" />

    <!-- Valores -->
    <text x="975" y="151" class="value" font-size="21">$HP</text>
    <text x="975" y="194" class="value" font-size="21">$ATK</text>
    <text x="975" y="237" class="value" font-size="21">$DEF</text>
    <text x="975" y="280" class="value" font-size="21">$SPATK</text>
    <text x="975" y="323" class="value" font-size="21">$SPDEF</text>
    <text x="975" y="366" class="value" font-size="21">$SPEED</text>

    <line
        x1="$STATS_X"
        y1="390"
        x2="1015"
        y2="390"
        class="divider"
    />

    <text
        x="$STATS_X"
        y="428"
        class="label"
        font-size="23"
    >TOTAL</text>

    <text
        x="665"
        y="428"
        class="value"
        font-size="23"
    >$TOTAL</text>

    <!-- Separador columna derecha -->
    <line
        x1="1065"
        y1="72"
        x2="1065"
        y2="420"
        class="divider"
    />

    <!-- Información derecha -->
    <text
        x="$RIGHT_COLUMN_X"
        y="122"
        font-family="JetBrainsMono Nerd Font, JetBrains Mono, monospace"
        font-size="22"
        font-weight="700"
        fill="#946BFF"
    >󰓎</text>

    <text x="1150" y="122" class="muted" font-size="21" font-weight="700">Habilidades</text>
    <text x="1355" y="122" class="value" font-size="21">$SVG_ABILITIES</text>

    <text
        x="$RIGHT_COLUMN_X"
        y="172"
        font-family="JetBrainsMono Nerd Font, JetBrains Mono, monospace"
        font-size="22"
        font-weight="700"
        fill="#82DA42"
    >󰍎</text>

    <text x="1150" y="172" class="muted" font-size="21" font-weight="700">Región</text>
    <text x="1355" y="172" class="value" font-size="21">$SVG_REGION</text>

    <text
        x="$RIGHT_COLUMN_X"
        y="222"
        font-family="JetBrainsMono Nerd Font, JetBrains Mono, monospace"
        font-size="22"
        font-weight="700"
        fill="#F5DF32"
    >Ⅲ</text>

    <text x="1150" y="222" class="muted" font-size="21" font-weight="700">Generación</text>
    <text x="1355" y="222" class="value" font-size="21">$GENERATION_ROMAN</text>

    <text
        x="$RIGHT_COLUMN_X"
        y="272"
        font-family="JetBrainsMono Nerd Font, JetBrains Mono, monospace"
        font-size="22"
        font-weight="700"
        fill="#FF4F55"
    >◉</text>

    <text x="1150" y="272" class="muted" font-size="21" font-weight="700">Categoría</text>
    <text x="1355" y="272" class="value" font-size="21">$SVG_CATEGORY</text>

    <text
        x="$RIGHT_COLUMN_X"
        y="322"
        font-family="JetBrainsMono Nerd Font, JetBrains Mono, monospace"
        font-size="22"
        font-weight="700"
        fill="#36BFF2"
    >󰦪</text>

    <text x="1150" y="322" class="muted" font-size="21" font-weight="700">Altura</text>
    <text x="1355" y="322" class="value" font-size="21">${HEIGHT} m</text>

    <text
        x="$RIGHT_COLUMN_X"
        y="372"
        font-family="JetBrainsMono Nerd Font, JetBrains Mono, monospace"
        font-size="22"
        font-weight="700"
        fill="#A16BF5"
    >󰔏</text>

    <text x="1150" y="372" class="muted" font-size="21" font-weight="700">Peso</text>
    <text x="1355" y="372" class="value" font-size="21">${WEIGHT} kg</text>

    <!-- Línea inferior -->
    <line
        x1="20"
        y1="452"
        x2="$((PANEL_WIDTH - 20))"
        y2="452"
        class="divider"
    />
</svg>
EOF

# ────────────────────────────────────────────────────────────────
# Renderizar base SVG
# ────────────────────────────────────────────────────────────────

magick \
    -background none \
    -density 144 \
    "$SVG_FILE" \
    -resize "${PANEL_WIDTH}x${PANEL_HEIGHT}!" \
    "$BASE_FILE"

# ────────────────────────────────────────────────────────────────
# Preparar sprite
# ────────────────────────────────────────────────────────────────

magick \
    "$SELECTED_IMAGE" \
    -coalesce \
    -delete 1--1 \
    -background none \
    -alpha on \
    -filter point \
    -resize "${SPRITE_WIDTH}x${SPRITE_HEIGHT}>" \
    -gravity center \
    -extent "${SPRITE_WIDTH}x${SPRITE_HEIGHT}" \
    "$SPRITE_FILE"

# ────────────────────────────────────────────────────────────────
# Componer panel final
# ────────────────────────────────────────────────────────────────

magick \
    "$BASE_FILE" \
    "$SPRITE_FILE" \
    -geometry "+${SPRITE_X}+${SPRITE_Y}" \
    -composite \
    -strip \
    "$FINAL_PANEL"

if [[ ! -s "$FINAL_PANEL" ]]; then
    echo "No se pudo generar el panel de $NAME." >&2
    exit 1
fi

ln -sfn "$(basename "$FINAL_PANEL")" "$CURRENT_PANEL"

# Limpiar temporales de este render.
rm -f \
    "$SVG_FILE" \
    "$SPRITE_FILE" \
    "$BASE_FILE"

printf '%s\n' "$FINAL_PANEL"
