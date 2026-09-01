#!/usr/bin/env bash
# polyvm plugin management.
#
# Plugins follow the asdf plugin contract, so any asdf plugin repository works
# unchanged. A plugin is a git repo with executables under bin/:
#
#   bin/list-all             required   print every installable version
#   bin/install              required   install into $ASDF_INSTALL_PATH
#   bin/download             optional   fetch into $ASDF_DOWNLOAD_PATH first
#   bin/list-bin-paths       optional   dirs holding executables, default "bin"
#   bin/exec-env             optional   sourced before running a binary
#   bin/exec-path            optional   remap a binary path
#   bin/latest-stable        optional   resolve "latest"
#   bin/uninstall            optional   custom removal
#   bin/post-plugin-add      optional   run after the plugin is added
#   bin/post-plugin-update   optional   run after the plugin is updated
#   bin/list-legacy-filenames / bin/parse-legacy-file   optional
#
# See docs/plugin-api.md.

POLYVM_PLUGIN_INDEX_URL="${POLYVM_PLUGIN_INDEX_URL:-https://github.com/asdf-vm/asdf-plugins.git}"

# ------------------------------------------------------------- built-ins
#
# Plugins that ship with polyvm live in contrib/plugins/<name>. They are
# ordinary plugins following the same contract; the only difference is that
# `polyvm plugin add <name>` finds them without touching the network.

polyvm_builtin_plugin_path() {
  printf '%s\n' "${POLYVM_BUILTIN_PLUGIN_DIR}/$1"
}

polyvm_builtin_plugin_exists() {
  [ -d "$(polyvm_builtin_plugin_path "$1")" ]
}

polyvm_builtin_plugin_list() {
  polyvm_dir_has_entries "$POLYVM_BUILTIN_PLUGIN_DIR" || return 0
  local dir
  for dir in "$POLYVM_BUILTIN_PLUGIN_DIR"/*; do
    [ -d "$dir" ] || continue
    basename "$dir"
  done
}

# Copy a built-in into the data dir. Copying rather than symlinking means an
# updated polyvm never silently changes an installed plugin underneath you;
# `polyvm plugin update <name>` refreshes it deliberately.
polyvm_builtin_plugin_copy() {
  local name="$1" dest="$2"
  local src
  src="$(polyvm_builtin_plugin_path "$name")"
  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  cp -R "$src" "$dest"
  # Hooks must be executable even if the filesystem lost the bit in transit.
  if [ -d "${dest}/bin" ]; then
    chmod +x "${dest}"/bin/* 2>/dev/null || true
  fi
  printf 'builtin\n' > "${dest}/.polyvm-source-url"
}

# ---------------------------------------------------------------- index

# shellcheck disable=SC2120  # the force argument is optional
polyvm_plugin_index_sync() {
  local force="${1:-}"
  if [ -d "${POLYVM_PLUGIN_INDEX_DIR}/.git" ]; then
    # Refresh at most once a day unless forced.
    if [ -z "$force" ] && [ -f "${POLYVM_PLUGIN_INDEX_DIR}/.polyvm-synced" ]; then
      local age_ok=""
      # find -newermt is not portable; compare against a marker file we touch.
      if [ -n "$(find "${POLYVM_PLUGIN_INDEX_DIR}/.polyvm-synced" -mtime -1 2>/dev/null)" ]; then
        age_ok=yes
      fi
      [ -n "$age_ok" ] && return 0
    fi
    polyvm_debug "refreshing plugin index"
    ( cd "$POLYVM_PLUGIN_INDEX_DIR" && git fetch --quiet origin && git reset --quiet --hard origin/HEAD ) \
      || polyvm_warn "could not refresh the plugin index, using the cached copy"
  else
    polyvm_step "fetching the plugin index"
    rm -rf "$POLYVM_PLUGIN_INDEX_DIR"
    git clone --quiet --depth 1 "$POLYVM_PLUGIN_INDEX_URL" "$POLYVM_PLUGIN_INDEX_DIR" \
      || polyvm_die "could not clone the plugin index from $POLYVM_PLUGIN_INDEX_URL"
  fi
  touch "${POLYVM_PLUGIN_INDEX_DIR}/.polyvm-synced" 2>/dev/null || true
}

# polyvm_plugin_index_url <shortname>  -> git url on stdout
polyvm_plugin_index_url() {
  local name="$1"
  polyvm_plugin_index_sync
  local file="${POLYVM_PLUGIN_INDEX_DIR}/plugins/${name}"
  [ -f "$file" ] || return 1
  # Lines look like: repository = https://github.com/some-owner/some-repo.git
  awk -F'=' '/^[[:space:]]*repository[[:space:]]*=/ { sub(/^[[:space:]]+/, "", $2); sub(/[[:space:]]+$/, "", $2); print $2; exit }' "$file"
}

polyvm_plugin_index_search() {
  local query="${1:-}"

  # Built-ins first, so `polyvm plugin search python` shows the one polyvm
  # ships before the community list.
  local name
  for name in $(polyvm_builtin_plugin_list); do
    if [ -z "$query" ]; then
      printf '%s\t(built in)\n' "$name"
    else
      case "$name" in
        *"$query"*) printf '%s\t(built in)\n' "$name" ;;
      esac
    fi
  done

  polyvm_plugin_index_sync
  local dir="${POLYVM_PLUGIN_INDEX_DIR}/plugins"
  [ -d "$dir" ] || polyvm_die "plugin index is empty"
  local entry name
  for entry in "$dir"/*; do
    [ -f "$entry" ] || continue
    name="$(basename "$entry")"
    if [ -z "$query" ]; then
      printf '%s\n' "$name"
    else
      case "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" in
        *"$(printf '%s' "$query" | tr '[:upper:]' '[:lower:]')"*) printf '%s\n' "$name" ;;
      esac
    fi
  done
}

# ---------------------------------------------------------------- hooks

# Export the environment an asdf plugin hook expects. Callers set
# POLYVM_HOOK_* first where relevant.
polyvm_export_hook_env() {
  local plugin="$1"
  ASDF_DIR="$POLYVM_DIR"
  ASDF_DATA_DIR="$POLYVM_DATA_DIR"
  ASDF_PLUGIN_PATH="$(polyvm_plugin_path "$plugin")"
  ASDF_CONCURRENCY="${POLYVM_CONCURRENCY:-$(polyvm_cpu_count)}"
  POLYVM_PLUGIN_PATH="$ASDF_PLUGIN_PATH"
  POLYVM_CONCURRENCY="$ASDF_CONCURRENCY"
  export ASDF_DIR ASDF_DATA_DIR ASDF_PLUGIN_PATH ASDF_CONCURRENCY \
    POLYVM_PLUGIN_PATH POLYVM_CONCURRENCY
}

polyvm_plugin_has_hook() {
  local plugin="$1" hook="$2"
  [ -f "$(polyvm_plugin_path "$plugin")/bin/${hook}" ]
}

# polyvm_run_hook <plugin> <hook> [args...]
# Runs the hook if present. Returns 0 and prints nothing when absent.
polyvm_run_hook() {
  local plugin="$1" hook="$2"
  shift 2
  local script
  script="$(polyvm_plugin_path "$plugin")/bin/${hook}"
  [ -f "$script" ] || return 0
  polyvm_export_hook_env "$plugin"
  polyvm_ensure_asdf_compat
  # Many asdf plugins call `asdf` from inside their hooks. Put the translating
  # compat shim on PATH for the hook only, never for the user's shell.
  if [ -x "$script" ]; then
    PATH="${POLYVM_COMPAT_DIR}:${PATH}" "$script" "$@"
  else
    PATH="${POLYVM_COMPAT_DIR}:${PATH}" bash "$script" "$@"
  fi
}

# Same, but fails loudly when the hook is missing.
polyvm_run_required_hook() {
  local plugin="$1" hook="$2"
  shift 2
  polyvm_plugin_has_hook "$plugin" "$hook" \
    || polyvm_die "plugin '$plugin' has no bin/${hook} hook, it does not follow the plugin contract"
  polyvm_run_hook "$plugin" "$hook" "$@"
}

# ---------------------------------------------------------------- commands

# polyvm_plugin_add <name> [git-url] [git-ref]
polyvm_plugin_add() {
  local name="$1" url="${2:-}" ref="${3:-}"
  polyvm_validate_plugin_name "$name"

  local dest
  dest="$(polyvm_plugin_path "$name")"
  if [ -d "$dest" ]; then
    polyvm_warn "plugin '$name' is already installed"
    return 0
  fi

  # A built-in wins over the index, so a first-party plugin is what you get
  # by default and no network call is needed.
  if [ -z "$url" ] && polyvm_builtin_plugin_exists "$name"; then
    polyvm_step "adding built-in plugin $name"
    mkdir -p "$POLYVM_PLUGIN_DIR"
    polyvm_builtin_plugin_copy "$name" "$dest"
    ASDF_PLUGIN_SOURCE_URL="builtin"
    POLYVM_PLUGIN_SOURCE_URL="builtin"
    export ASDF_PLUGIN_SOURCE_URL POLYVM_PLUGIN_SOURCE_URL
    polyvm_run_hook "$name" post-plugin-add || \
      polyvm_warn "the post-plugin-add hook for '$name' failed"
    polyvm_ok "added plugin $name"
    return 0
  fi

  if [ -z "$url" ]; then
    url="$(polyvm_plugin_index_url "$name")" \
      || polyvm_die "no plugin named '$name' in the index. Pass a git URL: polyvm plugin add $name <url>"
    [ -n "$url" ] || polyvm_die "the index entry for '$name' has no repository URL"
  fi

  polyvm_step "adding plugin $name from $url"
  mkdir -p "$POLYVM_PLUGIN_DIR"
  git clone --quiet "$url" "$dest" || {
    rm -rf "$dest"
    polyvm_die "could not clone $url"
  }
  if [ -n "$ref" ]; then
    ( cd "$dest" && git checkout --quiet "$ref" ) || {
      rm -rf "$dest"
      polyvm_die "could not check out ref '$ref' in $url"
    }
  fi

  # Record where it came from so `plugin list --urls` is honest.
  printf '%s\n' "$url" > "${dest}/.polyvm-source-url"

  ASDF_PLUGIN_SOURCE_URL="$url"
  POLYVM_PLUGIN_SOURCE_URL="$url"
  export ASDF_PLUGIN_SOURCE_URL POLYVM_PLUGIN_SOURCE_URL
  polyvm_run_hook "$name" post-plugin-add || \
    polyvm_warn "the post-plugin-add hook for '$name' failed"

  polyvm_ok "added plugin $name"
}

polyvm_plugin_remove() {
  local name="$1"
  polyvm_require_plugin "$name"

  local plugin_dir install_dir download_dir
  plugin_dir="$(polyvm_plugin_path "$name")"
  install_dir="${POLYVM_INSTALL_DIR}/${name}"
  download_dir="${POLYVM_DOWNLOAD_DIR}/${name}"

  polyvm_run_hook "$name" pre-plugin-remove || true

  polyvm_safe_rm_rf "$plugin_dir"
  [ -d "$install_dir" ] && polyvm_safe_rm_rf "$install_dir"
  [ -d "$download_dir" ] && polyvm_safe_rm_rf "$download_dir"
  polyvm_reshim_all
  polyvm_ok "removed plugin $name and every version it installed"
}

# polyvm_plugin_list [--urls] [--refs]
polyvm_plugin_list() {
  local show_urls="" show_refs=""
  local arg
  for arg in "$@"; do
    case "$arg" in
      --urls) show_urls=yes ;;
      --refs) show_refs=yes ;;
      *) polyvm_die "unknown option for plugin list: $arg" ;;
    esac
  done

  if ! polyvm_dir_has_entries "$POLYVM_PLUGIN_DIR"; then
    polyvm_info "no plugins installed. Add one with: polyvm plugin add <name>"
    return 0
  fi

  local dir name url ref
  for dir in "$POLYVM_PLUGIN_DIR"/*; do
    [ -d "$dir" ] || continue
    name="$(basename "$dir")"
    if [ -z "$show_urls" ] && [ -z "$show_refs" ]; then
      printf '%s\n' "$name"
      continue
    fi
    url=""
    ref=""
    [ -f "${dir}/.polyvm-source-url" ] && url="$(cat "${dir}/.polyvm-source-url")"
    # shellcheck disable=SC2015  # `|| true` is the fallback inside the subshell
    [ -z "$url" ] && url="$( cd "$dir" && git config --get remote.origin.url 2>/dev/null || true )"
    # shellcheck disable=SC2015
    ref="$( cd "$dir" && git rev-parse --short HEAD 2>/dev/null || true )"
    if [ -n "$show_urls" ] && [ -n "$show_refs" ]; then
      printf '%s\t%s\t%s\n' "$name" "$url" "$ref"
    elif [ -n "$show_urls" ]; then
      printf '%s\t%s\n' "$name" "$url"
    else
      printf '%s\t%s\n' "$name" "$ref"
    fi
  done
}

# polyvm_plugin_update <name|--all> [ref]
polyvm_plugin_update() {
  local target="$1" ref="${2:-}"
  if [ "$target" = "--all" ] || [ "$target" = "all" ]; then
    local dir
    if ! polyvm_dir_has_entries "$POLYVM_PLUGIN_DIR"; then
      polyvm_info "no plugins installed"
      return 0
    fi
    for dir in "$POLYVM_PLUGIN_DIR"/*; do
      [ -d "$dir" ] || continue
      polyvm_plugin_update_one "$(basename "$dir")" ""
    done
    return 0
  fi
  polyvm_plugin_update_one "$target" "$ref"
}

polyvm_plugin_update_one() {
  local name="$1" ref="${2:-}"
  polyvm_require_plugin "$name"
  local dir prev post
  dir="$(polyvm_plugin_path "$name")"

  if [ "$(cat "${dir}/.polyvm-source-url" 2>/dev/null)" = "builtin" ]; then
    polyvm_builtin_plugin_exists "$name" \
      || polyvm_die "plugin '$name' was installed as a built-in but polyvm no longer ships it"
    polyvm_step "refreshing built-in plugin $name"
    polyvm_builtin_plugin_copy "$name" "$dir"
    polyvm_run_hook "$name" post-plugin-update || \
      polyvm_warn "the post-plugin-update hook for '$name' failed"
    polyvm_ok "refreshed $name from the polyvm source tree"
    return 0
  fi

  [ -d "${dir}/.git" ] || {
    polyvm_warn "plugin '$name' is not a git checkout, skipping"
    return 0
  }

  # shellcheck disable=SC2015
  prev="$( cd "$dir" && git rev-parse HEAD 2>/dev/null || true )"
  polyvm_step "updating plugin $name"
  if [ -n "$ref" ]; then
    ( cd "$dir" && git fetch --quiet origin && git checkout --quiet "$ref" ) \
      || polyvm_die "could not check out '$ref' for plugin $name"
  else
    ( cd "$dir" && git fetch --quiet origin && git reset --quiet --hard "@{u}" 2>/dev/null ) \
      || ( cd "$dir" && git pull --quiet --ff-only ) \
      || polyvm_die "could not update plugin $name"
  fi
  # shellcheck disable=SC2015
  post="$( cd "$dir" && git rev-parse HEAD 2>/dev/null || true )"

  if [ "$prev" = "$post" ]; then
    polyvm_ok "$name is already up to date"
    return 0
  fi

  ASDF_PLUGIN_PREV_REF="$prev"
  ASDF_PLUGIN_POST_REF="$post"
  POLYVM_PLUGIN_PREV_REF="$prev"
  POLYVM_PLUGIN_POST_REF="$post"
  export ASDF_PLUGIN_PREV_REF ASDF_PLUGIN_POST_REF \
    POLYVM_PLUGIN_PREV_REF POLYVM_PLUGIN_POST_REF
  polyvm_run_hook "$name" post-plugin-update || \
    polyvm_warn "the post-plugin-update hook for '$name' failed"

  polyvm_ok "updated $name to ${post}"
}
