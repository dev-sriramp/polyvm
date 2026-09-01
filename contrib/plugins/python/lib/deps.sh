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

# macOS libraries come from Homebrew, whose headers are never on the default
# include path: the build is pointed at them by setup_darwin_build_env. So a
# header probe means nothing there, and the right question is whether the
# formula is installed.
#
# formula|required|what breaks without it
POLYVM_PY_BREW_FORMULAS='
openssl@3|yes|no ssl module, so pip cannot reach the network
readline|no|no history or editing in the REPL
sqlite|no|no sqlite3 module
xz|no|no lzma module
zlib|no|compression support may be incomplete
tcl-tk|no|no tkinter, so IDLE and turtle will not run
'

# Is this formula actually installed?
brew_formula_installed() {
  local prefix
  prefix="$(brew --prefix "$1" 2>/dev/null || true)"
  [ -n "$prefix" ] && [ -d "$prefix" ]
}

# Do we have a working compiler? On macOS /usr/bin/cc exists even with no
# command line tools installed and fails the moment you use it, so the only
# honest test is to compile something.
darwin_toolchain_ok() {
  xcode-select -p >/dev/null 2>&1 || return 1
  local dir
  dir="$(mktemp -d 2>/dev/null)" || return 1
  printf 'int main(void) { return 0; }\n' > "${dir}/probe.c"
  local ok=1
  cc -fsyntax-only "${dir}/probe.c" >/dev/null 2>&1 && ok=0
  rm -rf "$dir"
  return $ok
}

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

# The refresh step, where the package manager needs one. Empty otherwise.
pkg_update_command() {
  case "$1" in
    apt) printf 'apt-get update\n' ;;
    *) printf '' ;;
  esac
}

pkg_install_command() {
  case "$1" in
    apt) printf 'apt-get install -y\n' ;;
    dnf) printf 'dnf install -y\n' ;;
    yum) printf 'yum install -y\n' ;;
    apk) printf 'apk add --no-cache\n' ;;
    pacman) printf 'pacman -S --needed --noconfirm\n' ;;
    zypper) printf 'zypper install -y\n' ;;
    brew) printf 'brew install\n' ;;
    *) printf '' ;;
  esac
}

# "" when already root or using Homebrew, "sudo " when we need and have it.
# Returns 1 when the packages cannot be installed from here at all.
privilege_prefix() {
  local pm="$1"
  [ "$pm" = "brew" ] && { printf ''; return 0; }
  if [ "$(id -u 2>/dev/null || echo 1)" = "0" ]; then
    printf ''
    return 0
  fi
  if has sudo; then
    printf 'sudo '
    return 0
  fi
  return 1
}

# The command a person would type, for display and for running.
full_install_command() {
  local pm="$1" prefix="$2" packages="$3"
  local update install
  update="$(pkg_update_command "$pm")"
  install="$(pkg_install_command "$pm")"
  [ -n "$install" ] || return 1
  if [ -n "$update" ]; then
    printf '%s%s && %s%s%s\n' "$prefix" "$update" "$prefix" "$install" "$packages"
  else
    printf '%s%s%s\n' "$prefix" "$install" "$packages"
  fi
}

# Ask, unless told otherwise. Reads from the terminal directly, so it still
# works when polyvm's stdin is a pipe. Returns 1 when we must not or cannot ask.
#
#   POLYVM_INSTALL_DEPS=yes   install without asking, for Dockerfiles and CI
#   POLYVM_INSTALL_DEPS=no    never install, just report
#   unset or "ask"            prompt when there is a terminal, report otherwise
confirm_install() {
  local prompt="$1" reply=""
  case "${POLYVM_INSTALL_DEPS:-ask}" in
    yes|true|1) return 0 ;;
    no|false|0) return 1 ;;
  esac
  # Never prompt where nobody can answer. A build that hangs waiting for input
  # in CI is worse than one that fails with instructions.
  if [ ! -t 0 ] && [ ! -t 1 ]; then
    return 1
  fi

  # Read from the terminal rather than stdin, so this still works when polyvm
  # itself was piped something.
  if [ -e /dev/tty ] && { : > /dev/tty; } 2>/dev/null; then
    printf '%s [Y/n] ' "$prompt" > /dev/tty
    IFS= read -r reply < /dev/tty 2>/dev/null || return 1
  elif [ -t 0 ]; then
    printf '%s [Y/n] ' "$prompt" >&2
    IFS= read -r reply || return 1
  else
    return 1
  fi
  case "$reply" in
    ""|y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

run_install() {
  local pm="$1" prefix="$2" packages="$3"
  local update install
  update="$(pkg_update_command "$pm")"
  install="$(pkg_install_command "$pm")"

  if [ -n "$update" ]; then
    msg "==> ${prefix}${update}"
    # shellcheck disable=SC2086
    ${prefix}${update} || warn "the package list refresh failed, continuing anyway"
  fi
  msg "==> ${prefix}${install}${packages}"
  # shellcheck disable=SC2086
  ${prefix}${install}${packages}
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

# Collect what is missing. Sets:
#   PY_MISSING_TOOLCHAIN     packages providing a compiler and make
#   PY_MISSING_REQUIRED      packages without which the build fails or ssl is lost
#   PY_MISSING_RECOMMENDED   packages whose absence costs a stdlib module
#   PY_MISSING_REPORT        human readable list, indented
#   PY_CC                    the compiler found, empty when there is none
collect_missing() {
  local pm="$1" field
  field="$(pkg_field_for "$pm")"

  PY_CC="$(find_compiler || true)"
  PY_MISSING_TOOLCHAIN=""
  PY_MISSING_REQUIRED=""
  PY_MISSING_RECOMMENDED=""
  PY_MISSING_REPORT=""

  local tools=""
  [ -n "$PY_CC" ] || tools="a C compiler"
  if ! has make; then
    if [ -n "$tools" ]; then tools="${tools} and make"; else tools="make"; fi
  fi
  if [ -n "$tools" ]; then
    PY_MISSING_TOOLCHAIN=" $(toolchain_package_for "$pm")"
    PY_MISSING_REPORT="${PY_MISSING_REPORT}    $(toolchain_package_for "$pm")
        ${tools}, without which nothing can be compiled
"
  fi

  # Headers can only be probed once a compiler exists. When there is none, the
  # toolchain package pulls in the basics and the rest is checked on the retry.
  [ -n "$PY_CC" ] || return 0

  # On macOS the equivalent check is "is the Homebrew formula installed", done
  # in handle_darwin. Probing include paths here would report every library as
  # missing even when all of them are installed.
  [ "$(plugin_os)" = "darwin" ] && return 0

  local line header pkg why
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    header="$(printf '%s' "$line" | cut -d'|' -f1)"
    pkg="$(printf '%s' "$line" | cut -d'|' -f"$field")"
    why="$(printf '%s' "$line" | cut -d'|' -f7)"
    probe_header "$header" "$PY_CC" && continue
    PY_MISSING_REQUIRED="${PY_MISSING_REQUIRED} ${pkg}"
    PY_MISSING_REPORT="${PY_MISSING_REPORT}    ${pkg}
        ${why}
"
  done <<REQUIRED
$POLYVM_PY_REQUIRED_HEADERS
REQUIRED

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    header="$(printf '%s' "$line" | cut -d'|' -f1)"
    pkg="$(printf '%s' "$line" | cut -d'|' -f"$field")"
    why="$(printf '%s' "$line" | cut -d'|' -f7)"
    probe_header "$header" "$PY_CC" && continue
    PY_MISSING_RECOMMENDED="${PY_MISSING_RECOMMENDED} ${pkg}"
    PY_MISSING_REPORT="${PY_MISSING_REPORT}    ${pkg}
        ${why}
"
  done <<RECOMMENDED
$POLYVM_PY_RECOMMENDED_HEADERS
RECOMMENDED
}

# Everything Python needs, checked before a single byte is downloaded.
# Returns 0 when Python can be built here, 1 when it cannot.
python_preflight() {
  local os pm prefix
  os="$(plugin_os)"
  pm="$(detect_pkg_manager)"

  if [ "$os" = "windows" ]; then
    die "building Python from source is not supported on Windows yet.
  Use WSL, where polyvm is fully supported. See docs/windows.md."
  fi

  # A version that does not exist is worth catching before a toolchain install.
  if [ -n "${ASDF_INSTALL_VERSION:-}" ] && [ "${ASDF_INSTALL_TYPE:-version}" = "version" ]; then
    check_version_exists "$ASDF_INSTALL_VERSION" || return 1
  fi

  msg "==> checking the build prerequisites for Python"

  # macOS is a different problem: the toolchain comes from the command line
  # tools and the libraries from Homebrew, neither of which a header probe on
  # the default include path can see. It gets its own path rather than a
  # special case wedged inside the Linux one.
  if [ "$os" = "darwin" ]; then
    PY_CC="$(find_compiler || true)"
    handle_darwin
    return $?
  fi

  local attempt=1
  while [ "$attempt" -le 2 ]; do
    collect_missing "$pm"

    if [ -z "$PY_MISSING_TOOLCHAIN" ] && [ -z "$PY_MISSING_REQUIRED" ] \
       && [ -z "$PY_MISSING_RECOMMENDED" ]; then
      msg "==> prerequisites ok (${PY_CC})"
      return 0
    fi

    local packages
    packages="${PY_MISSING_TOOLCHAIN}${PY_MISSING_REQUIRED}${PY_MISSING_RECOMMENDED}"

    if ! prefix="$(privilege_prefix "$pm")"; then
      report_missing "$pm" "" "$packages"
      printf '  You are not root and sudo is not available, so polyvm cannot\n' >&2
      printf '  install these for you. Ask an administrator, or run polyvm as root.\n' >&2
      [ -n "$PY_MISSING_TOOLCHAIN" ] || [ -n "$PY_MISSING_REQUIRED" ] && return 1
      return 0
    fi

    local cmd
    if ! cmd="$(full_install_command "$pm" "$prefix" "$packages")"; then
      report_missing "$pm" "$prefix" "$packages"
      printf '  polyvm does not know the package manager here. Install the\n' >&2
      printf '  development packages for those, then run this again.\n' >&2
      [ -n "$PY_MISSING_TOOLCHAIN" ] || [ -n "$PY_MISSING_REQUIRED" ] && return 1
      return 0
    fi

    report_missing "$pm" "$prefix" "$packages"
    printf '\n  polyvm can install them with:\n\n    %s\n\n' "$cmd" >&2

    if [ "$attempt" -eq 2 ]; then
      printf '  Some packages are still missing after the install.\n' >&2
      [ -n "$PY_MISSING_TOOLCHAIN" ] || [ -n "$PY_MISSING_REQUIRED" ] && return 1
      return 0
    fi

    if confirm_install "  Install them now?"; then
      printf '\n' >&2
      if ! run_install "$pm" "$prefix" "$packages"; then
        warn "the package install did not finish cleanly"
      fi
      printf '\n' >&2
      msg "==> re-checking"
      attempt=$((attempt + 1))
      continue
    fi

    printf '\n  Not installing. Run that yourself when you are ready.\n' >&2
    printf '  Nothing was downloaded.\n' >&2
    [ -n "$PY_MISSING_TOOLCHAIN" ] || [ -n "$PY_MISSING_REQUIRED" ] && return 1
    return 0
  done

  return 1
}

# Print what is missing and why, once, before asking anything.
report_missing() {
  local pm="$1" prefix="$2" packages="$3"
  printf '\n' >&2
  if [ -n "$PY_MISSING_TOOLCHAIN" ] || [ -n "$PY_MISSING_REQUIRED" ]; then
    printf 'Python is compiled from source, and this machine is missing things it needs:\n\n' >&2
  else
    printf 'Python will build, but these are missing and parts of the standard\n' >&2
    printf 'library would be left out:\n\n' >&2
  fi
  printf '%s' "$PY_MISSING_REPORT" >&2
}

# macOS: check the command line tools and the Homebrew formulas, and offer to
# install what is missing, the same way the Linux path does.
handle_darwin() {
  if ! darwin_toolchain_ok; then
    printf '\n' >&2
    printf 'Python is compiled from source, and the macOS command line tools\n' >&2
    printf 'are not installed. They provide the C compiler.\n\n' >&2
    printf '  polyvm can start the installer with:\n\n' >&2
    printf '    xcode-select --install\n\n' >&2
    if confirm_install "  Run it now?"; then
      xcode-select --install 2>/dev/null || true
      printf '\n  Finish the installer that just opened, then run this again.\n' >&2
      printf '  Nothing was downloaded.\n' >&2
      return 1
    fi
    printf '\n  Run that yourself when you are ready.\n' >&2
    printf '  Nothing was downloaded.\n' >&2
    return 1
  fi

  if ! has brew; then
    warn "Homebrew was not found. Python will build, but is likely to end up
         without ssl, readline or sqlite3, and you will only find out when
         something imports them. Install Homebrew first: https://brew.sh"
    msg "==> toolchain ok (${PY_CC})"
    return 0
  fi

  local line formula required why
  local missing_required="" missing_optional="" report="" packages=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    formula="$(printf '%s' "$line" | cut -d'|' -f1)"
    required="$(printf '%s' "$line" | cut -d'|' -f2)"
    why="$(printf '%s' "$line" | cut -d'|' -f3)"
    brew_formula_installed "$formula" && continue
    report="${report}    ${formula}
        ${why}
"
    packages="${packages} ${formula}"
    if [ "$required" = "yes" ]; then
      missing_required="${missing_required} ${formula}"
    else
      missing_optional="${missing_optional} ${formula}"
    fi
  done <<BREW
$POLYVM_PY_BREW_FORMULAS
BREW

  if [ -z "$packages" ]; then
    msg "==> prerequisites ok (${PY_CC})"
    return 0
  fi

  printf '\n' >&2
  if [ -n "$missing_required" ]; then
    printf 'Python needs these Homebrew formulas and they are not installed:\n\n' >&2
  else
    printf 'Python will build, but these Homebrew formulas are missing and parts\n' >&2
    printf 'of the standard library would be left out:\n\n' >&2
  fi
  printf '%s' "$report" >&2
  printf '\n  polyvm can install them with:\n\n    brew install%s\n\n' "$packages" >&2

  if confirm_install "  Install them now?"; then
    printf '\n' >&2
    msg "==> brew install${packages}"
    # shellcheck disable=SC2086
    if brew install ${packages}; then
      printf '\n' >&2
      msg "==> prerequisites ok (${PY_CC})"
      return 0
    fi
    warn "the brew install did not finish cleanly"
    [ -n "$missing_required" ] && return 1
    return 0
  fi

  printf '\n  Not installing. Run that yourself when you are ready.\n' >&2
  if [ -n "$missing_required" ]; then
    printf '  Nothing was downloaded.\n' >&2
    return 1
  fi
  printf '  Continuing without them.\n' >&2
  return 0
}

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
