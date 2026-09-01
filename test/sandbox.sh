#!/usr/bin/env bash
# Install polyvm into a throwaway prefix and open a shell with it active.
#
# Nothing outside the sandbox directory is touched: your .bashrc and .zshrc are
# left alone, and your real ~/.polyvm, if you have one, is untouched.
#
#   ./test/sandbox.sh              set up and open a subshell
#   ./test/sandbox.sh --no-shell   set up only, print how to activate it
#   ./test/sandbox.sh --clean      delete the sandbox
#
#   POLYVM_SANDBOX=/path/to/dir    use a different location

set -euo pipefail

REPO="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
SANDBOX="${POLYVM_SANDBOX:-${TMPDIR:-/tmp}/polyvm-sandbox}"
SANDBOX="${SANDBOX%/}"
PREFIX="${SANDBOX}/.polyvm"

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_GREEN=$'\033[32m'; C_BLUE=$'\033[34m'; C_YELLOW=$'\033[33m'
else
  C_RESET=""; C_GREEN=""; C_BLUE=""; C_YELLOW=""
fi
step() { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*" >&2; }
ok()   { printf '%sok%s %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
note() { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }

case "${1:-}" in
  --clean)
    rm -rf "$SANDBOX"
    ok "removed ${SANDBOX}"
    exit 0
    ;;
esac

OPEN_SHELL=yes
[ "${1:-}" = "--no-shell" ] && OPEN_SHELL=no

step "checking that the repo can execute its own hooks"
if [ ! -x "${REPO}/bin/polyvm" ]; then
  note "bin/polyvm is not executable. Fixing it."
  chmod +x "${REPO}/bin/polyvm"
fi
chmod +x "${REPO}"/contrib/plugins/*/bin/* 2>/dev/null || true
if [ ! -x "${REPO}/bin/polyvm" ]; then
  note "The executable bit will not stick on this filesystem. If the repo lives
on an exFAT or FAT volume, git and the plugin hooks will misbehave. Move the
repo to an APFS or ext4 volume before testing."
  exit 1
fi

step "running the test suite"
"${REPO}/test/run.sh"

step "installing into ${PREFIX}"
rm -rf "$SANDBOX"
mkdir -p "$SANDBOX"
POLYVM_DIR="$PREFIX" POLYVM_NO_RC=1 bash "${REPO}/install.sh" >/dev/null
ok "installed"

cat > "${SANDBOX}/activate" <<ACTIVATE
# Source this to use the sandboxed polyvm in the current shell.
export POLYVM_DIR="${PREFIX}"
. "${PREFIX}/polyvm.sh"
export PS1="(polyvm-sandbox) \${PS1:-\\$ }"
ACTIVATE

printf '\n' >&2
ok "sandbox ready at ${SANDBOX}"
printf '\n' >&2
printf 'Try:\n' >&2
printf '  polyvm doctor\n' >&2
printf '  polyvm plugin add python\n' >&2
printf '  polyvm list-all python | tail -20\n' >&2
printf '  polyvm install python 3.13.1\n' >&2
printf '  polyvm global python 3.13.1\n' >&2
printf '  python --version\n' >&2
printf '\n' >&2
printf 'Delete it all with:\n' >&2
printf '  ./test/sandbox.sh --clean\n' >&2
printf '\n' >&2

if [ "$OPEN_SHELL" = "no" ]; then
  printf 'Activate it in this shell with:\n' >&2
  printf '  . %s/activate\n' "$SANDBOX" >&2
  exit 0
fi

step "opening a subshell, type exit to leave"
POLYVM_DIR="$PREFIX" bash --rcfile "${SANDBOX}/activate" -i
