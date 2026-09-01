# polyvm

[![ci](https://github.com/dev-sriramp/polyvm/actions/workflows/ci.yml/badge.svg)](https://github.com/dev-sriramp/polyvm/actions/workflows/ci.yml)

One version manager for every language.

`pyenv` handles Python. `nvm` handles Node. `rbenv` handles Ruby. polyvm handles
all of them from a single tool, a single config file and a single place on disk.

```sh
polyvm plugin add python
polyvm install python 3.13.1
polyvm global python 3.13.1

polyvm plugin add nodejs
polyvm install nodejs 22.14.0
polyvm local nodejs 22.14.0
```

Python ships with polyvm. Every other language is one `polyvm plugin add` away.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/dev-sriramp/polyvm/main/install.sh | bash
```

Then open a new shell. The installer clones polyvm into `~/.polyvm` and adds a
block to your `.bashrc` and `.zshrc`.

Requirements: bash, git, tar, and either curl or wget. Linux and macOS. polyvm targets bash 3.2, so
the bash that ships with macOS is enough. Windows is a work in progress; WSL
works today. See [docs/windows.md](docs/windows.md).

To check the install:

```sh
polyvm doctor
```

polyvm tells you when a new release is out and updates itself:

```sh
polyvm update
```

Languages that compile from source need a toolchain. polyvm checks before it
downloads anything, and tells you exactly what to install:

```sh
polyvm doctor python
```

## How versions are chosen

polyvm reads a `.polyvm-versions` file, one line per language:

```
nodejs 22.14.0
python 3.13.1
ruby   3.4.1
```

Lookup order, first hit wins:

1. `polyvm shell <lang> <version>` for the current shell
2. the nearest `.polyvm-versions` walking up from the current directory
3. the nearest `.tool-versions` (asdf's file, read as is)
4. a legacy file such as `.python-version` or `.node-version`
5. the global file at `~/.polyvm/versions`

Commit `.polyvm-versions` and everyone on the project gets the same runtimes
with `polyvm install`.

## Why shims

Every executable a language installs gets a small stub in `~/.polyvm/shims`,
which sits on your `PATH`. Running `node` runs the stub, which asks polyvm which
version applies to the current directory and hands off to the real binary.

That means the right version is used by cron jobs, Makefiles, editors, CI
scripts and anything else that never sources your shell config. Tools that only
rewrite `PATH` in an interactive shell cannot do that.

## Languages

**Python is built in.** `polyvm plugin add python` needs no network lookup and
gives you every version pyenv can install, around 1,090 of them including PyPy,
GraalPy and Miniconda. Your existing `.python-version` files are read as is.
See [docs/python.md](docs/python.md).

For everything else:

```sh
polyvm plugin available          # every language you can add
polyvm plugin available rust     # narrowed down
polyvm plugin add rust
polyvm list-all rust             # every version you can install
```

Plugins follow the asdf plugin contract, so every existing asdf plugin works
unchanged and `polyvm plugin add <name>` resolves through the asdf plugin index.
Writing your own takes two shell scripts. See [docs/plugin-api.md](docs/plugin-api.md).

## Documentation

- [docs/install.md](docs/install.md) - installing, including in containers and Dockerfiles
- [docs/commands.md](docs/commands.md) - every command
- [docs/python.md](docs/python.md) - the built-in Python plugin, and the pyenv equivalents
- [docs/architecture.md](docs/architecture.md) - how it works and where files live
- [docs/plugin-api.md](docs/plugin-api.md) - writing a plugin
- [docs/asdf-compatibility.md](docs/asdf-compatibility.md) - what carries over from asdf
- [docs/windows.md](docs/windows.md) - where the Windows port stands
- [docs/development.md](docs/development.md) - testing polyvm locally

## Development

```sh
make check    # syntax, lint and the test suite
make sandbox  # install into a throwaway prefix and open a shell inside it
make docker   # run the suite in Ubuntu, Debian, Fedora and Alpine containers
make install  # install from this checkout into ~/.polyvm
```

`make sandbox` never touches your shell rc files or a real `~/.polyvm`, so you
can try a work-in-progress build without it taking over the shell you work in.
See [docs/development.md](docs/development.md).

## Contributing

Bug reports, plugins and pull requests are welcome. Read
[CONTRIBUTING.md](CONTRIBUTING.md) first, particularly the portability rules:
polyvm targets bash 3.2 and busybox, and both break quietly rather than loudly.

- [CONTRIBUTING.md](CONTRIBUTING.md) - setup, the rules, how to add a language
- [CHANGELOG.md](CHANGELOG.md) - what changed in each release
- [SECURITY.md](SECURITY.md) - reporting a vulnerability, and what polyvm does on your machine
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)

## License

polyvm is released under the [MIT License](LICENSE). You can use it, modify it
and ship it in commercial software; keep the copyright notice.

polyvm installs and runs code it does not own, and those pieces carry their own
licenses:

| Component | License | Note |
|---|---|---|
| polyvm | MIT | This repository |
| [python-build](https://github.com/pyenv/pyenv) | MIT | Vendored at runtime by the Python plugin, cloned into `~/.polyvm/cache`. Not redistributed here |
| [asdf plugin index](https://github.com/asdf-vm/asdf-plugins) | MIT | Cloned to resolve plugin names |
| Plugins you add | Their own | Each plugin is a separate repository with its own license |
| Language runtimes you install | Their own | CPython is under the PSF License, Node.js under MIT, and so on |

polyvm is not affiliated with pyenv, asdf, nvm or the Python Software
Foundation. It reuses their published interfaces and gives credit where it is
due, which is a lot: python-build in particular represents years of work on the
awkward parts of compiling Python, and polyvm would be far worse without it.
