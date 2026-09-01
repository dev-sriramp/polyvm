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

Python needs a compiler and a set of development headers. Without them Python
still builds but silently drops standard library modules, and you find out
later when `import ssl` fails. polyvm checks first and prints the exact command
for your platform.

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
