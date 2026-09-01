polyvm is one version manager for every language. `pyenv` handles Python, `nvm`
handles Node, `rbenv` handles Ruby. polyvm handles all of them from a single
tool, a single config file and a single place on disk.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/dev-sriramp/polyvm/main/install.sh | bash
```

Open a new shell, then:

```sh
polyvm doctor
polyvm plugin add python
polyvm install python 3.13.1
polyvm global python 3.13.1
python --version
```

Linux and macOS. Needs bash, git, curl and tar and nothing else. Targets bash
3.2, so the bash that ships with macOS is enough.
[Full install guide](https://github.com/dev-sriramp/polyvm/blob/main/docs/install.md),
including containers and Dockerfiles.

## What is in 0.1.0

**Shims, not just a shell function.** Every executable a language installs gets
a stub on your `PATH`, so the right version is used by cron jobs, Makefiles,
editors and CI scripts that never source your shell config. Tools that only
rewrite `PATH` in an interactive shell cannot do that.

**Python built in.** No plugin to hunt for. It compiles CPython with
python-build, the builder pyenv itself uses, so all ~1,090 recipes work
including PyPy, GraalPy, Anaconda and Miniconda. Your existing
`.python-version` files are read as is. On macOS it wires up Homebrew's openssl
and readline automatically, which is the step most people miss and the reason a
Mac built Python so often ends up without `ssl`.

**asdf compatible.** Every existing asdf plugin works unchanged, and
`polyvm plugin add <name>` resolves through the asdf plugin index. `.tool-versions`
is read as is, so an existing asdf project needs no changes.

**Per directory versions.** `.polyvm-versions` committed to a repository means
`polyvm install` gives everyone the same runtimes.

**Update notifications.** polyvm tells you when a new release is out and
`polyvm update` moves you to it. The check runs at most once a day, detached in
the background, so it can never make a command hang.

## Commands

```sh
polyvm install <lang> <version>    # or latest, or latest:3.12
polyvm global <lang> <version>     # your default
polyvm local <lang> <version>      # this directory and below
polyvm shell <lang> <version>      # this shell only
polyvm current                     # what is active and which file set it
polyvm which python                # the binary that would actually run
polyvm list-all <lang>             # everything installable
polyvm plugin add <lang>           # add a language
polyvm doctor                      # check the install
```

Coming from pyenv? Every equivalent is in
[docs/python.md](https://github.com/dev-sriramp/polyvm/blob/main/docs/python.md).

## Tested

71 assertions on every push, across Ubuntu, Debian, Fedora, Alpine and macOS,
including the suite under stock macOS bash 3.2 and against busybox coreutils.
CI also installs a real Node runtime, checks the shim works with no shell
integration at all, and builds CPython from source to confirm `ssl`, `sqlite3`,
`lzma`, `bz2`, `ctypes` and `readline` all came out whole.

## Not yet

Windows. The platform seams are in place and the plan is in
[docs/windows.md](https://github.com/dev-sriramp/polyvm/blob/main/docs/windows.md).
WSL works today.

## License

MIT.
