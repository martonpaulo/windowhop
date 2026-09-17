# Task entry points. `make validate` is the one CI runs.

.DEFAULT_GOAL := help

.PHONY: help build test validate check

help: ## List the targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  make %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Debug build (must be warning-free)
	swift build

test: ## Unit and integration tests
	swift test

validate: ## Repository invariants, the static site and the release-script fixtures
	scripts/validate.sh

check: build test validate ## Everything a commit needs
