# Security

## Reporting a vulnerability

Report security issues privately through GitHub's
[private vulnerability reporting](https://github.com/dev-sriramp/polyvm/security/advisories/new)
rather than in a public issue.

Please include what an attacker can do, the steps to reproduce it, and the
polyvm version and platform. You will get an acknowledgement within a few days.

## What polyvm does on your machine

Worth knowing, because a version manager is a natural supply chain target.

- **It downloads and runs code.** A plugin is a git repository whose hooks
  polyvm executes, and those hooks download and build language runtimes. Adding
  a plugin is equivalent to running its author's shell scripts. Only add
  plugins you trust, and prefer the built in ones.
- **Checksums.** The bundled Python plugin verifies the SHA-256 of the CPython
  source tarball against the checksum in the python-build recipe before
  building. Third party plugins verify whatever their authors chose to verify,
  which may be nothing.
- **`plugin add` clones over HTTPS** from the URL in the asdf plugin index, or
  from a URL you pass. It does not verify a signature on the plugin itself.
- **Shims go on your `PATH`**, ahead of system binaries, and are what `python`
  and `node` resolve to. Anything that can write to `~/.polyvm/shims` can
  intercept those commands. Keep that directory to your own user.
- **Removal is bounded.** `polyvm` refuses to remove any path outside
  `$POLYVM_DATA_DIR`, and any path containing `..`, so a malicious plugin name
  cannot walk out of the data directory.
- **No telemetry.** The only network calls polyvm makes on its own are the
  plugin index clone, the update check against your git remote's tags, and
  whatever a plugin does during an install.

## Reducing what polyvm can reach

```sh
export POLYVM_UPDATE_CHECK=never   # no update checks
```

Everything else is driven by the plugins you add, so the meaningful control is
which plugins you install.
