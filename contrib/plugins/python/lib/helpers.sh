#!/usr/bin/env bash
# Shared helpers for the bundled polyvm Python plugin.
#
# Python is compiled from source, the same way pyenv does it, using
# python-build from the pyenv repository. python-build carries a build recipe
# for every CPython, PyPy, GraalPy, Anaconda and Miniconda release, which is
# why pyenv can install anything; polyvm reuses it rather than reinventing it.

set -uo pipefail

# The pyenv checkout lives in the data dir, not the plugin dir, so refreshing
# the plugin does not throw away a 1000-recipe clone.
POLYVM_CACHE_DIR="${POLYVM_DATA_DIR:-${POLYVM_DIR:-$HOME/.polyvm}}/cache"
PYENV_DIR="${POLYVM_CACHE_DIR}/python-build/pyenv"
PYENV_SYNC_MARKER="${PYENV_DIR}/.polyvm-synced"
PYTHON_BUILD_DIR="${PYENV_DIR}/plugins/python-build"
PYTHON_BUILD_BIN="${PYTHON_BUILD_DIR}/bin/python-build"
PYTHON_BUILD_DEFINITIONS="${PYTHON_BUILD_DIR}/share/python-build"
PYENV_REPO="${POLYVM_PYENV_REPO:-https://github.com/pyenv/pyenv.git}"

msg()  { printf '%s\n' "$*" >&2; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

has() { command -v "$1" >/dev/null 2>&1; }

plugin_os() {
  case "$(uname -s)" in
    Linux) printf 'linux\n' ;;
    Darwin) printf 'darwin\n' ;;
    MINGW*|MSYS*|CYGWIN*) printf 'windows\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

# --------------------------------------------------------- python-build

ensure_python_build() {
  if [ -x "$PYTHON_BUILD_BIN" ]; then
    return 0
  fi
  msg "==> fetching python-build (the builder pyenv uses)"
  rm -rf "$PYENV_DIR"
  mkdir -p "$(dirname "$PYENV_DIR")"
  git clone --quiet --depth 1 "$PYENV_REPO" "$PYENV_DIR" \
    || die "could not clone $PYENV_REPO"
  [ -x "$PYTHON_BUILD_BIN" ] \
    || die "the pyenv checkout has no python-build at $PYTHON_BUILD_BIN"
  touch "$PYENV_SYNC_MARKER" 2>/dev/null || true
}

# True when the recipes were refreshed within the last day.
python_build_is_fresh() {
  [ -f "$PYENV_SYNC_MARKER" ] || return 1
  [ -n "$(find "$PYENV_SYNC_MARKER" -mtime -1 2>/dev/null)" ]
}

update_python_build() {
  if [ ! -d "${PYENV_DIR}/.git" ]; then
    ensure_python_build
    return 0
  fi
  msg "==> updating python-build"
  ( cd "$PYENV_DIR" \
    && git fetch --quiet --depth 1 origin HEAD \
    && git reset --quiet --hard FETCH_HEAD ) \
    || warn "could not update python-build, using the copy already on disk"
  touch "$PYENV_SYNC_MARKER" 2>/dev/null || true
}

definition_file() {
  printf '%s\n' "${PYTHON_BUILD_DEFINITIONS}/$1"
}

definition_exists() {
  [ -f "$(definition_file "$1")" ]
}

# Fetch new release recipes when a version is not known yet.
ensure_definition() {
  local version="$1"
  ensure_python_build
  definition_exists "$version" && return 0
  msg "==> ${version} is not in the local recipes, refreshing them"
  update_python_build
  definition_exists "$version" && return 0
  return 1
}

# Every installable version, oldest first.
list_definitions() {
  ensure_python_build
  local entry name
  for entry in "$PYTHON_BUILD_DEFINITIONS"/*; do
    [ -f "$entry" ] || continue
    name="$(basename "$entry")"
    printf '%s\n' "$name"
  done | sort_versions
}

# Sort versions oldest first, with prereleases ahead of the release they lead
# to, so 3.13.0rc1 comes before 3.13.0.
#
# This deliberately avoids `sort -V`, which is a GNU extension that older BSD
# and macOS sort implementations do not have. Instead it builds an explicit
# sort key and uses a plain lexicographic sort, which every sort can do:
#
#   1. a prerelease marker right after a digit or dash gets a "!" in front.
#      "!" is below every digit and letter in ASCII, so 3.13.0!rc1 sorts
#      before 3.13.0.
#   2. every run of digits is zero padded to 8 places, so 9 sorts before 10.
#   3. a trailing "~" is appended. "~" is above "!", which is what makes a
#      bare release sort after its own release candidates.
sort_versions() {
  awk '
    {
      original = $0
      key = $0

      # 1. mark prereleases
      out = ""
      rest = key
      while (match(rest, /[0-9-](rc|alpha|beta|dev|pre|a|b)/)) {
        out = out substr(rest, 1, RSTART) "!"
        rest = substr(rest, RSTART + 1)
      }
      key = out rest

      # 2. zero pad every run of digits
      out = ""
      rest = key
      while (match(rest, /[0-9]+/)) {
        out = out substr(rest, 1, RSTART - 1) sprintf("%08d", substr(rest, RSTART, RLENGTH) + 0)
        rest = substr(rest, RSTART + RLENGTH)
      }
      key = out rest

      # 3. terminator
      printf "%s~\t%s\n", key, original
    }
  ' | LC_ALL=C sort | cut -f2-
}

# Plain CPython releases only: 3.13.1 yes, 3.13.0rc1 no, pypy3.10-7.3.17 no.
stable_cpython_versions() {
  list_definitions | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$'
}

# ------------------------------------------------- source tarball for a version

# Print "url<TAB>sha256" for the CPython tarball a definition downloads.
# Prefers .tar.xz, which is what python-build uses wherever tar supports it.
definition_source_url() {
  local version="$1" file
  file="$(definition_file "$version")"
  [ -f "$file" ] || return 1

  local line
  line="$(grep -oE '"https://[^"]*Python-[^"]*\.tar\.xz#[a-f0-9]{64}"' "$file" | head -n1)"
  if [ -z "$line" ]; then
    line="$(grep -oE '"https://[^"]*\.(tar\.gz|tgz|tar\.bz2)#[a-f0-9]{64}"' "$file" | head -n1)"
  fi
  [ -n "$line" ] || return 1

  line="${line%\"}"
  line="${line#\"}"
  printf '%s\t%s\n' "${line%%#*}" "${line##*#}"
}

sha256_of() {
  if has sha256sum; then
    sha256sum "$1" | awk '{print $1}'
  elif has shasum; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    printf '\n'
  fi
}

# --------------------------------------------------------- build environment

# Build prerequisites are not this plugin's job any more. polyvm checks them
# for every language from contrib/requirements/python, so the same machinery
# serves Ruby, Erlang, PHP and the rest.
#
# What is left here is the one check only this plugin can make: whether the
# requested version is a thing that exists.

# Catch a version that does not exist before anyone installs a toolchain for it.
check_version_exists() {
  local version="$1"
  ensure_python_build
  definition_exists "$version" && return 0

  update_python_build >/dev/null 2>&1 || true
  definition_exists "$version" && return 0

  printf '\n' >&2
  printf 'error: there is no Python %s.\n\n' "$version" >&2

  local near
  near="$(list_definitions | grep -E "^${version}" | tail -n8 || true)"
  if [ -n "$near" ]; then
    printf '  Did you mean one of these?\n\n' >&2
    printf '%s\n' "$near" | sed 's/^/    /' >&2
    printf '\n' >&2
  fi
  printf '  See everything:  polyvm list-all python\n' >&2
  printf '  Newest stable:   polyvm install python latest\n' >&2
  return 1
}

# On macOS, point the build at Homebrew's libraries when they are installed.
# Without this, a Python built on a Mac often ends up with no ssl or readline.
setup_darwin_build_env() {
  [ "$(plugin_os)" = "darwin" ] || return 0
  has brew || return 0

  local formula prefix
  for formula in openssl@3 readline zlib xz bzip2 sqlite; do
    prefix="$(brew --prefix "$formula" 2>/dev/null || true)"
    if [ -z "$prefix" ] || [ ! -d "$prefix" ]; then continue; fi
    export LDFLAGS="-L${prefix}/lib ${LDFLAGS:-}"
    export CPPFLAGS="-I${prefix}/include ${CPPFLAGS:-}"
    if [ -d "${prefix}/lib/pkgconfig" ]; then
      export PKG_CONFIG_PATH="${prefix}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
    fi
  done

  # python-build reads this to configure --with-openssl.
  prefix="$(brew --prefix openssl@3 2>/dev/null || true)"
  if [ -n "$prefix" ] && [ -d "$prefix" ]; then
    export PYTHON_BUILD_CONFIGURE_WITH_OPENSSL=1
    export PYTHON_BUILD_OPENSSL_PREFIX="$prefix"
  fi
}
