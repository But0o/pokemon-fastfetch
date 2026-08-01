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

if ((pokemon_count <= 0)); then
    printf '[ERROR] La Pokédex no contiene entradas.\n' >&2
    exit 1
fi

printf '  [OK] %s Pokémon\n' "$pokemon_count"

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

if [[ "$installed_count" != "$pokemon_count" ]]; then
    printf '[ERROR] La Pokédex instalada tiene %s entradas; se esperaban %s.\n' \
        "$installed_count" \
        "$pokemon_count" >&2
    exit 1
fi

printf '  [OK] Instalación aislada\n'

printf '\n==> Probando ayudas\n'

"$ROOT_DIR/install.sh" --help >/dev/null
"$ROOT_DIR/upgrade-v1-to-v2.sh" --help >/dev/null
"$ROOT_DIR/random-fastfetch.sh" --help >/dev/null
"$ROOT_DIR/render-pokemon.sh" --help >/dev/null

printf '  [OK] Ayudas disponibles\n'

printf '\nTodos los tests finalizaron correctamente.\n'