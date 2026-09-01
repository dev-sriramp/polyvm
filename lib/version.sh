#!/usr/bin/env bash
# polyvm version resolution.
#
# Lookup order for a plugin, first hit wins:
#   1. POLYVM_<PLUGIN>_VERSION env var (set by `polyvm shell`)
#   2. ASDF_<PLUGIN>_VERSION env var (asdf compatibility)
#   3. nearest .polyvm-versions walking up from $PWD
#   4. nearest .tool-versions walking up from $PWD (asdf compatibility)
#   5. legacy version file (.node-version, .python-version) when enabled
#   6. global versions file ($POLYVM_DATA_DIR/versions)
#
# A version line may list several versions. The first one that is actually
# installed wins, which is how `nodejs 22.3.0 20.14.0` fallbacks work.

POLYVM_VERSION_FILE_NAMES=".polyvm-versions .tool-versions"

# polyvm_versions_from_file <file> <plugin>  -> "v1 v2" on stdout
polyvm_versions_from_file() {
  local file="$1" plugin="$2"
  [ -f "$file" ] || return 1
  # Strip comments, match the plugin in field 1, print the rest.
  awk -v plugin="$plugin" '
    { sub(/#.*/, "") }
    $1 == plugin {
      out = ""
      for (i = 2; i <= NF; i++) out = out (out == "" ? "" : " ") $i
      if (out != "") { print out; found = 1; exit }
    }
    END { if (!found) exit 1 }
  ' "$file"
}

# polyvm_find_version_file <plugin>  -> path on stdout
# Walks up from $PWD (or $1 dir override via POLYVM_LOOKUP_DIR).
polyvm_find_version_file() {
  local plugin="$1"
  local dir="${POLYVM_LOOKUP_DIR:-$PWD}"
  local name
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    for name in $POLYVM_VERSION_FILE_NAMES; do
      if [ -f "${dir}/${name}" ] && polyvm_versions_from_file "${dir}/${name}" "$plugin" >/dev/null 2>&1; then
        printf '%s\n' "${dir}/${name}"
        return 0
      fi
    done
    dir="$(dirname "$dir")"
  done
  # Check / itself once.
  for name in $POLYVM_VERSION_FILE_NAMES; do
    if [ -f "/${name}" ] && polyvm_versions_from_file "/${name}" "$plugin" >/dev/null 2>&1; then
      printf '%s\n' "/${name}"
      return 0
    fi
  done
  return 1
}

# Legacy files such as .python-version or .node-version, resolved through the
# plugin's own list-legacy-filenames and parse-legacy-file hooks. On by
# default, because a pyenv or nvm user expects their existing files to work.
# Set POLYVM_LEGACY_VERSION_FILE=no to ignore them.
polyvm_legacy_version() {
  local plugin="$1"
  [ "${POLYVM_LEGACY_VERSION_FILE:-yes}" != "no" ] || return 1

  local plugin_path
  plugin_path="$(polyvm_plugin_path "$plugin")"
  [ -x "${plugin_path}/bin/list-legacy-filenames" ] || return 1

  local names
  names="$("${plugin_path}/bin/list-legacy-filenames" 2>/dev/null)" || return 1
  [ -n "$names" ] || return 1

  local dir="${POLYVM_LOOKUP_DIR:-$PWD}" name file
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    for name in $names; do
      file="${dir}/${name}"
      if [ -f "$file" ]; then
        if [ -x "${plugin_path}/bin/parse-legacy-file" ]; then
          "${plugin_path}/bin/parse-legacy-file" "$file" 2>/dev/null | head -n1 | polyvm_trim
        else
          head -n1 "$file" | polyvm_trim
        fi
        return 0
      fi
    done
    dir="$(dirname "$dir")"
  done
  return 1
}

# polyvm_resolve_versions_var <plugin>
# Sets POLYVM_RESOLVED_VERSIONS and POLYVM_VERSION_SOURCE. Returns 1 when no
# version file mentions the plugin. Assigning rather than printing matters:
# a command substitution would throw the source away.
# shellcheck disable=SC2034  # POLYVM_RESOLVED_* are read by callers
polyvm_resolve_versions_var() {
  local plugin="$1"
  local env_name
  env_name="$(polyvm_env_name "$plugin")"

  POLYVM_RESOLVED_VERSIONS=""
  POLYVM_VERSION_SOURCE=""

  local from_env
  eval "from_env=\${POLYVM_${env_name}_VERSION:-}"
  if [ -n "$from_env" ]; then
    POLYVM_RESOLVED_VERSIONS="$from_env"
    POLYVM_VERSION_SOURCE="POLYVM_${env_name}_VERSION"
    return 0
  fi

  eval "from_env=\${ASDF_${env_name}_VERSION:-}"
  if [ -n "$from_env" ]; then
    POLYVM_RESOLVED_VERSIONS="$from_env"
    POLYVM_VERSION_SOURCE="ASDF_${env_name}_VERSION"
    return 0
  fi

  local file versions
  if file="$(polyvm_find_version_file "$plugin")"; then
    POLYVM_RESOLVED_VERSIONS="$(polyvm_versions_from_file "$file" "$plugin")"
    POLYVM_VERSION_SOURCE="$file"
    return 0
  fi

  if versions="$(polyvm_legacy_version "$plugin")" && [ -n "$versions" ]; then
    POLYVM_RESOLVED_VERSIONS="$versions"
    POLYVM_VERSION_SOURCE="legacy version file"
    return 0
  fi

  if [ -f "$POLYVM_GLOBAL_VERSIONS_FILE" ]; then
    if versions="$(polyvm_versions_from_file "$POLYVM_GLOBAL_VERSIONS_FILE" "$plugin")"; then
      POLYVM_RESOLVED_VERSIONS="$versions"
      POLYVM_VERSION_SOURCE="$POLYVM_GLOBAL_VERSIONS_FILE"
      return 0
    fi
  fi

  return 1
}

# Printing wrapper. Loses POLYVM_VERSION_SOURCE when used in a subshell.
polyvm_resolve_versions() {
  polyvm_resolve_versions_var "$1" || return 1
  printf '%s\n' "$POLYVM_RESOLVED_VERSIONS"
}

# polyvm_resolve_version_var <plugin>
# Sets POLYVM_RESOLVED_VERSION and POLYVM_VERSION_SOURCE to the single version
# that applies: the first candidate that is installed, or "system", or the
# first candidate when none are installed, so callers can report a useful
# "not installed" error.
polyvm_resolve_version_var() {
  local plugin="$1"
  local first="" v
  POLYVM_RESOLVED_VERSION=""
  polyvm_resolve_versions_var "$plugin" || return 1
  for v in $POLYVM_RESOLVED_VERSIONS; do
    [ -n "$first" ] || first="$v"
    if [ "$v" = "system" ]; then
      POLYVM_RESOLVED_VERSION="system"
      return 0
    fi
    case "$v" in
      path:*)
        POLYVM_RESOLVED_VERSION="$v"
        return 0
        ;;
    esac
    if polyvm_version_installed "$plugin" "$v"; then
      POLYVM_RESOLVED_VERSION="$v"
      return 0
    fi
  done
  POLYVM_RESOLVED_VERSION="$first"
  return 0
}

# Printing wrapper.
polyvm_resolve_version() {
  polyvm_resolve_version_var "$1" || return 1
  printf '%s\n' "$POLYVM_RESOLVED_VERSION"
}

# ---------------------------------------------------------------- writing

# polyvm_write_version_file <file> <plugin> <version...>
polyvm_write_version_file() {
  local file="$1" plugin="$2"
  shift 2
  local versions="$*"
  local tmp
  tmp="${file}.polyvm.$$"

  if [ -f "$file" ]; then
    awk -v plugin="$plugin" '$1 != plugin' "$file" > "$tmp"
  else
    : > "$tmp"
  fi
  printf '%s %s\n' "$plugin" "$versions" >> "$tmp"
  # Keep the file sorted by plugin name so diffs stay small.
  sort -o "$tmp" "$tmp"
  mv "$tmp" "$file"
}

polyvm_set_global() {
  local plugin="$1"
  shift
  mkdir -p "$(dirname "$POLYVM_GLOBAL_VERSIONS_FILE")"
  polyvm_write_version_file "$POLYVM_GLOBAL_VERSIONS_FILE" "$plugin" "$@"
}

polyvm_set_local() {
  local plugin="$1"
  shift
  local file="${PWD}/.polyvm-versions"
  # If the directory already uses .tool-versions, keep writing there.
  if [ ! -f "$file" ] && [ -f "${PWD}/.tool-versions" ]; then
    file="${PWD}/.tool-versions"
  fi
  polyvm_write_version_file "$file" "$plugin" "$@"
  printf '%s\n' "$file"
}

# Every plugin named across the resolved version files, deduplicated.
polyvm_all_plugins_in_scope() {
  local file
  {
    for file in $(polyvm_version_files_in_scope); do
      awk '{ sub(/#.*/, "") } NF > 1 { print $1 }' "$file"
    done
    ls -1 "$POLYVM_PLUGIN_DIR" 2>/dev/null || true
  } | sort -u
}

polyvm_version_files_in_scope() {
  local dir="${POLYVM_LOOKUP_DIR:-$PWD}" name
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    for name in $POLYVM_VERSION_FILE_NAMES; do
      [ -f "${dir}/${name}" ] && printf '%s\n' "${dir}/${name}"
    done
    dir="$(dirname "$dir")"
  done
  [ -f "$POLYVM_GLOBAL_VERSIONS_FILE" ] && printf '%s\n' "$POLYVM_GLOBAL_VERSIONS_FILE"
  return 0
}
