#!/usr/bin/env bash
# polyvm install engine: resolve version specs, run plugin hooks, install and
# remove runtimes.

# Versions that look like a prerelease. Used when a plugin has no
# bin/latest-stable of its own.
POLYVM_UNSTABLE_PATTERN='(^|[-._])(alpha|beta|rc|pre|preview|dev|nightly|snapshot|next|canary|insiders|milestone|m[0-9]|ea|test)([-._0-9]|$)'

# polyvm_list_all <plugin> [query]
#
# Prints one version per line when piped, so `polyvm list-all python | grep 3.13`
# works. Lays them out in columns and adds a summary when a person is reading,
# because a bare 1,090 line dump is not a useful answer to "what can I install".
polyvm_list_all() {
  local plugin="$1" query="${2:-}"
  polyvm_require_plugin "$plugin"

  local raw versions count
  raw="$(polyvm_run_required_hook "$plugin" list-all)" \
    || polyvm_die "the list-all hook for '$plugin' failed"

  # list-all prints a single space separated line by convention.
  versions="$(printf '%s\n' "$raw" | tr ' ' '\n' | sed '/^$/d' | {
    if [ -n "$query" ]; then grep -- "$query" || true; else cat; fi
  })"

  count="$(printf '%s' "$versions" | grep -c . || true)"

  if [ "$count" -eq 0 ]; then
    if [ -n "$query" ]; then
      polyvm_info "no ${plugin} version matches '${query}'"
      polyvm_info "see everything with: polyvm list-all ${plugin}"
    else
      polyvm_info "the ${plugin} plugin reported no installable versions"
    fi
    return 0
  fi

  printf '%s\n' "$versions" | polyvm_print_list

  # Everything below is orientation for a human, so it goes to stderr and only
  # when one is there.
  [ -t 1 ] || return 0
  local newest
  newest="$(printf '%s\n' "$versions" | tail -n1)"
  printf '\n' >&2
  if [ -n "$query" ]; then
    polyvm_info "${count} ${plugin} versions match '${query}'"
  else
    polyvm_info "${count} ${plugin} versions available"
    polyvm_info "narrow the list with: polyvm list-all ${plugin} <query>"
  fi
  polyvm_info "install one with:     polyvm install ${plugin} ${newest}"
  polyvm_info "or the newest stable: polyvm install ${plugin} latest"
}

# polyvm_latest_version <plugin> [query]
polyvm_latest_version() {
  local plugin="$1" query="${2:-}"
  polyvm_require_plugin "$plugin"

  if polyvm_plugin_has_hook "$plugin" latest-stable; then
    local out
    out="$(polyvm_run_hook "$plugin" latest-stable "$query" | polyvm_trim)"
    if [ -n "$out" ]; then
      printf '%s\n' "$out"
      return 0
    fi
  fi

  local latest
  latest="$(polyvm_list_all "$plugin" "$query" \
    | grep -Ev "$POLYVM_UNSTABLE_PATTERN" \
    | tail -n1)"
  [ -n "$latest" ] || polyvm_die "could not work out the latest version of '$plugin'"
  printf '%s\n' "$latest"
}

# polyvm_resolve_spec <plugin> <spec>
# Turns "latest", "latest:20", "ref:main" or a literal version into the
# version string used for the install directory.
polyvm_resolve_spec() {
  local plugin="$1" spec="$2"
  case "$spec" in
    latest)
      polyvm_latest_version "$plugin" ""
      ;;
    latest:*)
      polyvm_latest_version "$plugin" "${spec#latest:}"
      ;;
    ref:*)
      printf '%s\n' "$spec"
      ;;
    *)
      printf '%s\n' "$spec"
      ;;
  esac
}

# Directory name for a version. ref:main becomes ref-main so it is a safe
# single path segment.
polyvm_version_dirname() {
  case "$1" in
    ref:*) printf 'ref-%s\n' "$(printf '%s' "${1#ref:}" | tr '/' '-')" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

polyvm_list_installed() {
  local plugin="${1:-}"
  if [ -n "$plugin" ]; then
    polyvm_require_plugin "$plugin"
    local dir="${POLYVM_INSTALL_DIR}/${plugin}"
    if ! polyvm_dir_has_entries "$dir"; then
      polyvm_info "no versions of '$plugin' installed"
      return 0
    fi
    local v current=""
    current="$(polyvm_resolve_version "$plugin" 2>/dev/null || true)"
    for v in "$dir"/*; do
      [ -d "$v" ] || continue
      v="$(basename "$v")"
      if [ "$v" = "$current" ]; then
        printf ' *%s\n' "$v"
      else
        printf '  %s\n' "$v"
      fi
    done
    return 0
  fi

  if ! polyvm_dir_has_entries "$POLYVM_INSTALL_DIR"; then
    polyvm_info "nothing installed yet. Try: polyvm plugin add <name> && polyvm install <name> latest"
    return 0
  fi
  local p
  for p in "$POLYVM_INSTALL_DIR"/*; do
    [ -d "$p" ] || continue
    printf '%s\n' "$(basename "$p")"
    polyvm_list_installed "$(basename "$p")"
  done
}

# polyvm_install_version <plugin> <spec> [--keep-download]
polyvm_install_version() {
  local plugin="$1" spec="$2" keep_download="${3:-}"
  polyvm_require_plugin "$plugin"

  local version dirname install_path download_path install_type
  version="$(polyvm_resolve_spec "$plugin" "$spec")"
  polyvm_validate_version_string "$(polyvm_version_dirname "$version")"
  dirname="$(polyvm_version_dirname "$version")"
  install_path="${POLYVM_INSTALL_DIR}/${plugin}/${dirname}"
  download_path="${POLYVM_DOWNLOAD_DIR}/${plugin}/${dirname}"

  case "$version" in
    ref:*) install_type="ref" ;;
    *) install_type="version" ;;
  esac

  if [ -d "$install_path" ]; then
    polyvm_ok "${plugin} ${version} is already installed"
    return 0
  fi

  # Preflight before anything is downloaded. A missing compiler is not worth
  # discovering after a 25 MB download and two minutes of configure.
  if polyvm_plugin_has_hook "$plugin" preflight \
     && [ -z "${POLYVM_SKIP_PREFLIGHT:-}" ]; then
    POLYVM_INSTALL_VERSION="$version"
    ASDF_INSTALL_VERSION="${version#ref:}"
    export POLYVM_INSTALL_VERSION ASDF_INSTALL_VERSION
    if ! polyvm_run_hook "$plugin" preflight; then
      polyvm_die "${plugin} is not ready to build on this machine.
  Fix the above, then run: polyvm install ${plugin} ${version}
  To try anyway: POLYVM_SKIP_PREFLIGHT=1 polyvm install ${plugin} ${version}"
    fi
  fi

  polyvm_step "installing ${plugin} ${version}"

  ASDF_INSTALL_TYPE="$install_type"
  ASDF_INSTALL_VERSION="${version#ref:}"
  ASDF_INSTALL_PATH="$install_path"
  ASDF_DOWNLOAD_PATH="$download_path"
  POLYVM_INSTALL_TYPE="$ASDF_INSTALL_TYPE"
  POLYVM_INSTALL_VERSION="$ASDF_INSTALL_VERSION"
  POLYVM_INSTALL_PATH="$ASDF_INSTALL_PATH"
  POLYVM_DOWNLOAD_PATH="$ASDF_DOWNLOAD_PATH"
  export ASDF_INSTALL_TYPE ASDF_INSTALL_VERSION ASDF_INSTALL_PATH ASDF_DOWNLOAD_PATH \
    POLYVM_INSTALL_TYPE POLYVM_INSTALL_VERSION POLYVM_INSTALL_PATH POLYVM_DOWNLOAD_PATH

  if polyvm_plugin_has_hook "$plugin" download; then
    mkdir -p "$download_path"
    if ! polyvm_run_hook "$plugin" download; then
      rm -rf "$download_path"
      polyvm_die "download failed for ${plugin} ${version}"
    fi
  fi

  mkdir -p "$install_path"
  if ! polyvm_run_required_hook "$plugin" install; then
    rm -rf "$install_path"
    polyvm_die "install failed for ${plugin} ${version}"
  fi

  if [ -z "$keep_download" ] && [ "${POLYVM_KEEP_DOWNLOADS:-no}" != "yes" ]; then
    [ -d "$download_path" ] && rm -rf "$download_path"
  fi

  polyvm_reshim "$plugin" "$dirname"
  polyvm_ok "installed ${plugin} ${version}"
}

# Install every plugin/version named by the version files in scope.
polyvm_install_from_files() {
  local installed_any="" file plugin versions v
  local files
  files="$(polyvm_version_files_in_scope)"
  [ -n "$files" ] || polyvm_die "no .polyvm-versions or .tool-versions file found, and no global versions set"

  for file in $files; do
    while IFS= read -r line; do
      case "$line" in
        ""|\#*) continue ;;
      esac
      plugin="$(printf '%s' "$line" | awk '{print $1}')"
      versions="$(printf '%s' "$line" | awk '{ for (i=2;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":"") }')"
      if [ -z "$plugin" ] || [ -z "$versions" ]; then continue; fi
      polyvm_plugin_installed "$plugin" || {
        polyvm_warn "skipping '$plugin', the plugin is not installed. Run: polyvm plugin add $plugin"
        continue
      }
      for v in $versions; do
        [ "$v" = "system" ] && continue
        case "$v" in path:*) continue ;; esac
        polyvm_install_version "$plugin" "$v"
        installed_any=yes
        break
      done
    done < <(awk '{ sub(/#.*/, "") } NF > 1' "$file")
  done

  [ -n "$installed_any" ] || polyvm_info "nothing to install"
}

# polyvm_uninstall_version <plugin> <version>
polyvm_uninstall_version() {
  local plugin="$1" version="$2"
  polyvm_require_plugin "$plugin"
  local dirname install_path
  dirname="$(polyvm_version_dirname "$version")"
  install_path="${POLYVM_INSTALL_DIR}/${plugin}/${dirname}"
  [ -d "$install_path" ] || polyvm_die "${plugin} ${version} is not installed"

  ASDF_INSTALL_TYPE="version"
  ASDF_INSTALL_VERSION="${version#ref:}"
  ASDF_INSTALL_PATH="$install_path"
  export ASDF_INSTALL_TYPE ASDF_INSTALL_VERSION ASDF_INSTALL_PATH

  polyvm_run_hook "$plugin" uninstall || \
    polyvm_warn "the uninstall hook for '$plugin' failed, removing the directory anyway"

  polyvm_safe_rm_rf "$install_path"
  polyvm_reshim_all
  polyvm_ok "removed ${plugin} ${version}"
}
