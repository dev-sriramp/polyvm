#!/usr/bin/env bash
# polyvm util: platform detection, downloads, checksums, temp handling.

polyvm_has() {
  command -v "$1" >/dev/null 2>&1
}

# linux | darwin | windows
#
# "windows" covers the POSIX layers polyvm can run under there: Git Bash,
# MSYS2 and Cygwin. WSL reports Linux, correctly, since it is Linux.
polyvm_os() {
  local os
  os="$(uname -s)"
  case "$os" in
    Linux) printf 'linux\n' ;;
    Darwin) printf 'darwin\n' ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT) printf 'windows\n' ;;
    *) printf '%s\n' "$(printf '%s' "$os" | tr '[:upper:]' '[:lower:]')" ;;
  esac
}

polyvm_is_windows() {
  [ "$(polyvm_os)" = "windows" ]
}

# Platforms polyvm is supported on today. Windows is a work in progress; see
# docs/windows.md. Everything platform-specific goes through these helpers so
# the port stays additive.
polyvm_platform_supported() {
  case "$(polyvm_os)" in
    linux|darwin) return 0 ;;
    *) return 1 ;;
  esac
}

# Suffix an executable carries on this platform.
polyvm_exe_suffix() {
  if polyvm_is_windows; then printf '.exe\n'; else printf '\n'; fi
}

# Separator between entries in a PATH-style list.
polyvm_path_list_sep() {
  printf ':\n'
}

# Does this file count as a runnable program here? On Windows filesystems the
# executable bit is unreliable, so fall back to the extension.
polyvm_is_executable() {
  local file="$1"
  [ -f "$file" ] || return 1
  if [ -x "$file" ]; then
    return 0
  fi
  if polyvm_is_windows; then
    case "$file" in
      *.exe|*.EXE|*.cmd|*.CMD|*.bat|*.BAT|*.com|*.COM) return 0 ;;
    esac
  fi
  return 1
}

# Command name a shim should be created under, with any Windows suffix removed
# so `python.exe` is reachable as `python`.
polyvm_shim_name() {
  local name="$1"
  if polyvm_is_windows; then
    case "$name" in
      *.exe|*.EXE|*.cmd|*.CMD|*.bat|*.BAT|*.com|*.COM) name="${name%.*}" ;;
    esac
  fi
  printf '%s\n' "$name"
}

# amd64 | arm64 | 386 | armv7
polyvm_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) printf 'amd64\n' ;;
    aarch64|arm64) printf 'arm64\n' ;;
    i386|i686) printf '386\n' ;;
    armv7*) printf 'armv7\n' ;;
    *) printf '%s\n' "$arch" ;;
  esac
}

# Number of CPUs, used for ASDF_CONCURRENCY.
polyvm_cpu_count() {
  local n=""
  if polyvm_has nproc; then
    n="$(nproc 2>/dev/null || true)"
  elif polyvm_has sysctl; then
    n="$(sysctl -n hw.ncpu 2>/dev/null || true)"
  fi
  case "$n" in
    ''|*[!0-9]*) printf '1\n' ;;
    *) printf '%s\n' "$n" ;;
  esac
}

polyvm_mktemp_dir() {
  local template="${POLYVM_TMP_DIR}/polyvm.XXXXXX"
  mkdir -p "$POLYVM_TMP_DIR"
  # BSD mktemp needs -t or an explicit template with -d; this form works on both.
  mktemp -d "$template" 2>/dev/null || {
    local d="${POLYVM_TMP_DIR}/polyvm.$$.$RANDOM"
    mkdir -p "$d" && printf '%s\n' "$d"
  }
}

# polyvm_download <url> <dest>
polyvm_download() {
  local url="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if polyvm_has curl; then
    curl --fail --silent --show-error --location --retry 3 \
      --connect-timeout 20 -o "$dest" "$url"
  elif polyvm_has wget; then
    wget --quiet --tries=3 --timeout=20 -O "$dest" "$url"
  else
    polyvm_die "neither curl nor wget is available"
  fi
}

# polyvm_fetch <url>  -> stdout
polyvm_fetch() {
  local url="$1"
  if polyvm_has curl; then
    curl --fail --silent --show-error --location --retry 3 --connect-timeout 20 "$url"
  elif polyvm_has wget; then
    wget --quiet --tries=3 --timeout=20 -O- "$url"
  else
    polyvm_die "neither curl nor wget is available"
  fi
}

polyvm_sha256() {
  local file="$1"
  if polyvm_has sha256sum; then
    sha256sum "$file" | awk '{print $1}'
  elif polyvm_has shasum; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    polyvm_die "neither sha256sum nor shasum is available"
  fi
}

# polyvm_verify_sha256 <file> <expected>
polyvm_verify_sha256() {
  local actual
  actual="$(polyvm_sha256 "$1")"
  if [ "$actual" != "$2" ]; then
    polyvm_die "checksum mismatch for $1
  expected $2
  actual   $actual"
  fi
}

# Strip leading/trailing whitespace from stdin.
polyvm_trim() {
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# Absolute path of a directory that already exists, without realpath(1),
# which is missing on stock macOS.
polyvm_abs_dir() {
  local dir="$1"
  ( cd "$dir" 2>/dev/null && pwd -P )
}

# Is $1 a directory that exists and contains at least one entry
polyvm_dir_has_entries() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  local entry
  for entry in "$dir"/* "$dir"/.[!.]*; do
    [ -e "$entry" ] && return 0
  done
  return 1
}

# Remove a directory tree, refusing paths outside POLYVM_DATA_DIR.
polyvm_safe_rm_rf() {
  local target="$1"
  case "$target" in
    "$POLYVM_DATA_DIR"/*) : ;;
    *) polyvm_die "refusing to remove path outside polyvm data dir: $target" ;;
  esac
  case "$target" in
    *..*) polyvm_die "refusing to remove path containing ..: $target" ;;
  esac
  rm -rf "$target"
}

# Terminal width, without tput, which is missing on minimal images.
polyvm_term_width() {
  local cols="${COLUMNS:-}"
  if [ -z "$cols" ] && [ -t 1 ]; then
    cols="$(stty size 2>/dev/null | awk '{print $2}')"
  fi
  case "$cols" in
    ''|*[!0-9]*) cols=80 ;;
  esac
  [ "$cols" -lt 40 ] && cols=40
  printf '%s\n' "$cols"
}

# Lay stdin out in columns, down then across, like ls.
#
# Only ever called when stdout is a terminal. Piped output stays one item per
# line so `polyvm list-all python | grep 3.13` keeps working.
polyvm_columnate() {
  local width
  width="$(polyvm_term_width)"
  awk -v total="$width" '
    { items[n++] = $0; if (length($0) > w) w = length($0) }
    END {
      if (n == 0) exit
      w += 2
      cols = int(total / w)
      if (cols < 1) cols = 1
      rows = int((n + cols - 1) / cols)
      for (r = 0; r < rows; r++) {
        line = ""
        for (c = 0; c < cols; c++) {
          i = c * rows + r
          if (i < n) line = line sprintf("%-*s", w, items[i])
        }
        sub(/[ ]+$/, "", line)
        print line
      }
    }
  '
}

# Print a list, in columns when a human is reading it.
polyvm_print_list() {
  if [ -t 1 ]; then
    polyvm_columnate
  else
    cat
  fi
}

# Confirm prompt. Returns 0 on yes. Auto-yes when POLYVM_YES is set or
# stdin is not a terminal (non-interactive install scripts).
polyvm_confirm() {
  local prompt="$1"
  if [ -n "${POLYVM_YES:-}" ] || [ ! -t 0 ]; then
    return 0
  fi
  local reply=""
  printf '%s [y/N] ' "$prompt" >&2
  read -r reply
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}
