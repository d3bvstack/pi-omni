# Makefile for the pi agent sandbox image.
#
# Every target is phony: none of them writes a file worth declaring, they just
# wrap the tools they call. `make help` lists the targets and the variables.
#
# Words that are not targets are service names for the compose commands, so
# `make build pi` and `make shell pi` read the same way as `make build` and
# `make shell`. Everything that needs a value still takes it as `name=value`.

SHELL := /bin/bash
# Fail fast on errors, unset variables and a failing stage of a pipeline.
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# Variables, all overridable on the command line. The inline `##` comments feed
# `make help`; make keeps the alignment padding in front of them as part of the
# value, which is why the recipes read every variable through $(strip).

image ?= pi-agent:latest                      ## Container image name
install_dir ?= $(HOME)/.local/bin             ## Where `install` puts the pi symlink
compose ?= docker compose                     ## Compose command
pi_package ?= @earendil-works/pi-coding-agent ## npm package holding the agent
dockerfile ?= Dockerfile                      ## File holding the PI_VERSION pin
version ?=                                    ## Version for `pin` (required, no default)
filter ?=                                    ## Substring selecting test cases for `test`

# `bin/pi` reads PI_IMAGE, and compose reads it too, so exporting it once keeps
# every target consistent without repeating it on each command line.
export PI_IMAGE := $(strip $(image))

# ------------------------------------------------------------- arguments

# MAKECMDGOALS holds every word after "make". Make consumes the ones naming a
# target; the rest are service names. Naming the targets in one place keeps the
# filter below honest, so a new target only has to be listed here once.
TARGETS  := help build shell install uninstall update pin clean test
SERVICES := pi

# A service word is not a target, so without this `make shell pi` would fail on
# a missing rule before the recipe ever ran.
.PHONY: $(SERVICES)
$(SERVICES):
	@:

# Drop the target words; what is left is the service the user asked for. Empty
# means the one service this project ships, so `make build` and `make build pi`
# do the same thing. A word that is neither goes to the recipe unchanged and
# fails at the no-op rule above, rather than silently building something else.
SERVICE := $(or $(filter-out $(TARGETS) $(SERVICES),$(MAKECMDGOALS)),pi)

# No target here produces a file, so none of them can go stale. Split in two
# rather than continued, so that one `sed` can read the whole list.
.PHONY: help build shell install uninstall update pin clean test

help: ## Show the available targets and variables
	@printf 'Usage: make <target> [service...] [var=value ...]\n\nTargets:\n'
	@awk 'BEGIN {FS = ":.*?## "} \
		/^[a-z][a-z0-9-]*:.*?## / {printf "  %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf '\nVariables:\n'
	@awk 'BEGIN {FS = "## "} \
		/^[a-z_]+[ \t]*[?=].*## / { \
			name = $$1; sub(/[ \t]*[?=].*$$/, "", name); \
			now = $$1; sub(/^[a-z_]+[ \t]*[?]=[[:space:]]*/, "", now); \
			sub(/[[:space:]]+$$/, "", now); \
			printf "  %-10s %s (now: %s)\n", name, $$2, \
				now == "" ? "<empty>" : now }' $(MAKEFILE_LIST)

build: ## Build the container image (service defaults to pi)
	$(strip $(compose)) build $(SERVICE)

shell: ## Attach to sh inside a container (service defaults to pi)
	$(strip $(compose)) exec $(SERVICE) sh

install: ## Symlink pi into install_dir (override with install_dir=)
	@link=$(strip $(install_dir))/pi; src='$(CURDIR)/bin/pi'; \
	mkdir -p "$$(dirname "$$link")"; \
	if [ -e "$$link" ] && [ "$$link" -ef "$$src" ]; then \
		echo "$$link already links to $$src"; \
	else \
		ln -sf "$$src" "$$link" && \
		echo "installed $$link -- restart your shell to pick it up"; \
	fi

uninstall: ## Remove the symlink installed by `install`, if it is ours
	@link=$(strip $(install_dir))/pi; \
	if [ ! -e "$$link" ] && [ ! -L "$$link" ]; then \
		echo "nothing to remove: $$link does not exist"; \
	elif [ ! -L "$$link" ]; then \
		echo "refusing to remove $$link: not a symlink"; exit 1; \
	elif [ "$$(readlink "$$link")" != '$(CURDIR)/bin/pi' ]; then \
		echo "refusing to remove $$link: it points elsewhere"; exit 1; \
	else \
		rm -f "$$link" && echo "removed $$link"; \
	fi

update: ## Pin the latest published pi version in the Dockerfile
	@pkg=$(strip $(pi_package)); \
	latest=$$(npm view "$$pkg" version) || { \
		echo "update: could not query npm for $$pkg" >&2; exit 1; }; \
	test -n "$$latest" || { echo "update: npm reported no version" >&2; exit 1; }; \
	$(MAKE) --no-print-directory pin version="$$latest"; \
	echo "run 'make build' to rebuild $(strip $(image))"

pin: ## Pin a specific pi version in the Dockerfile (version=x.y.z)
	@file=$(strip $(dockerfile)); ver=$(strip $(version)); \
	test -n "$$ver" || { \
		echo "pin: no version given, e.g. make pin version=1.0.0" >&2; exit 1; }; \
	grep -qE '^ARG PI_VERSION=' "$$file" || { \
		echo "pin: no 'ARG PI_VERSION=' line in $$file" >&2; exit 1; }; \
	tmp=$$(mktemp) && \
	sed -E "s/^(ARG PI_VERSION=).*/\\1$$ver/" "$$file" >"$$tmp" && \
	mv "$$tmp" "$$file" && \
	echo "pinned PI_VERSION=$$ver in $$file"

test: ## Run the Makefile test suite (filter=substring to narrow it down)
	@MAKE_TEST_FILTER='$(strip $(filter))' test/make-targets.sh

clean: ## Remove the image, the project network and stopped containers
	-$(strip $(compose)) down --remove-orphans
	-docker image rm $(strip $(image))
