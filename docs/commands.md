# Command reference

## Runtimes

### `polyvm install`

Install every plugin and version named by the version files in scope.

```sh
polyvm install
```

### `polyvm install <plugin> [version]`

Install one version. The version can be a literal, `latest`, `latest:<prefix>`
or `ref:<git-ref>` when the plugin supports building from source. With no
version, `latest` is used.

```sh
polyvm install nodejs 22.14.0
polyvm install nodejs latest
polyvm install nodejs latest:20
polyvm install nodejs ref:main
```

### `polyvm uninstall <plugin> <version>`

Remove an installed version and rebuild the shims.

### `polyvm list [plugin]`

Installed versions. The active one is marked with `*`.

### `polyvm list-all <plugin> [query]`

Every version the plugin can install, optionally filtered.

```sh
polyvm list-all python 3.13
```

### `polyvm latest <plugin> [query]`

The newest stable version. Prereleases are skipped.

## Choosing versions

### `polyvm global <plugin> <version> [fallback...]`

Write to `~/.polyvm/versions`. Applies everywhere unless something more specific
overrides it.

### `polyvm local <plugin> <version> [fallback...]`

Write to `.polyvm-versions` in the current directory. Applies to this directory
and everything under it. If the directory already has a `.tool-versions`, that
file is used instead so an existing asdf project stays intact.

### `polyvm shell <plugin> <version>`

Set the version for this shell only. Needs the shell integration, since only a
shell function can change the current shell.

```sh
polyvm shell nodejs 20.18.1
polyvm shell nodejs system
polyvm shell nodejs --unset
```

### `polyvm current [plugin]`

The active version for each plugin and the file or variable it came from.

```
nodejs           22.14.0          /home/you/work/api/.polyvm-versions
python           3.13.1           /home/you/.polyvm/versions
```

### `polyvm where <plugin> [version]`

The install directory for a version.

### `polyvm which <command>`

The binary a command would actually run.

## Plugins

### `polyvm plugin add <name> [git-url] [git-ref]`

Add a language. With no URL, polyvm looks for a built-in plugin first and falls
back to the asdf plugin index.

```sh
polyvm plugin add python                                       # built in
polyvm plugin add nodejs                                       # asdf index
polyvm plugin add mylang https://github.com/me/polyvm-mylang.git
```

Built-in plugins ship inside polyvm under `contrib/plugins/`. `polyvm plugin
update <name>` refreshes one from the polyvm source tree rather than from git.

### `polyvm plugin list [--urls] [--refs]`

### `polyvm plugin remove <name>`

Removes the plugin and every version it installed.

### `polyvm plugin update <name|--all> [ref]`

### `polyvm plugin search [query]`

Search the plugin index.

## Running things

### `polyvm exec <plugin> <command> [args]`

Run a command with a plugin's resolved version active, without going through a
shim.

```sh
polyvm exec nodejs npm test
```

### `polyvm env <plugin> [command]`

Print the environment a plugin would run under, or run a command in it.

### `polyvm reshim [plugin] [version]`

Rebuild the shims. Needed after a package manager installs a new global
executable, for example `npm install -g typescript`.

## Maintenance

### `polyvm doctor`

Check the installation: required tools, whether the shims are on `PATH`, whether
the shell integration is loaded.

### `polyvm update`

Update polyvm itself to the newest release tag. Checks the remote immediately
rather than using the cached answer, and refreshes any built-in plugins so they
do not stay on the previous copy.

polyvm checks for a newer release at most once a day, in the background, and
prints a one line notice on your next command. Turn it off with
`POLYVM_UPDATE_CHECK=never`. It is already off in CI.

### `polyvm init <bash|zsh>`

Print the shell integration snippet, for adding to an rc file by hand.

### `polyvm version`

## Environment variables

| Variable | Meaning |
|---|---|
| `POLYVM_DIR` | Where polyvm lives. Default `~/.polyvm` |
| `POLYVM_DATA_DIR` | Where plugins and runtimes live. Defaults to `POLYVM_DIR` |
| `POLYVM_<PLUGIN>_VERSION` | Force a version, highest priority |
| `POLYVM_CONCURRENCY` | Build parallelism passed to plugins. Defaults to the CPU count |
| `POLYVM_KEEP_DOWNLOADS` | `yes` to keep downloaded archives after install |
| `POLYVM_LEGACY_VERSION_FILE` | `no` to ignore `.python-version` and similar. On by default |
| `POLYVM_PYTHON_OPTIMIZE` | `no` for a faster, unoptimised Python build |
| `POLYVM_DEBUG` | Any value turns on verbose output |
| `POLYVM_YES` | Skip confirmation prompts |
| `NO_COLOR` | Disable colored output |
| `POLYVM_UPDATE_CHECK` | `never` to disable the update notice |
| `POLYVM_UPDATE_INTERVAL_HOURS` | How often to re-check for a release. Default 24 |
