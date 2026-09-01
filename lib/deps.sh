#!/usr/bin/env bash
# Build prerequisites, for every language rather than one.
#
# Languages that compile from source need a toolchain and development headers.
# Get it wrong and you hit one of two bad endings: the build dies at
# "no acceptable C compiler found", or it succeeds and quietly leaves out half
# the standard library, which you discover weeks later.
#
# polyvm keeps what each language needs in contrib/requirements/<plugin>, as
# data rather than code, so adding a language is a file rather than a patch.
# The check runs before anything is downloaded, and offers to install what is
# missing.
#
# Requirements file format, one requirement per line, ten pipe separated fields:
#
#   kind|spec|required|why|apt|dnf|apk|pacman|zypper|brew
#
#   kind      tool    spec is a command that must exist
#             header  spec is a C header that must be compilable
#   required  yes     missing this stops the install
#             no      missing this only warns, and names what is lost
#   why       what breaks without it, shown to the user
#   the rest  the package providing it, per package manager. Leave a field
#             empty when that manager has no such package or does not need one.

polyvm_requirements_dir() {
  printf '%s\n' "${POLYVM_REQUIREMENTS_DIR:-${POLYVM_DIR}/contrib/requirements}"
}

polyvm_requirements_file() {
  printf '%s\n' "$(polyvm_requirements_dir)/$1"
}

polyvm_has_requirements() {
  [ -f "$(polyvm_requirements_file "$1")" ]
}

# Languages polyvm knows the prerequisites for.
polyvm_requirements_list() {
  local dir entry
  dir="$(polyvm_requirements_dir)"
  [ -d "$dir" ] || return 0
  for entry in "$dir"/*; do
    [ -f "$entry" ] || continue
    basename "$entry"
  done
}

# ------------------------------------------------------- package managers

polyvm_pkg_manager() {
  if polyvm_has apt-get; then printf 'apt\n'
  elif polyvm_has dnf; then printf 'dnf\n'
  elif polyvm_has yum; then printf 'yum\n'
  elif polyvm_has apk; then printf 'apk\n'
  elif polyvm_has pacman; then printf 'pacman\n'
  elif polyvm_has zypper; then printf 'zypper\n'
  elif polyvm_has brew; then printf 'brew\n'
  else printf 'unknown\n'
  fi
}

# Which field of a requirements line holds this manager's package name.
polyvm_pkg_field() {
  case "$1" in
    apt) printf '5\n' ;;
    dnf|yum) printf '6\n' ;;
    apk) printf '7\n' ;;
    pacman) printf '8\n' ;;
    zypper) printf '9\n' ;;
    brew) printf '10\n' ;;
    *) printf '5\n' ;;
  esac
}

polyvm_pkg_update_command() {
  case "$1" in
    apt) printf 'apt-get update\n' ;;
    *) printf '' ;;
  esac
}

polyvm_pkg_install_command() {
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

# "" when already root or using Homebrew, "sudo " when we need it and have it.
# Returns 1 when these packages cannot be installed from here at all.
polyvm_privilege_prefix() {
  local pm="$1"
  [ "$pm" = "brew" ] && { printf ''; return 0; }
  if [ "$(id -u 2>/dev/null || echo 1)" = "0" ]; then
    printf ''
    return 0
  fi
  if polyvm_has sudo; then
    printf 'sudo '
    return 0
  fi
  return 1
}

polyvm_full_install_command() {
  local pm="$1" prefix="$2" packages="$3"
  local update install
  update="$(polyvm_pkg_update_command "$pm")"
  install="$(polyvm_pkg_install_command "$pm")"
  [ -n "$install" ] || return 1
  if [ -n "$update" ]; then
    printf '%s%s && %s%s%s\n' "$prefix" "$update" "$prefix" "$install" "$packages"
  else
    printf '%s%s%s\n' "$prefix" "$install" "$packages"
  fi
}

# Ask, unless told otherwise.
#
#   POLYVM_INSTALL_DEPS=yes   install without asking, for Dockerfiles and CI
#   POLYVM_INSTALL_DEPS=no    never install, only report
#   unset or "ask"            prompt when someone can answer, report otherwise
polyvm_confirm_install() {
  local prompt="$1" reply=""
  case "${POLYVM_INSTALL_DEPS:-ask}" in
    yes|true|1) return 0 ;;
    no|false|0) return 1 ;;
  esac

  # Never prompt where nobody can answer. A build hanging on input in CI is
  # worse than one that fails with instructions.
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

polyvm_run_pkg_install() {
  local pm="$1" prefix="$2" packages="$3"
  local update install
  update="$(polyvm_pkg_update_command "$pm")"
  install="$(polyvm_pkg_install_command "$pm")"

  if [ -n "$update" ]; then
    polyvm_step "${prefix}${update}"
    # shellcheck disable=SC2086
    ${prefix}${update} || polyvm_warn "the package list refresh failed, continuing anyway"
  fi
  polyvm_step "${prefix}${install}${packages}"
  # shellcheck disable=SC2086
  ${prefix}${install}${packages}
}

# ------------------------------------------------------------- detection

polyvm_find_compiler() {
  local candidate
  for candidate in "${CC:-}" cc gcc clang; do
    [ -n "$candidate" ] || continue
    polyvm_has "$candidate" && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

# Compile a one line program that includes the header. This is the only
# reliable test: include paths differ across Debian multiarch, musl, macOS SDKs
# and Homebrew prefixes, so scanning directories gets it wrong.
polyvm_probe_header() {
  local header="$1" cc="$2" dir ok=1
  [ -n "$cc" ] || return 1
  dir="$(mktemp -d 2>/dev/null)" || return 1
  printf '#include <%s>\nint main(void) { return 0; }\n' "$header" > "${dir}/probe.c"
  # shellcheck disable=SC2086
  "$cc" -fsyntax-only ${CPPFLAGS:-} "${dir}/probe.c" >/dev/null 2>&1 && ok=0
  rm -rf "$dir"
  return $ok
}

# macOS libraries come from Homebrew, whose headers are never on the default
# include path, so the right question there is whether the formula is present.
polyvm_brew_formula_installed() {
  local prefix
  prefix="$(brew --prefix "$1" 2>/dev/null || true)"
  [ -n "$prefix" ] && [ -d "$prefix" ]
}

# On macOS /usr/bin/cc exists even with no command line tools and fails the
# moment you use it, so the only honest test is to compile something.
polyvm_darwin_toolchain_ok() {
  xcode-select -p >/dev/null 2>&1 || return 1
  local dir ok=1
  dir="$(mktemp -d 2>/dev/null)" || return 1
  printf 'int main(void) { return 0; }\n' > "${dir}/probe.c"
  cc -fsyntax-only "${dir}/probe.c" >/dev/null 2>&1 && ok=0
  rm -rf "$dir"
  return $ok
}

# --------------------------------------------------------------- the check

# polyvm_collect_missing <plugin> <pm>
# Sets POLYVM_DEP_REQUIRED, POLYVM_DEP_OPTIONAL, POLYVM_DEP_REPORT and
# POLYVM_DEP_CC. Package lists are space prefixed and ready to append.
polyvm_collect_missing() {
  local plugin="$1" pm="$2"
  local field file line kind spec required why pkg present
  field="$(polyvm_pkg_field "$pm")"
  file="$(polyvm_requirements_file "$plugin")"

  POLYVM_DEP_REQUIRED=""
  POLYVM_DEP_OPTIONAL=""
  POLYVM_DEP_REPORT=""
  POLYVM_DEP_CC="$(polyvm_find_compiler || true)"

  local darwin=""
  [ "$(polyvm_os)" = "darwin" ] && darwin=yes

  while IFS= read -r line; do
    case "$line" in ""|\#*) continue ;; esac
    kind="$(printf '%s' "$line" | cut -d'|' -f1)"
    spec="$(printf '%s' "$line" | cut -d'|' -f2)"
    required="$(printf '%s' "$line" | cut -d'|' -f3)"
    why="$(printf '%s' "$line" | cut -d'|' -f4)"
    pkg="$(printf '%s' "$line" | cut -d'|' -f"$field")"

    present=no
    case "$kind" in
      tool)
        polyvm_has "$spec" && present=yes
        ;;
      header)
        if [ -n "$darwin" ]; then
          # A header probe means nothing on macOS. Ask Homebrew instead, and
          # treat a header with no formula as satisfied.
          local formula
          formula="$(printf '%s' "$line" | cut -d'|' -f10)"
          if [ -z "$formula" ]; then
            present=yes
          elif polyvm_has brew && polyvm_brew_formula_installed "$formula"; then
            present=yes
          fi
        else
          polyvm_probe_header "$spec" "$POLYVM_DEP_CC" && present=yes
        fi
        ;;
      *)
        present=yes
        ;;
    esac

    [ "$present" = yes ] && continue
    [ -n "$pkg" ] || continue

    POLYVM_DEP_REPORT="${POLYVM_DEP_REPORT}    ${pkg}
        ${why}
"
    if [ "$required" = "yes" ]; then
      POLYVM_DEP_REQUIRED="${POLYVM_DEP_REQUIRED} ${pkg}"
    else
      POLYVM_DEP_OPTIONAL="${POLYVM_DEP_OPTIONAL} ${pkg}"
    fi
  done < "$file"
}

# polyvm_check_requirements <plugin>
# Returns 0 when the language can be built here, 1 when it cannot.
polyvm_check_requirements() {
  local plugin="$1"
  polyvm_has_requirements "$plugin" || return 0

  local os pm prefix
  os="$(polyvm_os)"
  pm="$(polyvm_pkg_manager)"

  polyvm_step "checking the build prerequisites for ${plugin}"

  # macOS needs its compiler from the command line tools, and /usr/bin/cc lies
  # about being one, so check before anything else.
  if [ "$os" = "darwin" ] && ! polyvm_darwin_toolchain_ok; then
    printf '\n' >&2
    printf '%s needs a C compiler and the macOS command line tools are not installed.\n\n' "$plugin" >&2
    printf '  polyvm can start the installer with:\n\n    xcode-select --install\n\n' >&2
    if polyvm_confirm_install "  Run it now?"; then
      xcode-select --install 2>/dev/null || true
      printf '\n  Finish the installer that just opened, then run this again.\n' >&2
    else
      printf '\n  Run that yourself when you are ready.\n' >&2
    fi
    printf '  Nothing was downloaded.\n' >&2
    return 1
  fi

  if [ "$os" = "darwin" ] && ! polyvm_has brew; then
    polyvm_warn "Homebrew was not found. ${plugin} may build, but is likely to end up
         missing libraries, and you will only find out when something uses them.
         Install Homebrew first: https://brew.sh"
  fi

  local attempt=1 packages cmd
  while [ "$attempt" -le 2 ]; do
    polyvm_collect_missing "$plugin" "$pm"

    if [ -z "$POLYVM_DEP_REQUIRED" ] && [ -z "$POLYVM_DEP_OPTIONAL" ]; then
      polyvm_ok "prerequisites for ${plugin} are satisfied"
      return 0
    fi

    packages="${POLYVM_DEP_REQUIRED}${POLYVM_DEP_OPTIONAL}"

    printf '\n' >&2
    if [ -n "$POLYVM_DEP_REQUIRED" ]; then
      printf '%s cannot be built here. Missing:\n\n' "$plugin" >&2
    else
      printf '%s will build, but these are missing and parts of it will be\n' "$plugin" >&2
      printf 'left out:\n\n' >&2
    fi
    printf '%s' "$POLYVM_DEP_REPORT" >&2

    if ! prefix="$(polyvm_privilege_prefix "$pm")"; then
      printf '\n  You are not root and sudo is not available, so polyvm cannot\n' >&2
      printf '  install these. Ask an administrator, or run polyvm as root.\n' >&2
      [ -n "$POLYVM_DEP_REQUIRED" ] && return 1
      return 0
    fi

    if ! cmd="$(polyvm_full_install_command "$pm" "$prefix" "$packages")"; then
      printf '\n  polyvm does not know the package manager here. Install those,\n' >&2
      printf '  then run this again.\n' >&2
      [ -n "$POLYVM_DEP_REQUIRED" ] && return 1
      return 0
    fi

    printf '\n  polyvm can install them with:\n\n    %s\n\n' "$cmd" >&2

    if [ "$attempt" -eq 2 ]; then
      printf '  Some are still missing after the install.\n' >&2
      [ -n "$POLYVM_DEP_REQUIRED" ] && return 1
      return 0
    fi

    if polyvm_confirm_install "  Install them now?"; then
      printf '\n' >&2
      polyvm_run_pkg_install "$pm" "$prefix" "$packages" \
        || polyvm_warn "the package install did not finish cleanly"
      printf '\n' >&2
      polyvm_step "re-checking"
      attempt=$((attempt + 1))
      continue
    fi

    printf '\n  Not installing. Run that yourself when you are ready.\n' >&2
    if [ -n "$POLYVM_DEP_REQUIRED" ]; then
      printf '  Nothing was downloaded.\n' >&2
      return 1
    fi
    printf '  Continuing without them.\n' >&2
    return 0
  done

  return 1
}
