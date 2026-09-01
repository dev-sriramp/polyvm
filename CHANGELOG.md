# Changelog

Notable changes to polyvm. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and polyvm uses
[semantic versioning](https://semver.org/).

## [0.1.2] - 2026-09-01

### Added

- **polyvm offers to install missing build dependencies instead of only
  reporting them.** When a language cannot be built, the prerequisite check now
  prints the exact command and asks whether to run it. Say yes and it installs,
  re-checks and carries on with the build.
- `POLYVM_INSTALL_DEPS` controls that: `yes` installs without asking, for
  Dockerfiles and CI; `no` never installs; unset asks when a terminal is
  present.
- The requested version is validated before any of this, so you never install a
  toolchain for a version that does not exist. `polyvm install python 3.17` now
  says there is no such version and points at `polyvm list-all python`.
- macOS gets the same treatment with the right tools: polyvm offers to run
  `xcode-select --install` for the compiler, and `brew install` for the
  libraries. It checks which Homebrew formulas are installed rather than
  probing include paths, since a Homebrew header is never on the default
  include path, so the old check reported every library as missing.

### Changed

- The prerequisite check no longer prints the same install command twice.

### Notes

- polyvm never installs system packages without being asked or told. It only
  prompts when a terminal is there to answer and when it can actually install,
  meaning as root or with `sudo` available. Where it cannot, it reports the
  command for someone else to run. It will not prompt in CI, where a hung build
  waiting for input would be worse than a clear failure.

## [0.1.1] - 2026-09-01

### Added

- **Prerequisite checks before installing.** A new optional `bin/preflight`
  plugin hook runs before anything is downloaded, so a machine that cannot
  build a language says so up front instead of failing at `configure` after a
  25 MB download.
- The Python plugin implements it. It probes for a C compiler and each
  development header by compiling against them, rather than guessing at
  include paths, which differ across Debian multiarch, musl, macOS SDKs and
  Homebrew prefixes. It then prints a single copy-paste command with the right
  package names for apt, dnf, yum, apk, pacman, zypper or brew. A missing
  compiler, `zlib`, `openssl` or `libffi` stops the install; missing optional
  headers warn and name the standard library module that would be lost.
- `polyvm doctor <plugin>` runs that check on its own, without downloading
  anything.
- `POLYVM_SKIP_PREFLIGHT=1` to install anyway.
- `polyvm plugin available [query]` lists every language you can add, built-in
  and from the index, marking the ones already installed.
- `POLYVM_PLUGIN_INDEX_DIR` is honoured, so a mirrored or offline clone of the
  plugin index can be used instead of reaching GitHub.

### Changed

- `polyvm list-all` lays versions out in columns and follows them with a count
  and the command to install one, instead of printing 1,090 bare lines. Piped
  output is unchanged: one version per line, no decoration on either stream.
- `polyvm plugin add` now says what to run next, because adding a plugin
  installs nothing by itself.
- `polyvm plugin search` is an alias for `polyvm plugin available`.

### Fixed

- **`curl … | bash` aborted immediately** with `BASH_SOURCE[0]: unbound
  variable`. The documented one-line install never worked; only running
  `install.sh` as a file did, which is the one form the tests used.
- `install.sh` and `polyvm doctor` required `curl` specifically, refusing to
  install on a minimal image that ships only `wget`, which polyvm handles fine
  everywhere else.
- `POLYVM_PLUGIN_INDEX_DIR` was overwritten during path setup and could not be
  overridden.
- The `macos-13` CI runner has been retired and that job queued forever. The
  matrix moved to `macos-14` and every job now has a timeout.
- `.gitignore` used unanchored patterns. `plugins/` matches at any depth, so it
  also excluded `contrib/plugins` and kept the built-in Python plugin out of
  the repository entirely. All runtime-data patterns are now anchored to the
  repository root, and CI fails if any source file is ignored or if a file the
  build references is untracked.

### Notes

- The test suite now points at a local plugin-index fixture and asserts that no
  command clones anything, so it is genuinely offline and runs in about two
  seconds. 91 assertions, verified under busybox with `wget` and no `curl`.

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

[0.1.2]: https://github.com/dev-sriramp/polyvm/releases/tag/v0.1.2
[0.1.1]: https://github.com/dev-sriramp/polyvm/releases/tag/v0.1.1
[0.1.0]: https://github.com/dev-sriramp/polyvm/releases/tag/v0.1.0
