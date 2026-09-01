SHELL := /usr/bin/env bash

SOURCES := bin/polyvm lib/core.sh lib/util.sh lib/version.sh lib/plugin.sh \
           lib/compat.sh lib/deps.sh lib/shim.sh lib/install.sh polyvm.sh install.sh \
           lib/update.sh uninstall.sh test/run.sh test/sandbox.sh \
           test/docker.sh scripts/release.sh completions/polyvm.bash \
           contrib/plugins/python/lib/helpers.sh \
           $(wildcard contrib/plugins/python/bin/*)

.PHONY: help test lint syntax check sandbox sandbox-clean docker release install uninstall print-sources

help:
	@echo "make test      run the test suite"
	@echo "make lint      run shellcheck"
	@echo "make syntax    parse every script"
	@echo "make check     syntax, lint and tests in one go"
	@echo "make sandbox   install into a throwaway prefix and open a shell"
	@echo "make sandbox-clean  delete the sandbox"
	@echo "make docker    run the suite in Linux containers"
	@echo "make release VERSION=x.y.z  bump, tag and print the push command"
	@echo "make install   install from this checkout into POLYVM_DIR"
	@echo "make uninstall remove the installation"

test:
	@./test/run.sh

print-sources:
	@echo $(SOURCES)

syntax:
	@for f in $(SOURCES); do bash -n "$$f" || exit 1; done
	@echo "syntax ok"

lint:
	@command -v shellcheck >/dev/null || { echo "shellcheck is not installed"; exit 1; }
	@shellcheck -s bash -e SC1090,SC1091 $(SOURCES)
	@echo "lint ok"

check: syntax lint test

sandbox:
	@./test/sandbox.sh

sandbox-clean:
	@./test/sandbox.sh --clean

docker:
	@./test/docker.sh

release:
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=0.2.0"; exit 1; }
	@./scripts/release.sh "$(VERSION)"

install:
	@bash install.sh

uninstall:
	@bash uninstall.sh
