# Changelog

Notable changes to polyvm. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and polyvm uses
[semantic versioning](https://semver.org/).

## [0.1.0] - 2026-09-01

First release.

### Added

**Core**

- Shim based version management. Every executable a language installs gets a
  stub in `~/.polyvm/shims`, so the right version is used by cron jobs,
  Makefiles, editors and CI scripts that never source your shell config.
- Version resolution from `.polyvm-versions`, `.tool-versions`,
  `.python-version` style legacy files, and a global file, with per line
  fallback lists such as `nodejs 22.14.0 20.18.1`.
- `polyvm global`, `local` and `shell` for user wide, per directory and per
  shell selection.
- `install`, `uninstall`, `list`, `list-all`, `latest`, `current`, `where`,
  `which`, `exec`, `env`, `reshim`, `doctor`, `update` and `init`.
- Shell integration for bash and zsh, plus completions for both.
- `install.sh` and `uninstall.sh` with idempotent shell rc patching.

**Plugins**

- asdf compatible plugin contract, so every existing asdf plugin works
  unchanged and `polyvm plugin add <name>` resolves through the asdf plugin
  index.
- A translating `asdf` shim, scoped to hook execution, for the many plugins
  that shell out to `asdf` from inside their own hooks.
- Built in plugins under `contrib/plugins`, found before the index, so a first
  party plugin needs no network and no separate repository.

**Python**

- Bundled Python plugin that compiles CPython with python-build, the builder
  pyenv uses, covering around 1,090 versions including PyPy, GraalPy, Anaconda
  and Miniconda.
- Separate download and install steps. The source tarball is fetched and its
  SHA-256 verified first, so a retried build does not download again.
- Build dependency preflight that names the exact fix per platform, and
  automatic Homebrew wiring on macOS so a Mac built Python has ssl and readline.
- `default-python-packages` support, matching pyenv-default-packages.

**Release and tooling**

- Update notifications. polyvm checks for a newer release tag at most once a
  day, in a detached background process, and prints a one line notice on your
  next command. Off in CI and with `POLYVM_UPDATE_CHECK=never`.
- `polyvm update` moves to the newest release tag and refreshes built in
  plugins.
- GitHub Actions for lint, tests on Linux and macOS, the suite under stock
  macOS bash 3.2, a distro matrix, a real runtime install, a CPython source
  build, and a release workflow that refuses to publish when the tag and the
  `VERSION` file disagree.
- `test/sandbox.sh` for a throwaway local install, `test/docker.sh` for the
  distro matrix, `scripts/release.sh` for cutting a release.

### Notes

- Targets bash 3.2 so the bash that ships with macOS is enough. Verified
  against busybox coreutils, which is the Alpine userland.
- Windows is not supported yet. The platform seams are in place and the plan is
  in [docs/windows.md](docs/windows.md). WSL works today.

[0.1.0]: https://github.com/dev-sriramp/polyvm/releases/tag/v0.1.0
