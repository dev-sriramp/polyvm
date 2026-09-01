# Windows

Short version: polyvm runs on Linux and macOS today. Windows is a work in
progress and this page is the plan, not a promise.

## What already works

Under a POSIX layer, meaning Git Bash, MSYS2 or Cygwin, polyvm installs and the
core commands run: `plugin add`, `list`, `global`, `local`, `current`, `which`,
`reshim`. `uname -s` reports `MINGW64_NT` or similar, and polyvm reports the
platform as `windows`.

Under WSL there is nothing to do. WSL is Linux, `uname -s` says `Linux`, and
polyvm is fully supported there today. If you want a working setup on a Windows
machine this afternoon, WSL is the answer.

## What does not work yet

**Building from source.** The Python plugin compiles CPython with the same
builder pyenv uses, which needs a POSIX toolchain. It refuses to run on Windows
rather than failing halfway through a build. Any plugin that downloads a
prebuilt binary can work; anything that compiles cannot.

**Native shims.** polyvm generates a bash stub per executable. `cmd.exe` and
PowerShell cannot run one. polyvm already writes a `.cmd` wrapper beside each
shim when it detects Windows, which covers the common case, but that wrapper
shells out to bash and so still depends on Git Bash being installed. A native
port needs shims that do not need bash at all.

**Shell integration.** `polyvm.sh` targets bash and zsh. PowerShell needs its
own equivalent for `polyvm shell` and for putting the shim directory on `PATH`.

## How the code is arranged for the port

Everything platform-specific goes through a helper in `lib/util.sh`, so adding
Windows means filling those in rather than editing logic scattered across the
codebase:

| Helper | Purpose |
|---|---|
| `polyvm_os` | `linux`, `darwin` or `windows`. Detects MinGW, MSYS and Cygwin |
| `polyvm_is_windows` | Guard for a Windows-only branch |
| `polyvm_platform_supported` | What `polyvm doctor` reports |
| `polyvm_exe_suffix` | `.exe` on Windows, empty elsewhere |
| `polyvm_is_executable` | Uses the executable bit, falls back to the extension on Windows where that bit is unreliable |
| `polyvm_shim_name` | Strips `.exe` so `python.exe` is reachable as `python` |
| `polyvm_write_shim_cmd` | Writes the `.cmd` wrapper |

Version resolution, the plugin contract and the version file format are already
platform independent and need no changes.

## Remaining work

1. **Shims without bash.** Either a small native launcher, or a `.cmd` that
   resolves the version itself. The `.cmd` route keeps polyvm dependency free
   but means reimplementing version resolution in batch, which is unpleasant.
2. **PowerShell integration.** A `polyvm.ps1` providing the `polyvm` function
   and `polyvm shell`.
3. **Path handling.** Windows `PATH` uses `;` and mixed drive-letter paths.
   `polyvm_path_list_sep` exists as the seam; the shim dispatcher and
   `polyvm env` need to use it.
4. **A prebuilt-binary Python plugin.** The compile-from-source path will not
   come to native Windows. python-build-standalone publishes Windows builds, so
   a second install strategy in the Python plugin is the realistic answer.
5. **CI on a Windows runner**, so this stops being theoretical.

## If you are on Windows now

Use WSL. Everything in the README works unchanged.
