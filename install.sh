#!/usr/bin/env bash
# polyvm bootstrap installer. Linux and macOS.
#
#   curl -fsSL https://raw.githubusercontent.com/dev-sriramp/polyvm/main/install.sh | bash
#
# Or from a local checkout:
#
#   ./install.sh
#
# Environment:
#   POLYVM_DIR     install location, default $HOME/.polyvm
#   POLYVM_REPO    git URL to clone from
#   POLYVM_REF     branch or tag to check out
#   POLYVM_NO_RC   set to 1 to skip editing shell rc files

set -euo pipefail

POLYVM_REPO="${POLYVM_REPO:-https://github.com/dev-sriramp/polyvm.git}"
POLYVM_REF="${POLYVM_REF:-main}"
POLYVM_DIR="${POLYVM_DIR:-$HOME/.polyvm}"

RC_START="# >>> polyvm >>>"
RC_END="# <<< polyvm <<<"

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

step() { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*" >&2; }
ok()   { printf '%sok%s %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
warn() { printf '%swarning:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

has() { command -v "$1" >/dev/null 2>&1; }

# ------------------------------------------------------------ preflight

case "$(uname -s)" in
  Linux|Darwin) : ;;
  MINGW*|MSYS*|CYGWIN*)
    warn "Windows support is a work in progress. polyvm will install and the
         core commands work under Git Bash and MSYS2, but plugins that build
         from source will not. See docs/windows.md."
    ;;
  *) die "polyvm supports Linux and macOS. Found: $(uname -s)" ;;
esac

for tool in git tar; do
  has "$tool" || die "$tool is required but not installed"
done

# polyvm downloads with curl or wget, whichever is present, so requiring curl
# specifically would refuse to install on a minimal image that ships only wget.
if ! has curl && ! has wget; then
  die "either curl or wget is required, and neither is installed"
fi

if [ -z "${BASH_VERSION:-}" ]; then
  die "run this installer with bash: bash install.sh"
fi

# ------------------------------------------------------------ install

# Are we running from inside a polyvm checkout, or piped from curl?
#
# BASH_SOURCE[0] is unset for `curl ... | bash` and for `bash -c "$(curl ...)"`,
# which is how most people install. Under `set -u` reading it unguarded aborts
# the script, so the documented one-line install would fail before doing
# anything. Guard it, and treat "no script on disk" as the piped case.
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
SCRIPT_DIR=""
if [ -n "$SCRIPT_SOURCE" ] && [ -f "$SCRIPT_SOURCE" ]; then
  SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" && pwd )"
fi

LOCAL_CHECKOUT=""
if [ -n "$SCRIPT_DIR" ] && [ -f "${SCRIPT_DIR}/bin/polyvm" ] && [ -f "${SCRIPT_DIR}/lib/core.sh" ]; then
  LOCAL_CHECKOUT="$SCRIPT_DIR"
fi

if [ -d "${POLYVM_DIR}/.git" ]; then
  step "polyvm is already installed at ${POLYVM_DIR}, updating"
  ( cd "$POLYVM_DIR" && git fetch --quiet origin && git checkout --quiet "$POLYVM_REF" && git pull --quiet --ff-only ) \
    || warn "could not update the existing checkout, leaving it as is"
elif [ -n "$LOCAL_CHECKOUT" ] && [ "$LOCAL_CHECKOUT" != "$POLYVM_DIR" ]; then
  step "installing from the local checkout at ${LOCAL_CHECKOUT}"
  mkdir -p "$POLYVM_DIR"
  # Copy the source, not the runtime data.
  for entry in bin lib completions contrib polyvm.sh; do
    [ -e "${LOCAL_CHECKOUT}/${entry}" ] || continue
    rm -rf "${POLYVM_DIR:?}/${entry}"
    cp -R "${LOCAL_CHECKOUT}/${entry}" "${POLYVM_DIR}/${entry}"
  done
elif [ -n "$LOCAL_CHECKOUT" ] && [ "$LOCAL_CHECKOUT" = "$POLYVM_DIR" ]; then
  step "using the checkout already at ${POLYVM_DIR}"
else
  step "cloning polyvm into ${POLYVM_DIR}"
  [ -e "$POLYVM_DIR" ] && die "${POLYVM_DIR} already exists and is not a git checkout. Move it aside first."
  git clone --quiet --branch "$POLYVM_REF" "$POLYVM_REPO" "$POLYVM_DIR" \
    || die "could not clone ${POLYVM_REPO}. Set POLYVM_REPO to the right URL."
fi

chmod +x "${POLYVM_DIR}/bin/polyvm"
mkdir -p "${POLYVM_DIR}/shims" "${POLYVM_DIR}/plugins" \
         "${POLYVM_DIR}/installs" "${POLYVM_DIR}/downloads" "${POLYVM_DIR}/tmp"
ok "installed polyvm into ${POLYVM_DIR}"

# ------------------------------------------------------------ shell rc

rc_block() {
  cat <<RC
${RC_START}
export POLYVM_DIR="${POLYVM_DIR}"
export PATH="\$POLYVM_DIR/shims:\$PATH"
[ -s "\$POLYVM_DIR/polyvm.sh" ] && . "\$POLYVM_DIR/polyvm.sh"
${RC_END}
RC
}

patch_rc() {
  local file="$1"
  [ -n "$file" ] || return 0

  if [ -f "$file" ] && grep -Fq "$RC_START" "$file"; then
    # Replace the existing block so re-running the installer stays clean.
    local tmp="${file}.polyvm.$$"
    awk -v start="$RC_START" -v end="$RC_END" '
      $0 == start { skip = 1 }
      skip != 1 { print }
      $0 == end { skip = 0 }
    ' "$file" > "$tmp"
    rc_block >> "$tmp"
    mv "$tmp" "$file"
    ok "refreshed the polyvm block in ${file}"
    return 0
  fi

  mkdir -p "$(dirname "$file")"
  [ -f "$file" ] || : > "$file"
  printf '\n' >> "$file"
  rc_block >> "$file"
  ok "added polyvm to ${file}"
}

if [ "${POLYVM_NO_RC:-}" = "1" ]; then
  warn "skipping shell rc changes because POLYVM_NO_RC=1"
else
  RC_FILES=""
  # bash
  if [ -f "$HOME/.bashrc" ]; then
    RC_FILES="$RC_FILES $HOME/.bashrc"
  elif [ "$(uname -s)" = "Darwin" ] && [ -f "$HOME/.bash_profile" ]; then
    RC_FILES="$RC_FILES $HOME/.bash_profile"
  elif has bash; then
    RC_FILES="$RC_FILES $HOME/.bashrc"
  fi
  # zsh
  if has zsh || [ -f "$HOME/.zshrc" ]; then
    RC_FILES="$RC_FILES ${ZDOTDIR:-$HOME}/.zshrc"
  fi

  for rc in $RC_FILES; do
    patch_rc "$rc"
  done
fi

# ------------------------------------------------------------ done

printf '\n'
ok "polyvm ${C_RESET}is installed"
printf '\n'
printf 'Open a new shell, or run:\n'
printf '  %s\n\n' ". \"${POLYVM_DIR}/polyvm.sh\""
printf 'Then add a language and install a version:\n'
printf '  polyvm plugin add nodejs\n'
printf '  polyvm install nodejs latest\n'
printf '  polyvm global nodejs latest\n\n'
printf 'Check the install any time with:\n'
printf '  polyvm doctor\n'
