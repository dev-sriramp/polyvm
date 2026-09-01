# Installing polyvm

Works on Linux and macOS. Needs bash, git, curl and tar, and nothing else.
polyvm targets bash 3.2, so the bash that ships with macOS is enough.

## One line

```sh
curl -fsSL https://raw.githubusercontent.com/dev-sriramp/polyvm/main/install.sh | bash
```

Open a new shell, then:

```sh
polyvm doctor
```

The installer clones polyvm into `~/.polyvm` and adds a marked block to your
`.bashrc` and `.zshrc`. Re-running it replaces that block rather than appending
another copy.

## Pinning a release

```sh
POLYVM_REF=v0.1.0 bash -c "$(curl -fsSL https://raw.githubusercontent.com/dev-sriramp/polyvm/v0.1.0/install.sh)"
```

## From a clone

If you would rather read the script before running it, which is a reasonable
thing to want from something that edits your shell config:

```sh
git clone https://github.com/dev-sriramp/polyvm.git ~/.polyvm
cd ~/.polyvm
less install.sh
./install.sh
```

## In a Linux container

```sh
# Debian or Ubuntu
apt-get update && apt-get install -y bash git curl ca-certificates tar

# Fedora
dnf install -y bash git curl tar

# Alpine
apk add --no-cache bash git curl tar
```

Then install and use it. Containers usually run as root with no login shell, so
source the integration explicitly:

```sh
curl -fsSL https://raw.githubusercontent.com/dev-sriramp/polyvm/main/install.sh | bash
. ~/.polyvm/polyvm.sh

polyvm doctor
polyvm plugin add nodejs
polyvm install nodejs 22.14.0
polyvm global nodejs 22.14.0
node --version
```

In a Dockerfile, put the integration in the image environment rather than
sourcing it per layer:

```dockerfile
FROM debian:12

RUN apt-get update \
 && apt-get install -y --no-install-recommends bash git curl ca-certificates tar \
 && rm -rf /var/lib/apt/lists/*

ENV POLYVM_DIR=/opt/polyvm
ENV PATH=/opt/polyvm/shims:$PATH
ENV POLYVM_UPDATE_CHECK=never

RUN curl -fsSL https://raw.githubusercontent.com/dev-sriramp/polyvm/main/install.sh | POLYVM_NO_RC=1 bash

RUN polyvm plugin add nodejs \
 && polyvm install nodejs 22.14.0 \
 && polyvm global nodejs 22.14.0

# The shims are on PATH, so this works in every later layer and at runtime
RUN node --version
```

`POLYVM_NO_RC=1` skips the shell rc edits, which are pointless in an image, and
`PATH` carries the shims instead. `POLYVM_UPDATE_CHECK=never` keeps build logs
clean.

## Choosing where it goes

| Variable | Effect |
|---|---|
| `POLYVM_DIR` | Where polyvm is installed. Default `~/.polyvm` |
| `POLYVM_DATA_DIR` | Where plugins and runtimes live. Defaults to `POLYVM_DIR`. Split them to put runtimes on a different disk |
| `POLYVM_REF` | Branch or tag to install |
| `POLYVM_REPO` | Clone from a fork or a mirror |
| `POLYVM_NO_RC` | `1` to skip editing shell rc files |

For a system wide install:

```sh
sudo POLYVM_DIR=/opt/polyvm POLYVM_NO_RC=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/dev-sriramp/polyvm/main/install.sh)"
```

Then each user adds this to their own rc file:

```sh
export POLYVM_DIR=/opt/polyvm
export POLYVM_DATA_DIR="$HOME/.polyvm"
. "$POLYVM_DIR/polyvm.sh"
```

Sharing `POLYVM_DIR` while giving each user their own `POLYVM_DATA_DIR` means
one copy of polyvm and separate runtimes per user.

## Wiring it up by hand

If you skipped the rc changes, or use a shell the installer does not know:

```sh
polyvm init bash    # prints the three lines to add
polyvm init zsh
```

The minimum that makes polyvm work is the shims directory on `PATH`:

```sh
export PATH="$HOME/.polyvm/shims:$PATH"
```

Sourcing `polyvm.sh` on top of that adds `polyvm shell` and completions.

## Updating

```sh
polyvm update
```

polyvm checks for a new release at most once a day, in the background, and
prints a one line notice on your next command. Silence it with
`POLYVM_UPDATE_CHECK=never`.

## Uninstalling

```sh
~/.polyvm/uninstall.sh
```

Removes `~/.polyvm`, every runtime installed through it, and the block from
your rc files. Open a new shell afterwards to drop the shims from `PATH`.

## If something is wrong

```sh
polyvm doctor
```

It checks the required tools, whether the shims are on `PATH`, and whether the
shell integration is loaded, and prints the exact line to add when something is
missing.

**`polyvm: command not found`** means you have not opened a new shell, or the
rc block went into a file your shell does not read. `zsh` reads `.zshrc`, and a
non-interactive `bash` reads neither `.bashrc` nor `.bash_profile`, which is why
the shims on `PATH` matter more than the integration.

**`node: command not found` after installing it** means no version is selected.
Run `polyvm global nodejs <version>`.

**A command runs the wrong version** is answered by `polyvm which <command>`
and `polyvm current`, which shows the file each version came from.
