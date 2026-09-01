# Plugin API

A plugin is a git repository with executables under `bin/`. This is the asdf
plugin contract, unchanged, so any asdf plugin works with polyvm and any plugin
you write here works with asdf.

## Hooks

| Hook | Required | Purpose |
|---|---|---|
| `bin/list-all` | yes | Print every installable version, space separated, oldest first |
| `bin/install` | yes | Install into `$ASDF_INSTALL_PATH` |
| `bin/download` | no | Fetch into `$ASDF_DOWNLOAD_PATH` before install runs |
| `bin/list-bin-paths` | no | Directories holding executables, relative to the install path. Default `bin` |
| `bin/exec-env` | no | Sourced before a binary runs. Export what the runtime needs |
| `bin/exec-path` | no | Remap a binary path. Args: install path, command, default relative path |
| `bin/latest-stable` | no | Resolve `latest`. Arg: an optional filter |
| `bin/uninstall` | no | Custom removal. The directory is removed either way |
| `bin/post-plugin-add` | no | Runs after the plugin is added |
| `bin/post-plugin-update` | no | Runs after the plugin is updated |
| `bin/pre-plugin-remove` | no | Runs before the plugin is removed |
| `bin/list-legacy-filenames` | no | Legacy version files, for example `.node-version` |
| `bin/parse-legacy-file` | no | Read a version out of a legacy file |

`list-all` must print oldest first. `polyvm latest` takes the last line after
filtering out prereleases.

## Environment

polyvm exports both `ASDF_` and `POLYVM_` names. Use whichever you prefer; a
plugin meant to work in both tools should use the `ASDF_` names.

During `install` and `download`:

| Variable | Value |
|---|---|
| `ASDF_INSTALL_TYPE` | `version` or `ref` |
| `ASDF_INSTALL_VERSION` | The version, or the git ref when the type is `ref` |
| `ASDF_INSTALL_PATH` | Where the finished install must end up |
| `ASDF_DOWNLOAD_PATH` | Scratch space for the download hook |
| `ASDF_CONCURRENCY` | Suggested build parallelism |

Always available in a hook:

| Variable | Value |
|---|---|
| `ASDF_DIR` | The polyvm source directory |
| `ASDF_DATA_DIR` | The polyvm data directory |
| `ASDF_PLUGIN_PATH` | This plugin's directory |

During `post-plugin-add`: `ASDF_PLUGIN_SOURCE_URL`.
During `post-plugin-update`: `ASDF_PLUGIN_PREV_REF` and `ASDF_PLUGIN_POST_REF`.

## Calling polyvm from a hook

Plugins that call `asdf` from inside their hooks work as is. polyvm puts a
translating `asdf` on `PATH` for the duration of a hook, so `asdf reshim`,
`asdf where` and `asdf list` all reach polyvm. That shim is not on your own
`PATH`, only the hook's.

## A minimal plugin

```
polyvm-mylang/
└── bin/
    ├── list-all
    └── install
```

`bin/list-all`:

```bash
#!/usr/bin/env bash
set -euo pipefail
curl -fsSL https://api.example.com/versions \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
  | sort -V \
  | tr '\n' ' '
```

`bin/install`:

```bash
#!/usr/bin/env bash
set -euo pipefail

[ "$ASDF_INSTALL_TYPE" = "version" ] || {
  echo "mylang can only install released versions" >&2
  exit 1
}

case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=darwin ;;
  *) echo "unsupported OS" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) echo "unsupported architecture" >&2; exit 1 ;;
esac

url="https://example.com/mylang-${ASDF_INSTALL_VERSION}-${os}-${arch}.tar.gz"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL "$url" -o "$tmp/dist.tar.gz"
tar -xzf "$tmp/dist.tar.gz" -C "$tmp" --strip-components=1

mkdir -p "$ASDF_INSTALL_PATH"
cp -R "$tmp"/. "$ASDF_INSTALL_PATH/"
chmod +x "$ASDF_INSTALL_PATH"/bin/*
```

Make the hooks executable, commit, then:

```sh
polyvm plugin add mylang /path/to/polyvm-mylang
polyvm install mylang latest
```

A local path works as a git URL, which is the fastest way to iterate.

## Declaring what a language needs to build

A language that compiles from source needs a toolchain and development headers.
polyvm checks for them before anything is downloaded, and offers to install what
is missing. That check is driven by a file, not by code, so adding a language
means adding `contrib/requirements/<plugin>`:

```
# kind|spec|required|why|apt|dnf|apk|pacman|zypper|brew
tool|cc|yes|a C compiler, without which nothing can be compiled|build-essential|gcc|build-base|base-devel|gcc|
header|openssl/ssl.h|yes|no https, so gem install fails|libssl-dev|openssl-devel|openssl-dev|openssl|libopenssl-devel|openssl@3
header|readline/readline.h|no|no history or line editing|libreadline-dev|readline-devel|readline-dev|readline|readline-devel|readline
```

Ten pipe separated fields:

| Field | Meaning |
|---|---|
| `kind` | `tool` for a command that must exist, `header` for a C header |
| `spec` | The command name, or the header as you would `#include` it |
| `required` | `yes` stops the install when missing, `no` only warns |
| `why` | What breaks without it. This is shown to the user, so make it concrete |
| the rest | The package providing it for apt, dnf, apk, pacman, zypper and brew. Leave a field empty where there is no such package |

Headers are checked by compiling a program that includes them, not by looking
in `/usr/include`, because include paths differ across Debian multiarch, musl,
macOS SDKs and Homebrew prefixes. On macOS the Homebrew formula in the last
column is checked instead, since a Homebrew header is never on the default
include path.

Write the `why` field for someone who does not already know. "no ssl module, so
pip cannot reach the network" tells them what they lose;
"libssl-dev is missing" does not.

A plugin can also ship a `bin/preflight` hook for checks only it can make, such
as whether the requested version exists. It runs before the requirements check.

## Rules that matter

- Detect the OS and the architecture. Apple Silicon and arm64 Linux are common
  now, and a plugin that hardcodes x86_64 installs a binary that cannot run.
- Write only inside `$ASDF_INSTALL_PATH`. polyvm removes it if you fail.
- Print progress to stderr and keep stdout for data. `list-all` output is parsed.
- Exit non-zero on failure. A silent partial install is worse than a clean error.
