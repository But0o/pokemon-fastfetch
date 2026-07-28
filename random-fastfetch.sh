#!/usr/bin/env bash

set -Eeuo pipefail

# ─────────────────────────────────────────────
# Rutas portables
# ─────────────────────────────────────────────

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd
)"

BUILD_SCRIPT="$SCRIPT_DIR/build-pokedex-cache.sh"

POKEMON_DIR="${POKEMON_DIR:-$HOME/.local/share/pokimg/images}"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pokemon-fastfetch"
CACHE_FILE="$CACHE_DIR/pokedex.json"
WORK_DIR="$CACHE_DIR/generated"
FINAL_IMAGE="$WORK_DIR/pokemon-fastfetch.png"

mkdir -p "$WORK_DIR"

# ─────────────────────────────────────────────
# Dependencias
# ─────────────────────────────────────────────

DEPENDENCIES=(
    jq
    shuf
    magick
    fc-match
    fastfetch
)

for command_name in "${DEPENDENCIES[@]}"; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'Falta instalar: %s\n' "$command_name"
        exit 1
    fi
done

if [[ ! -d "$POKEMON_DIR" ]]; then
    echo "No existe la carpeta de imágenes:"
    echo "$POKEMON_DIR"
    echo
    echo "Podés especificar otra ubicación con:"
    echo
    echo 'POKEMON_DIR="/ruta/a/images" ./random-fastfetch.sh'
    exit 1
fi

if [[ ! -s "$CACHE_FILE" ]]; then
    echo "No existe la caché Pokédex o está vacía:"
    echo "$CACHE_FILE"
    echo
    echo "Generala ejecutando:"
    echo "$BUILD_SCRIPT"
    exit 1
fi

if ! jq empty "$CACHE_FILE" >/dev/null 2>&1; then
    echo "La caché JSON está dañada:"
    echo "$CACHE_FILE"
    exit 1
fi

# ─────────────────────────────────────────────
# Obtener JetBrains Mono Nerd Font
# ─────────────────────────────────────────────

FONT_FILE="$(
    fc-match \
        -f '%{file}\n' \
        'JetBrainsMono Nerd Font' \
        2>/dev/null |
        head -n 1
)"

if [[ -z "$FONT_FILE" || ! -f "$FONT_FILE" ]]; then
    FONT_FILE="$(
        fc-match \
            -f '%{file}\n' \
            'JetBrains Mono Nerd Font' \
            2>/dev/null |
            head -n 1
    )"
fi

if [[ -z "$FONT_FILE" || ! -f "$FONT_FILE" ]]; then
    FONT_FILE="$(
        fc-match \
            -f '%{file}\n' \
            'JetBrainsMonoNL Nerd Font' \
            2>/dev/null |
            head -n 1
    )"
fi

if [[ -z "$FONT_FILE" || ! -f "$FONT_FILE" ]]; then
    FONT_FILE="$(
        fc-match \
            -f '%{file}\n' \
            'JetBrains Mono' \
            2>/dev/null |
            head -n 1
    )"
fi

if [[ -z "$FONT_FILE" || ! -f "$FONT_FILE" ]]; then
    echo "No se encontró JetBrains Mono Nerd Font."
    exit 1
fi

# ─────────────────────────────────────────────
# Elegir Pokémon aleatorio directamente del JSON
#
# No recorre la carpeta completa.
# No consulta Internet.
# ─────────────────────────────────────────────

if ! POKEMON_DATA="$(
    jq -c '
        .[]
        | select(
            (.image? | type == "string")
            and (.image | length > 0)
        )
    ' "$CACHE_FILE" 2>/dev/null |
        shuf --head-count=1
)"; then
    echo "No se pudo leer la caché JSON:"
    echo "$CACHE_FILE"
    exit 1
fi

if [[ -z "$POKEMON_DATA" || "$POKEMON_DATA" == "null" ]]; then
    echo "No se encontraron Pokémon válidos en el JSON."
    exit 1
fi

# ─────────────────────────────────────────────
# Leer todos los campos con una llamada a jq
# ─────────────────────────────────────────────

IFS=$'\t' read -r \
    IMAGE_FILENAME \
    NUMBER \
    DISPLAY_NAME \
    PRIMARY_TYPE \
    TYPE \
    REGION \
    GENERATION \
    IS_LEGENDARY \
    IS_MYTHICAL < <(
        jq -r '
            def title_words:
                gsub("-"; " ")
                | split(" ")
                | map(
                    if length > 0 then
                        (.[0:1] | ascii_upcase) + .[1:]
                    else
                        .
                    end
                )
                | join(" ");

            [
                (.image // ""),
                (.number // "000"),
                (.name // "Desconocido"),
                (.types[0] // "normal"),
                (
                    (.types // ["normal"])
                    | map(title_words)
                    | join(" / ")
                ),
                (.region // "Desconocida"),
                (.generation // 0),
                (.legendary // false),
                (.mythical // false)
            ]
            | @tsv
        ' <<< "$POKEMON_DATA"
    )

SELECTED_IMAGE="$POKEMON_DIR/$IMAGE_FILENAME"

if [[ ! -f "$SELECTED_IMAGE" ]]; then
    echo "No existe la imagen seleccionada:"
    echo "$SELECTED_IMAGE"
    echo
    echo "Carpeta configurada:"
    echo "$POKEMON_DIR"
    echo
    echo "Regenerá la caché ejecutando:"
    echo "$BUILD_SCRIPT"
    exit 1
fi

# ─────────────────────────────────────────────
# Categoría
# ─────────────────────────────────────────────

if [[ "$IS_MYTHICAL" == "true" ]]; then
    CATEGORY="Mítico"
elif [[ "$IS_LEGENDARY" == "true" ]]; then
    CATEGORY="Legendario"
else
    CATEGORY="Normal"
fi

# ─────────────────────────────────────────────
# Generación en números romanos
# ─────────────────────────────────────────────

case "$GENERATION" in
    1)
        GENERATION_DISPLAY="I"
        ;;

    2)
        GENERATION_DISPLAY="II"
        ;;

    3)
        GENERATION_DISPLAY="III"
        ;;

    4)
        GENERATION_DISPLAY="IV"
        ;;

    5)
        GENERATION_DISPLAY="V"
        ;;

    6)
        GENERATION_DISPLAY="VI"
        ;;

    7)
        GENERATION_DISPLAY="VII"
        ;;

    8)
        GENERATION_DISPLAY="VIII"
        ;;

    9)
        GENERATION_DISPLAY="IX"
        ;;

    *)
        GENERATION_DISPLAY="?"
        ;;
esac

# ─────────────────────────────────────────────
# Limitar textos largos
# ─────────────────────────────────────────────

DISPLAY_NAME="${DISPLAY_NAME:0:18}"
TYPE="${TYPE:0:20}"
REGION="${REGION:0:16}"
CATEGORY="${CATEGORY:0:16}"

# ─────────────────────────────────────────────
# Color según tipo principal
# ─────────────────────────────────────────────

case "$PRIMARY_TYPE" in
    normal)
        TYPE_COLOR="#a8a77a"
        ;;

    fire)
        TYPE_COLOR="#ee8130"
        ;;

    water)
        TYPE_COLOR="#6390f0"
        ;;

    electric)
        TYPE_COLOR="#f7d02c"
        ;;

    grass)
        TYPE_COLOR="#7ac74c"
        ;;

    ice)
        TYPE_COLOR="#96d9d6"
        ;;

    fighting)
        TYPE_COLOR="#c22e28"
        ;;

    poison)
        TYPE_COLOR="#a33ea1"
        ;;

    ground)
        TYPE_COLOR="#e2bf65"
        ;;

    flying)
        TYPE_COLOR="#a98ff3"
        ;;

    psychic)
        TYPE_COLOR="#f95587"
        ;;

    bug)
        TYPE_COLOR="#a6b91a"
        ;;

    rock)
        TYPE_COLOR="#b6a136"
        ;;

    ghost)
        TYPE_COLOR="#735797"
        ;;

    dragon)
        TYPE_COLOR="#6f35fc"
        ;;

    dark)
        TYPE_COLOR="#705746"
        ;;

    steel)
        TYPE_COLOR="#b7b7ce"
        ;;

    fairy)
        TYPE_COLOR="#d685ad"
        ;;

    *)
        TYPE_COLOR="#a7afb2"
        ;;
esac

# ─────────────────────────────────────────────
# Color de categoría
# ─────────────────────────────────────────────

case "$CATEGORY" in
    "Mítico")
        CATEGORY_COLOR="#f7d02c"
        ;;

    "Legendario")
        CATEGORY_COLOR="#ff6b6b"
        ;;

    *)
        CATEGORY_COLOR="#d8dddf"
        ;;
esac

# ─────────────────────────────────────────────
# Generar sprite y ficha en una sola ejecución
# ─────────────────────────────────────────────

magick \
    \( \
        "$SELECTED_IMAGE" \
        -background none \
        -alpha on \
        -filter point \
        -resize '420x300>' \
        -gravity center \
        -extent 640x310 \
    \) \
    \( \
        -size 640x445 \
        xc:none \
        -font "$FONT_FILE" \
        -stroke none \
        -gravity northwest \
        \
        -fill "#a7afb2" \
        -pointsize 29 \
        -annotate "+26+0" \
        "+----------------------------------+" \
        \
        -fill "$TYPE_COLOR" \
        -pointsize 38 \
        -annotate "+185+13" \
        "[ POKÉDEX ]" \
        \
        -fill "$TYPE_COLOR" \
        -pointsize 29 \
        -annotate "+26+62" \
        "+----------------------------------+" \
        \
        -fill "#a7afb2" \
        -annotate "+26+89" \
        "| > CATEG.  :" \
        -annotate "+26+145" \
        "| > Nº      :" \
        -annotate "+26+201" \
        "| > NOMBRE  :" \
        -annotate "+26+257" \
        "| > TIPO    :" \
        -annotate "+26+313" \
        "| > REGIÓN  :" \
        -annotate "+26+369" \
        "| > GEN.    :" \
        \
        -fill "$CATEGORY_COLOR" \
        -annotate "+292+89" \
        "$CATEGORY" \
        \
        -fill "#d8dddf" \
        -annotate "+292+145" \
        "#$NUMBER" \
        -annotate "+292+201" \
        "$DISPLAY_NAME" \
        \
        -fill "$TYPE_COLOR" \
        -annotate "+292+257" \
        "$TYPE" \
        \
        -fill "#d8dddf" \
        -annotate "+292+313" \
        "$REGION" \
        -annotate "+292+369" \
        "$GENERATION_DISPLAY" \
        \
        -fill "#a7afb2" \
        -annotate "+595+89" \
        "|" \
        -annotate "+595+145" \
        "|" \
        -annotate "+595+201" \
        "|" \
        -annotate "+595+257" \
        "|" \
        -annotate "+595+313" \
        "|" \
        -annotate "+595+369" \
        "|" \
        -annotate "+26+414" \
        "+----------------------------------+" \
    \) \
    -background none \
    -gravity center \
    -append \
    "$FINAL_IMAGE"

# ─────────────────────────────────────────────
# Ejecutar Fastfetch
# ─────────────────────────────────────────────

exec /usr/bin/fastfetch \
    --logo "$FINAL_IMAGE" \
    --logo-type kitty-direct \
    --logo-width 27 \
    --logo-height 29 \
    --logo-padding-left 2 \
    --logo-padding-right 3 \
    --logo-padding-top 0
