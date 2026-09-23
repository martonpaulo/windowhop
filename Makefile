# Task entry points: skill-deck's fourteen shared targets plus WindowHop's `strings` pair.
# `make validate` runs on every change in CI; `make check CONFIGURATION=release` is the
# path-filtered build job. No target publishes anything: only the tag workflow does.

.DEFAULT_GOAL := help

.PHONY: help build test lint format validate strings strings-check check \
	app dmg icon screenshots keys appcast clean

# Any compiler warning fails `build` and `test`, locally and in CI. Package.swift turns
# warnings into errors (`.treatAllWarnings(as: .error)`), but some Swift 6 diagnostics stay
# warnings anyway, so scripts/fail-on-warnings.sh also fails on any `warning:` line that
# points into Sources/ or Tests/. Plain `swift build` does not run that second check.
CONFIGURATION ?= debug
SWIFT_SOURCES ?= Sources Tests

# FORCE=1 lets `app` and `dmg` replace an existing bundle, archive or disk image.
FORCE ?=
FORCE_FLAG := $(if $(filter 1,$(FORCE)),--force,)

# `appcast` inputs, for a rehearsal or a recovery; the release workflow calls the script itself.
VERSION ?=
BUILD_NUMBER ?=
ARCHIVE ?=
SIGNATURE ?=

help: ## List the targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  make %-14s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build (CONFIGURATION=debug|release); fails on any warning
	scripts/fail-on-warnings.sh swift build -c $(CONFIGURATION)

test: ## Unit and integration tests; fails on any warning
	scripts/fail-on-warnings.sh swift test

# Both tools read the repository-root .swiftlint.yml and .swift-format, which are unchanged
# copies of the shared skill-deck files; --strict turns every warning into a failure.
lint: ## SwiftLint, then swift-format lint; read-only, fails on any finding
	swiftlint lint --strict --quiet
	swift format lint --strict --recursive $(SWIFT_SOURCES)

format: ## Rewrite the sources with swift-format (the only target that edits sources)
	swift format format --in-place --recursive $(SWIFT_SOURCES)

validate: ## Repository invariants, the static site and the release-script fixtures
	scripts/validate.sh

strings: ## Regenerate Support/Localizable.xcstrings and Support/en.lproj from the sources
	scripts/strings.sh

strings-check: ## Fail when the String Catalog is out of date with the sources
	scripts/strings.sh --check

check: build lint test validate strings-check ## Everything a commit needs, stopping at the first failure

app: ## build/WindowHop.app and its update zip (ad-hoc unless DEVELOPER_ID_IDENTITY; FORCE=1 replaces)
	scripts/package-app.sh $(FORCE_FLAG)

dmg: app ## The branded DMG from build/WindowHop.app, with the committed art (FORCE=1 replaces)
	scripts/make-dmg.sh $(FORCE_FLAG)

# The art is committed; regenerate it only after changing a generator. The iconset and the
# DMG background frames are intermediates in artifacts/.
icon: ## Regenerate the app icon, favicons, installer icon and DMG background
	scripts/make-icon.swift artifacts/icon
	iconutil -c icns artifacts/icon/AppIcon.iconset -o Support/AppIcon.icns
	scripts/make-icon.swift --favicon site
	scripts/render-installer-icon.swift
	scripts/render-dmg-background.swift
	tiffutil -cathidpicheck artifacts/dmg-bg.png artifacts/dmg-bg@2x.png \
		-out Support/WindowHopInstallerBackground.tiff

# capture-screenshots.sh drives the debug binary, so it builds that first.
screenshots: ## Capture site/screenshots/ (Retina display and Screen Recording permission)
	$(MAKE) build CONFIGURATION=debug
	scripts/capture-screenshots.sh

keys: ## Once per machine: the Sparkle key in the login Keychain matches SUPublicEDKey
	scripts/make-keys.sh

appcast: ## Add one appcast.xml entry: VERSION, BUILD_NUMBER, ARCHIVE and SIGNATURE are required
	scripts/make-appcast.sh --version "$(VERSION)" --build-number "$(BUILD_NUMBER)" \
		--archive "$(ARCHIVE)" --signature '$(SIGNATURE)'

clean: ## Remove the SwiftPM build, build/ and artifacts/
	swift package clean
	rm -rf .build build artifacts
