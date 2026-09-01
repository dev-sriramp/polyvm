#!/usr/bin/env bash
# polyvm self-update checks.
#
# The goal is a one line notice when a newer polyvm exists, and never a command
# that feels slower because of it. So:
#
#   - the check result is cached and only refreshed once a day
#   - the refresh runs in the background and never blocks the command you ran
#   - the notice comes from the cache, so it costs one file read
#   - exec-shim, which runs on every `python` or `node` invocation, never
#     checks at all
#   - it is off in CI and can be turned off entirely

POLYVM_UPDATE_INTERVAL_HOURS="${POLYVM_UPDATE_INTERVAL_HOURS:-24}"

polyvm_update_cache_file() {
  printf '%s\n' "${POLYVM_DATA_DIR}/.update-check"
}

polyvm_update_check_enabled() {
  [ "${POLYVM_UPDATE_CHECK:-auto}" != "never" ] || return 1
  [ -z "${POLYVM_NO_UPDATE_CHECK:-}" ] || return 1
  # Nobody reads an upgrade notice in a CI log.
  [ -z "${CI:-}" ] || return 1
  [ -d "${POLYVM_DIR}/.git" ] || return 1
  return 0
}

polyvm_update_cache_fresh() {
  local file
  file="$(polyvm_update_cache_file)"
  [ -f "$file" ] || return 1
  # find -mmin is portable across GNU and BSD.
  [ -n "$(find "$file" -mmin "-$((POLYVM_UPDATE_INTERVAL_HOURS * 60))" 2>/dev/null)" ]
}

# Highest vX.Y.Z tag on the remote. Uses git rather than a host specific API,
# so it works on GitHub, GitLab or a private mirror without a token.
polyvm_update_latest_remote() {
  local remote
  # shellcheck disable=SC2015  # `|| true` is the fallback inside the subshell
  remote="$( cd "$POLYVM_DIR" && git config --get remote.origin.url 2>/dev/null || true )"
  [ -n "$remote" ] || return 1

  git ls-remote --tags --refs "$remote" 2>/dev/null \
    | awk '{print $2}' \
    | sed -e 's|refs/tags/||' -e 's/^v//' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | polyvm_version_sort \
    | tail -n1
}

# Sort dotted versions oldest first without sort -V, which stock macOS sort
# does not have.
polyvm_version_sort() {
  awk '
    {
      out = ""
      rest = $0
      while (match(rest, /[0-9]+/)) {
        out = out substr(rest, 1, RSTART - 1) sprintf("%08d", substr(rest, RSTART, RLENGTH) + 0)
        rest = substr(rest, RSTART + RLENGTH)
      }
      printf "%s\t%s\n", out rest, $0
    }
  ' | LC_ALL=C sort | cut -f2-
}

# True when $1 is a strictly newer version than $2.
polyvm_version_gt() {
  [ "$1" != "$2" ] || return 1
  local newest
  newest="$(printf '%s\n%s\n' "$1" "$2" | polyvm_version_sort | tail -n1)"
  [ "$newest" = "$1" ]
}

# Refresh the cache in the background. Detached, output discarded, so a slow or
# offline network cannot make a polyvm command hang.
polyvm_update_refresh_async() {
  polyvm_update_check_enabled || return 0
  polyvm_update_cache_fresh && return 0

  local file
  file="$(polyvm_update_cache_file)"
  mkdir -p "$(dirname "$file")"
  # Touch first so a failing or slow check does not retry on every command.
  : > "$file"

  (
    latest="$(polyvm_update_latest_remote 2>/dev/null || true)"
    if [ -n "$latest" ]; then
      printf '%s\n' "$latest" > "$file"
    fi
  ) >/dev/null 2>&1 &
  # Detach so the shell never reports a background job.
  disown 2>/dev/null || true
  return 0
}

# Print the notice, if there is one. Always to stderr, so piping stdout is safe.
polyvm_update_notice() {
  polyvm_update_check_enabled || return 0

  local file latest
  file="$(polyvm_update_cache_file)"
  if [ -f "$file" ]; then
    latest="$(tr -d '[:space:]' < "$file" 2>/dev/null || true)"
    if [ -n "$latest" ] && polyvm_version_gt "$latest" "$POLYVM_VERSION"; then
      printf '\n' >&2
      printf '%spolyvm %s is available%s, you have %s\n' \
        "$POLYVM_C_YELLOW" "$latest" "$POLYVM_C_RESET" "$POLYVM_VERSION" >&2
      printf '  update with: %spolyvm update%s\n' \
        "$POLYVM_C_BLUE" "$POLYVM_C_RESET" >&2
      printf '  silence this: export POLYVM_UPDATE_CHECK=never\n' >&2
      printf '\n' >&2
    fi
  fi

  polyvm_update_refresh_async
}

# Check right now rather than from the cache. Used by `polyvm update`.
polyvm_update_latest_now() {
  local latest
  latest="$(polyvm_update_latest_remote 2>/dev/null || true)"
  if [ -n "$latest" ]; then
    printf '%s\n' "$latest" > "$(polyvm_update_cache_file)"
    printf '%s\n' "$latest"
    return 0
  fi
  return 1
}
