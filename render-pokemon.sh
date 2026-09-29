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

show_help() {
    cat <<EOF

Pokémon Fastfetch renderer v${APP_VERSION}

Uso:

  render-pokemon.sh charizard
  render-pokemon.sh pikachu
  render-pokemon.sh 6
  render-pokemon.sh 25
  render-pokemon.sh --check "Mr. Mime"

El script genera un panel PNG y muestra su ruta absoluta.

Variables opcionales:

  POKEMON_DIR
      Carpeta que contiene las imágenes.

  PF_RENDER_WIDTH / PF_RENDER_HEIGHT
      Tamaño exacto del panel en píxeles. random-fastfetch.sh los
      calcula a partir del tamaño real de la terminal.

  POKEMON_PANEL_WIDTH / POKEMON_PANEL_HEIGHT
      Tamaño usado cuando el renderer se ejecuta solo.
      Predeterminado: 1580x450.

El diseño es responsive: el contenido se redistribuye según la
proporción del panel. En paneles angostos se oculta la columna de
información (habilidades, región, etc.).
EOF
}

# Process informational options before loading configuration,
# creating cache directories, or validating runtime dependencies.
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

# Tamaño real en píxeles. random-fastfetch.sh lo calcula a partir de la
# terminal y lo pasa con PF_RENDER_*; se usan variables propias para que
# el archivo de configuración (que se carga arriba) no las pise.
PANEL_WIDTH="${PF_RENDER_WIDTH:-${POKEMON_PANEL_WIDTH:-1580}}"
PANEL_HEIGHT="${PF_RENDER_HEIGHT:-${POKEMON_PANEL_HEIGHT:-450}}"

if ! [[ "$PANEL_WIDTH" =~ ^[0-9]+$ ]] || ((PANEL_WIDTH < 200)); then
    PANEL_WIDTH=1580
fi

if ! [[ "$PANEL_HEIGHT" =~ ^[0-9]+$ ]] || ((PANEL_HEIGHT < 60)); then
    PANEL_HEIGHT=450
fi

# Máximo de paneles guardados en caché (uno por Pokémon y tamaño).
PANEL_CACHE_MAX="${POKEMON_PANEL_CACHE_MAX:-60}"

if ! [[ "$PANEL_CACHE_MAX" =~ ^[0-9]+$ ]] || ((PANEL_CACHE_MAX < 1)); then
    PANEL_CACHE_MAX=60
fi

# ────────────────────────────────────────────────────────────────
# Dependencias
# ────────────────────────────────────────────────────────────────

pf_require_commands \
    jq \
    sha256sum \
    fc-match \
    sed \
    awk \
    find

# ImageMagick 7 usa "magick"; ImageMagick 6 (Debian/Ubuntu) usa "convert".
if pf_command_exists magick; then
    MAGICK_BIN="magick"
elif pf_command_exists convert; then
    MAGICK_BIN="convert"
else
    pf_die "Falta ImageMagick: no se encontró 'magick' ni 'convert'."
fi

# Solo se comprueba que exista: validar todo el JSON en cada arranque
# costaría otra lectura completa. Si está roto, la consulta de abajo falla.
pf_require_nonempty_file "$POKEDEX_FILE" "La caché Pokédex"
pf_require_directory "$POKEMON_DIR" "El directorio de imágenes"


# --check: solo resuelve el Pokémon y comprueba su imagen, sin renderizar.
# Imprime la clave canónica (lo usa "--set").
CHECK_ONLY=false

if [[ "${1:-}" == "--check" ]]; then
    CHECK_ONLY=true
    shift
fi

# PF_FORCE_RENDER=1 descarta los paneles cacheados de este Pokémon
# y vuelve a renderizar (lo usa "--rerender").
FORCE_RENDER="${PF_FORCE_RENDER:-0}"

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

clamp() {
    local VALUE="$1"
    local MINIMUM="$2"
    local MAXIMUM="$3"

    if ((VALUE < MINIMUM)); then
        VALUE="$MINIMUM"
    fi

    if ((VALUE > MAXIMUM)); then
        VALUE="$MAXIMUM"
    fi

    printf '%s' "$VALUE"
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
    local MAX_WIDTH="${2:-285}"
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
# Seleccionar entrada y leer datos
#
# Una sola llamada a jq resuelve el Pokémon (por número, clave o
# api_name) y devuelve todos los campos como asignaciones de shell
# escapadas con @sh. Antes eran unas 22 llamadas separadas.
# ────────────────────────────────────────────────────────────────

REQUEST_ID=0
REQUEST_NAME=""

if [[ "$REQUEST" =~ ^[0-9]+$ ]]; then
    REQUEST_ID="$((10#$REQUEST))"
else
    REQUEST_NAME="$(normalize_name "$REQUEST")"
fi

POKEMON_KEY=""

if ! POKEMON_FIELDS="$(
    jq -r \
        --arg request_name "$REQUEST_NAME" \
        --argjson request_id "$REQUEST_ID" \
        '
            def field($name; $value):
                "\($name)=\($value | tostring | @sh)";

            (
                if $request_id > 0 then
                    first(to_entries[] | select((.value.id // 0) == $request_id))
                elif has($request_name) then
                    { key: $request_name, value: .[$request_name] }
                else
                    first(to_entries[] | select((.value.api_name // "") == $request_name))
                end
            ) // null
            | if . == null or .value == null then
                empty
            else
                .key as $key
                | .value as $p
                | [
                    field("POKEMON_KEY"; $key),
                    field("POKEMON_DATA"; $p | tojson),
                    field("ID"; $p.id // 0),
                    field("NAME"; $p.name // $p.api_name // "Desconocido"),
                    field("API_NAME"; $p.api_name // ""),
                    field("IMAGE_VALUE"; $p.image // ""),
                    field("PRIMARY_TYPE"; $p.types[0] // "normal"),
                    field("SECONDARY_TYPE"; $p.types[1] // ""),
                    field("REGION"; $p.region // "Desconocida"),
                    field("GENERATION"; $p.generation // 0),
                    field("HEIGHT"; $p.height_m // 0),
                    field("WEIGHT"; $p.weight_kg // 0),
                    field("IS_LEGENDARY"; $p.legendary // false),
                    field("IS_MYTHICAL"; $p.mythical // false),
                    field("IS_BABY"; $p.baby // false),
                    field("HP"; $p.stats.hp // 0),
                    field("ATK"; $p.stats.attack // 0),
                    field("DEF"; $p.stats.defense // 0),
                    field("SPATK"; $p.stats.special_attack // 0),
                    field("SPDEF"; $p.stats.special_defense // 0),
                    field("SPEED"; $p.stats.speed // 0),
                    field(
                        "ABILITIES";
                        ($p.abilities // [])
                        | map(
                            gsub("-"; " ")
                            | split(" ")
                            | map(
                                if length > 0 then
                                    (.[0:1] | ascii_upcase) + .[1:]
                                else
                                    .
                                end
                            )
                            | join(" ")
                        )
                        | join(", ")
                    )
                ]
                | join("\n")
            end
        ' \
        "$POKEDEX_FILE" 2>/dev/null
)"; then
    pf_die "No se pudo leer la caché Pokédex (¿JSON inválido?): $POKEDEX_FILE"
fi

# Las asignaciones vienen escapadas con @sh, así que eval es seguro.
eval "$POKEMON_FIELDS"

if [[ -z "$POKEMON_KEY" ]]; then
    pf_die "No se encontró el Pokémon: $REQUEST"
fi

# Los números se usan en aritmética de Bash: solo se aceptan enteros.
for NUMERIC_FIELD in ID GENERATION HP ATK DEF SPATK SPDEF SPEED; do
    if ! [[ "${!NUMERIC_FIELD}" =~ ^[0-9]+$ ]]; then
        printf -v "$NUMERIC_FIELD" '%s' 0
    fi
done

NUMBER="$(printf '%03d' "$ID")"

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

if [[ "$CHECK_ONLY" == "true" ]]; then
    printf '%s\n' "$POKEMON_KEY"
    exit 0
fi

# ────────────────────────────────────────────────────────────────
# Caché del panel
#
# Se comprueba antes de preparar textos, colores, layout o fuente: si el
# panel ya existe, el renderer termina acá.
# ────────────────────────────────────────────────────────────────

IMAGE_MTIME="$(
    stat \
        --format='%Y' \
        "$SELECTED_IMAGE" \
        2>/dev/null ||
        printf '0'
)"

RENDER_VERSION="pokemon-fastfetch-v2-render-7-responsive"

read -r CACHE_HASH _ < <(
    printf '%s' \
        "$RENDER_VERSION" \
        "$PANEL_WIDTH" \
        "$PANEL_HEIGHT" \
        "$IMAGE_MTIME" \
        "$POKEMON_DATA" |
        sha256sum
)

CACHE_HASH="${CACHE_HASH:0:16}"
SAFE_KEY="${POKEMON_KEY//[^a-zA-Z0-9._-]/-}"

FINAL_PANEL="$PANELS_DIR/${SAFE_KEY}-${CACHE_HASH}.png"
CURRENT_PANEL="$PANELS_DIR/${SAFE_KEY}.png"

if [[ "$FORCE_RENDER" == "1" ]]; then
    rm -f "$PANELS_DIR/${SAFE_KEY}-"*.png 2>/dev/null || true
elif [[ -s "$FINAL_PANEL" ]]; then
    printf '%s\n' "$FINAL_PANEL"
    exit 0
fi

if [[ ! -d "$PANELS_DIR" || ! -d "$TEMP_DIR" ]]; then
    mkdir -p "$PANELS_DIR" "$TEMP_DIR"
fi

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

# ────────────────────────────────────────────────────────────────
# Layout responsive
#
# Todo se dibuja en "unidades de diseño" con una altura fija de 450.
# El ancho en unidades sale de la proporción real del panel, así que en
# una terminal más ancha hay más unidades horizontales y el contenido se
# redistribuye en lugar de estirarse o dejar huecos.
# ────────────────────────────────────────────────────────────────

DESIGN_HEIGHT=450
DESIGN_WIDTH="$((PANEL_WIDTH * DESIGN_HEIGHT / PANEL_HEIGHT))"

# Debajo de este ancho no entra bien la columna de información.
FULL_LAYOUT_MIN_WIDTH=1400

MARGIN=20

# Ancho aproximado de un carácter de JetBrains Mono a 21 unidades
# (0.6 em), multiplicado por 10 para trabajar con enteros.
CHAR_WIDTH_X10=126

if ((DESIGN_WIDTH >= FULL_LAYOUT_MIN_WIDTH)); then
    SHOW_INFO_COLUMN=true
    SPRITE_WIDTH="$(clamp "$((DESIGN_WIDTH * 26 / 100))" 340 465)"
else
    SHOW_INFO_COLUMN=false
    SPRITE_WIDTH="$(clamp "$((DESIGN_WIDTH * 32 / 100))" 280 465)"
fi

SPRITE_HEIGHT=415
SPRITE_X="$MARGIN"
SPRITE_Y=18

STATS_X="$((SPRITE_X + SPRITE_WIDTH + 35))"

if [[ "$SHOW_INFO_COLUMN" == "true" ]]; then
    # La columna de información mide lo justo para su texto más largo
    # (hasta 34 caracteres) y queda pegada al borde derecho. Las
    # estadísticas ocupan todo el espacio del medio.
    LONGEST_INFO_VALUE=0

    for INFO_TEXT in "$ABILITIES" "$REGION" "$CATEGORY" "${HEIGHT} m" "${WEIGHT} kg"; do
        if ((${#INFO_TEXT} > LONGEST_INFO_VALUE)); then
            LONGEST_INFO_VALUE="${#INFO_TEXT}"
        fi
    done

    LONGEST_INFO_VALUE="$(clamp "$LONGEST_INFO_VALUE" 12 34)"

    # 200 = ícono + etiqueta; +1 carácter de aire.
    WANTED_INFO_WIDTH="$((200 + (LONGEST_INFO_VALUE + 1) * CHAR_WIDTH_X10 / 10))"

    # 95 = espacio a ambos lados del separador vertical.
    AVAILABLE_WIDTH="$((DESIGN_WIDTH - STATS_X - MARGIN - 95))"
    MAXIMUM_INFO_WIDTH="$((AVAILABLE_WIDTH - 490))"

    INFO_WIDTH="$WANTED_INFO_WIDTH"

    if ((INFO_WIDTH > MAXIMUM_INFO_WIDTH)); then
        INFO_WIDTH="$MAXIMUM_INFO_WIDTH"
    fi

    STATS_WIDTH="$((AVAILABLE_WIDTH - INFO_WIDTH))"

    # En terminales muy anchas no estiramos las barras sin límite:
    # el espacio sobrante se reparte alrededor del separador.
    EXTRA_GAP=0

    if ((STATS_WIDTH > 1100)); then
        EXTRA_GAP="$(((STATS_WIDTH - 1100) / 2))"
        STATS_WIDTH=1100
    fi

    SEPARATOR_X="$((STATS_X + STATS_WIDTH + 50 + EXTRA_GAP))"
    INFO_X="$((DESIGN_WIDTH - MARGIN - INFO_WIDTH))"
    INFO_LABEL_X="$((INFO_X + 40))"
    INFO_VALUE_X="$((INFO_X + 200))"
    INFO_VALUE_CHARS="$(((INFO_WIDTH - 200) * 10 / CHAR_WIDTH_X10))"

    if ((INFO_VALUE_CHARS < 4)); then
        INFO_VALUE_CHARS=4
    fi
else
    STATS_WIDTH="$(clamp "$((DESIGN_WIDTH - STATS_X - MARGIN))" 490 1200)"
    INFO_VALUE_CHARS=18
fi

# Columnas internas del bloque de estadísticas.
STAT_ICON_X="$((STATS_X + 95))"
BAR_X="$((STATS_X + 140))"
BAR_WIDTH="$((STATS_WIDTH - 140 - 75))"
STAT_VALUE_X="$((BAR_X + BAR_WIDTH + 25))"
STATS_END_X="$((STATS_X + STATS_WIDTH))"

NUMBER_X="$((STATS_X + 235))"
TYPE_BADGE_X="$((STATS_X + 145))"
TYPE_TEXT_X="$((STATS_X + 160))"
TYPE_SLASH_X="$((STATS_X + 300))"
TYPE2_BADGE_X="$((STATS_X + 325))"
TYPE2_TEXT_X="$((STATS_X + 340))"
TOTAL_VALUE_X="$((STATS_X + 145))"

# Limitar textos para evitar que se salgan del panel.
NAME="$(truncate_text "$NAME" 22)"
ABILITIES="$(truncate_text "$ABILITIES" "$INFO_VALUE_CHARS")"
REGION="$(truncate_text "$REGION" "$INFO_VALUE_CHARS")"
CATEGORY="$(truncate_text "$CATEGORY" "$INFO_VALUE_CHARS")"

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
# Medidas del diseño
# ────────────────────────────────────────────────────────────────

# Las posiciones se calculan en la sección "Layout responsive".
HP_BAR="$(calculate_bar_width "$HP" "$BAR_WIDTH")"
ATK_BAR="$(calculate_bar_width "$ATK" "$BAR_WIDTH")"
DEF_BAR="$(calculate_bar_width "$DEF" "$BAR_WIDTH")"
SPATK_BAR="$(calculate_bar_width "$SPATK" "$BAR_WIDTH")"
SPDEF_BAR="$(calculate_bar_width "$SPDEF" "$BAR_WIDTH")"
SPEED_BAR="$(calculate_bar_width "$SPEED" "$BAR_WIDTH")"

# Tamaño y posición del sprite en píxeles reales.
SPRITE_PX_WIDTH="$((SPRITE_WIDTH * PANEL_HEIGHT / DESIGN_HEIGHT))"
SPRITE_PX_HEIGHT="$((SPRITE_HEIGHT * PANEL_HEIGHT / DESIGN_HEIGHT))"
SPRITE_PX_X="$((SPRITE_X * PANEL_HEIGHT / DESIGN_HEIGHT))"
SPRITE_PX_Y="$((SPRITE_Y * PANEL_HEIGHT / DESIGN_HEIGHT))"

SVG_FILE="$TEMP_DIR/${SAFE_KEY}-${CACHE_HASH}-$$.svg"
PANEL_TEMP_FILE="$TEMP_DIR/${SAFE_KEY}-${CACHE_HASH}-$$.png"

# ────────────────────────────────────────────────────────────────
# Generar SVG
# ────────────────────────────────────────────────────────────────

cat > "$SVG_FILE" <<EOF
<svg
    xmlns="http://www.w3.org/2000/svg"
    width="$PANEL_WIDTH"
    height="$PANEL_HEIGHT"
    viewBox="0 0 $DESIGN_WIDTH $DESIGN_HEIGHT"
    preserveAspectRatio="xMinYMin meet"
>
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
    <text x="$STATS_X" y="55" class="text" font-size="31" font-weight="700">$SVG_NAME</text>
    <text x="$NUMBER_X" y="55" class="muted" font-size="25">#$NUMBER</text>

    <!-- Tipo -->
    <text x="$STATS_X" y="98" class="muted" font-size="22">Tipo</text>

    <rect
        x="$TYPE_BADGE_X"
        y="68"
        width="145"
        height="39"
        rx="7"
        fill="none"
        stroke="$PRIMARY_TYPE_COLOR"
        stroke-width="1.5"
    />

    <text
        x="$TYPE_TEXT_X"
        y="95"
        font-family="JetBrainsMono Nerd Font, JetBrains Mono, monospace"
        font-size="21"
        font-weight="700"
        fill="$PRIMARY_TYPE_COLOR"
    >$SVG_PRIMARY_ICON $SVG_PRIMARY_NAME</text>
EOF

if [[ -n "$SECONDARY_TYPE" ]]; then
    cat >> "$SVG_FILE" <<EOF
    <text x="$TYPE_SLASH_X" y="96" class="muted" font-size="23">/</text>

    <rect
        x="$TYPE2_BADGE_X"
        y="68"
        width="165"
        height="39"
        rx="7"
        fill="none"
        stroke="$SECONDARY_TYPE_COLOR"
        stroke-width="1.5"
    />

    <text
        x="$TYPE2_TEXT_X"
        y="95"
        font-family="JetBrainsMono Nerd Font, JetBrains Mono, monospace"
        font-size="21"
        font-weight="700"
        fill="$SECONDARY_TYPE_COLOR"
    >$SVG_SECONDARY_ICON $SVG_SECONDARY_NAME</text>
EOF
fi

# Filas de estadísticas: etiqueta, ícono, color, valor y ancho de barra.
STAT_ROWS=(
    "HP|♥|#FF575F|$HP|$HP_BAR"
    "ATK|×|#FF922B|$ATK|$ATK_BAR"
    "DEF|●|#F4EA68|$DEF|$DEF_BAR"
    "SPATK|★|#B477ED|$SPATK|$SPATK_BAR"
    "SPDEF|◆|#51DA7B|$SPDEF|$SPDEF_BAR"
    "SPD|↦|#64CFE4|$SPEED|$SPEED_BAR"
)

printf '\n    <!-- Estadísticas -->\n' >> "$SVG_FILE"

STAT_INDEX=0

for STAT_ROW in "${STAT_ROWS[@]}"; do
    IFS='|' read -r STAT_LABEL STAT_ICON STAT_COLOR STAT_VALUE STAT_BAR <<< "$STAT_ROW"

    TEXT_Y="$((151 + STAT_INDEX * 43))"
    BAR_Y="$((131 + STAT_INDEX * 43))"

    cat >> "$SVG_FILE" <<EOF
    <text x="$STATS_X" y="$TEXT_Y" class="label" font-size="21">$STAT_LABEL</text>
    <text x="$STAT_ICON_X" y="$TEXT_Y" class="text" font-size="20">$STAT_ICON</text>
    <rect x="$BAR_X" y="$BAR_Y" width="$BAR_WIDTH" height="23" rx="2" class="bar-background" />
    <rect x="$BAR_X" y="$BAR_Y" width="$STAT_BAR" height="23" rx="2" fill="$STAT_COLOR" />
    <text x="$STAT_VALUE_X" y="$TEXT_Y" class="value" font-size="21">$STAT_VALUE</text>
EOF

    STAT_INDEX=$((STAT_INDEX + 1))
done

cat >> "$SVG_FILE" <<EOF

    <line x1="$STATS_X" y1="390" x2="$STATS_END_X" y2="390" class="divider" />

    <text x="$STATS_X" y="428" class="label" font-size="23">TOTAL</text>
    <text x="$TOTAL_VALUE_X" y="428" class="value" font-size="23">$TOTAL</text>
EOF

# ────────────────────────────────────────────────────────────────
# Columna de información (solo si hay espacio)
# ────────────────────────────────────────────────────────────────

if [[ "$SHOW_INFO_COLUMN" == "true" ]]; then
    INFO_ROWS=(
        "󰓎|#946BFF|Habilidades|$SVG_ABILITIES"
        "󰍎|#82DA42|Región|$SVG_REGION"
        "Ⅲ|#F5DF32|Generación|$GENERATION_ROMAN"
        "◉|#FF4F55|Categoría|$SVG_CATEGORY"
        "󰦪|#36BFF2|Altura|${HEIGHT} m"
        "󰔏|#A16BF5|Peso|${WEIGHT} kg"
    )

    cat >> "$SVG_FILE" <<EOF

    <!-- Separador columna derecha -->
    <line x1="$SEPARATOR_X" y1="72" x2="$SEPARATOR_X" y2="420" class="divider" />

    <!-- Información derecha -->
EOF

    INFO_INDEX=0

    for INFO_ROW in "${INFO_ROWS[@]}"; do
        IFS='|' read -r INFO_ICON INFO_COLOR INFO_LABEL INFO_VALUE <<< "$INFO_ROW"

        INFO_Y="$((122 + INFO_INDEX * 50))"

        cat >> "$SVG_FILE" <<EOF
    <text
        x="$INFO_X"
        y="$INFO_Y"
        font-family="JetBrainsMono Nerd Font, JetBrains Mono, monospace"
        font-size="22"
        font-weight="700"
        fill="$INFO_COLOR"
    >$INFO_ICON</text>
    <text x="$INFO_LABEL_X" y="$INFO_Y" class="muted" font-size="21" font-weight="700">$INFO_LABEL</text>
    <text x="$INFO_VALUE_X" y="$INFO_Y" class="value" font-size="21">$INFO_VALUE</text>
EOF

        INFO_INDEX=$((INFO_INDEX + 1))
    done
fi

# Sin línea inferior: el divisor del panel del sistema queda justo debajo.
printf '</svg>\n' >> "$SVG_FILE"

# ────────────────────────────────────────────────────────────────
# Renderizar el panel
#
# Un solo proceso de ImageMagick rasteriza el SVG, prepara el sprite y
# los compone. Antes eran tres procesos con dos PNG intermedios.
# La compresión PNG rápida genera archivos algo más grandes pero ahorra
# tiempo en cada render; la imagen es idéntica píxel a píxel.
# ────────────────────────────────────────────────────────────────

"$MAGICK_BIN" \
    -background none \
    -density 144 \
    "$SVG_FILE" \
    -resize "${PANEL_WIDTH}x${PANEL_HEIGHT}!" \
    \( \
        "$SELECTED_IMAGE" \
        -coalesce \
        -delete 1--1 \
        -background none \
        -alpha on \
        -filter point \
        -resize "${SPRITE_PX_WIDTH}x${SPRITE_PX_HEIGHT}>" \
        -gravity center \
        -extent "${SPRITE_PX_WIDTH}x${SPRITE_PX_HEIGHT}" \
        +gravity \
    \) \
    -geometry "+${SPRITE_PX_X}+${SPRITE_PX_Y}" \
    -composite \
    -strip \
    -define png:compression-level=1 \
    -define png:compression-filter=0 \
    "$PANEL_TEMP_FILE"

# Mover al nombre final recién al terminar: otro proceso nunca ve un
# panel a medio escribir (importante con el pre-render en segundo plano).
mv -f "$PANEL_TEMP_FILE" "$FINAL_PANEL"

if [[ ! -s "$FINAL_PANEL" ]]; then
    pf_die "No se pudo generar el panel de $NAME."
fi

ln -sfn "${FINAL_PANEL##*/}" "$CURRENT_PANEL"

# Limpiar temporales de este render.
rm -f "$SVG_FILE" "$PANEL_TEMP_FILE"

# ────────────────────────────────────────────────────────────────
# Limpiar caché vieja
#
# Cada tamaño de terminal genera un panel nuevo, así que se conservan
# solo los PANEL_CACHE_MAX más recientes. Solo corre después de un
# render nuevo, nunca cuando se reutiliza un panel.
# ────────────────────────────────────────────────────────────────

find "$PANELS_DIR" \
    -maxdepth 1 \
    -type f \
    -name '*.png' \
    -printf '%T@ %p\n' \
    2>/dev/null |
    sort -rn |
    tail -n "+$((PANEL_CACHE_MAX + 1))" |
    cut -d ' ' -f 2- |
    xargs -r rm -f -- ||
    true

# Enlaces que apuntaban a paneles borrados y temporales abandonados.
find "$PANELS_DIR" -maxdepth 1 -xtype l -delete 2>/dev/null || true
find "$TEMP_DIR" -maxdepth 1 -type f -mmin +60 -delete 2>/dev/null || true

printf '%s\n' "$FINAL_PANEL"