# Task entry points. `make validate` is the one CI runs.

.DEFAULT_GOAL := help

.PHONY: help build test validate check

# Any compiler warning fails `build` and `test`, locally and in CI.
SWIFT_FLAGS := -Xswiftc -warnings-as-errors
CONFIGURATION ?= debug

help: ## List the targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  make %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build (CONFIGURATION=debug|release); fails on any warning
	swift build -c $(CONFIGURATION) $(SWIFT_FLAGS)

test: ## Unit and integration tests; fails on any warning
	swift test $(SWIFT_FLAGS)

validate: ## Repository invariants, the static site and the release-script fixtures
	scripts/validate.sh

check: build test validate ## Everything a commit needs
