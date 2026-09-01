polyvm now offers to install what a build needs, instead of handing you an
error and walking away.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/dev-sriramp/polyvm/main/install.sh | bash
```

Already have polyvm? `polyvm update`.

## What changed

**Before**, installing Python on a machine without a toolchain ended here:

```
error: Python is compiled from source, and this machine is missing a C compiler and make.
  Install the toolchain:
    sudo apt-get update && sudo apt-get install -y build-essential
  Then run this again. Nothing was downloaded.
```

**Now** it offers to do it for you:

```
Python is compiled from source, and this machine is missing things it needs:

    build-essential
        a C compiler and make, without which nothing can be compiled

  polyvm can install them with:

    sudo apt-get update && sudo apt-get install -y build-essential

  Install them now? [Y/n]
```

Say yes and it installs, re-checks, and goes straight on to the build. Say no
and it stops, having downloaded nothing.

**On macOS it uses the right tools.** The compiler comes from the command line
tools, so it offers to run `xcode-select --install`. The libraries come from
Homebrew, so it checks which formulas are installed and offers
`brew install openssl@3 tcl-tk`. It no longer probes include paths there, which
never contain Homebrew headers and so reported every library as missing. This
is the step people miss most often with pyenv, and why a Mac-built Python so
often ends up with no `ssl`.

**Versions are validated first**, so you never install a toolchain for
something that does not exist:

```
$ polyvm install python 3.17
error: there is no Python 3.17.
  See everything:  polyvm list-all python
  Newest stable:   polyvm install python latest
```

## Control

| `POLYVM_INSTALL_DEPS` | Effect |
|---|---|
| unset | Ask, when there is a terminal to answer |
| `yes` | Install without asking. Use this in Dockerfiles and CI |
| `no` | Never install, just report the command |

In a Dockerfile:

```dockerfile
ENV POLYVM_INSTALL_DEPS=yes
RUN polyvm plugin add python && polyvm install python 3.13.1
```

## What it will not do

polyvm never installs system packages without being asked or told. It prompts
only when a terminal is present and only when it can actually install, meaning
as root or with `sudo` available. Where it cannot, it prints the command for
someone with the rights to run it. It will not prompt in CI, because a build
hanging on input nobody will type is worse than a clear failure.

## Tested

106 assertions on every push across Ubuntu, Debian, Fedora, Alpine and macOS,
including under stock macOS bash 3.2 and busybox coreutils. The dependency
install path is tested against a stubbed package manager, so the tests never
touch a real system.
