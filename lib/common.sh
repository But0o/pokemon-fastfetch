#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Pokémon Fastfetch
#
# Shared Bash library.
#
# Responsibilities:
#   - Console output helpers
#   - Validation helpers
#   - Dependency checks
#   - Path utilities
#   - JSON validation
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

if [[ -n "${POKEMON_FASTFETCH_COMMON_LOADED:-}" ]]; then
    return 0
fi

readonly POKEMON_FASTFETCH_COMMON_LOADED=1

# ----------------------------------------------------------------
# Colores
# ----------------------------------------------------------------

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    PF_RESET=$'\033[0m'
    PF_BOLD=$'\033[1m'

    PF_RED=$'\033[31m'
    PF_GREEN=$'\033[32m'
    PF_YELLOW=$'\033[33m'
    PF_CYAN=$'\033[36m'
else
    PF_RESET=""
    PF_BOLD=""

    PF_RED=""
    PF_GREEN=""
    PF_YELLOW=""
    PF_CYAN=""
fi

# ----------------------------------------------------------------
# Mensajes
# ----------------------------------------------------------------

pf_info() {
    printf '%s%s[INFO]%s %s\n' \
        "$PF_BOLD" \
        "$PF_CYAN" \
        "$PF_RESET" \
        "$*"
}

pf_success() {
    printf '%s%s[OK]%s %s\n' \
        "$PF_BOLD" \
        "$PF_GREEN" \
        "$PF_RESET" \
        "$*"
}

pf_warn() {
    printf '%s%s[AVISO]%s %s\n' \
        "$PF_BOLD" \
        "$PF_YELLOW" \
        "$PF_RESET" \
        "$*" >&2
}

pf_error() {
    printf '%s%s[ERROR]%s %s\n' \
        "$PF_BOLD" \
        "$PF_RED" \
        "$PF_RESET" \
        "$*" >&2
}

pf_die() {
    pf_error "$*"
    exit 1
}

# ----------------------------------------------------------------
# Comandos y dependencias
# ----------------------------------------------------------------

pf_command_exists() {
    local command_name="${1:-}"

    [[ -n "$command_name" ]] || return 1
    command -v "$command_name" >/dev/null 2>&1
}

pf_require_command() {
    local command_name="${1:-}"

    if [[ -z "$command_name" ]]; then
        pf_die "No se indicó qué comando validar."
    fi

    if ! pf_command_exists "$command_name"; then
        pf_die "Falta instalar o encontrar el comando: $command_name"
    fi
}

pf_require_commands() {
    local command_name=""

    for command_name in "$@"; do
        pf_require_command "$command_name"
    done
}

# ----------------------------------------------------------------
# Validación de archivos y directorios
# ----------------------------------------------------------------

pf_require_file() {
    local file_path="${1:-}"
    local description="${2:-El archivo}"

    if [[ -z "$file_path" ]]; then
        pf_die "No se indicó la ruta del archivo que se debe validar."
    fi

    if [[ ! -f "$file_path" ]]; then
        pf_die "$description no existe: $file_path"
    fi
}

pf_require_nonempty_file() {
    local file_path="${1:-}"
    local description="${2:-El archivo}"

    if [[ -z "$file_path" ]]; then
        pf_die "No se indicó la ruta del archivo que se debe validar."
    fi

    if [[ ! -s "$file_path" ]]; then
        pf_die "$description no existe o está vacío: $file_path"
    fi
}

pf_require_directory() {
    local directory_path="${1:-}"
    local description="${2:-El directorio}"

    if [[ -z "$directory_path" ]]; then
        pf_die "No se indicó la ruta del directorio que se debe validar."
    fi

    if [[ ! -d "$directory_path" ]]; then
        pf_die "$description no existe: $directory_path"
    fi
}

pf_require_executable() {
    local file_path="${1:-}"
    local description="${2:-El ejecutable}"

    if [[ -z "$file_path" ]]; then
        pf_die "No se indicó la ruta del ejecutable que se debe validar."
    fi

    if [[ ! -x "$file_path" ]]; then
        pf_die "$description no existe o no tiene permisos de ejecución: $file_path"
    fi
}

pf_require_json() {
    local file_path="${1:-}"
    local description="${2:-El archivo JSON}"

    if [[ -z "$file_path" ]]; then
        pf_die "No se indicó la ruta del JSON que se debe validar."
    fi

    pf_require_nonempty_file "$file_path" "$description"
    pf_require_command jq

    if ! jq empty "$file_path" >/dev/null 2>&1; then
        pf_die "$description contiene un JSON inválido: $file_path"
    fi
}