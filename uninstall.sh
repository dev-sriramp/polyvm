#!/usr/bin/env bash
# Remove polyvm, every plugin and every runtime it installed.
#
#   ./uninstall.sh            ask first
#   POLYVM_YES=1 ./uninstall.sh   do not ask

set -euo pipefail

POLYVM_DIR="${POLYVM_DIR:-$HOME/.polyvm}"
RC_START="# >>> polyvm >>>"
RC_END="# <<< polyvm <<<"

[ -d "$POLYVM_DIR" ] || { printf 'polyvm is not installed at %s\n' "$POLYVM_DIR" >&2; exit 0; }

printf 'This removes %s including every runtime installed through polyvm.\n' "$POLYVM_DIR" >&2
if [ -z "${POLYVM_YES:-}" ] && [ -t 0 ]; then
  printf 'Continue? [y/N] ' >&2
  read -r reply
  case "$reply" in
    y|Y|yes|YES) : ;;
    *) printf 'cancelled\n' >&2; exit 1 ;;
  esac
fi

for rc in "$HOME/.bashrc" "$HOME/.bash_profile" "${ZDOTDIR:-$HOME}/.zshrc"; do
  [ -f "$rc" ] || continue
  grep -Fq "$RC_START" "$rc" || continue
  tmp="${rc}.polyvm.$$"
  awk -v start="$RC_START" -v end="$RC_END" '
    $0 == start { skip = 1 }
    skip != 1 { print }
    $0 == end { skip = 0 }
  ' "$rc" > "$tmp"
  mv "$tmp" "$rc"
  printf 'cleaned %s\n' "$rc" >&2
done

rm -rf "$POLYVM_DIR"
printf 'removed %s\n' "$POLYVM_DIR" >&2
printf 'Open a new shell to drop the shims from PATH.\n' >&2
