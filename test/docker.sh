#!/usr/bin/env bash
# Run the polyvm test suite inside Linux containers.
#
#   ./test/docker.sh                  every default image
#   ./test/docker.sh alpine:3.20      one image
#   ./test/docker.sh --shell ubuntu:24.04   drop into a shell in that image
#
# The repo is mounted read only, so a container cannot modify your checkout.
# Each image installs only bash, git, curl and tar, which is exactly polyvm's
# stated dependency set. If a run fails on a distro, that dependency list is
# wrong, which is the point of testing this way.

set -uo pipefail

REPO="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

DEFAULT_IMAGES="ubuntu:24.04 ubuntu:22.04 debian:12 fedora:41 alpine:3.20"

RUNTIME="${POLYVM_CONTAINER_RUNTIME:-}"
if [ -z "$RUNTIME" ]; then
  if command -v docker >/dev/null 2>&1; then
    RUNTIME=docker
  elif command -v podman >/dev/null 2>&1; then
    RUNTIME=podman
  else
    printf 'error: neither docker nor podman is installed\n' >&2
    exit 1
  fi
fi

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_RED=""; C_GREEN=""; C_BLUE=""
fi

# Package install command per distro family.
prep_for() {
  case "$1" in
    ubuntu*|debian*)
      printf 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq >/dev/null && apt-get install -y -qq bash git curl ca-certificates tar >/dev/null'
      ;;
    fedora*|rockylinux*|almalinux*)
      printf 'dnf install -y -q bash git curl tar >/dev/null'
      ;;
    alpine*)
      printf 'apk add --no-cache -q bash git curl tar >/dev/null'
      ;;
    archlinux*)
      printf 'pacman -Sy --noconfirm --quiet bash git curl tar >/dev/null'
      ;;
    *)
      printf 'true'
      ;;
  esac
}

OPEN_SHELL=no
if [ "${1:-}" = "--shell" ]; then
  OPEN_SHELL=yes
  shift
fi

if [ $# -gt 0 ]; then
  IMAGES="$*"
else
  IMAGES="$DEFAULT_IMAGES"
fi

if [ "$OPEN_SHELL" = "yes" ]; then
  image="${IMAGES%% *}"
  printf '%s==>%s opening a shell in %s\n' "$C_BLUE" "$C_RESET" "$image" >&2
  exec "$RUNTIME" run --rm -it \
    -v "${REPO}:/src:ro" \
    -w /root \
    "$image" \
    sh -c "$(prep_for "$image"); cp -R /src /polyvm && cd /polyvm && exec bash -i"
fi

FAILED=""
PASSED=""

for image in $IMAGES; do
  printf '\n%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$image" >&2
  if "$RUNTIME" run --rm \
      -v "${REPO}:/src:ro" \
      -e NO_COLOR=1 \
      -e CI=1 \
      "$image" \
      sh -c "$(prep_for "$image") && cp -R /src /polyvm && chmod -R +x /polyvm/bin /polyvm/test /polyvm/contrib/plugins/*/bin 2>/dev/null; cd /polyvm && ./test/run.sh" 2>&1 | tail -5; then
    printf '%sok%s %s\n' "$C_GREEN" "$C_RESET" "$image" >&2
    PASSED="$PASSED $image"
  else
    printf '%sFAILED%s %s\n' "$C_RED" "$C_RESET" "$image" >&2
    FAILED="$FAILED $image"
  fi
done

printf '\n' >&2
printf 'passed:%s\n' "${PASSED:- none}" >&2
if [ -n "$FAILED" ]; then
  printf 'failed:%s\n' "$FAILED" >&2
  exit 1
fi
printf 'every image passed\n' >&2
