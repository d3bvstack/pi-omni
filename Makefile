SHELL := /bin/bash
.DEFAULT_GOAL := help

install_dir ?= $(HOME)/.local/bin
image ?= pi-agent:latest
compose := docker compose

.PHONY: help build install clean

help: ## Show the available targets
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "} {printf "  %-9s %s\n", $$1, $$2}'

build: ## Build the container image
	PI_IMAGE=$(image) $(compose) build pi

install: ## Symlink pi into ~/.local/bin (override with install_dir=)
	@mkdir -p $(install_dir)
	@ln -sf $(CURDIR)/bin/pi $(install_dir)/pi
	@echo "installed $(install_dir)/pi -- restart your shell to pick it up"

clean: ## Remove the image, the project network and stopped containers
	-$(compose) down --remove-orphans
	-docker image rm $(image)
