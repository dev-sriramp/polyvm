# bash completion for polyvm

_polyvm_plugins() {
  local dir="${POLYVM_DATA_DIR:-${POLYVM_DIR:-$HOME/.polyvm}}/plugins"
  [ -d "$dir" ] && ls -1 "$dir" 2>/dev/null
}

_polyvm_versions() {
  local dir="${POLYVM_DATA_DIR:-${POLYVM_DIR:-$HOME/.polyvm}}/installs/$1"
  [ -d "$dir" ] && ls -1 "$dir" 2>/dev/null
}

# COMPREPLY=( $(compgen ...) ) is the portable completion idiom. mapfile does
# not exist in bash 3.2, which is what stock macOS ships.
# shellcheck disable=SC2207
_polyvm() {
  local cur
  cur="${COMP_WORDS[COMP_CWORD]}"

  local commands="install uninstall list list-all latest global local shell current where which exec env reshim plugin doctor update init version help"

  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
    return 0
  fi

  case "${COMP_WORDS[1]}" in
    plugin|plugins)
      if [ "$COMP_CWORD" -eq 2 ]; then
        COMPREPLY=( $(compgen -W "add list remove update search" -- "$cur") )
      elif [ "$COMP_CWORD" -eq 3 ] && [ "${COMP_WORDS[2]}" != "add" ]; then
        COMPREPLY=( $(compgen -W "$(_polyvm_plugins)" -- "$cur") )
      fi
      ;;
    install|uninstall|list-all|latest|global|local|shell|current|where|exec|env|reshim)
      if [ "$COMP_CWORD" -eq 2 ]; then
        COMPREPLY=( $(compgen -W "$(_polyvm_plugins)" -- "$cur") )
      elif [ "$COMP_CWORD" -eq 3 ]; then
        COMPREPLY=( $(compgen -W "$(_polyvm_versions "${COMP_WORDS[2]}") latest system" -- "$cur") )
      fi
      ;;
    init)
      COMPREPLY=( $(compgen -W "bash zsh" -- "$cur") )
      ;;
  esac
  return 0
}

complete -F _polyvm polyvm
