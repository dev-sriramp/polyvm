#!/usr/bin/env bash
# polyvm core: paths, logging, guards.
# Targets bash 3.2 so it runs on stock macOS. No associative arrays,
# no ${var^^}, no mapfile.

# The single source of truth is the VERSION file, so cutting a release is one
# edit and one tag. The literal is the fallback for an odd install layout.
# shellcheck disable=SC2034  # read by bin/polyvm after sourcing
POLYVM_VERSION="0.1.0"
if [ -n "${POLYVM_DIR:-}" ] && [ -r "${POLYVM_DIR}/VERSION" ]; then
  POLYVM_VERSION="$(tr -d '[:space:]' < "${POLYVM_DIR}/VERSION")"
elif [ -r "$( dirname "${BASH_SOURCE[0]}" )/../VERSION" ]; then
  POLYVM_VERSION="$(tr -d '[:space:]' < "$( dirname "${BASH_SOURCE[0]}" )/../VERSION")"
fi

# POLYVM_DIR   where the polyvm source lives (bin/, lib/, polyvm.sh)
# POLYVM_DATA_DIR  where user data lives (plugins/, installs/, shims/)
# They default to the same directory but can be split for packaging.
polyvm_init_paths() {
  if [ -z "${POLYVM_DIR:-}" ]; then
    POLYVM_DIR="${HOME}/.polyvm"
  fi
  if [ -z "${POLYVM_DATA_DIR:-}" ]; then
    POLYVM_DATA_DIR="$POLYVM_DIR"
  fi
  export POLYVM_DIR POLYVM_DATA_DIR

  POLYVM_PLUGIN_DIR="${POLYVM_DATA_DIR}/plugins"
  POLYVM_INSTALL_DIR="${POLYVM_DATA_DIR}/installs"
  POLYVM_DOWNLOAD_DIR="${POLYVM_DATA_DIR}/downloads"
  POLYVM_SHIM_DIR="${POLYVM_DATA_DIR}/shims"
  POLYVM_TMP_DIR="${POLYVM_DATA_DIR}/tmp"
  POLYVM_GLOBAL_VERSIONS_FILE="${POLYVM_DATA_DIR}/versions"
  # Overridable, so an air-gapped or mirrored setup can point at its own clone
  # of the plugin index instead of reaching GitHub.
  if [ -z "${POLYVM_PLUGIN_INDEX_DIR:-}" ]; then
    POLYVM_PLUGIN_INDEX_DIR="${POLYVM_DATA_DIR}/plugin-index"
  fi
  POLYVM_COMPAT_DIR="${POLYVM_DATA_DIR}/compat"
  if [ -z "${POLYVM_BUILTIN_PLUGIN_DIR:-}" ]; then
    POLYVM_BUILTIN_PLUGIN_DIR="${POLYVM_DIR}/contrib/plugins"
  fi
  export POLYVM_PLUGIN_DIR POLYVM_INSTALL_DIR POLYVM_DOWNLOAD_DIR \
    POLYVM_SHIM_DIR POLYVM_TMP_DIR POLYVM_GLOBAL_VERSIONS_FILE \
    POLYVM_PLUGIN_INDEX_DIR POLYVM_COMPAT_DIR POLYVM_BUILTIN_PLUGIN_DIR
}

polyvm_ensure_dirs() {
  mkdir -p \
    "$POLYVM_PLUGIN_DIR" \
    "$POLYVM_INSTALL_DIR" \
    "$POLYVM_DOWNLOAD_DIR" \
    "$POLYVM_SHIM_DIR" \
    "$POLYVM_TMP_DIR" \
    "$POLYVM_COMPAT_DIR"
}

# ---------------------------------------------------------------- output

polyvm_init_colors() {
  POLYVM_C_RESET=""
  POLYVM_C_RED=""
  POLYVM_C_YELLOW=""
  POLYVM_C_GREEN=""
  POLYVM_C_BLUE=""
  POLYVM_C_DIM=""
  if [ -n "${NO_COLOR:-}" ]; then return 0; fi
  if [ "${POLYVM_COLOR:-auto}" = "never" ]; then return 0; fi
  if [ "${POLYVM_COLOR:-auto}" = "always" ] || [ -t 2 ]; then
    POLYVM_C_RESET=$'\033[0m'
    POLYVM_C_RED=$'\033[31m'
    POLYVM_C_YELLOW=$'\033[33m'
    POLYVM_C_GREEN=$'\033[32m'
    POLYVM_C_BLUE=$'\033[34m'
    POLYVM_C_DIM=$'\033[2m'
  fi
}

polyvm_info() {
  printf '%s\n' "$*" >&2
}

polyvm_step() {
  printf '%s==>%s %s\n' "$POLYVM_C_BLUE" "$POLYVM_C_RESET" "$*" >&2
}

polyvm_ok() {
  printf '%sok%s %s\n' "$POLYVM_C_GREEN" "$POLYVM_C_RESET" "$*" >&2
}

polyvm_warn() {
  printf '%swarning:%s %s\n' "$POLYVM_C_YELLOW" "$POLYVM_C_RESET" "$*" >&2
}

polyvm_err() {
  printf '%serror:%s %s\n' "$POLYVM_C_RED" "$POLYVM_C_RESET" "$*" >&2
}

polyvm_die() {
  polyvm_err "$*"
  exit 1
}

polyvm_debug() {
  [ -n "${POLYVM_DEBUG:-}" ] || return 0
  printf '%sdebug:%s %s\n' "$POLYVM_C_DIM" "$POLYVM_C_RESET" "$*" >&2
}

# ---------------------------------------------------------------- guards

# Plugin names become directory names and env var fragments. Keep them tight.
polyvm_validate_plugin_name() {
  local name="$1"
  case "$name" in
    "" ) polyvm_die "plugin name is empty" ;;
    *[!a-zA-Z0-9_.-]* ) polyvm_die "invalid plugin name: $name (allowed: letters, digits, . _ -)" ;;
    .|..|-* ) polyvm_die "invalid plugin name: $name" ;;
  esac
}

polyvm_validate_version_string() {
  local version="$1"
  case "$version" in
    "" ) polyvm_die "version is empty" ;;
    */*|*..*) polyvm_die "invalid version: $version" ;;
  esac
}

polyvm_plugin_path() {
  printf '%s\n' "${POLYVM_PLUGIN_DIR}/$1"
}

polyvm_plugin_installed() {
  [ -d "$(polyvm_plugin_path "$1")" ]
}

polyvm_require_plugin() {
  polyvm_validate_plugin_name "$1"
  if ! polyvm_plugin_installed "$1"; then
    polyvm_die "plugin '$1' is not installed. Run: polyvm plugin add $1"
  fi
}

polyvm_install_path() {
  # $1 plugin, $2 version
  printf '%s\n' "${POLYVM_INSTALL_DIR}/$1/$2"
}

polyvm_version_installed() {
  [ -d "$(polyvm_install_path "$1" "$2")" ]
}

# Uppercase without bash 4 parameter expansion.
polyvm_upcase() {
  printf '%s\n' "$1" | tr '[:lower:]' '[:upper:]'
}

# Env var fragment for a plugin: node-js -> NODE_JS
polyvm_env_name() {
  polyvm_upcase "$1" | tr '.-' '__'
}
