#!/bin/bash
# Executable fixtures for scripts/stamp-app-metadata.sh, run against a
# throwaway copy of Support/Info.plist: no build, no signing, no release.
# Strict mode: a helper that expects a failing exit status captures it with `|| status=$?`,
# so one failing check is counted and reported instead of ending the run.
set -euo pipefail
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
PLIST="$SANDBOX/Info.plist"
cp "$REPO_ROOT/Support/Info.plist" "$PLIST"

stamp() {
    local status=0
    "$REPO_ROOT/scripts/stamp-app-metadata.sh" "$@" >/dev/null 2>&1 || status=$?
    echo "$status"
}
read_key() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true; }

# --- a valid stamp writes all three keys ---------------------------------------
check "valid stamp exits 0" "$(stamp "$PLIST" 9.8.7 90807 2026-09-15)" "0"
check "version is stamped" "$(read_key CFBundleShortVersionString)" "9.8.7"
check "build is stamped" "$(read_key CFBundleVersion)" "90807"
check "release date is added" "$(read_key AppReleaseDate)" "2026-09-15"

# --- restamping replaces the date instead of failing on Add --------------------
check "restamp exits 0" "$(stamp "$PLIST" 9.8.7 90807 2026-10-01)" "0"
check "release date is replaced" "$(read_key AppReleaseDate)" "2026-10-01"

# --- a malformed date is refused and leaves the plist untouched -----------------
for bad in "" "2026-9-15" "15/09/2026" "2026-09-15T10:00:00Z" "junk"; do
    check "malformed date '$bad' exits 1" "$(stamp "$PLIST" 1.0.0 10000 "$bad")" "1"
done
check "refused stamps change nothing" "$(read_key CFBundleShortVersionString) $(read_key AppReleaseDate)" \
    "9.8.7 2026-10-01"

# --- usage errors ---------------------------------------------------------------
check "missing arguments exit 2" "$(stamp "$PLIST" 1.0.0 10000)" "2"
check "missing plist exits 1" "$(stamp "$SANDBOX/none.plist" 1.0.0 10000 2026-09-15)" "1"

# --- the committer date is a valid stamp ------------------------------------------
check "git committer date is YYYY-MM-DD" \
    "$(git log -1 --format=%cs | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || true)" "1"

if [ "$FAILED" -gt 0 ]; then
    echo "stamp-app-metadata: $FAILED failed, $PASSED passed" >&2
    exit 1
fi
echo "stamp-app-metadata: all $PASSED checks passed"
