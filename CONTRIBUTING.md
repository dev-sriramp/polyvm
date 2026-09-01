# Contributing

## Getting set up

```sh
git clone https://github.com/dev-sriramp/polyvm.git
cd polyvm
make check      # syntax, shellcheck, the test suite
make sandbox    # a throwaway install you can play with
```

`make sandbox` installs into a temporary prefix and opens a shell inside it. It
never touches your shell rc files or a real `~/.polyvm`, so you can try a
work in progress build without it taking over the shell you work in.

## Before you open a pull request

```sh
make check
```

That has to pass. If you touched version resolution or shim dispatch, add an
assertion to `test/run.sh`; those two are where the subtle bugs live.

If you can, also run:

```sh
make docker     # the distro matrix, needs docker or podman
/bin/bash ./test/run.sh   # on macOS, this is bash 3.2
```

## The rules that keep polyvm portable

polyvm runs on stock macOS and on Alpine. Both are less forgiving than a modern
Linux, and both break quietly rather than loudly.

**bash 3.2.** macOS ships bash 3.2 and polyvm targets it. Your Homebrew bash is
probably 5.x, so a bash 4 feature passes locally and breaks for everyone on a
stock Mac. No associative arrays, no `${var^^}`, no `mapfile`, no `&>>`.

**No GNU only tools or flags.** `sort -V`, `readlink -f`, `sed -i` with no
argument, `date -d` and `find -newermt` are all missing or different on macOS.
polyvm avoids every one of them. Check `man` on macOS before using a flag.

**busybox counts too.** On Alpine, `awk`, `sed`, `grep`, `sort`, `find` and
`cut` are busybox implementations. Keep to the common subset.

**Anything platform specific goes through a helper** in `lib/util.sh`
(`polyvm_os`, `polyvm_is_windows`, `polyvm_exe_suffix`, `polyvm_is_executable`,
`polyvm_shim_name`). Do not scatter `uname` checks through the code.

**Assign, do not print, when a caller needs more than one value.** A command
substitution runs in a subshell, so anything the function sets is lost.
`polyvm_resolve_version_var` and `polyvm_resolve_command_var` exist because
printing versions of them threw away the information their callers needed for
error messages. This has caused two real bugs; do not reintroduce it.

**Keep `exec-shim` fast.** It runs on every `python` and `node` invocation. No
network, no update checks, no work that is not needed to find the binary.

## Style

- Two space indent, no tabs.
- `local` for every function variable.
- Quote every expansion unless you specifically want word splitting.
- Comments explain why, not what. If a line needs a comment to say what it
  does, rewrite the line.
- Errors go to stderr and say what to do next, not just what went wrong.

## Adding a language

Most languages should be an ordinary plugin in their own repository, following
the [plugin API](docs/plugin-api.md). Since polyvm is asdf compatible, an
existing asdf plugin usually already works, so check before writing one.

A plugin belongs in `contrib/plugins` only when it needs to work with no
network lookup and is worth maintaining in this repository. Python is there
because it is the most commonly wanted and the hardest to install correctly.

## Commit messages

A short imperative subject, then a body explaining why. If you fixed a bug,
say what the wrong behaviour was, not just that it is fixed.

## Reporting a bug

Include the output of:

```sh
polyvm doctor
polyvm current
bash --version
uname -a
```

For an install failure, re-run with `POLYVM_DEBUG=1` and include the log.
