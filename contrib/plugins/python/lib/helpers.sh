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

# Missing headers are the single most common reason a Python build fails, and
# the linker error it produces says nothing useful. Check first and name the
# exact command that fixes it.
check_build_deps() {
  local os missing=""
  os="$(plugin_os)"

  has make || missing="$missing make"
  has cc || has gcc || has clang || missing="$missing a C compiler"

  case "$os" in
    darwin)
      if ! xcode-select -p >/dev/null 2>&1; then
        die "the Xcode command line tools are required to build Python.
  Install them with:
    xcode-select --install"
      fi
      if [ -n "$missing" ]; then
        die "missing build tools:$missing
  Install the Xcode command line tools with:
    xcode-select --install"
      fi
      if ! has brew; then
        warn "Homebrew was not found. Python will build, but modules that need
         openssl, readline, sqlite, xz or tk may be skipped. Installing them helps:
           brew install openssl@3 readline sqlite3 xz zlib tcl-tk"
      fi
      ;;
    linux)
      local header
      for header in zlib.h openssl/ssl.h bzlib.h ffi.h sqlite3.h; do
        if ! find_header "$header"; then
          missing="$missing $header"
        fi
      done
      if [ -n "$missing" ]; then
        warn "these build dependencies look missing:$missing
         Python may build without some standard library modules. Install them with:
           Debian/Ubuntu: sudo apt-get install -y build-essential zlib1g-dev libssl-dev \\
                            libbz2-dev libffi-dev libsqlite3-dev libreadline-dev \\
                            liblzma-dev libncursesw5-dev tk-dev uuid-dev
           Fedora/RHEL:   sudo dnf install -y gcc make zlib-devel openssl-devel bzip2-devel \\
                            libffi-devel sqlite-devel readline-devel xz-devel \\
                            ncurses-devel tk-devel libuuid-devel
           Alpine:        sudo apk add build-base zlib-dev openssl-dev bzip2-dev libffi-dev \\
                            sqlite-dev readline-dev xz-dev ncurses-dev tk-dev util-linux-dev"
      fi
      ;;
    windows)
      die "building Python from source is not supported on Windows yet.
  See docs/windows.md for where the port stands."
      ;;
  esac
}

find_header() {
  local header="$1" dir
  for dir in /usr/include /usr/local/include /usr/include/x86_64-linux-gnu \
             /usr/include/aarch64-linux-gnu; do
    [ -f "${dir}/${header}" ] && return 0
  done
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
