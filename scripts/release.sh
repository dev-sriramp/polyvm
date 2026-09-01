#!/usr/bin/env bash
# Cut a polyvm release.
#
#   ./scripts/release.sh 0.2.0
#
# Updates VERSION, commits, tags v0.2.0 and pushes. The release workflow in
# .github/workflows/release.yml takes it from there.

set -euo pipefail

REPO="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$REPO"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  printf 'usage: ./scripts/release.sh <version>   for example 0.2.0\n' >&2
  exit 1
fi

case "$VERSION" in
  [0-9]*.[0-9]*.[0-9]*) : ;;
  *) printf 'error: version must look like 0.2.0, got %s\n' "$VERSION" >&2; exit 1 ;;
esac

CURRENT="$(tr -d '[:space:]' < VERSION)"
if [ "$VERSION" = "$CURRENT" ]; then
  printf 'error: VERSION is already %s\n' "$VERSION" >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  printf 'error: the working tree is dirty. Commit or stash first.\n' >&2
  git status --short >&2
  exit 1
fi

if git rev-parse "v${VERSION}" >/dev/null 2>&1; then
  printf 'error: tag v%s already exists\n' "$VERSION" >&2
  exit 1
fi

printf '==> running the full check\n' >&2
make check

printf '==> bumping %s to %s\n' "$CURRENT" "$VERSION" >&2
printf '%s\n' "$VERSION" > VERSION
git add VERSION
git commit -q -m "Release ${VERSION}"
git tag -a "v${VERSION}" -m "polyvm ${VERSION}"

printf '\n' >&2
printf 'Tagged v%s locally. Push it with:\n' "$VERSION" >&2
printf '  git push origin HEAD --follow-tags\n' >&2
printf '\n' >&2
printf 'Anyone on an older polyvm will see the update notice within a day, or\n' >&2
printf 'immediately when they run: polyvm update\n' >&2
