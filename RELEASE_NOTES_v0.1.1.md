A bug-fix and usability release. **If you installed 0.1.0 with the one-line
command, it did not work.** That is fixed here.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/dev-sriramp/polyvm/main/install.sh | bash
```

Already have polyvm? `polyvm update`.

## Fixed

**`curl … | bash` aborted immediately.** `install.sh` read `BASH_SOURCE[0]`
unguarded under `set -u`, and that variable is unset when a script arrives on
stdin. The documented install never ran. Only `bash install.sh` from a checkout
worked, which was the one form the tests covered.

**`install.sh` demanded `curl`**, so it refused to install on a minimal image
that ships only `wget`, even though polyvm uses whichever it finds everywhere
else.

**The built-in Python plugin was missing from the 0.1.0 tarball.**
`.gitignore` had `plugins/` without a leading slash, and git matches that at
any depth, so it also excluded `contrib/plugins`. `polyvm plugin add python`
silently fell back to the community asdf plugin. CI now fails if any source
file is gitignored or if a file the build references is untracked.

## Added

**Prerequisite checks that run before anything is downloaded.** Installing a
language that compiles from source used to fail like this:

```
configure: error: no acceptable C compiler found in $PATH
BUILD FAILED (Ubuntu 26.04 using python-build 2.8.4)
```

after a 25 MB download and a couple of minutes. Now:

```
==> checking the build prerequisites for Python
error: Python is compiled from source, and this machine is missing a C compiler.
  Install the toolchain:
    sudo apt-get update && sudo apt-get install -y build-essential
  Then run this again. Nothing was downloaded.
```

The check probes for each header by actually compiling against it, rather than
guessing at include paths, which differ across Debian multiarch, musl, macOS
SDKs and Homebrew prefixes. It detects your package manager and prints one
command with the right package names for apt, dnf, yum, apk, pacman, zypper or
brew. A missing compiler, `zlib`, `openssl` or `libffi` stops the install;
missing optional headers only warn, and name the standard library module you
would lose.

Run it yourself any time:

```sh
polyvm doctor python
```

Plugins expose this through a new optional `bin/preflight` hook, so any plugin
can refuse before a download. `POLYVM_SKIP_PREFLIGHT=1` overrides it.

**Browsing what you can install:**

```sh
polyvm plugin available          # every language you can add, installed ones marked
polyvm plugin available ruby     # narrowed
polyvm list-all python           # every version, in columns, with a count
```

Piped, both print bare names one per line with no decoration on either stream,
so `polyvm list-all python | grep 3.13` and `xargs polyvm plugin add` work.

**`POLYVM_PLUGIN_INDEX_DIR`** now lets an air-gapped or mirrored setup point at
its own clone of the plugin index.

## Changed

`polyvm plugin add` now tells you what to run next, since adding a plugin
installs nothing by itself.

## Upgrading

```sh
polyvm update
```

That moves you to the new release and refreshes built-in plugins. If you added
Python on 0.1.0 and only did a `git pull`, run `polyvm plugin update python` so
you get the bundled plugin rather than the copy made when you added it.

## Tested

91 assertions on every push across Ubuntu, Debian, Fedora, Alpine and macOS,
including the suite under stock macOS bash 3.2 and against busybox coreutils
with `wget` and no `curl`. CI installs a real Node runtime, checks the shim
works with no shell integration at all, and builds CPython from source to
confirm `ssl`, `sqlite3`, `lzma`, `bz2`, `ctypes` and `readline` all survived.
