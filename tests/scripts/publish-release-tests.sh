#!/usr/bin/env bash
# Counterexamples for scripts/publish-release.sh, the canonical publication script.
#
# skill-deck's suite owns the script's general behavior; these cases pin the two
# publication gaps WindowHop's audit found (#52, #53), run against the real script
# with tests/scripts/fake-gh.py on PATH as `gh`. No network, no token, no signing
# material, no real release.
set -euo pipefail
cd "$(dirname "$0")/../.."
REPO_ROOT=$PWD

PASSED=0
FAILED=0
check() { # $1 label, $2 actual, $3 expected
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
mkdir -p "$SANDBOX/bin"
cp "$REPO_ROOT/tests/scripts/fake-gh.py" "$SANDBOX/bin/gh"
chmod +x "$SANDBOX/bin/gh"
export FAKE_GH_STATE="$SANDBOX/state.json" FAKE_GH_LOG="$SANDBOX/operations.log"

# A fresh case: three local artifacts, notes, and no release yet.
fresh() {
    rm -rf "$SANDBOX/artifacts"
    mkdir -p "$SANDBOX/artifacts"
    printf 'installer-zip' >"$SANDBOX/artifacts/WindowHop-1.2.3-Installer.zip"
    printf 'disk-image-bytes' >"$SANDBOX/artifacts/WindowHop-1.2.3.dmg"
    printf 'NEW-DATA' >"$SANDBOX/artifacts/WindowHop-1.2.3.zip"
    printf 'Notes.\n' >"$SANDBOX/notes.md"
    echo '{"exists": false, "draft": false, "assets": {}}' >"$FAKE_GH_STATE"
}

# Sets an existing release: $1 draft (true/false), then one name[=<bytes>|=nodigest] per
# asset. The asset gets the local file's size and the digest of <bytes> (default: the
# local file's own bytes), or no digest at all.
release() {
    python3 - "$FAKE_GH_STATE" "$SANDBOX/artifacts" "$@" <<'PY'
import hashlib, json, os, sys
path, folder, draft, specs = sys.argv[1], sys.argv[2], sys.argv[3] == "true", sys.argv[4:]
assets = {}
for spec in specs:
    name, _, content = spec.partition("=")
    local = open(os.path.join(folder, name), "rb").read()
    asset = {"size": len(local)}
    if content != "nodigest":
        asset["digest"] = "sha256:" + hashlib.sha256(content.encode() if content else local).hexdigest()
    assets[name] = asset
json.dump({"exists": True, "draft": draft, "assets": assets}, open(path, "w"))
PY
}
ALL=(WindowHop-1.2.3-Installer.zip WindowHop-1.2.3.dmg WindowHop-1.2.3.zip)

# Runs the real script as release.yml does; sets STATUS and leaves stderr in err.log.
publish() {
    : >"$FAKE_GH_LOG"
    STATUS=0
    PATH="$SANDBOX/bin:$PATH" "$REPO_ROOT/scripts/publish-release.sh" --tag v1.2.3 \
        --notes-file "$SANDBOX/notes.md" \
        --artifact "$SANDBOX/artifacts/WindowHop-1.2.3-Installer.zip" \
        --artifact "$SANDBOX/artifacts/WindowHop-1.2.3.dmg" \
        --artifact "$SANDBOX/artifacts/WindowHop-1.2.3.zip" \
        >"$SANDBOX/out.log" 2>"$SANDBOX/err.log" || STATUS=$?
}
operations() { tr '\n' ' ' <"$FAKE_GH_LOG" | sed 's/ $//'; }
draft() { python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["draft"])' "$FAKE_GH_STATE"; }
state() { # the release itself, without the fake's own query counter
    python3 -c 'import json, sys; s = json.load(open(sys.argv[1])); s.pop("draftQueries", None); print(json.dumps(s, sort_keys=True))' "$FAKE_GH_STATE"
}
writes() { grep -cE '^(create|upload|edit)' "$FAKE_GH_LOG" || true; }

# --- #52: an unreadable draft state is never read as public ---------------------------

# The audit's counterexample: a complete draft whose draft-state read times out once
# returned "already published" with the release still a draft.
fresh
release true "${ALL[@]}"
FAKE_GH_FAIL=view:isDraft publish
check "#52 unreadable draft state of an existing release fails" "$STATUS" "1"
check "#52 unreadable draft state writes nothing" "$(writes)" "0"
check "#52 unreadable draft state leaves the release a draft" "$(draft)" "True"
check "#52 unreadable draft state is reported" \
    "$(grep -c 'could not read whether release v1.2.3 is a draft' "$SANDBOX/err.log")" "1"

fresh
release true "${ALL[@]}"
FAKE_GH_FAIL=view:isDraft=null publish
check "#52 a draft state that is neither true nor false fails" "$STATUS" "1"
check "#52 a missing draft state writes nothing" "$(writes)" "0"

# A fresh publication whose final draft-state read (the first and only one) fails:
# the run fails, so release.yml never reaches the appcast step.
fresh
FAKE_GH_FAIL='view:isDraft#1' publish
check "#52 unreadable draft state after publishing fails" "$STATUS" "1"
check "#52 the failure comes after the publish attempt" \
    "$(operations)" "view create upload:WindowHop-1.2.3-Installer.zip upload:WindowHop-1.2.3.dmg upload:WindowHop-1.2.3.zip view edit:publish view"

fresh
FAKE_GH_FAIL=edit:noop publish
check "#52 a release still a draft after publishing fails" "$STATUS" "1"
check "#52 a release still a draft is reported" \
    "$(grep -c 'is still a draft after publishing' "$SANDBOX/err.log")" "1"

# Draft and public stay distinct outcomes: a readable draft is completed ...
fresh
release true "${ALL[@]}"
publish
check "#52 a readable draft is completed" "$STATUS" "0"
check "#52 a completed draft ends public" "$(draft)" "False"
check "#52 a completed draft is never recreated" "$(grep -c '^create$' "$FAKE_GH_LOG" || true)" "0"

# ... and a genuine public release with these exact artifacts is a read-only no-op.
fresh
release false "${ALL[@]}"
before=$(state)
publish
check "#52 a matching public release is a no-op" "$STATUS" "0"
check "#52 the no-op only reads" "$(operations)" "view view"
check "#52 the no-op leaves the release unchanged" "$(state)" "$before"

# --- #53: equal name and size is not equal content ------------------------------------

# The audit's counterexample: the public update archive holds OLD-DATA, the rebuilt one
# NEW-DATA — eight bytes each, so a size-only check accepted the rerun.
fresh
release false WindowHop-1.2.3-Installer.zip WindowHop-1.2.3.dmg WindowHop-1.2.3.zip=OLD-DATA
before=$(state)
publish
check "#53 a same-size public asset with other bytes fails" "$STATUS" "1"
check "#53 a same-size mismatch only reads" "$(operations)" "view view"
check "#53 a same-size mismatch leaves the public release unchanged" "$(state)" "$before"
check "#53 a same-size mismatch is reported" \
    "$(grep -c 'asset WindowHop-1.2.3.zip is sha256:' "$SANDBOX/err.log")" "1"

# An identical rerun is still a read-only no-op, now proven by digest.
fresh
release false "${ALL[@]}"
publish
check "#53 an identical public release is a no-op" "$STATUS" "0"
check "#53 an identical rerun only reads" "$(operations)" "view view"

# An asset GitHub reports no digest for cannot be verified, so it is never a match.
fresh
release false WindowHop-1.2.3-Installer.zip WindowHop-1.2.3.dmg WindowHop-1.2.3.zip=nodigest
publish
check "#53 a public asset without a digest fails" "$STATUS" "1"
check "#53 a public asset without a digest writes nothing" "$(writes)" "0"

# A draft is not yet public, so a same-size wrong asset there is re-uploaded, verified
# and published: drafts heal, public releases never do.
fresh
release true WindowHop-1.2.3-Installer.zip WindowHop-1.2.3.dmg WindowHop-1.2.3.zip=OLD-DATA
publish
check "#53 a draft with a same-size wrong asset is repaired" "$STATUS" "0"
check "#53 the repaired draft ends public" "$(draft)" "False"

# Bytes altered on the way up keep their size but not their digest: the draft is never
# published, so release.yml never writes an appcast entry whose signature describes the
# local archive rather than the stored one.
fresh
FAKE_GH_FAIL=upload:WindowHop-1.2.3.zip:corrupt publish
check "#53 an upload stored with other bytes fails" "$STATUS" "1"
check "#53 an upload stored with other bytes is never published" \
    "$(grep -c '^edit:publish$' "$FAKE_GH_LOG" || true)" "0"
check "#53 an upload stored with other bytes stays a draft" "$(draft)" "True"

if [ "$FAILED" -gt 0 ]; then
    echo "publish-release: $FAILED failed, $PASSED passed" >&2
    exit 1
fi
echo "publish-release: all $PASSED checks passed"
