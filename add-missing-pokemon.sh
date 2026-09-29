#!/usr/bin/env bash

set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Pokémon Fastfetch
#
# Missing Pokémon importer.
#
# Responsibilities:
#   - Scan the local Pokémon image directory
#   - Detect species missing from config/pokedex.json
#   - Validate species through PokeAPI
#   - Retrieve Pokémon and species metadata
#   - Add valid missing Pokémon to the bundled Pokédex
#   - Preserve the original Pokédex through a backup
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

POKEDEX_FILE="$SCRIPT_DIR/config/pokedex.json"

CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/pokemon-fastfetch"
CONFIG_FILE="$CONFIG_ROOT/config"

if [[ -r "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

POKEMON_DIR="${POKEMON_DIR:-$HOME/.local/share/pokimg/images}"

API_BASE="https://pokeapi.co/api/v2"

TEMP_DIR="$(
    mktemp -d \
        "${TMPDIR:-/tmp}/pokemon-fastfetch-import.XXXXXX"
)"

WORKING_JSON="$TEMP_DIR/pokedex.json"
NEW_ENTRIES_JSONL="$TEMP_DIR/new-entries.jsonl"

ADDED=0
SKIPPED=0
FAILED=0

cleanup() {
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

show_help() {
    cat <<EOF
Pokémon Fastfetch - Missing Pokémon importer

Uso:

  ./add-missing-pokemon.sh

Variables opcionales:

  POKEMON_DIR
      Directorio que contiene los sprites Pokémon.

Ejemplo:

  POKEMON_DIR="\$HOME/.local/share/pokimg/images" \
      ./add-missing-pokemon.sh

El script solamente agrega especies que:

  1. Tienen un sprite local.
  2. No existen actualmente en config/pokedex.json.
  3. Existen como especie válida en PokeAPI.

Las formas alternativas no se agregan como especies independientes.
EOF
}

case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
esac

pf_require_commands \
    jq \
    curl \
    find \
    sort \
    cp \
    mv \
    date \
    sed \
    awk \
    tr \
    head

pf_require_json \
    "$POKEDEX_FILE" \
    "La Pokédex"

pf_require_directory \
    "$POKEMON_DIR" \
    "El directorio de imágenes"

cp "$POKEDEX_FILE" "$WORKING_JSON"
: > "$NEW_ENTRIES_JSONL"

# Claves e IDs existentes, cargados una sola vez en memoria.
# Antes se releía el JSON completo por cada sprite.
declare -A KNOWN_KEYS=()
declare -A KNOWN_IDS=()

while IFS=$'\t' read -r EXISTING_KEY EXISTING_ID; do
    KNOWN_KEYS["$EXISTING_KEY"]=1
    KNOWN_IDS["$EXISTING_ID"]=1
done < <(
    jq -r 'to_entries[] | [.key, (.value.id // 0 | tostring)] | @tsv' "$WORKING_JSON"
)

BACKUP_FILE="$SCRIPT_DIR/config/pokedex-backup-$(date +%Y%m%d-%H%M%S).json"

cp "$POKEDEX_FILE" "$BACKUP_FILE"

pf_success "Backup creado: $BACKUP_FILE"

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

generation_region() {
    case "$1" in
        1)
            printf 'Kanto'
            ;;
        2)
            printf 'Johto'
            ;;
        3)
            printf 'Hoenn'
            ;;
        4)
            printf 'Sinnoh'
            ;;
        5)
            printf 'Unova'
            ;;
        6)
            printf 'Kalos'
            ;;
        7)
            printf 'Alola'
            ;;
        8)
            printf 'Galar'
            ;;
        9)
            printf 'Paldea'
            ;;
        *)
            printf 'Desconocida'
            ;;
    esac
}

title_case_name() {
    local value="${1:-}"

    printf '%s' "$value" |
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

find_sprite() {
    local pokemon_name="${1:-}"

    find "$POKEMON_DIR" \
        -maxdepth 1 \
        -type f \
        \( \
            -iname "${pokemon_name}.png" \
            -o -iname "${pokemon_name}.webp" \
            -o -iname "${pokemon_name}.jpg" \
            -o -iname "${pokemon_name}.jpeg" \
            -o -iname "${pokemon_name}.gif" \
        \) \
        -printf '%f\n' \
        2>/dev/null |
        head -n 1
}

mapfile -t SPRITE_NAMES < <(
    find "$POKEMON_DIR" \
        -maxdepth 1 \
        -type f \
        \( \
            -iname '*.png' \
            -o -iname '*.webp' \
            -o -iname '*.jpg' \
            -o -iname '*.jpeg' \
            -o -iname '*.gif' \
        \) \
        -printf '%f\n' |
        sed -E 's/\.(png|webp|jpg|jpeg|gif)$//' |
        tr '[:upper:]' '[:lower:]' |
        sort -u
)

TOTAL_SPRITES="${#SPRITE_NAMES[@]}"
CURRENT=0

printf '\nSprites encontrados: %d\n\n' "$TOTAL_SPRITES"

for POKEMON_NAME in "${SPRITE_NAMES[@]}"; do
    CURRENT=$((CURRENT + 1))

    printf '\r[%4d/%4d] %-30s' \
        "$CURRENT" \
        "$TOTAL_SPRITES" \
        "$POKEMON_NAME"

    # Ya existe con esa clave exacta.
    if [[ -n "${KNOWN_KEYS[$POKEMON_NAME]:-}" ]]; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # -------------------------------------------------------------------------
    # Consultar species
    #
    # Si pokemon-species/<nombre> no existe, probablemente el sprite sea una
    # forma alternativa y no una especie base.
    # -------------------------------------------------------------------------

    SPECIES_FILE="$TEMP_DIR/species-${POKEMON_NAME}.json"

    if ! curl \
        --silent \
        --show-error \
        --fail \
        --retry 2 \
        --retry-delay 1 \
        --connect-timeout 8 \
        --max-time 20 \
        --output "$SPECIES_FILE" \
        "$API_BASE/pokemon-species/$POKEMON_NAME"
    then
        rm -f "$SPECIES_FILE"
        continue
    fi

    if ! jq empty "$SPECIES_FILE" >/dev/null 2>&1; then
        FAILED=$((FAILED + 1))
        rm -f "$SPECIES_FILE"
        continue
    fi

    SPECIES_API_NAME="$(
        jq -r \
            '.name // empty' \
            "$SPECIES_FILE"
    )"

    if [[ "$SPECIES_API_NAME" != "$POKEMON_NAME" ]]; then
        continue
    fi

    ID="$(
        jq -r \
            '.id // 0' \
            "$SPECIES_FILE"
    )"

    if ! [[ "$ID" =~ ^[0-9]+$ ]] || ((ID <= 0)); then
        FAILED=$((FAILED + 1))
        continue
    fi

    # Evitar duplicar IDs por si una especie ya existe bajo otra clave.
    if [[ -n "${KNOWN_IDS[$ID]:-}" ]]; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # -------------------------------------------------------------------------
    # Consultar datos Pokémon
    # -------------------------------------------------------------------------

    POKEMON_FILE="$TEMP_DIR/pokemon-${ID}.json"

    if ! curl \
        --silent \
        --show-error \
        --fail \
        --retry 2 \
        --retry-delay 1 \
        --connect-timeout 8 \
        --max-time 20 \
        --output "$POKEMON_FILE" \
        "$API_BASE/pokemon/$ID"
    then
        FAILED=$((FAILED + 1))
        rm -f "$POKEMON_FILE"
        continue
    fi

    if ! jq empty "$POKEMON_FILE" >/dev/null 2>&1; then
        FAILED=$((FAILED + 1))
        rm -f "$POKEMON_FILE"
        continue
    fi

    SPRITE_FILE="$(
        find_sprite "$POKEMON_NAME"
    )"

    if [[ -z "$SPRITE_FILE" ]]; then
        FAILED=$((FAILED + 1))
        continue
    fi

    GENERATION_NAME="$(
        jq -r \
            '.generation.name // empty' \
            "$SPECIES_FILE"
    )"

    GENERATION="$(
        generation_number "$GENERATION_NAME"
    )"

    REGION="$(
        generation_region "$GENERATION"
    )"

    DISPLAY_NAME="$(
        title_case_name "$POKEMON_NAME"
    )"

    # -------------------------------------------------------------------------
    # Construir entrada nueva
    #
    # IMPORTANTE:
    # usamos --slurpfile en lugar de --argjson para evitar superar ARG_MAX
    # con respuestas grandes de PokeAPI.
    # -------------------------------------------------------------------------

    NEW_ENTRY="$(
        jq -cn \
            --slurpfile species "$SPECIES_FILE" \
            --slurpfile pokemon "$POKEMON_FILE" \
            --arg name "$DISPLAY_NAME" \
            --arg api_name "$POKEMON_NAME" \
            --arg image "$SPRITE_FILE" \
            --arg region "$REGION" \
            --argjson generation "$GENERATION" \
            '
                $species[0] as $species
                | $pokemon[0] as $pokemon
                | {
                    id: (
                        $species.id
                        // 0
                    ),

                    name: $name,

                    api_name: $api_name,

                    image: $image,

                    types: (
                        [
                            $pokemon.types[]
                            | .type.name
                        ]
                    ),

                    region: $region,

                    generation: $generation,

                    height_m: (
                        (
                            $pokemon.height
                            // 0
                        ) / 10
                    ),

                    weight_kg: (
                        (
                            $pokemon.weight
                            // 0
                        ) / 10
                    ),

                    legendary: (
                        $species.is_legendary
                        // false
                    ),

                    mythical: (
                        $species.is_mythical
                        // false
                    ),

                    baby: (
                        $species.is_baby
                        // false
                    ),

                    abilities: (
                        [
                            $pokemon.abilities[]
                            | .ability.name
                        ]
                    ),

                    stats: {
                        hp: (
                            [
                                $pokemon.stats[]
                                | select(
                                    .stat.name == "hp"
                                )
                                | .base_stat
                            ][0] // 0
                        ),

                        attack: (
                            [
                                $pokemon.stats[]
                                | select(
                                    .stat.name == "attack"
                                )
                                | .base_stat
                            ][0] // 0
                        ),

                        defense: (
                            [
                                $pokemon.stats[]
                                | select(
                                    .stat.name == "defense"
                                )
                                | .base_stat
                            ][0] // 0
                        ),

                        special_attack: (
                            [
                                $pokemon.stats[]
                                | select(
                                    .stat.name == "special-attack"
                                )
                                | .base_stat
                            ][0] // 0
                        ),

                        special_defense: (
                            [
                                $pokemon.stats[]
                                | select(
                                    .stat.name == "special-defense"
                                )
                                | .base_stat
                            ][0] // 0
                        ),

                        speed: (
                            [
                                $pokemon.stats[]
                                | select(
                                    .stat.name == "speed"
                                )
                                | .base_stat
                            ][0] // 0
                        )
                    },

                    base_experience: (
                        $pokemon.base_experience
                        // 0
                    )
                }
            '
    )"

    # Las entradas nuevas se juntan y se agregan todas juntas al final,
    # en vez de reescribir la Pokédex completa por cada una.
    jq -cn \
        --arg key "$POKEMON_NAME" \
        --argjson value "$NEW_ENTRY" \
        '{key: $key, value: $value}' >> "$NEW_ENTRIES_JSONL"

    KNOWN_KEYS["$POKEMON_NAME"]=1
    KNOWN_IDS["$ID"]=1

    ADDED=$((ADDED + 1))

    printf '\n  + agregado: %s (#%s)\n' \
        "$POKEMON_NAME" \
        "$ID"

    sleep 0.05
done

printf '\n\n'

if ((ADDED > 0)); then
    jq -s \
        '.[0] + (.[1:] | map({(.key): .value}) | add // {})' \
        "$WORKING_JSON" \
        "$NEW_ENTRIES_JSONL" \
        > "$TEMP_DIR/pokedex-next.json"

    mv "$TEMP_DIR/pokedex-next.json" "$WORKING_JSON"
fi

# -----------------------------------------------------------------------------
# Validación final
# -----------------------------------------------------------------------------

pf_require_json \
    "$WORKING_JSON" \
    "La Pokédex generada"

OLD_TOTAL="$(
    jq 'length' "$POKEDEX_FILE"
)"

NEW_TOTAL="$(
    jq 'length' "$WORKING_JSON"
)"

if ((NEW_TOTAL < OLD_TOTAL)); then
    pf_die "La Pokédex resultante contiene menos entradas que la original."
fi

UNIQUE_ID_COUNT="$(
    jq '
        [
            .[]
            | .id
        ]
        | unique
        | length
    ' "$WORKING_JSON"
)"

if [[ "$UNIQUE_ID_COUNT" -ne "$NEW_TOTAL" ]]; then
    pf_die "Se detectaron IDs duplicados en la Pokédex generada."
fi

mv "$WORKING_JSON" "$POKEDEX_FILE"

INSTALLED_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pokemon-fastfetch"
INSTALLED_CACHE_FILE="$INSTALLED_CACHE_DIR/pokedex.json"

if [[ -d "$INSTALLED_CACHE_DIR" ]]; then
    cp "$POKEDEX_FILE" "$INSTALLED_CACHE_FILE"

    pf_success "Caché instalada sincronizada: $INSTALLED_CACHE_FILE"
else
    pf_info "No se encontró una instalación activa para sincronizar la caché."
fi

pf_success "Importación finalizada."

printf '\n'
printf 'Entradas originales: %s\n' "$OLD_TOTAL"
printf 'Entradas finales:    %s\n' "$NEW_TOTAL"
printf 'IDs únicos:          %s\n' "$UNIQUE_ID_COUNT"
printf 'Pokémon agregados:   %s\n' "$ADDED"
printf 'Ignorados:           %s\n' "$SKIPPED"
printf 'Fallidos:            %s\n' "$FAILED"
printf '\n'
printf 'Backup:\n%s\n' "$BACKUP_FILE"