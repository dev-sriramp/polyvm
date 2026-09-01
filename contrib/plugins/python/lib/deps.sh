#!/usr/bin/env bash
# Build prerequisite detection for the Python plugin.
#
# Compiling CPython needs a toolchain and a set of development headers. When
# they are missing you get one of two bad outcomes: configure dies with
# "no acceptable C compiler found", or, worse, the build succeeds and you get a
# Python with no ssl, so pip fails weeks later with an error that says nothing
# about the real cause.
#
# So this runs before anything is downloaded, probes by actually compiling
# rather than guessing at include paths, and prints one command to copy for the
# distribution you are actually on.

# header|apt|dnf|apk|pacman|zypper|what breaks without it
POLYVM_PY_REQUIRED_HEADERS='
zlib.h|zlib1g-dev|zlib-devel|zlib-dev|zlib|zlib-devel|the build fails outright
openssl/ssl.h|libssl-dev|openssl-devel|openssl-dev|openssl|libopenssl-devel|no ssl module, so pip cannot reach the network
ffi.h|libffi-dev|libffi-devel|libffi-dev|libffi|libffi-devel|no ctypes module
'

POLYVM_PY_RECOMMENDED_HEADERS='
bzlib.h|libbz2-dev|bzip2-devel|bzip2-dev|bzip2|libbz2-devel|no bz2 module
sqlite3.h|libsqlite3-dev|sqlite-devel|sqlite-dev|sqlite|sqlite3-devel|no sqlite3 module
readline/readline.h|libreadline-dev|readline-devel|readline-dev|readline|readline-devel|no history or editing in the REPL
lzma.h|liblzma-dev|xz-devel|xz-dev|xz|xz-devel|no lzma module
ncurses.h|libncursesw5-dev|ncurses-devel|ncurses-dev|ncurses|ncurses-devel|no curses module
uuid/uuid.h|uuid-dev|libuuid-devel|util-linux-dev|util-linux|libuuid-devel|no uuid module
tk.h|tk-dev|tk-devel|tk-dev|tk|tk-devel|no tkinter, so IDLE and turtle will not run
'

# Which package manager is in charge here, and which column of the tables to
# read for it.
detect_pkg_manager() {
  if has apt-get; then printf 'apt\n'
  elif has dnf; then printf 'dnf\n'
  elif has yum; then printf 'yum\n'
  elif has apk; then printf 'apk\n'
  elif has pacman; then printf 'pacman\n'
  elif has zypper; then printf 'zypper\n'
  elif has brew; then printf 'brew\n'
  else printf 'unknown\n'
  fi
}

pkg_field_for() {
  case "$1" in
    apt) printf '2\n' ;;
    dnf|yum) printf '3\n' ;;
    apk) printf '4\n' ;;
    pacman) printf '5\n' ;;
    zypper) printf '6\n' ;;
    *) printf '2\n' ;;
  esac
}

install_command_for() {
  case "$1" in
    apt) printf 'sudo apt-get update && sudo apt-get install -y\n' ;;
    dnf) printf 'sudo dnf install -y\n' ;;
    yum) printf 'sudo yum install -y\n' ;;
    apk) printf 'sudo apk add --no-cache\n' ;;
    pacman) printf 'sudo pacman -S --needed\n' ;;
    zypper) printf 'sudo zypper install -y\n' ;;
    brew) printf 'brew install\n' ;;
    *) printf '' ;;
  esac
}

toolchain_package_for() {
  case "$1" in
    apt) printf 'build-essential\n' ;;
    dnf|yum) printf 'gcc make\n' ;;
    apk) printf 'build-base\n' ;;
    pacman) printf 'base-devel\n' ;;
    zypper) printf 'gcc make\n' ;;
    *) printf '' ;;
  esac
}

find_compiler() {
  local candidate
  for candidate in "${CC:-}" cc gcc clang; do
    [ -n "$candidate" ] || continue
    if has "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# Compile a one line program that includes the header. This is the only
# reliable test: include paths differ across Debian multiarch, musl, macOS SDKs
# and Homebrew prefixes, so scanning directories gets it wrong.
probe_header() {
  local header="$1" cc="$2" dir
  dir="$(mktemp -d 2>/dev/null)" || return 1
  printf '#include <%s>\nint main(void) { return 0; }\n' "$header" > "${dir}/probe.c"
  local ok=1
  # shellcheck disable=SC2086
  if "$cc" -fsyntax-only ${CPPFLAGS:-} "${dir}/probe.c" >/dev/null 2>&1; then
    ok=0
  fi
  rm -rf "$dir"
  return $ok
}

# Run every check. Returns 0 when Python can be built, 1 when it cannot.
python_preflight() {
  local os pm field cc
  os="$(plugin_os)"
  pm="$(detect_pkg_manager)"
  field="$(pkg_field_for "$pm")"

  if [ "$os" = "windows" ]; then
    die "building Python from source is not supported on Windows yet.
  Use WSL, where polyvm is fully supported. See docs/windows.md."
  fi

  msg "==> checking the build prerequisites for Python"

  # --- toolchain ---------------------------------------------------------
  local missing_tools=""
  cc="$(find_compiler || true)"
  [ -n "$cc" ] || missing_tools="a C compiler"
  if ! has make; then
    [ -n "$missing_tools" ] && missing_tools="${missing_tools} and make" || missing_tools="make"
  fi

  if [ "$os" = "darwin" ] && [ -z "$cc" ]; then
    printf '\n' >&2
    die "Python needs a C compiler and the macOS command line tools are not installed.

  Install them, which takes a few minutes:

    xcode-select --install

  Then run this again."
  fi

  if [ -n "$missing_tools" ]; then
    local cmd toolchain
    cmd="$(install_command_for "$pm")"
    toolchain="$(toolchain_package_for "$pm")"
    printf '\n' >&2
    if [ -n "$cmd" ] && [ -n "$toolchain" ]; then
      die "Python is compiled from source, and this machine is missing ${missing_tools}.

  Install the toolchain:

    ${cmd} ${toolchain}

  Then run this again. Nothing was downloaded."
    fi
    die "Python is compiled from source, and this machine is missing ${missing_tools}.
  Install a C compiler and make, then run this again. Nothing was downloaded."
  fi

  # --- headers -----------------------------------------------------------
  local line header pkg why
  local missing_required="" missing_required_pkgs=""
  local missing_recommended="" missing_recommended_pkgs=""

  # Read line by line. `for line in $table` would split on the spaces inside
  # the description column and turn every word into its own package name.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    header="$(printf '%s' "$line" | cut -d'|' -f1)"
    pkg="$(printf '%s' "$line" | cut -d'|' -f"$field")"
    why="$(printf '%s' "$line" | cut -d'|' -f7)"
    probe_header "$header" "$cc" && continue
    missing_required="${missing_required}    ${pkg}
        ${why}
"
    missing_required_pkgs="$missing_required_pkgs $pkg"
  done <<REQUIRED
$POLYVM_PY_REQUIRED_HEADERS
REQUIRED

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    header="$(printf '%s' "$line" | cut -d'|' -f1)"
    pkg="$(printf '%s' "$line" | cut -d'|' -f"$field")"
    why="$(printf '%s' "$line" | cut -d'|' -f7)"
    probe_header "$header" "$cc" && continue
    missing_recommended="${missing_recommended}    ${pkg}
        ${why}
"
    missing_recommended_pkgs="$missing_recommended_pkgs $pkg"
  done <<RECOMMENDED
$POLYVM_PY_RECOMMENDED_HEADERS
RECOMMENDED

  # macOS gets its libraries from Homebrew, and the headers are not on the
  # default include path until the build is pointed at them, which
  # setup_darwin_build_env does. Report rather than block.
  if [ "$os" = "darwin" ]; then
    if [ -n "$missing_required" ] || [ -n "$missing_recommended" ]; then
      if has brew; then
        warn "some libraries were not found on the default include path.
         If the finished Python is missing a module, install these and rebuild:
           brew install openssl@3 readline sqlite3 xz zlib tcl-tk"
      else
        warn "Homebrew was not found. Python will build, but is likely to end up
         without ssl, readline or sqlite3. Install Homebrew first:
           https://brew.sh"
      fi
    fi
    msg "==> toolchain ok (${cc})"
    return 0
  fi

  local cmd
  cmd="$(install_command_for "$pm")"

  if [ -n "$missing_required" ]; then
    printf '\n' >&2
    printf 'error: Python cannot be built here. These are required and missing:\n\n' >&2
    printf '%s' "$missing_required" >&2
    if [ -n "$missing_recommended" ]; then
      printf '\n  These are optional. Without them Python still builds, but with pieces\n' >&2
      printf '  of the standard library missing:\n\n' >&2
      printf '%s' "$missing_recommended" >&2
    fi
    printf '\n' >&2
    if [ -n "$cmd" ]; then
      printf '  Install everything at once:\n\n' >&2
      printf '    %s%s%s\n\n' "$cmd" "$missing_required_pkgs" "$missing_recommended_pkgs" >&2
    else
      printf '  Install the development packages for those headers, then try again.\n\n' >&2
    fi
    printf '  Nothing was downloaded.\n' >&2
    return 1
  fi

  if [ -n "$missing_recommended" ]; then
    printf '\n' >&2
    warn "Python will build, but these are missing and parts of the standard
         library will be left out:"
    printf '%s' "$missing_recommended" >&2
    if [ -n "$cmd" ]; then
      printf '\n  Install them first if you want a complete Python:\n\n' >&2
      printf '    %s%s\n\n' "$cmd" "$missing_recommended_pkgs" >&2
    fi
    printf '  Continuing in 5 seconds. Press Ctrl-C to stop.\n' >&2
    [ -n "${POLYVM_YES:-}" ] || [ ! -t 0 ] || sleep 5
  fi

  msg "==> prerequisites ok (${cc})"
  return 0
}
