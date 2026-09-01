# Python

Python ships with polyvm. There is no plugin to hunt for and no repository to
add:

```sh
polyvm plugin add python
polyvm install python 3.13.1
polyvm global python 3.13.1
```

Everything pyenv does, polyvm does with the same commands it uses for every
other language.

## pyenv equivalents

| pyenv | polyvm |
|---|---|
| (no equivalent) | `polyvm doctor python` |
| `pyenv install --list` | `polyvm list-all python` |
| `pyenv install 3.13.1` | `polyvm install python 3.13.1` |
| `pyenv versions` | `polyvm list python` |
| `pyenv global 3.13.1` | `polyvm global python 3.13.1` |
| `pyenv local 3.13.1` | `polyvm local python 3.13.1` |
| `pyenv shell 3.13.1` | `polyvm shell python 3.13.1` |
| `pyenv version` | `polyvm current python` |
| `pyenv which python` | `polyvm which python` |
| `pyenv prefix` | `polyvm where python` |
| `pyenv rehash` | `polyvm reshim python` |
| `pyenv uninstall 3.13.1` | `polyvm uninstall python 3.13.1` |

An existing `.python-version` file works unchanged. polyvm reads it, so you can
switch without touching your projects.

## How it builds

polyvm compiles CPython from source using python-build, the builder that pyenv
itself uses. That is a deliberate choice: python-build carries a tested recipe
for every CPython, PyPy, GraalPy, Anaconda and Miniconda release, handles the
platform quirks that make Python awkward to compile, and is maintained by the
pyenv project. Around 1,090 versions are installable.

The first `polyvm plugin add python` clones the recipes into
`~/.polyvm/cache/python-build`. They refresh automatically, at most once a day
when you list versions, and immediately if you ask for a version the local
copy does not know about yet.

Installing happens in two steps. `bin/download` fetches the source tarball into
the download directory and verifies its SHA-256 against the checksum in the
recipe. `bin/install` then builds from that cached tarball, so a build you have
to retry does not download again.

## Build dependencies

Python needs a compiler and a set of development headers. Get this wrong and
you hit one of two bad outcomes: the build dies at `configure: error: no
acceptable C compiler found`, or, worse, it succeeds and hands you a Python
with no `ssl`, so `pip` fails weeks later with an error that says nothing about
the real cause.

polyvm checks before it downloads anything:

```sh
polyvm doctor python
```

The same check runs automatically at the start of every install. It probes by
actually compiling a program against each header rather than guessing at
include paths, because those differ across Debian multiarch, musl, macOS SDKs
and Homebrew prefixes. It then prints one command to copy for the package
manager you actually have.

A missing compiler or a missing `zlib`, `openssl` or `libffi` header stops the
install before a single byte is downloaded. Missing optional headers only warn,
and name the module you will lose.

**It offers to fix it rather than just complaining.** When it can, it prints
the exact command and asks:

```
Python is compiled from source, and this machine is missing things it needs:

    build-essential
        a C compiler, without which nothing can be compiled

  polyvm can install them with:

    sudo apt-get update && sudo apt-get install -y build-essential

  Install them now? [Y/n]
```

Say yes and it installs them, re-checks, and carries on with the build. Say no
and it stops, having downloaded nothing.

It only asks when there is a terminal to answer, and only when it can actually
install: as root, or with `sudo` available. Otherwise it reports the command and
tells you to run it yourself. It never installs anything without being asked
or told.

On macOS the same thing happens, with the right tools for the platform. The
compiler comes from the command line tools, so polyvm offers to run
`xcode-select --install`. The libraries come from Homebrew, so it checks which
formulas are actually installed rather than probing include paths, which never
contain Homebrew headers, and offers:

```
Python needs these Homebrew formulas and they are not installed:

    openssl@3
        no ssl module, so pip cannot reach the network
    tcl-tk
        no tkinter, so IDLE and turtle will not run

  polyvm can install them with:

    brew install openssl@3 tcl-tk

  Install them now? [Y/n]
```

This is the step people miss most often with pyenv, and the reason a
Mac-built Python so often has no `ssl` or `readline`.

| `POLYVM_INSTALL_DEPS` | Effect |
|---|---|
| unset or `ask` | Prompt when a terminal is present, report otherwise |
| `yes` | Install without asking. For Dockerfiles and CI |
| `no` | Never install, just report |

`POLYVM_SKIP_PREFLIGHT=1` skips the whole check.

The version is validated too, so you never install a toolchain for a version
that does not exist:

```
$ polyvm install python 3.17
error: there is no Python 3.17.
  See everything:  polyvm list-all python
  Newest stable:   polyvm install python latest
```

**macOS**

```sh
xcode-select --install
brew install openssl@3 readline sqlite3 xz zlib tcl-tk
```

polyvm finds those Homebrew formulas automatically and points the build at
them. This is the step most people miss, and it is why a Mac-built Python so
often ends up without ssl or readline.

**Debian and Ubuntu**

```sh
sudo apt-get install -y build-essential zlib1g-dev libssl-dev libbz2-dev \
  libffi-dev libsqlite3-dev libreadline-dev liblzma-dev libncursesw5-dev \
  tk-dev uuid-dev
```

**Fedora and RHEL**

```sh
sudo dnf install -y gcc make zlib-devel openssl-devel bzip2-devel libffi-devel \
  sqlite-devel readline-devel xz-devel ncurses-devel tk-devel libuuid-devel
```

Check what you ended up with:

```sh
python -c "import ssl, sqlite3, lzma, bz2, ctypes, readline; print('ok')"
```

## Options

| Variable | Default | Effect |
|---|---|---|
| `POLYVM_PYTHON_OPTIMIZE` | `yes` | Builds with `--enable-optimizations --with-lto`. Slower to build, faster at runtime. Set to `no` for a quick install |
| `PYTHON_CONFIGURE_OPTS` | empty | Passed through to configure, for example `--enable-shared` |
| `MAKE_OPTS` | `-j<cpus>` | Build parallelism |
| `POLYVM_CONCURRENCY` | CPU count | What `MAKE_OPTS` derives from |
| `POLYVM_DEBUG` | unset | Show the full build log |

A build takes a few minutes with optimizations on, about one minute without.

## Default packages

To get the same tooling in every Python you install, list the packages one per
line in `~/.polyvm/default-python-packages`:

```
pip
setuptools
wheel
ipython
```

They are installed into each new version right after the build. This is the
same idea as the pyenv-default-packages plugin.

## What is not supported

`polyvm install python ref:main` does not work. python-build builds from
released source tarballs, not arbitrary git refs. For a development build use a
dev recipe:

```sh
polyvm install python 3.15-dev
```

Building on native Windows is not supported. See [windows.md](windows.md).

## Other Python distributions

`polyvm list-all python` includes more than CPython:

```sh
polyvm install python pypy3.11-7.3.22
polyvm install python miniconda3-3.12-24.5.0-0
polyvm install python graalpy-24.1.1
```

`polyvm latest python` deliberately returns only plain CPython releases, never
a prerelease and never an alternative implementation.
