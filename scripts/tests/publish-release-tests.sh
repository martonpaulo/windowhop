#!/bin/bash
# Executable fixtures for scripts/publish-release.sh.
#
# A fake `gh` on PATH records every operation and holds the release state in a
# JSON file, so the real script's operation order and failure handling are
# exercised without a network, a token, or any signing material.
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

# Builds an isolated sandbox: fake gh, artifacts, notes, empty release state.
setup() {
    SANDBOX=$(mktemp -d)
    mkdir -p "$SANDBOX/bin" "$SANDBOX/artifacts"
    printf 'installer' > "$SANDBOX/artifacts/one.zip"
    printf 'diskimage-bytes' > "$SANDBOX/artifacts/two.dmg"
    printf 'update' > "$SANDBOX/artifacts/three.zip"
    printf 'notes\n' > "$SANDBOX/notes.md"
    echo '{"exists": false, "draft": true, "assets": {}}' > "$SANDBOX/state.json"
    : > "$SANDBOX/operations.log"
    cp "$REPO_ROOT/scripts/tests/fake-gh.py" "$SANDBOX/bin/gh"
    chmod +x "$SANDBOX/bin/gh"
    export FAKE_GH_STATE="$SANDBOX/state.json"
    export FAKE_GH_LOG="$SANDBOX/operations.log"
    export FAKE_GH_FAIL="${FAKE_GH_FAIL:-}"
}

teardown() {
    rm -rf "$SANDBOX"
    unset FAKE_GH_STATE FAKE_GH_LOG FAKE_GH_FAIL
}

run_publish() {
    PATH="$SANDBOX/bin:$PATH" "$REPO_ROOT/scripts/publish-release.sh" v1.2.3 "$SANDBOX/notes.md" \
        "$SANDBOX/artifacts/one.zip" "$SANDBOX/artifacts/two.dmg" "$SANDBOX/artifacts/three.zip" \
        > "$SANDBOX/out.log" 2>&1
    echo $?
}

operations() { tr '\n' ' ' < "$SANDBOX/operations.log" | sed 's/ $//'; }

# --- a fresh release publishes every artifact, in order -------------------
setup
status=$(run_publish)
check "fresh publish succeeds" "$status" "0"
check "fresh publish order" "$(operations)" \
    "view create upload:one.zip upload:two.dmg upload:three.zip view edit:publish view view"
check "release is public" "$(python3 -c 'import json;print(json.load(open("'"$SANDBOX"'/state.json"))["draft"])')" "False"
teardown

# --- an upload failure never publishes ------------------------------------
setup
FAKE_GH_FAIL="upload:two.dmg" status=$(FAKE_GH_FAIL="upload:two.dmg" run_publish)
check "failed upload fails the run" "$status" "1"
check "failed upload never publishes" "$(grep -c 'edit:publish' "$SANDBOX/operations.log")" "0"
teardown

# --- an incomplete draft is completed on retry ----------------------------
setup
echo '{"exists": true, "draft": true, "assets": {"one.zip": 9}}' > "$SANDBOX/state.json"
status=$(run_publish)
check "incomplete draft retry succeeds" "$status" "0"
check "incomplete draft is not recreated" "$(grep -c '^create$' "$SANDBOX/operations.log")" "0"
check "incomplete draft ends public" \
    "$(python3 -c 'import json;print(json.load(open("'"$SANDBOX"'/state.json"))["draft"])')" "False"
teardown

# --- a complete public release is a read-only no-op -----------------------
setup
echo '{"exists": true, "draft": false, "assets": {"one.zip": 9, "two.dmg": 15, "three.zip": 6}}' \
    > "$SANDBOX/state.json"
status=$(run_publish)
check "complete public release is a no-op" "$status" "0"
check "no-op mutates nothing" "$(operations)" "view view"
teardown

# --- a public release with a different asset must not be overwritten ------
setup
echo '{"exists": true, "draft": false, "assets": {"one.zip": 4242, "two.dmg": 15, "three.zip": 6}}' \
    > "$SANDBOX/state.json"
status=$(run_publish)
check "conflicting public asset fails" "$status" "1"
check "conflicting public asset is never uploaded" "$(grep -c 'upload:' "$SANDBOX/operations.log")" "0"
teardown

# --- a public release missing an artifact is not silently accepted --------
setup
echo '{"exists": true, "draft": false, "assets": {"one.zip": 9}}' > "$SANDBOX/state.json"
status=$(run_publish)
check "incomplete public release fails" "$status" "1"
teardown

# --- an auth or network error is never read as "no release yet" -----------
setup
status=$(FAKE_GH_FAIL="view:auth" run_publish)
check "auth error fails" "$status" "1"
check "auth error creates nothing" "$(grep -c '^create$' "$SANDBOX/operations.log")" "0"
teardown

# --- missing local artifacts fail before any GitHub operation -------------
setup
rm "$SANDBOX/artifacts/two.dmg"
status=$(run_publish)
check "missing artifact fails" "$status" "1"
check "missing artifact touches no release" "$(operations)" ""
teardown

# --- empty release notes fail before any GitHub operation -----------------
setup
: > "$SANDBOX/notes.md"
status=$(run_publish)
check "empty notes fail" "$status" "1"
check "empty notes touch no release" "$(operations)" ""
teardown

echo "publish-release fixtures: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
