# asdf compatibility

polyvm implements the asdf plugin contract. That is a deliberate choice: it
means every language asdf supports is available on day one instead of waiting
for someone to write a polyvm-specific plugin.

## What carries over

- **Plugins.** Any asdf plugin repository works unchanged. `polyvm plugin add
  python` resolves the name through the asdf plugin index.
- **`.tool-versions`.** Read exactly as asdf reads it, at any level of the
  directory tree. An existing asdf project needs no changes.
- **Hook environment.** `ASDF_INSTALL_PATH`, `ASDF_DOWNLOAD_PATH`,
  `ASDF_CONCURRENCY` and the rest are all exported.
- **`ASDF_<PLUGIN>_VERSION`.** Honoured, one step below the polyvm equivalent.
- **Plugins that call `asdf`.** Several plugins shell out to `asdf` inside their
  own hooks. asdf-nodejs ends its install hook with `asdf reshim nodejs
  $version`. polyvm puts a translating `asdf` on `PATH` while a hook runs, so
  those plugins work. That shim is scoped to hook execution and never appears on
  your own `PATH`.

## Differences

| | asdf | polyvm |
|---|---|---|
| Default version file | `.tool-versions` | `.polyvm-versions`, falls back to `.tool-versions` |
| Global file | `~/.tool-versions` | `~/.polyvm/versions` |
| Plugin subcommands | `asdf plugin add` and `asdf plugin-add` | `polyvm plugin add` |
| Legacy version files | on by default in some versions | off unless `POLYVM_LEGACY_VERSION_FILE=yes` |
| Data directory | `~/.asdf` | `~/.polyvm` |

polyvm does not read `~/.tool-versions` as a global file. Set globals with
`polyvm global`, which writes `~/.polyvm/versions`.

## Moving an existing asdf setup

Project files need no changes. For the plugins and the global versions:

```sh
# plugins
asdf plugin list | while read -r p; do polyvm plugin add "$p"; done

# global versions
while read -r plugin version _; do
  [ -n "$plugin" ] || continue
  polyvm global "$plugin" "$version"
done < ~/.tool-versions

# runtimes
polyvm install
```

The two tools can coexist. Both put a shim directory on `PATH`, so whichever
comes first wins. Keep only one on `PATH` at a time to avoid confusion.

## Known limits

- A plugin that hardcodes `~/.asdf` instead of reading `$ASDF_DATA_DIR` will
  write to the wrong place. This is rare and is a bug in the plugin.
- Plugins that depend on asdf internals beyond the documented hooks and the
  common commands are not supported.
