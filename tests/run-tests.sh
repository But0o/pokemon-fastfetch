#!/usr/bin/env bash

set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Pokémon Fastfetch
#
# Automated test suite.
#
# Responsibilities:
#   - Validate Bash syntax
#   - Validate project files
#   - Validate the Pokédex
#   - Test isolated installations
#   - Verify command help screens
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

ROOT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1
    pwd
)"

TEST_ROOT="$(
    mktemp -d "${TMPDIR:-/tmp}/pokemon-fastfetch-tests.XXXXXX"
)"

cleanup() {
    rm -rf "$TEST_ROOT"
}

trap cleanup EXIT

REAL_HOME="$HOME"
POKEMON_DIR="${POKEMON_DIR:-$REAL_HOME/.local/share/pokimg/images}"

scripts=(
    "$ROOT_DIR/install.sh"
    "$ROOT_DIR/uninstall.sh"
    "$ROOT_DIR/upgrade-v1-to-v2.sh"
    "$ROOT_DIR/random-fastfetch.sh"
    "$ROOT_DIR/render-pokemon.sh"
    "$ROOT_DIR/build-pokedex-cache.sh"
    "$ROOT_DIR/add-missing-pokemon.sh"
    "$ROOT_DIR/download-sprites.sh"
    "$ROOT_DIR/lib/common.sh"
)

printf '==> Verificando sintaxis Bash\n'

for script in "${scripts[@]}"; do
    bash -n "$script"
    printf '  [OK] %s\n' "${script#"$ROOT_DIR/"}"
done

printf '\n==> Validando archivos obligatorios\n'

required_files=(
    "$ROOT_DIR/VERSION"
    "$ROOT_DIR/LICENSE"
    "$ROOT_DIR/README.md"
    "$ROOT_DIR/CHANGELOG.md"
    "$ROOT_DIR/config/pokedex.json"
    "$ROOT_DIR/config/megas.json"
    "$ROOT_DIR/add-missing-pokemon.sh"
    "$ROOT_DIR/download-sprites.sh"
    "$ROOT_DIR/lib/common.sh"
)

for file in "${required_files[@]}"; do
    [[ -s "$file" ]] || {
        printf '[ERROR] Falta o está vacío: %s\n' "$file" >&2
        exit 1
    }

    printf '  [OK] %s\n' "${file#"$ROOT_DIR/"}"
done

printf '\n==> Validando Pokédex\n'

jq empty "$ROOT_DIR/config/pokedex.json"

pokemon_count="$(
    jq 'length' "$ROOT_DIR/config/pokedex.json"
)"

# Al menos las 8 primeras generaciones. Se pueden agregar más (Gen 9)
# sin tocar este test, siempre que los IDs sigan siendo 1..N sin huecos.
if [[ "$pokemon_count" -lt 898 ]]; then
    printf '[ERROR] Se esperaban al menos 898 Pokémon y se encontraron %s.\n' \
        "$pokemon_count" >&2
    exit 1
fi

if ! jq -e '[.[].id] | sort == [range(1; length + 1)]' \
    "$ROOT_DIR/config/pokedex.json" >/dev/null; then
    printf '[ERROR] Los IDs de la Pokédex no son consecutivos desde 1.\n' >&2
    exit 1
fi

unique_id_count="$(
    jq '
        [
            .[]
            | .id
        ]
        | unique
        | length
    ' "$ROOT_DIR/config/pokedex.json"
)"

if [[ "$unique_id_count" -ne "$pokemon_count" ]]; then
    printf '[ERROR] Se detectaron IDs duplicados en la Pokédex.\n' >&2
    printf 'Entradas: %s\n' "$pokemon_count" >&2
    printf 'IDs únicos: %s\n' "$unique_id_count" >&2
    exit 1
fi

printf '  [OK] %s Pokémon con IDs únicos\n' "$pokemon_count"

# Megaevoluciones: cada una apunta a una forma base de la Pokédex, tiene
# su sprite en mega/ y las seis estadísticas.
if ! jq -e --slurpfile pokedex "$ROOT_DIR/config/pokedex.json" '
    length >= 48
    and all(to_entries[];
        .value.base as $base
        | .value.mega == true
        and ($pokedex[0] | has($base))
        and (.value.image == "mega/\(.key).png")
        and ((.value.stats // {}) | length == 6)
        and ((.value.types // []) | length >= 1)
    )
' "$ROOT_DIR/config/megas.json" >/dev/null; then
    printf '[ERROR] config/megas.json tiene entradas inválidas.\n' >&2
    exit 1
fi

printf '  [OK] %s megaevoluciones válidas\n' "$(jq 'length' "$ROOT_DIR/config/megas.json")"

printf '\n==> Probando biblioteca común\n'

bash -c '
    set -Eeuo pipefail
    source "$1"
    pf_require_file "$2" "El README"
    pf_require_json "$3" "La Pokédex"
' _ \
    "$ROOT_DIR/lib/common.sh" \
    "$ROOT_DIR/README.md" \
    "$ROOT_DIR/config/pokedex.json"

printf '  [OK] lib/common.sh\n'

printf '\n==> Probando instalación aislada\n'

TEST_HOME="$TEST_ROOT/home"
mkdir -p "$TEST_HOME"

env \
    HOME="$TEST_HOME" \
    XDG_DATA_HOME="$TEST_HOME/.local/share" \
    XDG_CONFIG_HOME="$TEST_HOME/.config" \
    XDG_CACHE_HOME="$TEST_HOME/.cache" \
    "$ROOT_DIR/install.sh" \
        --yes \
        --no-autostart \
        --pokemon-dir "$POKEMON_DIR"

installed_dir="$TEST_HOME/.local/share/pokemon-fastfetch"
installed_cache="$TEST_HOME/.cache/pokemon-fastfetch/pokedex.json"

installed_files=(
    "$installed_dir/random-fastfetch.sh"
    "$installed_dir/render-pokemon.sh"
    "$installed_dir/build-pokedex-cache.sh"
    "$installed_dir/uninstall.sh"
    "$installed_dir/lib/common.sh"
    "$installed_dir/VERSION"
)

for file in "${installed_files[@]}"; do
    [[ -s "$file" ]] || {
        printf '[ERROR] No se instaló correctamente: %s\n' "$file" >&2
        exit 1
    }
done

jq empty "$installed_cache"

installed_count="$(
    jq 'length' "$installed_cache"
)"

if [[ "$installed_count" -ne "$pokemon_count" ]]; then
    printf '[ERROR] La Pokédex instalada tiene %s entradas; se esperaban %s.\n' \
        "$installed_count" \
        "$pokemon_count" >&2
    exit 1
fi

installed_unique_id_count="$(
    jq '
        [
            .[]
            | .id
        ]
        | unique
        | length
    ' "$installed_cache"
)"

if [[ "$installed_unique_id_count" -ne "$installed_count" ]]; then
    printf '[ERROR] La Pokédex instalada contiene IDs duplicados.\n' >&2
    exit 1
fi

printf '  [OK] Instalación aislada con %s Pokémon\n' "$installed_count"

printf '\n==> Probando renderizado\n'

if command -v magick >/dev/null 2>&1; then
    TEST_MAGICK=magick
elif command -v convert >/dev/null 2>&1; then
    TEST_MAGICK=convert
else
    TEST_MAGICK=""
fi

if [[ -z "$TEST_MAGICK" ]] || ! command -v fc-match >/dev/null 2>&1; then
    printf '  [SKIP] Falta ImageMagick o fontconfig\n'
else
    RENDER_HOME="$TEST_ROOT/render-home"
    RENDER_IMAGES="$TEST_ROOT/render-images"

    mkdir -p "$RENDER_HOME/.cache/pokemon-fastfetch" "$RENDER_IMAGES"
    cp "$ROOT_DIR/config/pokedex.json" "$RENDER_HOME/.cache/pokemon-fastfetch/"
    "$TEST_MAGICK" -size 64x64 xc:none -fill '#f5d142' \
        -draw 'circle 32,32 32,8' "$RENDER_IMAGES/pikachu.png"

    render() {
        env \
            HOME="$RENDER_HOME" \
            XDG_CACHE_HOME="$RENDER_HOME/.cache" \
            XDG_CONFIG_HOME="$RENDER_HOME/.config" \
            POKEMON_DIR="$RENDER_IMAGES" \
            "$@"
    }

    # --check resuelve números y nombres sin renderizar.
    [[ "$(render "$ROOT_DIR/render-pokemon.sh" --check 25)" == "pikachu" ]] || {
        printf '[ERROR] render-pokemon.sh --check 25 no devolvió pikachu.\n' >&2
        exit 1
    }

    if render "$ROOT_DIR/render-pokemon.sh" --check noexiste >/dev/null 2>&1; then
        printf '[ERROR] --check aceptó un Pokémon inexistente.\n' >&2
        exit 1
    fi

    printf '  [OK] render-pokemon.sh --check\n'

    # Render completo a dos tamaños (layout completo y compacto).
    for size in 1760x460 900x322; do
        panel="$(
            render \
                PF_RENDER_WIDTH="${size%x*}" \
                PF_RENDER_HEIGHT="${size#*x}" \
                "$ROOT_DIR/render-pokemon.sh" pikachu
        )"

        actual_size="$("$TEST_MAGICK" identify -format '%wx%h' "$panel" 2>/dev/null ||
            identify -format '%wx%h' "$panel")"

        if [[ "$actual_size" != "$size" ]]; then
            printf '[ERROR] Panel de %s generado con tamaño %s.\n' \
                "$size" "$actual_size" >&2
            exit 1
        fi

        printf '  [OK] Panel %s\n' "$size"
    done

    # Shiny: usa shiny/<imagen> y genera un panel aparte.
    mkdir -p "$RENDER_IMAGES/shiny"
    "$TEST_MAGICK" -size 64x64 xc:none -fill '#f59a42' \
        -draw 'circle 32,32 32,8' "$RENDER_IMAGES/shiny/pikachu.png"

    shiny_panel="$(
        render PF_RENDER_WIDTH=1760 PF_RENDER_HEIGHT=460 PF_SHINY=2 \
            "$ROOT_DIR/render-pokemon.sh" 25
    )"

    [[ "${shiny_panel##*/}" == pikachu-shiny-*.png && -s "$shiny_panel" ]] || {
        printf '[ERROR] No se generó el panel shiny: %s\n' "$shiny_panel" >&2
        exit 1
    }

    if render PF_SHINY=2 "$ROOT_DIR/render-pokemon.sh" --check 1 >/dev/null 2>&1; then
        printf '[ERROR] PF_SHINY=2 aceptó un Pokémon sin sprite shiny.\n' >&2
        exit 1
    fi

    printf '  [OK] Panel shiny\n'

    # Mega: datos de megas.json y sprites en mega/ y mega/shiny/.
    cp "$ROOT_DIR/config/megas.json" "$RENDER_HOME/.cache/pokemon-fastfetch/"
    mkdir -p "$RENDER_IMAGES/mega/shiny"
    "$TEST_MAGICK" -size 64x64 xc:none -fill '#7b5cc4' \
        -draw 'circle 32,32 32,8' "$RENDER_IMAGES/gengar.png"
    cp "$RENDER_IMAGES/gengar.png" "$RENDER_IMAGES/mega/gengar-mega.png"
    cp "$RENDER_IMAGES/gengar.png" "$RENDER_IMAGES/mega/shiny/gengar-mega.png"

    for shiny_level in 0 2; do
        mega_panel="$(
            render PF_RENDER_WIDTH=1760 PF_RENDER_HEIGHT=460 PF_SHINY="$shiny_level" \
                "$ROOT_DIR/render-pokemon.sh" gengar-mega
        )"

        expected_prefix="gengar-mega-"
        [[ "$shiny_level" == "2" ]] && expected_prefix="gengar-mega-shiny-"

        [[ "${mega_panel##*/}" == "$expected_prefix"* && -s "$mega_panel" ]] || {
            printf '[ERROR] No se generó el panel mega: %s\n' "$mega_panel" >&2
            exit 1
        }
    done

    # Por número se obtiene la forma base, no la mega.
    [[ "$(render "$ROOT_DIR/render-pokemon.sh" --check 94)" == "gengar" ]] || {
        printf '[ERROR] --check 94 no devolvió la forma base.\n' >&2
        exit 1
    }

    printf '  [OK] Panel mega y mega shiny\n'
fi

printf '\n==> Probando ayudas\n'

env \
    HOME="$TEST_HOME" \
    XDG_DATA_HOME="$TEST_HOME/.local/share" \
    XDG_CONFIG_HOME="$TEST_HOME/.config" \
    XDG_CACHE_HOME="$TEST_HOME/.cache" \
    "$ROOT_DIR/install.sh" --help >/dev/null

env \
    HOME="$TEST_HOME" \
    XDG_DATA_HOME="$TEST_HOME/.local/share" \
    XDG_CONFIG_HOME="$TEST_HOME/.config" \
    XDG_CACHE_HOME="$TEST_HOME/.cache" \
    "$ROOT_DIR/upgrade-v1-to-v2.sh" --help >/dev/null

env \
    HOME="$TEST_HOME" \
    XDG_DATA_HOME="$TEST_HOME/.local/share" \
    XDG_CONFIG_HOME="$TEST_HOME/.config" \
    XDG_CACHE_HOME="$TEST_HOME/.cache" \
    "$ROOT_DIR/random-fastfetch.sh" --help >/dev/null

env \
    HOME="$TEST_HOME" \
    XDG_DATA_HOME="$TEST_HOME/.local/share" \
    XDG_CONFIG_HOME="$TEST_HOME/.config" \
    XDG_CACHE_HOME="$TEST_HOME/.cache" \
    "$ROOT_DIR/render-pokemon.sh" --help >/dev/null

env \
    HOME="$TEST_HOME" \
    XDG_DATA_HOME="$TEST_HOME/.local/share" \
    XDG_CONFIG_HOME="$TEST_HOME/.config" \
    XDG_CACHE_HOME="$TEST_HOME/.cache" \
    "$ROOT_DIR/add-missing-pokemon.sh" --help >/dev/null

env \
    HOME="$TEST_HOME" \
    XDG_CONFIG_HOME="$TEST_HOME/.config" \
    "$ROOT_DIR/download-sprites.sh" --help >/dev/null

printf '  [OK] Ayudas disponibles\n'

printf '\nTodos los tests finalizaron correctamente.\n'