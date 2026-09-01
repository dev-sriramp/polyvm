# Testing polyvm locally

polyvm installs shims onto your `PATH` and edits your shell rc files, so the
first rule of testing it is to not let a work-in-progress version take over the
shell you work in. Everything below keeps the two apart.

## The short version

```sh
cd /Volumes/External/polyvm

make check     # syntax, lint and the test suite
make sandbox   # install into a throwaway prefix and open a shell inside it
```

Inside the sandbox shell, `polyvm` is the version you are working on. Type
`exit` to leave, and nothing on your machine has changed.

## The test suite

```sh
make test
```

63 assertions, no network, a few seconds. It builds a fixture plugin in a temp
directory and drives the real CLI against a throwaway data directory, so it
exercises the actual install, shim generation, version resolution and removal
paths rather than mocking them.

Run it before every commit. If you change version resolution or shim dispatch,
add an assertion; those two are where the subtle bugs live.

## Linting

```sh
make lint
```

Needs shellcheck:

```sh
brew install shellcheck        # macOS
sudo apt-get install shellcheck # Debian and Ubuntu
```

The tree is currently shellcheck clean. Keep it that way. Where a warning is
wrong, silence it with a `# shellcheck disable=SCxxxx` comment and a reason,
not by loosening `.shellcheckrc`.

## The sandbox

```sh
./test/sandbox.sh              # set up, then open a subshell with it active
./test/sandbox.sh --no-shell   # set up only, print how to activate it
./test/sandbox.sh --clean      # delete it
```

It installs into `$TMPDIR/polyvm-sandbox/.polyvm` with `POLYVM_NO_RC=1`, so your
`.bashrc` and `.zshrc` are untouched and a real `~/.polyvm`, if you have one, is
left alone. Override the location with `POLYVM_SANDBOX=/path/to/dir`.

A full manual pass inside the sandbox:

```sh
polyvm doctor
polyvm plugin add python
polyvm list-all python | tail -20
polyvm latest python
polyvm install python 3.13.1        # a few minutes, it compiles
polyvm global python 3.13.1
python --version
python -c "import ssl, sqlite3, lzma, bz2, ctypes, readline; print('ok')"

mkdir -p /tmp/proj && cd /tmp/proj
polyvm local python 3.13.1
cat .polyvm-versions
polyvm current python

pip install cowsay
polyvm reshim python
cowsay -t hello

polyvm uninstall python 3.13.1
polyvm plugin remove python
```

The `import ssl, sqlite3, ...` line is the one that matters. A Python built
without the right headers still starts, and only fails later when something
imports a missing module.

## Testing without a full build

Compiling Python takes minutes, which is slow for iterating on the CLI. Two
ways around it:

```sh
POLYVM_PYTHON_OPTIMIZE=no polyvm install python 3.13.1
```

Skips `--enable-optimizations`, roughly a minute instead of several.

Or use a plugin that just downloads a binary:

```sh
polyvm plugin add nodejs
polyvm install nodejs 22.14.0
```

For CLI work that is enough, and it is what the test suite does with its own
fixture plugin.

## Testing in Linux containers

The point of testing in containers is not "does it work on Linux", it is
"is the dependency list honest". Each image gets bash, git, curl and tar and
nothing else, so if polyvm quietly depends on something beyond that, the run
fails and you find out before a user does.

```sh
make docker                        # every default image
./test/docker.sh alpine:3.20       # one image
./test/docker.sh --shell debian:12 # drop into a shell inside the image
```

Defaults: `ubuntu:24.04`, `ubuntu:22.04`, `debian:12`, `fedora:41`,
`alpine:3.20`. Podman works too, and is picked up automatically; force one with
`POLYVM_CONTAINER_RUNTIME=podman`.

Your checkout is mounted read only and copied inside the container, so nothing
a container does can touch your working tree.

**Alpine is the one that matters.** It uses busybox, so `awk`, `sed`, `grep`,
`sort`, `find` and `cut` are the reduced busybox implementations rather than
GNU. Most portability bugs show up there first, in the same class as the
GNU-versus-BSD differences on macOS. If a change passes on Alpine and on stock
macOS bash 3.2, it will pass everywhere.

If you already have a Linux container and want to run the suite by hand:

```sh
# inside the container, with the repo at /polyvm
apk add bash git curl tar          # alpine
apt-get update && apt-get install -y bash git curl tar   # debian, ubuntu
dnf install -y bash git curl tar   # fedora

cd /polyvm && ./test/run.sh
```

Then the real thing, which the CI integration job also does:

```sh
POLYVM_DIR=/root/.polyvm POLYVM_NO_RC=1 ./install.sh
. /root/.polyvm/polyvm.sh
polyvm doctor
polyvm plugin add nodejs
polyvm install nodejs 22.14.0
polyvm global nodejs 22.14.0
node --version

# the test that matters: no shell integration at all
env -i PATH=/root/.polyvm/shims:/usr/bin:/bin sh -c 'node --version'
```

## Testing the installer

```sh
POLYVM_DIR=/tmp/polyvm-install POLYVM_NO_RC=1 ./install.sh
```

Drop `POLYVM_NO_RC=1` only when you are deliberately testing the rc file
patching. It is idempotent, it replaces its own block rather than appending, but
check the diff on your rc file the first time.

To test the real curl-pipe path once the repo is public:

```sh
curl -fsSL https://raw.githubusercontent.com/dev-sriramp/polyvm/main/install.sh | bash
```

## Installing it for real

Once it behaves in the sandbox:

```sh
make install     # installs from this checkout into ~/.polyvm
```

Open a new shell, then `polyvm doctor`. To back it out:

```sh
make uninstall
```

## Cutting a release

```sh
make release VERSION=0.2.0
git push origin HEAD --follow-tags
```

`scripts/release.sh` refuses to run on a dirty tree, runs `make check`, bumps
the `VERSION` file, commits and tags `v0.2.0`. Pushing the tag triggers
`.github/workflows/release.yml`, which:

1. checks the tag and the `VERSION` file agree, so a mistagged release cannot ship
2. runs syntax, lint and the suite
3. installs from the tag on Ubuntu and macOS the same way a user would, through
   the curl-pipe path, and asserts the installed version matches the tag
4. publishes a GitHub release with notes generated from the commits

`VERSION` is the single source of truth. `lib/core.sh` reads it, so
`polyvm version` and the update check are always consistent with the tag.

## How the update notice works

Once `v0.2.0` is tagged, anyone still on `0.1.0` sees this the next time they
run a polyvm command:

```
polyvm 0.2.0 is available, you have 0.1.0
  update with: polyvm update
  silence this: export POLYVM_UPDATE_CHECK=never
```

The rules it follows, all in `lib/update.sh`:

- The version comes from `git ls-remote --tags` against whatever remote the
  install was cloned from. No GitHub API, so no token and no rate limit, and it
  works on a private mirror.
- The result is cached in `$POLYVM_DATA_DIR/.update-check` and refreshed at
  most once a day.
- The refresh runs detached in the background. A slow or unreachable network
  can never make a polyvm command hang.
- The notice itself is one file read, printed to stderr so piping stdout stays
  clean.
- `exec-shim` never checks. That runs on every `python` and `node` invocation
  and has to stay fast.
- Machine-readable commands (`which`, `where`, `current`, `list-all`, `latest`,
  `init`, `version`, `shell-env`) never print it either.
- It is off when `CI` is set, when `POLYVM_UPDATE_CHECK=never`, and when polyvm
  was not installed from git.

`polyvm update` checks immediately rather than from the cache, checks out the
newest release tag, and refreshes any built-in plugins so a bundled plugin does
not stay on the old copy.

To test the notice without waiting for a real release:

```sh
printf '99.0.0\n' > ~/.polyvm/.update-check
polyvm list
```

## Things worth knowing

**Filesystem.** The repo needs a filesystem that keeps the executable bit.
exFAT and FAT do not, so plugin hooks silently stop being runnable and git
reports spurious changes. If the repo lives on an external drive, check it:

```sh
diskutil info /Volumes/External | grep -i "File System"
```

APFS or HFS+ is fine. If it says exFAT, move the repo to your home directory.
`test/sandbox.sh` checks for this before it does anything else.

**git status on network and FUSE mounts** can report stale results because it
compares file stat data. If something looks wrong, force it:

```sh
git update-index --really-refresh
git status
```

**bash 3.2.** macOS ships bash 3.2 and polyvm targets it, but your Homebrew
bash is probably 5.x, so a bash 4 feature will pass locally and break for
everyone on a stock Mac. Test against the system bash:

```sh
/bin/bash --version
/bin/bash ./test/run.sh
```

No associative arrays, no `${var^^}`, no `mapfile`, no `&>>`.

**GNU versus BSD tools.** `sort -V`, `sed -i` with no argument, `readlink -f`
and `date -d` all differ or are missing on macOS. polyvm avoids all four. If
you reach for a flag, check `man` on macOS before using it.
