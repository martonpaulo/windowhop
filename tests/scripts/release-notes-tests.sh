#!/bin/bash
# Executable fixtures for scripts/release-notes.sh, run against a throwaway
# Keep a Changelog file so the real CHANGELOG.md never shapes the result.
set -uo pipefail
cd "$(dirname "$0")/../.."
REPO_ROOT=$PWD

PASSED=0
FAILED=0
check() {
    if [ "$2" = "$3" ]; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
        echo "FAIL: $1" >&2
        echo "  expected: $3" >&2
        echo "  actual:   $2" >&2
    fi
}

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
FIXTURE="$SANDBOX/CHANGELOG.md"
cat > "$FIXTURE" <<'MD'
# Changelog

All notable changes are documented in this file.

## [Unreleased]

### Added

- Unreleased work.

## [1.1.10] - 2026-03-01

### Fixed

- Ten.

## [1.1.1] - 2026-02-01

### Changed

- One, first line
  continued.

## [1.1.0] - 2026-01-15

## [1.0.0] - 2026-01-01

First release.

### Added

- Everything.

[Unreleased]: https://example.com/compare/v1.1.10...HEAD
[1.1.10]: https://example.com/releases/tag/v1.1.10
[1.0.0]: https://example.com/releases/tag/v1.0.0
MD

# Prints the exit status; the notes land in $SANDBOX/out and stderr in $SANDBOX/err.
notes() {
    "$REPO_ROOT/scripts/release-notes.sh" "$@" > "$SANDBOX/out" 2> "$SANDBOX/err"
    echo $?
}

# --- the newest version ------------------------------------------------------
check "newest version succeeds" "$(notes --version 1.1.10 --changelog "$FIXTURE")" "0"
check "newest version prints its own body only" "$(cat "$SANDBOX/out")" "$(printf '### Fixed\n\n- Ten.')"

# --- a middle version, and 1.1.1 is not a prefix match of 1.1.10 --------------
check "middle version succeeds" "$(notes --version 1.1.1 --changelog "$FIXTURE")" "0"
check "middle version keeps continuation lines and never returns 1.1.10" \
    "$(cat "$SANDBOX/out")" "$(printf '### Changed\n\n- One, first line\n  continued.')"

# --- the last version stops before the link reference definitions -------------
check "last version succeeds" "$(notes --version 1.0.0 --changelog "$FIXTURE")" "0"
check "last version runs to the end of its section, not into the links" \
    "$(cat "$SANDBOX/out")" "$(printf 'First release.\n\n### Added\n\n- Everything.')"

# --- dots are literal, not regex wildcards ----------------------------------
printf '## [1x1x0] - 2026-01-01\n\n- Wrong.\n' > "$SANDBOX/dots.md"
check "a dot does not match any character" "$(notes --version 1.1.0 --changelog "$SANDBOX/dots.md")" "1"

# --- an empty section and a missing version fail ----------------------------
check "empty section exits 1" "$(notes --version 1.1.0 --changelog "$FIXTURE")" "1"
check "empty section prints nothing" "$(cat "$SANDBOX/out")" ""
check "missing version exits 1" "$(notes --version 9.9.9 --changelog "$FIXTURE")" "1"
check "missing version explains itself on stderr" "$(grep -c '9.9.9' "$SANDBOX/err")" "1"

# --- [Unreleased] is never a version -----------------------------------------
check "Unreleased is not accepted as a version" "$(notes --version Unreleased --changelog "$FIXTURE")" "2"
check "no version section contains the Unreleased entries" \
    "$(for v in 1.1.10 1.1.1 1.0.0; do notes --version "$v" --changelog "$FIXTURE" > /dev/null; cat "$SANDBOX/out"; done | grep -c 'Unreleased work')" "0"

# --- usage errors --------------------------------------------------------------
check "missing --version exits 2" "$(notes --changelog "$FIXTURE")" "2"
check "--version without a value exits 2" "$(notes --version)" "2"
check "unknown option exits 2" "$(notes --version 1.0.0 --bogus)" "2"
check "positional argument exits 2" "$(notes 1.0.0)" "2"

# --- the real changelog carries the shipped version --------------------------
SHIPPED=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)
check "the default changelog has notes for $SHIPPED" "$(notes --version "$SHIPPED")" "0"

if [ "$FAILED" -gt 0 ]; then
    echo "release-notes: $FAILED failed, $PASSED passed" >&2
    exit 1
fi
echo "release-notes: all $PASSED checks passed"
