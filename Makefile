# Task entry points. `make validate` is the one CI runs.

.DEFAULT_GOAL := help

.PHONY: help build test validate strings strings-check check

# Any compiler warning fails `build` and `test`, locally and in CI. Package.swift turns
# warnings into errors (`.treatAllWarnings(as: .error)`), but some Swift 6 diagnostics stay
# warnings anyway, so scripts/fail-on-warnings.sh also fails on any `warning:` line that
# points into Sources/ or Tests/. Plain `swift build` does not run that second check.
CONFIGURATION ?= debug

help: ## List the targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  make %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build (CONFIGURATION=debug|release); fails on any warning
	scripts/fail-on-warnings.sh swift build -c $(CONFIGURATION)

test: ## Unit and integration tests; fails on any warning
	scripts/fail-on-warnings.sh swift test

validate: ## Repository invariants, the static site and the release-script fixtures
	scripts/validate.sh

strings: ## Regenerate Support/Localizable.xcstrings and Support/en.lproj from the sources
	scripts/strings.sh

strings-check: ## Fail when the String Catalog is out of date with the sources
	scripts/strings.sh --check

check: build test validate strings-check ## Everything a commit needs
