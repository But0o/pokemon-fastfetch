#!/usr/bin/env bash

set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Pokémon Fastfetch - Descarga de sprites
#
# Descarga los sprites que faltan con la misma estética que pokimg: íconos de
# caja de 68x56 recortados al contenido y ampliados 9x sin suavizado.
#
#   - Normales que falten (por ejemplo, #899-#1025).
#   - Shiny de todos los Pokémon, en la subcarpeta "shiny/".
#   - Las 48 megaevoluciones clásicas (Gen 6 y 7), normales y shiny, en
#     "mega/" y "mega/shiny/".
#
# Fuentes:
#   - #1-#905:    PokéSprite (msikma/pokesprite), íconos de Espada/Escudo y
#                 versiones no oficiales de Leyendas Arceus.
#   - Megas:      PokéSprite (íconos de la Gen 7 adaptados a 68x56).
#   - #906-#1025: bamq/pokemon-sprites, íconos de Escarlata/Púrpura del
#                 National Pokédex Version Delta Project adaptados a 68x56.
#   - Nombres:    CSV de especies de PokéAPI.
#
# Los sprites son propiedad de Nintendo / Creatures Inc. / GAME FREAK Inc.
# Los créditos de los íconos de la Gen 9 están en el repositorio de bamq.
#
# Shell:
#   Bash 5.0+
#
# Repository:
#   https://github.com/But0o/pokemon-fastfetch
# -----------------------------------------------------------------------------

SCRIPT_PATH="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd
)/$(basename -- "${BASH_SOURCE[0]}")"

POKESPRITE_BASE="https://raw.githubusercontent.com/msikma/pokesprite/master"
BAMQ_BASE="https://raw.githubusercontent.com/bamq/pokemon-sprites/main"
SPECIES_CSV_URL="https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/pokemon_species.csv"

# Último número cubierto por PokéSprite.
POKESPRITE_LAST_ID=905

# Factor de ampliación de pokimg.
UPSCALE_PERCENT=900

# ────────────────────────────────────────────────────────────────
# Modo interno: procesar un sprite (lo usa xargs en paralelo)
# ────────────────────────────────────────────────────────────────

if [[ "${1:-}" == "--_process" ]]; then
    source_url="$2"
    destination="$3"
    label="${destination##*/}"
    label="${label%.png}"

    if [[ "$destination" == */shiny/* ]]; then
        label="$label (shiny)"
    fi

    download_file="$destination.download-$$"
    processed_file="$destination.processed-$$.png"

    # shellcheck disable=SC2317  # se ejecuta desde el trap
    cleanup_worker() {
        rm -f "$download_file" "$processed_file"
    }

    trap cleanup_worker EXIT

    if ! curl \
        --silent \
        --fail \
        --location \
        --retry 2 \
        --retry-delay 1 \
        --connect-timeout 10 \
        --max-time 30 \
        --output "$download_file" \
        "$source_url"; then
        printf 'FAIL\t%s\tno se pudo descargar\n' "$label"
        exit 0
    fi

    # Mismo proceso que pokimg: recortar el borde transparente y ampliar
    # con vecino más cercano para conservar los píxeles nítidos.
    if ! "$MAGICK_BIN" \
        "$download_file" \
        -trim \
        +repage \
        -filter point \
        -resize "${UPSCALE_PERCENT}%" \
        -strip \
        "$processed_file" 2>/dev/null ||
        [[ ! -s "$processed_file" ]]; then
        printf 'FAIL\t%s\tno se pudo procesar\n' "$label"
        exit 0
    fi

    mv -f "$processed_file" "$destination"
    printf 'OK\t%s\n' "$label"
    exit 0
fi

# ────────────────────────────────────────────────────────────────
# Biblioteca común y configuración
# ────────────────────────────────────────────────────────────────

SCRIPT_DIR="${SCRIPT_PATH%/*}"
COMMON_LIBRARY="$SCRIPT_DIR/lib/common.sh"

if [[ ! -r "$COMMON_LIBRARY" ]]; then
    printf '[ERROR] No se encontró la biblioteca común: %s\n' \
        "$COMMON_LIBRARY" >&2
    exit 1
fi

# shellcheck source=lib/common.sh
source "$COMMON_LIBRARY"

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/pokemon-fastfetch/config"

if [[ -r "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

DESTINATION_DIR="${POKEMON_DIR:-$HOME/.local/share/pokimg/images}"
DOWNLOAD_NORMAL=true
DOWNLOAD_SHINY=true
DOWNLOAD_MEGA=true
FORCE_DOWNLOAD=false
JOBS=8

# ────────────────────────────────────────────────────────────────
# Ayuda y argumentos
# ────────────────────────────────────────────────────────────────

show_help() {
    cat <<EOF
Uso:
  ./download-sprites.sh [opciones]

Descarga los sprites que faltan con la estética de pokimg:
  - normales que falten (por ejemplo, la Gen 9 y Leyendas Arceus);
  - shiny de todos los Pokémon, en la subcarpeta "shiny/";
  - las 48 megaevoluciones clásicas, normales y shiny, en "mega/".

Los sprites que ya existen no se vuelven a descargar.

Opciones:
  --dest DIR       Carpeta de imágenes. Predeterminado: POKEMON_DIR de la
                   configuración, o ~/.local/share/pokimg/images.
  --only-normal    Descargar solo los sprites normales.
  --only-shiny     Descargar solo los sprites shiny.
  --only-megas     Descargar solo las megaevoluciones (normales y shiny).
  --no-megas       No descargar las megaevoluciones.
  --force          Volver a descargar aunque el archivo exista.
  --jobs N         Descargas en paralelo. Predeterminado: 8.
  -h, --help       Mostrar esta ayuda.

Después de descargar la Gen 9, agregala a la Pokédex con:
  ./add-missing-pokemon.sh
EOF
}

while (($# > 0)); do
    case "$1" in
        --dest)
            DESTINATION_DIR="${2:-}"
            [[ -n "$DESTINATION_DIR" ]] || pf_die "--dest necesita una ruta."
            shift 2
            ;;

        --only-normal)
            DOWNLOAD_SHINY=false
            DOWNLOAD_MEGA=false
            shift
            ;;

        --only-shiny)
            DOWNLOAD_NORMAL=false
            DOWNLOAD_MEGA=false
            shift
            ;;

        --only-megas)
            DOWNLOAD_NORMAL=false
            DOWNLOAD_SHINY=false
            shift
            ;;

        --no-megas)
            DOWNLOAD_MEGA=false
            shift
            ;;

        --force)
            FORCE_DOWNLOAD=true
            shift
            ;;

        --jobs)
            JOBS="${2:-}"
            [[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || pf_die "--jobs necesita un número mayor a 0."
            shift 2
            ;;

        -h|--help)
            show_help
            exit 0
            ;;

        *)
            pf_die "Opción desconocida: $1 (usá --help)"
            ;;
    esac
done

# ────────────────────────────────────────────────────────────────
# Dependencias
# ────────────────────────────────────────────────────────────────

pf_require_commands curl jq awk xargs

if pf_command_exists magick; then
    MAGICK_BIN="magick"
elif pf_command_exists convert; then
    MAGICK_BIN="convert"
else
    pf_die "Falta ImageMagick: no se encontró 'magick' ni 'convert'."
fi

export MAGICK_BIN

mkdir -p "$DESTINATION_DIR"

if [[ "$DOWNLOAD_SHINY" == "true" ]]; then
    mkdir -p "$DESTINATION_DIR/shiny"
fi

if [[ "$DOWNLOAD_MEGA" == "true" ]]; then
    mkdir -p "$DESTINATION_DIR/mega/shiny"
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pokemon-fastfetch-sprites.XXXXXX")"

cleanup() {
    rm -rf "$WORK_DIR"
}

trap cleanup EXIT

# ────────────────────────────────────────────────────────────────
# Lista de especies: "número nombre-pokeapi nombre-en-la-fuente"
# ────────────────────────────────────────────────────────────────

pf_info "Descargando la lista de especies…"

curl --silent --fail --location --retry 2 \
    --output "$WORK_DIR/pokesprite.json" \
    "$POKESPRITE_BASE/data/pokemon.json" ||
    pf_die "No se pudo descargar la lista de PokéSprite."

curl --silent --fail --location --retry 2 \
    --output "$WORK_DIR/species.csv" \
    "$SPECIES_CSV_URL" ||
    pf_die "No se pudo descargar la lista de especies de PokéAPI."

{
    # #1-#905: el nombre de PokéSprite coincide con el de la Pokédex.
    jq -r --argjson last "$POKESPRITE_LAST_ID" '
        .[]
        | (.idx | tonumber) as $id
        | select($id <= $last)
        | "\($id) \(.slug.eng) \(.slug.eng)"
    ' "$WORK_DIR/pokesprite.json"

    # #906 en adelante: nombres de PokéAPI. Dos especies solo existen en
    # bamq con el nombre de su forma predeterminada.
    awk -F, -v last="$POKESPRITE_LAST_ID" '
        NR > 1 && $1 > last {
            source = $2
            if ($2 == "squawkabilly") source = "squawkabilly-green-plumage"
            if ($2 == "ogerpon") source = "ogerpon-teal-mask"
            print $1, $2, source
        }
    ' "$WORK_DIR/species.csv"
} | sort -n > "$WORK_DIR/species.txt"

SPECIES_COUNT="$(wc -l < "$WORK_DIR/species.txt")"

if ((SPECIES_COUNT == 0)); then
    pf_die "La lista de especies quedó vacía."
fi

# ────────────────────────────────────────────────────────────────
# Armar la lista de descargas
# ────────────────────────────────────────────────────────────────

TASKS_FILE="$WORK_DIR/tasks"
: > "$TASKS_FILE"

ALREADY_PRESENT=0
TASK_COUNT=0

add_task() {
    local url="$1"
    local destination="$2"

    if [[ "$FORCE_DOWNLOAD" != "true" && -s "$destination" ]]; then
        ALREADY_PRESENT=$((ALREADY_PRESENT + 1))
        return
    fi

    printf '%s\0%s\0' "$url" "$destination" >> "$TASKS_FILE"
    TASK_COUNT=$((TASK_COUNT + 1))
}

while read -r species_id species_name source_name; do
    if ((species_id <= POKESPRITE_LAST_ID)); then
        regular_url="$POKESPRITE_BASE/pokemon-gen8/regular/$source_name.png"
        shiny_url="$POKESPRITE_BASE/pokemon-gen8/shiny/$source_name.png"
    else
        regular_url="$BAMQ_BASE/pokemon/regular/$source_name.png"
        shiny_url="$BAMQ_BASE/pokemon/shiny/$source_name.png"
    fi

    if [[ "$DOWNLOAD_NORMAL" == "true" ]]; then
        add_task "$regular_url" "$DESTINATION_DIR/$species_name.png"
    fi

    if [[ "$DOWNLOAD_SHINY" == "true" ]]; then
        add_task "$shiny_url" "$DESTINATION_DIR/shiny/$species_name.png"
    fi
done < "$WORK_DIR/species.txt"

# Megaevoluciones: formas "mega", "mega-x" y "mega-y" de PokéSprite.
MEGA_COUNT=0

if [[ "$DOWNLOAD_MEGA" == "true" ]]; then
    while read -r mega_name; do
        MEGA_COUNT=$((MEGA_COUNT + 1))

        add_task \
            "$POKESPRITE_BASE/pokemon-gen8/regular/$mega_name.png" \
            "$DESTINATION_DIR/mega/$mega_name.png"

        add_task \
            "$POKESPRITE_BASE/pokemon-gen8/shiny/$mega_name.png" \
            "$DESTINATION_DIR/mega/shiny/$mega_name.png"
    done < <(
        jq -r '
            .[]
            | .slug.eng as $slug
            | (.["gen-8"].forms // {})
            | keys[]
            | select(test("^mega(-[xy])?$"))
            | "\($slug)-\(.)"
        ' "$WORK_DIR/pokesprite.json" | sort
    )
fi

printf '\n'
printf 'Especies:        %s\n' "$SPECIES_COUNT"
printf 'Megas:           %s\n' "$MEGA_COUNT"
printf 'Ya descargados:  %s\n' "$ALREADY_PRESENT"
printf 'Por descargar:   %s\n' "$TASK_COUNT"
printf 'Destino:         %s\n\n' "$DESTINATION_DIR"

if ((TASK_COUNT == 0)); then
    pf_success "No falta ningún sprite."
    exit 0
fi

# ────────────────────────────────────────────────────────────────
# Descargar en paralelo
# ────────────────────────────────────────────────────────────────

DOWNLOADED=0
FAILED=0
FAILED_NAMES=()
DONE=0

while IFS=$'\t' read -r status label reason; do
    DONE=$((DONE + 1))

    if [[ "$status" == "OK" ]]; then
        DOWNLOADED=$((DOWNLOADED + 1))
    else
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("$label: $reason")
    fi

    printf '\r[%4d/%4d] %-34s' "$DONE" "$TASK_COUNT" "$label"
done < <(
    xargs -0 -n 2 -P "$JOBS" "$SCRIPT_PATH" --_process < "$TASKS_FILE"
)

printf '\n\n'

pf_success "Descarga finalizada."
printf 'Descargados:  %s\n' "$DOWNLOADED"
printf 'Fallidos:     %s\n' "$FAILED"

if ((FAILED > 0)); then
    printf '\nNo se pudieron obtener:\n'
    printf '  - %s\n' "${FAILED_NAMES[@]}"
fi

printf '\nSi descargaste Pokémon nuevos, agregalos a la Pokédex con:\n'
printf '  ./add-missing-pokemon.sh\n'