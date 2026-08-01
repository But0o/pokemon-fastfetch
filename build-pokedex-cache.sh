#!/usr/bin/env bash

set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Pokémon Fastfetch
#
# Pokédex cache builder.
#
# Responsibilities:
#   - Enrich the bundled Pokédex
#   - Retrieve data from PokeAPI
#   - Preserve existing cache entries
#   - Validate the generated cache
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

# ────────────────────────────────────────────────────────────────
# Pokémon Fastfetch v2
# Completa la caché existente con estadísticas y habilidades.
#
# La conexión a PokeAPI se usa solamente al generar la caché.
# El script principal no necesitará internet.
# ────────────────────────────────────────────────────────────────

CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/pokemon-fastfetch"
CONFIG_FILE="$CONFIG_ROOT/config"

if [[ -r "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

CACHE_DIR="${CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/pokemon-fastfetch}"
CACHE_FILE="$CACHE_DIR/pokedex.json"
TEMP_DIR="$CACHE_DIR/build-v2"
TEMP_JSONL="$TEMP_DIR/pokemon.jsonl"
NEW_CACHE="$TEMP_DIR/pokedex-v2.json"

API_BASE="https://pokeapi.co/api/v2"

mkdir -p "$CACHE_DIR"
mkdir -p "$TEMP_DIR"

# ────────────────────────────────────────────────────────────────
# Colores
# ────────────────────────────────────────────────────────────────


YELLOW=$'\033[33m'
CYAN=$'\033[36m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

# ────────────────────────────────────────────────────────────────
# Dependencias
# ────────────────────────────────────────────────────────────────

pf_require_commands jq curl

# ────────────────────────────────────────────────────────────────
# Comprobar caché actual
# ────────────────────────────────────────────────────────────────

pf_require_json "$CACHE_FILE" "La caché Pokédex"

# ────────────────────────────────────────────────────────────────
# Copia de seguridad
# ────────────────────────────────────────────────────────────────

BACKUP_FILE="$CACHE_DIR/pokedex-backup-$(date +%Y%m%d-%H%M%S).json"

cp "$CACHE_FILE" "$BACKUP_FILE"

pf_success "Copia de seguridad creada: $BACKUP_FILE"
echo

# Limpiar resultado temporal anterior.
: > "$TEMP_JSONL"

TOTAL="$(
    jq 'length' "$CACHE_FILE"
)"

CURRENT=0
FAILED=0

printf '%sPokémon encontrados: %s%s\n\n' \
    "$BOLD" \
    "$TOTAL" \
    "$RESET"

# ────────────────────────────────────────────────────────────────
# Procesar cada Pokémon
# ────────────────────────────────────────────────────────────────

while IFS= read -r KEY; do
    CURRENT=$((CURRENT + 1))

    EXISTING_ENTRY="$(
        jq -c \
            --arg key "$KEY" \
            '.[$key]' \
            "$CACHE_FILE"
    )"

    ID="$(
        jq -r '.id // 0' <<< "$EXISTING_ENTRY"
    )"

    NAME="$(
        jq -r '
            .name
            // .api_name
            // "Desconocido"
        ' <<< "$EXISTING_ENTRY"
    )"

    printf '\r%s[%4d/%4d]%s %-28s' \
        "$CYAN" \
        "$CURRENT" \
        "$TOTAL" \
        "$RESET" \
        "$NAME"

    # Si ya tiene todas las estadísticas y habilidades,
    # reutilizamos la entrada sin consultar internet.
    HAS_COMPLETE_DATA="$(
        jq -r '
            (
                (.stats.hp // null) != null
                and
                (.stats.attack // null) != null
                and
                (.stats.defense // null) != null
                and
                (.stats.special_attack // null) != null
                and
                (.stats.special_defense // null) != null
                and
                (.stats.speed // null) != null
                and
                ((.abilities // []) | length > 0)
            )
        ' <<< "$EXISTING_ENTRY"
    )"

    if [[ "$HAS_COMPLETE_DATA" == "true" ]]; then
        jq -cn \
            --arg key "$KEY" \
            --argjson value "$EXISTING_ENTRY" \
            '{
                key: $key,
                value: $value
            }' >> "$TEMP_JSONL"

        continue
    fi

    API_RESPONSE="$(
        curl \
            --silent \
            --show-error \
            --fail \
            --retry 3 \
            --retry-delay 1 \
            --connect-timeout 8 \
            --max-time 20 \
            "$API_BASE/pokemon/$ID" \
            2>/dev/null ||
            true
    )"

    if [[ -z "$API_RESPONSE" ]]; then
        FAILED=$((FAILED + 1))

        jq -cn \
            --arg key "$KEY" \
            --argjson value "$EXISTING_ENTRY" \
            '{
                key: $key,
                value: $value
            }' >> "$TEMP_JSONL"

        continue
    fi

    API_DATA="$(
        jq -c '
            {
                stats: {
                    hp: (
                        [
                            .stats[]
                            | select(.stat.name == "hp")
                            | .base_stat
                        ][0] // 0
                    ),

                    attack: (
                        [
                            .stats[]
                            | select(.stat.name == "attack")
                            | .base_stat
                        ][0] // 0
                    ),

                    defense: (
                        [
                            .stats[]
                            | select(.stat.name == "defense")
                            | .base_stat
                        ][0] // 0
                    ),

                    special_attack: (
                        [
                            .stats[]
                            | select(.stat.name == "special-attack")
                            | .base_stat
                        ][0] // 0
                    ),

                    special_defense: (
                        [
                            .stats[]
                            | select(.stat.name == "special-defense")
                            | .base_stat
                        ][0] // 0
                    ),

                    speed: (
                        [
                            .stats[]
                            | select(.stat.name == "speed")
                            | .base_stat
                        ][0] // 0
                    )
                },

                abilities: (
                    [
                        .abilities[]
                        | .ability.name
                    ]
                ),

                base_experience: (
                    .base_experience // 0
                ),

                height_m: (
                    (.height // 0) / 10
                ),

                weight_kg: (
                    (.weight // 0) / 10
                )
            }
        ' <<< "$API_RESPONSE"
    )"

    MERGED_ENTRY="$(
        jq -cn \
            --argjson existing "$EXISTING_ENTRY" \
            --argjson api "$API_DATA" \
            '
                $existing
                *
                $api
            '
    )"

    jq -cn \
        --arg key "$KEY" \
        --argjson value "$MERGED_ENTRY" \
        '{
            key: $key,
            value: $value
        }' >> "$TEMP_JSONL"

    # Pequeña pausa para no saturar la API.
    sleep 0.05

done < <(
    jq -r '
        to_entries
        | sort_by(.value.id // 99999)
        | .[].key
    ' "$CACHE_FILE"
)

printf '\n\n'

# ────────────────────────────────────────────────────────────────
# Construir JSON final
# ────────────────────────────────────────────────────────────────

jq -s '
    from_entries
' "$TEMP_JSONL" > "$NEW_CACHE"

if ! jq empty "$NEW_CACHE" >/dev/null 2>&1; then
    pf_die "No se pudo generar la nueva caché."
fi

NEW_TOTAL="$(
    jq 'length' "$NEW_CACHE"
)"

if [[ "$NEW_TOTAL" -ne "$TOTAL" ]]; then
    pf_error "La cantidad de Pokémon no coincide."
    echo "Original: $TOTAL" >&2
    echo "Nueva:    $NEW_TOTAL" >&2
    exit 1
fi

# Guardado atómico.
mv "$NEW_CACHE" "$CACHE_FILE"

# ────────────────────────────────────────────────────────────────
# Validación
# ────────────────────────────────────────────────────────────────

COMPLETE_COUNT="$(
    jq '
        [
            .[]
            | select(
                (.stats.hp // null) != null
                and
                (.stats.attack // null) != null
                and
                (.stats.defense // null) != null
                and
                (.stats.special_attack // null) != null
                and
                (.stats.special_defense // null) != null
                and
                (.stats.speed // null) != null
                and
                ((.abilities // []) | length > 0)
            )
        ]
        | length
    ' "$CACHE_FILE"
)"

echo

pf_success "Caché v2 generada correctamente."

echo
echo "Archivo:"
echo "$CACHE_FILE"

echo
echo "Pokémon totales:    $TOTAL"
echo "Datos completos:    $COMPLETE_COUNT"
echo "Consultas fallidas: $FAILED"

echo
echo "Copia de seguridad:"
echo "$BACKUP_FILE"

echo
printf '%sEjemplo de Charizard:%s\n' \
    "$YELLOW" \
    "$RESET"

jq '
    .charizard
    | {
        id,
        name,
        types,
        abilities,
        stats,
        region,
        generation,
        height_m,
        weight_kg,
        image
    }
' "$CACHE_FILE" 2>/dev/null || true
