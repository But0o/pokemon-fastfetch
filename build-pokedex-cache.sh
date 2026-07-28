#!/usr/bin/env bash

set -Eeuo pipefail

# ─────────────────────────────────────────────
# Rutas
# ─────────────────────────────────────────────

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd
)"

POKEMON_DIR="${POKEMON_DIR:-$HOME/.local/share/pokimg/images}"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pokemon-fastfetch"
CACHE_FILE="$CACHE_DIR/pokedex.json"
TEMP_FILE="$CACHE_DIR/pokedex.tmp.json"

mkdir -p "$CACHE_DIR"

# ─────────────────────────────────────────────
# Dependencias
# ─────────────────────────────────────────────

DEPENDENCIES=(
    curl
    jq
    find
    sort
    sed
    awk
    basename
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
    echo "Instalá pokimg o ejecutá:"
    echo
    echo 'POKEMON_DIR="/ruta/a/images" ./build-pokedex-cache.sh'
    exit 1
fi

# ─────────────────────────────────────────────
# Crear JSON inicial
# ─────────────────────────────────────────────

if [[ ! -s "$CACHE_FILE" ]]; then
    printf '{}\n' > "$CACHE_FILE"
elif ! jq empty "$CACHE_FILE" >/dev/null 2>&1; then
    echo "La caché existente está dañada:"
    echo "$CACHE_FILE"
    echo
    echo "Eliminándola para generar una nueva."
    printf '{}\n' > "$CACHE_FILE"
fi

# ─────────────────────────────────────────────
# Limpiar archivo temporal al salir
# ─────────────────────────────────────────────

cleanup() {
    rm -f "$TEMP_FILE"
}

trap cleanup EXIT

# ─────────────────────────────────────────────
# Normalizar nombres para PokeAPI
# ─────────────────────────────────────────────

normalize_name() {
    local name="$1"

    name="${name,,}"

    name="$(
        printf '%s' "$name" |
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

    case "$name" in
        mrmime | mr-mime)
            name="mr-mime"
            ;;

        mimejr | mime-jr)
            name="mime-jr"
            ;;

        mrrime | mr-rime)
            name="mr-rime"
            ;;

        nidoranf | nidoran-f)
            name="nidoran-f"
            ;;

        nidoranm | nidoran-m)
            name="nidoran-m"
            ;;

        farfetchd | farfetch-d)
            name="farfetchd"
            ;;

        sirfetchd | sirfetch-d)
            name="sirfetchd"
            ;;

        hooh | ho-oh)
            name="ho-oh"
            ;;

        porygonz | porygon-z)
            name="porygon-z"
            ;;

        typenull | type-null)
            name="type-null"
            ;;

        jangmoo | jangmo-o)
            name="jangmo-o"
            ;;

        hakamoo | hakamo-o)
            name="hakamo-o"
            ;;

        kommoo | kommo-o)
            name="kommo-o"
            ;;

        tapukoko | tapu-koko)
            name="tapu-koko"
            ;;

        tapulele | tapu-lele)
            name="tapu-lele"
            ;;

        tapubulu | tapu-bulu)
            name="tapu-bulu"
            ;;

        tapufini | tapu-fini)
            name="tapu-fini"
            ;;
    esac

    printf '%s' "$name"
}

# ─────────────────────────────────────────────
# Nombre visible como alternativa
# ─────────────────────────────────────────────

display_name() {
    local name="$1"

    printf '%s' "$name" |
        sed 's/-/ /g' |
        awk '{
            for (i = 1; i <= NF; i++) {
                $i = toupper(substr($i, 1, 1)) substr($i, 2)
            }

            print
        }'
}

# ─────────────────────────────────────────────
# Región según generación
# ─────────────────────────────────────────────

region_from_generation() {
    case "$1" in
        generation-i)
            printf 'Kanto'
            ;;

        generation-ii)
            printf 'Johto'
            ;;

        generation-iii)
            printf 'Hoenn'
            ;;

        generation-iv)
            printf 'Sinnoh'
            ;;

        generation-v)
            printf 'Unova'
            ;;

        generation-vi)
            printf 'Kalos'
            ;;

        generation-vii)
            printf 'Alola'
            ;;

        generation-viii)
            printf 'Galar'
            ;;

        generation-ix)
            printf 'Paldea'
            ;;

        *)
            printf 'Desconocida'
            ;;
    esac
}

# ─────────────────────────────────────────────
# Número de generación
# ─────────────────────────────────────────────

generation_number() {
    case "$1" in
        generation-i)
            printf '1'
            ;;

        generation-ii)
            printf '2'
            ;;

        generation-iii)
            printf '3'
            ;;

        generation-iv)
            printf '4'
            ;;

        generation-v)
            printf '5'
            ;;

        generation-vi)
            printf '6'
            ;;

        generation-vii)
            printf '7'
            ;;

        generation-viii)
            printf '8'
            ;;

        generation-ix)
            printf '9'
            ;;

        *)
            printf '0'
            ;;
    esac
}

# ─────────────────────────────────────────────
# Descargar JSON con reintentos
# ─────────────────────────────────────────────

fetch_json() {
    local url="$1"

    curl \
        --silent \
        --show-error \
        --fail \
        --location \
        --retry 3 \
        --retry-delay 1 \
        --connect-timeout 10 \
        --max-time 30 \
        "$url" \
        2>/dev/null
}

# ─────────────────────────────────────────────
# Buscar imágenes
# ─────────────────────────────────────────────

mapfile -d '' -t IMAGES < <(
    find "$POKEMON_DIR" \
        -maxdepth 1 \
        -type f \
        \( \
            -iname '*.png' \
            -o -iname '*.jpg' \
            -o -iname '*.jpeg' \
            -o -iname '*.webp' \
        \) \
        -print0 |
        sort -z
)

TOTAL="${#IMAGES[@]}"

if (( TOTAL == 0 )); then
    echo "No se encontraron imágenes compatibles en:"
    echo "$POKEMON_DIR"
    exit 1
fi

CURRENT=0
ADDED=0
CACHED=0
FAILED=0

echo
echo "Generador de caché Pokémon Fastfetch"
echo "────────────────────────────────────────"
echo "Imágenes: $TOTAL"
echo "Origen:   $POKEMON_DIR"
echo "Caché:    $CACHE_FILE"
echo
echo "Podés detenerlo con Ctrl + C y continuarlo después."
echo

# ─────────────────────────────────────────────
# Procesar imágenes
# ─────────────────────────────────────────────

for image_path in "${IMAGES[@]}"; do
    ((CURRENT += 1))

    filename="$(basename "$image_path")"
    raw_name="${filename%.*}"
    api_name="$(normalize_name "$raw_name")"

    printf '[%4d/%4d] %-28s ' "$CURRENT" "$TOTAL" "$api_name"

    if jq -e \
        --arg pokemon "$api_name" \
        'has($pokemon)' \
        "$CACHE_FILE" \
        >/dev/null 2>&1; then

        echo "ya guardado"
        ((CACHED += 1))
        continue
    fi

    pokemon_json="$(
        fetch_json \
            "https://pokeapi.co/api/v2/pokemon/$api_name" ||
            true
    )"

    if [[ -z "$pokemon_json" ]] ||
        ! jq -e '.id and .species.url' \
            >/dev/null 2>&1 <<< "$pokemon_json"; then

        echo "no encontrado"
        ((FAILED += 1))
        continue
    fi

    species_url="$(
        jq -r '.species.url // empty' \
            <<< "$pokemon_json"
    )"

    species_json="$(
        fetch_json "$species_url" ||
            true
    )"

    if [[ -z "$species_json" ]] ||
        ! jq -e '.generation.name' \
            >/dev/null 2>&1 <<< "$species_json"; then

        echo "falló species"
        ((FAILED += 1))
        continue
    fi

    pokemon_id="$(
        jq -r '.id' <<< "$pokemon_json"
    )"

    printf -v pokemon_number '%03d' "$pokemon_id"

    pokemon_display_name="$(
        jq -r '
            [
                .names[]
                | select(.language.name == "es")
                | .name
            ][0] // empty
        ' <<< "$species_json"
    )"

    if [[ -z "$pokemon_display_name" ]]; then
        pokemon_display_name="$(display_name "$api_name")"
    fi

    types_json="$(
        jq '
            [
                .types
                | sort_by(.slot)[]
                | .type.name
            ]
        ' <<< "$pokemon_json"
    )"

    abilities_json="$(
        jq '
            [
                .abilities
                | sort_by(.slot)[]
                | .ability.name
            ]
        ' <<< "$pokemon_json"
    )"

    generation_name="$(
        jq -r \
            '.generation.name // "unknown"' \
            <<< "$species_json"
    )"

    generation="$(generation_number "$generation_name")"
    region="$(region_from_generation "$generation_name")"

    height_dm="$(
        jq -r '.height // 0' <<< "$pokemon_json"
    )"

    weight_hg="$(
        jq -r '.weight // 0' <<< "$pokemon_json"
    )"

    height_m="$(
        awk -v value="$height_dm" \
            'BEGIN {printf "%.1f", value / 10}'
    )"

    weight_kg="$(
        awk -v value="$weight_hg" \
            'BEGIN {printf "%.1f", value / 10}'
    )"

    color="$(
        jq -r \
            '.color.name // "unknown"' \
            <<< "$species_json"
    )"

    habitat="$(
        jq -r \
            '.habitat.name // "unknown"' \
            <<< "$species_json"
    )"

    legendary="$(
        jq -r \
            '.is_legendary // false' \
            <<< "$species_json"
    )"

    mythical="$(
        jq -r \
            '.is_mythical // false' \
            <<< "$species_json"
    )"

    baby="$(
        jq -r \
            '.is_baby // false' \
            <<< "$species_json"
    )"

    # Solo se guarda el nombre del archivo.
    # Esto permite usar el repositorio en cualquier PC.
    image_filename="$(basename "$image_path")"

    entry="$(
        jq -n \
            --arg key "$api_name" \
            --argjson id "$pokemon_id" \
            --arg number "$pokemon_number" \
            --arg name "$pokemon_display_name" \
            --arg api_name "$api_name" \
            --arg image "$image_filename" \
            --argjson types "$types_json" \
            --argjson abilities "$abilities_json" \
            --arg region "$region" \
            --argjson generation "$generation" \
            --argjson height "$height_m" \
            --argjson weight "$weight_kg" \
            --arg color "$color" \
            --arg habitat "$habitat" \
            --argjson legendary "$legendary" \
            --argjson mythical "$mythical" \
            --argjson baby "$baby" \
            '{
                ($key): {
                    id: $id,
                    number: $number,
                    name: $name,
                    api_name: $api_name,
                    image: $image,
                    types: $types,
                    abilities: $abilities,
                    region: $region,
                    generation: $generation,
                    height_m: $height,
                    weight_kg: $weight,
                    color: $color,
                    habitat: $habitat,
                    legendary: $legendary,
                    mythical: $mythical,
                    baby: $baby
                }
            }'
    )"

    if ! jq \
        --argjson entry "$entry" \
        '. + $entry' \
        "$CACHE_FILE" \
        > "$TEMP_FILE"; then

        echo "error escribiendo"
        ((FAILED += 1))
        continue
    fi

    mv "$TEMP_FILE" "$CACHE_FILE"

    echo "guardado"
    ((ADDED += 1))

    sleep 0.12
done

# ─────────────────────────────────────────────
# Ordenar por número de Pokédex
# ─────────────────────────────────────────────

if jq \
    'to_entries | sort_by(.value.id) | from_entries' \
    "$CACHE_FILE" \
    > "$TEMP_FILE"; then

    mv "$TEMP_FILE" "$CACHE_FILE"
fi

echo
echo "────────────────────────────────────────"
echo "Caché terminada"
echo
echo "Nuevos:       $ADDED"
echo "Ya guardados: $CACHED"
echo "Fallidos:     $FAILED"
echo "Total JSON:   $(jq 'length' "$CACHE_FILE")"
echo
echo "Archivo:"
echo "$CACHE_FILE"
