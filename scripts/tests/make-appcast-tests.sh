#!/bin/bash
# Executable fixtures for scripts/make-appcast.sh, run against a throwaway
# copy of the repository so the real appcast.xml is never touched.
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

SIG='sparkle:edSignature="AAAA" length="1234"'
OTHER_SIG='sparkle:edSignature="BBBB" length="1234"'

setup() {
    SANDBOX=$(mktemp -d)
    mkdir -p "$SANDBOX/scripts" "$SANDBOX/artifacts"
    cp "$REPO_ROOT/scripts/make-appcast.sh" "$SANDBOX/scripts/"
    : > "$SANDBOX/artifacts/WindowHop-1.2.3.zip"
}
teardown() { rm -rf "$SANDBOX"; }

run_appcast() {
    (cd "$SANDBOX" && ./scripts/make-appcast.sh "$1" "$2" "artifacts/WindowHop-$1.zip" "$3") \
        > "$SANDBOX/out.log" 2>&1
    echo $?
}

items() { grep -c "<item>" "$SANDBOX/appcast.xml"; }

# --- a first entry creates the feed ---------------------------------------
setup
status=$(run_appcast 1.2.3 10203 "$SIG")
check "first entry succeeds" "$status" "0"
check "first entry is written" "$(items)" "1"
check "first entry carries the signature" \
    "$(grep -c 'sparkle:edSignature="AAAA"' "$SANDBOX/appcast.xml")" "1"
teardown

# --- an identical rerun is an idempotent no-op ----------------------------
setup
run_appcast 1.2.3 10203 "$SIG" > /dev/null
before=$(md5 -q "$SANDBOX/appcast.xml" 2>/dev/null || md5sum "$SANDBOX/appcast.xml" | cut -d' ' -f1)
status=$(run_appcast 1.2.3 10203 "$SIG")
after=$(md5 -q "$SANDBOX/appcast.xml" 2>/dev/null || md5sum "$SANDBOX/appcast.xml" | cut -d' ' -f1)
check "identical rerun succeeds" "$status" "0"
check "identical rerun changes nothing" "$after" "$before"
check "identical rerun does not duplicate" "$(items)" "1"
teardown

# --- a same-version entry describing another build must fail --------------
setup
run_appcast 1.2.3 10203 "$SIG" > /dev/null
status=$(run_appcast 1.2.3 10203 "$OTHER_SIG")
check "mismatching signature fails" "$status" "1"
check "mismatching signature reports why" \
    "$(grep -c 'different signature or length' "$SANDBOX/out.log")" "1"
teardown

setup
run_appcast 1.2.3 10203 "$SIG" > /dev/null
status=$(run_appcast 1.2.3 99999 "$SIG")
check "mismatching build number fails" "$status" "1"
teardown

# --- a newer version is prepended and keeps the previous entries -----------
setup
run_appcast 1.2.3 10203 "$SIG" > /dev/null
: > "$SANDBOX/artifacts/WindowHop-1.3.0.zip"
status=$(run_appcast 1.3.0 10300 "$SIG")
check "second version succeeds" "$status" "0"
check "previous entry is preserved" "$(items)" "2"
check "newest entry comes first" \
    "$(grep -m1 '<title>' "$SANDBOX/appcast.xml" | tr -d ' ')" "<title>WindowHop</title>"
check "newest item precedes the older one" \
    "$(grep -o '<sparkle:shortVersionString>[^<]*' "$SANDBOX/appcast.xml" | head -1 | cut -d'>' -f2)" \
    "1.3.0"
teardown

echo "make-appcast fixtures: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
