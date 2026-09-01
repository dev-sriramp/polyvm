#!/usr/bin/env bash
# polyvm shell integration for bash and zsh.
#
# Source this from ~/.bashrc or ~/.zshrc:
#
#   export POLYVM_DIR="$HOME/.polyvm"
#   . "$POLYVM_DIR/polyvm.sh"
#
# It puts the shim directory on PATH and defines a `polyvm` function so that
# `polyvm shell <plugin> <version>` can change the current shell. Everything
# else works without this file.

# Work out where we live, in bash or zsh.
if [ -z "${POLYVM_DIR:-}" ]; then
  if [ -n "${BASH_SOURCE:-}" ]; then
    POLYVM_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
  elif [ -n "${ZSH_VERSION:-}" ]; then
    # ${(%):-%x} is zsh syntax for "path of this file". Wrapping it in eval
    # keeps bash, and static analysis, from ever parsing that expansion.
    __polyvm_self="$(eval 'printf %s "${(%):-%x}"')"
    POLYVM_DIR="$( cd -P "$( dirname "$__polyvm_self" )" && pwd )"
    unset __polyvm_self
  else
    POLYVM_DIR="$HOME/.polyvm"
  fi
fi
export POLYVM_DIR
export POLYVM_DATA_DIR="${POLYVM_DATA_DIR:-$POLYVM_DIR}"

# Put shims first on PATH, exactly once.
case ":${PATH}:" in
  *":${POLYVM_DATA_DIR}/shims:"*) : ;;
  *) PATH="${POLYVM_DATA_DIR}/shims:${PATH}" ;;
esac
export PATH

export POLYVM_SHELL_INTEGRATION=1

polyvm() {
  case "${1:-}" in
    shell)
      shift
      if [ "$#" -lt 2 ]; then
        printf 'usage: polyvm shell <plugin> <version|system|--unset>\n' >&2
        return 1
      fi
      local __polyvm_out
      __polyvm_out="$( "${POLYVM_DIR}/bin/polyvm" shell-env "$@" )" || return $?
      eval "$__polyvm_out"
      ;;
    *)
      "${POLYVM_DIR}/bin/polyvm" "$@"
      ;;
  esac
}

# Load completions when the shell supports them.
if [ -n "${BASH_VERSION:-}" ] && [ -r "${POLYVM_DIR}/completions/polyvm.bash" ]; then
  . "${POLYVM_DIR}/completions/polyvm.bash"
fi
if [ -n "${ZSH_VERSION:-}" ] && [ -d "${POLYVM_DIR}/completions" ]; then
  # shellcheck disable=SC2206  # zsh array, word splitting is intended
  fpath=("${POLYVM_DIR}/completions" $fpath)
fi
