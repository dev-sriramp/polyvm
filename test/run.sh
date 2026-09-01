#!/usr/bin/env bash
# polyvm test suite. No network required: it builds a local fixture plugin
# and drives the real CLI against a throwaway POLYVM_DIR.
#
#   ./test/run.sh

set -uo pipefail

REPO="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/polyvm-test.XXXXXX")"
export POLYVM_DIR="$REPO"
export POLYVM_DATA_DIR="${WORK}/data"
export POLYVM_YES=1
# No test may ever open an interactive prompt: `make test` from a terminal
# would hang waiting for an answer nobody expects to give.
export POLYVM_INSTALL_DEPS=no
export NO_COLOR=1
POLYVM="${REPO}/bin/polyvm"

PASS=0
FAIL=0

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

pass() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$desc"
  else
    fail "$desc" "expected [$expected] got [$actual]"
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  case "$haystack" in
    *"$needle"*) pass "$desc" ;;
    *) fail "$desc" "expected to find [$needle] in [$haystack]" ;;
  esac
}

assert_ok() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc" "command failed: $*"
  fi
}

assert_fails() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$desc" "command unexpectedly succeeded: $*"
  else
    pass "$desc"
  fi
}

# ------------------------------------------------- fixture plugin as a repo

make_fixture_plugin() {
  local dir="${WORK}/fixtures/demo"
  mkdir -p "${dir}/bin"

  cat > "${dir}/bin/list-all" <<'HOOK'
#!/usr/bin/env bash
echo "1.0.0 1.1.0 2.0.0 2.1.0-rc1"
HOOK

  cat > "${dir}/bin/install" <<'HOOK'
#!/usr/bin/env bash
set -e
mkdir -p "${ASDF_INSTALL_PATH}/bin"
cat > "${ASDF_INSTALL_PATH}/bin/demotool" <<TOOL
#!/usr/bin/env bash
echo "demotool ${ASDF_INSTALL_VERSION} env=\${DEMO_ENV:-unset} args=\$*"
TOOL
chmod +x "${ASDF_INSTALL_PATH}/bin/demotool"
HOOK

  cat > "${dir}/bin/list-bin-paths" <<'HOOK'
#!/usr/bin/env bash
echo "bin"
HOOK

  cat > "${dir}/bin/exec-env" <<'HOOK'
export DEMO_ENV=set
HOOK

  chmod +x "${dir}/bin/list-all" "${dir}/bin/install" "${dir}/bin/list-bin-paths"

  ( cd "$dir" \
    && git init -q \
    && git config user.email test@polyvm.local \
    && git config user.name polyvm-test \
    && git add -A \
    && git commit -qm "fixture" )

  printf '%s\n' "$dir"
}

# ------------------------------------------------------------------- tests

# A local stand-in for the asdf plugin index. Set before any command runs, so
# the whole suite stays offline: nothing here should ever hit the network.
FAKE_INDEX="${WORK}/fake-index"
mkdir -p "${FAKE_INDEX}/.git" "${FAKE_INDEX}/plugins"
for fake in nodejs ruby golang elixir; do
  printf 'repository = https://example.invalid/%s.git\n' "$fake" > "${FAKE_INDEX}/plugins/${fake}"
done
touch "${FAKE_INDEX}/.polyvm-synced"
export POLYVM_PLUGIN_INDEX_DIR="$FAKE_INDEX"

printf 'polyvm test suite\n'
printf 'data dir: %s\n\n' "$POLYVM_DATA_DIR"

printf 'cli basics\n'
assert_contains "version prints a version" "$("$POLYVM" version)" "polyvm"
assert_contains "help mentions plugins" "$("$POLYVM" help)" "plugin add"
assert_fails "unknown command exits non-zero" "$POLYVM" definitely-not-a-command

printf '\nplugins\n'
FIXTURE="$(make_fixture_plugin)"
assert_ok "plugin add from a git url" "$POLYVM" plugin add demo "$FIXTURE"
assert_eq "plugin list shows demo" "demo" "$("$POLYVM" plugin list)"
assert_contains "plugin list --urls shows the source" "$("$POLYVM" plugin list --urls)" "$FIXTURE"
assert_fails "adding an invalid plugin name is rejected" "$POLYVM" plugin add "bad/name" "$FIXTURE"

printf '\nversion listing\n'
assert_contains "list-all returns versions" "$("$POLYVM" list-all demo)" "1.1.0"
assert_eq "latest skips prereleases" "2.0.0" "$("$POLYVM" latest demo)"
assert_eq "latest with a query filters" "1.1.0" "$("$POLYVM" latest demo 1.)"

printf '\ninstalling\n'
assert_ok "install a specific version" "$POLYVM" install demo 1.0.0
assert_ok "install latest" "$POLYVM" install demo latest
assert_contains "list shows both versions" "$("$POLYVM" list demo)" "1.0.0"
assert_contains "list shows the latest version" "$("$POLYVM" list demo)" "2.0.0"
assert_ok "reinstalling is a no-op" "$POLYVM" install demo 1.0.0

printf '\nshims\n'
assert_ok "a shim was generated" test -x "${POLYVM_DATA_DIR}/shims/demotool"
assert_contains "the shim records provenance" "$(cat "${POLYVM_DATA_DIR}/shims/demotool")" "polyvm-plugin: demo"

printf '\nversion selection\n'
assert_ok "set a global version" "$POLYVM" global demo 1.0.0
assert_contains "current reports the global version" "$("$POLYVM" current demo)" "1.0.0"
assert_contains "which points into the install dir" "$("$POLYVM" which demotool)" "installs/demo/1.0.0/bin/demotool"
assert_eq "the shim runs the global version" \
  "demotool 1.0.0 env=set args=" \
  "$(PATH="${POLYVM_DATA_DIR}/shims:$PATH" demotool)"

PROJECT="${WORK}/project"
mkdir -p "$PROJECT"
assert_ok "set a local version" bash -c "cd '$PROJECT' && '$POLYVM' local demo 2.0.0"
assert_ok "the local version file was written" test -f "${PROJECT}/.polyvm-versions"
assert_eq "the shim honours the directory version" \
  "demotool 2.0.0 env=set args=" \
  "$(cd "$PROJECT" && PATH="${POLYVM_DATA_DIR}/shims:$PATH" demotool)"
assert_eq "the global version still applies elsewhere" \
  "demotool 1.0.0 env=set args=" \
  "$(cd "$WORK" && PATH="${POLYVM_DATA_DIR}/shims:$PATH" demotool)"

printf '\nasdf compatibility\n'
ASDF_PROJECT="${WORK}/asdf-project"
mkdir -p "$ASDF_PROJECT"
printf 'demo 2.0.0\n' > "${ASDF_PROJECT}/.tool-versions"
assert_eq "a .tool-versions file is honoured" \
  "demotool 2.0.0 env=set args=" \
  "$(cd "$ASDF_PROJECT" && PATH="${POLYVM_DATA_DIR}/shims:$PATH" demotool)"

printf '\nenv var override\n'
assert_eq "POLYVM_DEMO_VERSION wins over the version files" \
  "demotool 1.0.0 env=set args=" \
  "$(cd "$PROJECT" && POLYVM_DEMO_VERSION=1.0.0 PATH="${POLYVM_DATA_DIR}/shims:$PATH" demotool)"
assert_eq "shell-env prints an export line" \
  "export POLYVM_DEMO_VERSION=1.0.0" \
  "$("$POLYVM" shell-env demo 1.0.0)"
assert_fails "shell-env rejects a version that is not installed" "$POLYVM" shell-env demo 9.9.9

printf '\nexec and env\n'
assert_contains "exec runs under the resolved version" \
  "$(cd "$PROJECT" && "$POLYVM" exec demo demotool one two)" "demotool 2.0.0"
assert_contains "exec passes arguments through" \
  "$(cd "$PROJECT" && "$POLYVM" exec demo demotool one two)" "args=one two"
assert_contains "where prints the install path" "$("$POLYVM" where demo 2.0.0)" "installs/demo/2.0.0"

printf '\nfallback versions\n'
FALLBACK="${WORK}/fallback"
mkdir -p "$FALLBACK"
printf 'demo 9.9.9 1.0.0\n' > "${FALLBACK}/.polyvm-versions"
assert_eq "the first installed version in the list wins" \
  "demotool 1.0.0 env=set args=" \
  "$(cd "$FALLBACK" && PATH="${POLYVM_DATA_DIR}/shims:$PATH" demotool)"

printf '\nerror paths\n'
NOTINST="${WORK}/notinstalled"
mkdir -p "$NOTINST"
printf 'demo 9.9.9\n' > "${NOTINST}/.polyvm-versions"
# shellcheck disable=SC2015  # `|| true` is the fallback inside the subshell
ERR_OUT="$(cd "$NOTINST" && PATH="${POLYVM_DATA_DIR}/shims:$PATH" demotool 2>&1 || true)"
assert_contains "a missing version names the version" "$ERR_OUT" "demo 9.9.9"
assert_contains "a missing version suggests the install command" "$ERR_OUT" "polyvm install demo 9.9.9"
case "$ERR_OUT" in
  *"unbound variable"*) fail "the error path is free of unbound variables" "$ERR_OUT" ;;
  *) pass "the error path is free of unbound variables" ;;
esac
# shellcheck disable=SC2015
WHICH_ERR="$(cd "$NOTINST" && "$POLYVM" which demotool 2>&1 || true)"
assert_contains "which reports the missing version too" "$WHICH_ERR" "9.9.9"
UNMANAGED="$("$POLYVM" which definitely-not-a-command 2>&1 || true)"
assert_contains "an unmanaged command says so" "$UNMANAGED" "does not manage"

printf '\nreshim and removal\n'
assert_ok "reshim rebuilds everything" "$POLYVM" reshim
assert_ok "the shim survives a reshim" test -x "${POLYVM_DATA_DIR}/shims/demotool"
assert_ok "uninstall a version" "$POLYVM" uninstall demo 1.0.0
assert_ok "the install directory is gone" test ! -d "${POLYVM_DATA_DIR}/installs/demo/1.0.0"
assert_fails "uninstalling twice fails" "$POLYVM" uninstall demo 1.0.0
assert_ok "plugin remove" "$POLYVM" plugin remove demo
assert_ok "the plugin directory is gone" test ! -d "${POLYVM_DATA_DIR}/plugins/demo"
assert_ok "shims are cleaned up" test ! -e "${POLYVM_DATA_DIR}/shims/demotool"

printf '\nbuilt-in plugins\n'
BUILTIN_DIR="${WORK}/builtins"
mkdir -p "${BUILTIN_DIR}/embedded/bin"
cat > "${BUILTIN_DIR}/embedded/bin/list-all" <<'HOOK'
#!/usr/bin/env bash
echo "0.1.0 0.2.0"
HOOK
cat > "${BUILTIN_DIR}/embedded/bin/install" <<'HOOK'
#!/usr/bin/env bash
set -e
mkdir -p "${ASDF_INSTALL_PATH}/bin"
printf '#!/usr/bin/env bash\necho "embedded %s"\n' "$ASDF_INSTALL_VERSION" > "${ASDF_INSTALL_PATH}/bin/embedded"
chmod +x "${ASDF_INSTALL_PATH}/bin/embedded"
HOOK
cat > "${BUILTIN_DIR}/embedded/bin/list-legacy-filenames" <<'HOOK'
#!/usr/bin/env bash
echo ".embedded-version"
HOOK
cat > "${BUILTIN_DIR}/embedded/bin/parse-legacy-file" <<'HOOK'
#!/usr/bin/env bash
head -n1 "$1" | tr -d '[:space:]'
HOOK
chmod +x "${BUILTIN_DIR}"/embedded/bin/*
export POLYVM_BUILTIN_PLUGIN_DIR="$BUILTIN_DIR"

assert_ok "a built-in plugin is added with no git url and no network" "$POLYVM" plugin add embedded
assert_contains "the built-in is marked as such" "$("$POLYVM" plugin list --urls)" "builtin"
# Piped output carries no headings, markers or hints at all, on either stream,
# so it can be consumed by a script without filtering.
assert_eq "plugin search piped gives the bare name" "embedded" \
  "$("$POLYVM" plugin search embedded 2>/dev/null)"
assert_eq "piped output has no decoration on any stream" "embedded" \
  "$("$POLYVM" plugin search embedded 2>&1)"
assert_ok "updating a built-in re-copies it from the source tree" "$POLYVM" plugin update embedded
assert_ok "install from a built-in plugin" "$POLYVM" install embedded 0.2.0
assert_eq "the built-in's binary runs through a shim" \
  "embedded 0.2.0" \
  "$(cd "$WORK" && POLYVM_EMBEDDED_VERSION=0.2.0 PATH="${POLYVM_DATA_DIR}/shims:$PATH" embedded)"

printf '\nlegacy version files\n'
LEGACY="${WORK}/legacy"
mkdir -p "$LEGACY"
printf '0.2.0\n' > "${LEGACY}/.embedded-version"
assert_eq "a pyenv style .embedded-version file is honoured" \
  "embedded 0.2.0" \
  "$(cd "$LEGACY" && PATH="${POLYVM_DATA_DIR}/shims:$PATH" embedded)"
assert_fails "legacy files are ignored when POLYVM_LEGACY_VERSION_FILE=no" \
  env POLYVM_LEGACY_VERSION_FILE=no POLYVM_LOOKUP_DIR="$LEGACY" "$POLYVM" current embedded

printf '\npython plugin helpers\n'
PYHELPERS="${REPO}/contrib/plugins/python/lib/helpers.sh"
if [ -f "$PYHELPERS" ]; then
  assert_eq "version sort puts a release candidate before its release" \
    "3.13.0rc1 3.13.0 3.13.1" \
    "$(printf '3.13.1\n3.13.0\n3.13.0rc1\n' | bash -c ". '$PYHELPERS' >/dev/null 2>&1; sort_versions" | tr '\n' ' ' | sed 's/ $//')"
  assert_eq "the newest stable is last after sorting" \
    "3.14.7" \
    "$(printf '3.14.7\n3.9.1\n3.13.1\n' | bash -c ". '$PYHELPERS' >/dev/null 2>&1; sort_versions" | tail -n1)"
  assert_eq "a .python-version file parses to a bare version" \
    "3.13.1" \
    "$(printf '  3.13.1  \n' > "${WORK}/.python-version"; "${REPO}/contrib/plugins/python/bin/parse-legacy-file" "${WORK}/.python-version")"
  assert_contains "the plugin refuses a git ref with a useful message" \
    "$(ASDF_INSTALL_TYPE=ref ASDF_INSTALL_VERSION=main ASDF_INSTALL_PATH=/tmp/nope \
       "${REPO}/contrib/plugins/python/bin/install" 2>&1 || true)" \
    "not supported"
else
  fail "python plugin helpers are missing" "$PYHELPERS not found"
fi

printf '\nplatform helpers\n'
assert_contains "the OS is one polyvm supports" "linux darwin windows" "$(bash -c ". '${REPO}/lib/core.sh'; . '${REPO}/lib/util.sh'; polyvm_os")"
assert_eq "the exe suffix is empty off Windows" "" "$(bash -c ". '${REPO}/lib/core.sh'; . '${REPO}/lib/util.sh'; polyvm_exe_suffix")"
assert_eq "a shim name is unchanged off Windows" "python" "$(bash -c ". '${REPO}/lib/core.sh'; . '${REPO}/lib/util.sh'; polyvm_shim_name python")"

printf '\nupdate checks\n'
assert_ok "a newer version is detected" bash -c ". '${REPO}/lib/core.sh'; . '${REPO}/lib/util.sh'; . '${REPO}/lib/update.sh'; polyvm_version_gt 0.2.0 0.1.0"
assert_fails "an older version is not" bash -c ". '${REPO}/lib/core.sh'; . '${REPO}/lib/util.sh'; . '${REPO}/lib/update.sh'; polyvm_version_gt 0.1.0 0.2.0"
assert_fails "the same version is not newer" bash -c ". '${REPO}/lib/core.sh'; . '${REPO}/lib/util.sh'; . '${REPO}/lib/update.sh'; polyvm_version_gt 0.1.0 0.1.0"
assert_ok "10 sorts above 9, not below" bash -c ". '${REPO}/lib/core.sh'; . '${REPO}/lib/util.sh'; . '${REPO}/lib/update.sh'; polyvm_version_gt 0.10.0 0.9.0"
assert_eq "version sort orders releases correctly" \
  "0.1.0 0.9.0 0.10.0 1.0.0" \
  "$(printf '1.0.0\n0.10.0\n0.1.0\n0.9.0\n' | bash -c ". '${REPO}/lib/core.sh'; . '${REPO}/lib/util.sh'; . '${REPO}/lib/update.sh'; polyvm_version_sort" | tr '\n' ' ' | sed 's/ $//')"
assert_fails "checks are disabled under CI" \
  env CI=1 POLYVM_DIR="$REPO" bash -c ". '${REPO}/lib/core.sh'; polyvm_init_paths; . '${REPO}/lib/util.sh'; . '${REPO}/lib/update.sh'; polyvm_update_check_enabled"
assert_fails "checks are disabled by POLYVM_UPDATE_CHECK=never" \
  env POLYVM_UPDATE_CHECK=never POLYVM_DIR="$REPO" bash -c ". '${REPO}/lib/core.sh'; polyvm_init_paths; . '${REPO}/lib/util.sh'; . '${REPO}/lib/update.sh'; polyvm_update_check_enabled"
assert_eq "the reported version comes from the VERSION file" \
  "$(tr -d '[:space:]' < "${REPO}/VERSION")" \
  "$("$POLYVM" version | awk '{print $2}')"

printf '\npreflight\n'
# A plugin can refuse before anything is downloaded. This is what stops a user
# discovering they have no C compiler after a 25 MB download.
PREFIX_PLUGIN="${WORK}/fixtures/picky"
mkdir -p "${PREFIX_PLUGIN}/bin"
cat > "${PREFIX_PLUGIN}/bin/list-all" <<'HOOK'
#!/usr/bin/env bash
echo "1.0.0"
HOOK
cat > "${PREFIX_PLUGIN}/bin/download" <<'HOOK'
#!/usr/bin/env bash
mkdir -p "$ASDF_DOWNLOAD_PATH"
touch "${ASDF_DOWNLOAD_PATH}/downloaded-marker"
HOOK
cat > "${PREFIX_PLUGIN}/bin/install" <<'HOOK'
#!/usr/bin/env bash
mkdir -p "${ASDF_INSTALL_PATH}/bin"
printf '#!/usr/bin/env bash\necho picky\n' > "${ASDF_INSTALL_PATH}/bin/picky"
chmod +x "${ASDF_INSTALL_PATH}/bin/picky"
HOOK
cat > "${PREFIX_PLUGIN}/bin/preflight" <<'HOOK'
#!/usr/bin/env bash
if [ -f "${POLYVM_TEST_PREFLIGHT_PASS:-/nonexistent}" ]; then
  echo "prerequisites ok" >&2
  exit 0
fi
echo "error: you need the frobnicator. Install it with: apt-get install frob" >&2
exit 1
HOOK
chmod +x "${PREFIX_PLUGIN}"/bin/*
( cd "$PREFIX_PLUGIN" && git init -q && git config user.email t@polyvm.local \
  && git config user.name t && git add -A && git commit -qm fixture )
"$POLYVM" plugin add picky "$PREFIX_PLUGIN" >/dev/null 2>&1

PRE_OUT="$("$POLYVM" install picky 1.0.0 2>&1 || true)"
assert_contains "a failing preflight blocks the install" "$PRE_OUT" "not ready to build"
assert_contains "the plugin's own advice is shown" "$PRE_OUT" "frobnicator"
assert_contains "the escape hatch is offered" "$PRE_OUT" "POLYVM_SKIP_PREFLIGHT"
assert_ok "nothing was downloaded" test ! -e "${POLYVM_DATA_DIR}/downloads/picky/1.0.0/downloaded-marker"
assert_ok "nothing was installed" test ! -d "${POLYVM_DATA_DIR}/installs/picky/1.0.0"

DOCTOR_OUT="$("$POLYVM" doctor picky 2>&1 || true)"
assert_contains "doctor <plugin> runs the preflight" "$DOCTOR_OUT" "frobnicator"

touch "${WORK}/preflight-ok"
assert_ok "POLYVM_SKIP_PREFLIGHT bypasses the check" \
  env POLYVM_SKIP_PREFLIGHT=1 "$POLYVM" install picky 1.0.0
"$POLYVM" uninstall picky 1.0.0 >/dev/null 2>&1
assert_ok "a passing preflight lets the install proceed" \
  env POLYVM_TEST_PREFLIGHT_PASS="${WORK}/preflight-ok" "$POLYVM" install picky 1.0.0
assert_ok "doctor reports a plugin with no preflight" "$POLYVM" doctor embedded

printf '\nplugin discovery\n'
AVAIL="$("$POLYVM" plugin available 2>/dev/null)"
assert_contains "plugin available lists the index" "$AVAIL" "golang"
assert_contains "plugin available lists built-ins" "$AVAIL" "embedded"
assert_eq "piped output is one bare name per line" \
  "elixir golang nodejs ruby" \
  "$("$POLYVM" plugin available 2>/dev/null | grep -v embedded | sort | tr '\n' ' ' | sed 's/ $//')"
FILTERED="$("$POLYVM" plugin available ruby 2>/dev/null)"
assert_eq "a query filters the list" "ruby" "$FILTERED"
"$POLYVM" plugin remove picky >/dev/null 2>&1 || true
assert_contains "adding a plugin says what to do next" \
  "$("$POLYVM" plugin add picky "$PREFIX_PLUGIN" 2>&1 || true)" "polyvm list-all"
"$POLYVM" plugin remove picky >/dev/null 2>&1 || true

printf '\npiped install\n'
# curl | bash and bash -c "$(curl ...)" both leave BASH_SOURCE unset. Under
# set -u that aborted install.sh before it did anything, which broke the
# documented one-line install. A bogus repo makes this offline: the script must
# reach the clone and fail there, not die reading BASH_SOURCE.
PIPE_OUT="$(POLYVM_DIR="${WORK}/pipe" POLYVM_REPO=/nonexistent-polyvm-repo POLYVM_NO_RC=1 \
  bash -c "$(cat "${REPO}/install.sh")" 2>&1 || true)"
case "$PIPE_OUT" in
  *"unbound variable"*) fail "install.sh survives being piped to bash" "$PIPE_OUT" ;;
  *) pass "install.sh survives being piped to bash" ;;
esac
case "$PIPE_OUT" in
  *"cloning polyvm"*|*"is required"*)
    pass "the piped install gets past self-location and into its real work" ;;
  *)
    fail "the piped install gets past self-location and into its real work" "$PIPE_OUT" ;;
esac

PIPE_STDIN="$(POLYVM_DIR="${WORK}/pipe2" POLYVM_REPO=/nonexistent-polyvm-repo POLYVM_NO_RC=1 \
  bash < "${REPO}/install.sh" 2>&1 || true)"
case "$PIPE_STDIN" in
  *"unbound variable"*) fail "install.sh survives curl | bash" "$PIPE_STDIN" ;;
  *) pass "install.sh survives curl | bash" ;;
esac

printf '\npython dependency install\n'
PYDEPS="${REPO}/contrib/plugins/python/lib"
pydeps() {
  bash -c ". '${PYDEPS}/helpers.sh' >/dev/null 2>&1; . '${PYDEPS}/deps.sh'; $1" < /dev/null
}
assert_eq "the apt install command is right" "apt-get install -y" "$(pydeps 'pkg_install_command apt')"
assert_eq "the apk install command is right" "apk add --no-cache" "$(pydeps 'pkg_install_command apk')"
assert_eq "only apt needs a refresh step" "" "$(pydeps 'pkg_update_command dnf')"
assert_eq "the full command joins refresh and install" \
  "sudo apt-get update && sudo apt-get install -y libssl-dev" \
  "$(pydeps 'full_install_command apt "sudo " " libssl-dev"')"
assert_eq "a package manager with no install command is refused" "" \
  "$(pydeps 'full_install_command unknown "" " x" || true')"
assert_fails "POLYVM_INSTALL_DEPS=no never installs" \
  bash -c ". '${PYDEPS}/helpers.sh' >/dev/null 2>&1; . '${PYDEPS}/deps.sh'; POLYVM_INSTALL_DEPS=no confirm_install x < /dev/null"
assert_ok "POLYVM_INSTALL_DEPS=yes installs without asking" \
  bash -c ". '${PYDEPS}/helpers.sh' >/dev/null 2>&1; . '${PYDEPS}/deps.sh'; POLYVM_INSTALL_DEPS=yes confirm_install x < /dev/null"
# shellcheck disable=SC2016  # the variable is expanded inside pydeps, not here
assert_contains "every required header names the package and the cost" \
  "$(pydeps 'printf "%s" "$POLYVM_PY_REQUIRED_HEADERS"')" "pip cannot reach the network"

# macOS takes a different path: Homebrew formulas rather than header probes,
# because a Homebrew header is never on the default include path.
MACSTUB="${WORK}/macstub"
mkdir -p "$MACSTUB" "${WORK}/brew/readline"
cat > "${MACSTUB}/uname" <<'HOOK'
#!/usr/bin/env bash
case "${1:-}" in
  -s) echo Darwin ;;
  -m) echo arm64 ;;
  *) echo Darwin ;;
esac
HOOK
cat > "${MACSTUB}/xcode-select" <<'HOOK'
#!/usr/bin/env bash
[ "${FAKE_NO_CLT:-}" = "1" ] && exit 2
[ "${1:-}" = "-p" ] && echo /Library/Developer/CommandLineTools
exit 0
HOOK
cat > "${MACSTUB}/brew" <<HOOK
#!/usr/bin/env bash
case "\${1:-}" in
  --prefix) d="${WORK}/brew/\$2"; [ -d "\$d" ] && { echo "\$d"; exit 0; }; exit 1 ;;
  install) shift; echo "\$*" >> "${WORK}/brew-install.log" ;;
esac
HOOK
# Stub the compiler too, so the macOS checks behave the same whether or not
# the machine running the tests happens to have one.
cat > "${MACSTUB}/cc" <<'HOOK'
#!/usr/bin/env bash
exit 0
HOOK
chmod +x "${MACSTUB}"/*

assert_eq "an installed formula is detected" "yes" \
  "$(PATH="${MACSTUB}:$PATH" bash -c ". '${PYDEPS}/helpers.sh' >/dev/null 2>&1; . '${PYDEPS}/deps.sh'; brew_formula_installed readline && echo yes || echo no" < /dev/null)"
assert_eq "a missing formula is detected" "no" \
  "$(PATH="${MACSTUB}:$PATH" bash -c ". '${PYDEPS}/helpers.sh' >/dev/null 2>&1; . '${PYDEPS}/deps.sh'; brew_formula_installed openssl@3 && echo yes || echo no" < /dev/null)"
assert_eq "macOS is detected through uname" "darwin" \
  "$(PATH="${MACSTUB}:$PATH" bash -c ". '${PYDEPS}/helpers.sh' >/dev/null 2>&1; plugin_os" < /dev/null)"
MAC_OUT="$(PATH="${MACSTUB}:$PATH" POLYVM_INSTALL_DEPS=no bash -c ". '${PYDEPS}/helpers.sh' >/dev/null 2>&1; . '${PYDEPS}/deps.sh'; python_preflight" < /dev/null 2>&1 || true)"
assert_contains "macOS names the missing formula" "$MAC_OUT" "openssl@3"
assert_contains "macOS offers a brew command" "$MAC_OUT" "brew install"
case "$MAC_OUT" in
  *"zlib1g-dev"*|*"apt-get"*) fail "macOS does not suggest Linux packages" "$MAC_OUT" ;;
  *) pass "macOS does not suggest Linux packages" ;;
esac
MAC_NOCLT="$(PATH="${MACSTUB}:$PATH" FAKE_NO_CLT=1 POLYVM_INSTALL_DEPS=no bash -c ". '${PYDEPS}/helpers.sh' >/dev/null 2>&1; . '${PYDEPS}/deps.sh'; python_preflight" < /dev/null 2>&1 || true)"
assert_contains "macOS without the command line tools says so" "$MAC_NOCLT" "xcode-select --install"

printf '\noffline guarantee\n'
# The suite must never reach the network. If it does, it is slow, it fails on a
# plane, and it stops being a reliable signal in CI.
assert_eq "the plugin index used is the local fixture" "$FAKE_INDEX" "$POLYVM_PLUGIN_INDEX_DIR"
NET_OUT="$("$POLYVM" plugin available 2>&1)"
case "$NET_OUT" in
  *"fetching the plugin index"*) fail "no command clones the plugin index" "$NET_OUT" ;;
  *) pass "no command clones the plugin index" ;;
esac

printf '\nguards\n'
assert_fails "commands on a missing plugin fail cleanly" "$POLYVM" list-all demo
assert_fails "install on a missing plugin fails cleanly" "$POLYVM" install demo 1.0.0

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
