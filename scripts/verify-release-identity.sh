#!/bin/bash
# Rejects artifacts that would change WindowHop's effective macOS identity and
# invalidate an existing TCC grant. Run after signing and again from the DMG.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-build/WindowHop.app}"
EXPECTED_IDENTIFIER=com.perso.windowhop
EXPECTED_TEAM=TBN79KU9ML
EXPECTED_CERT=Support/WindowHopCodeSigning.cer
EXPECTED_REQUIREMENT=$(tr -d '\n' < Support/ExpectedDesignatedRequirement.txt)

[ -d "$APP" ] || { echo "Identity validation failed: app not found: $APP" >&2; exit 1; }
codesign --verify --deep --strict --verbose=2 "$APP"

SIGNATURE=$(codesign -dvvv "$APP" 2>&1)
grep -qx "Identifier=$EXPECTED_IDENTIFIER" <<< "$SIGNATURE" || {
    echo "Identity validation failed: signing identifier is not $EXPECTED_IDENTIFIER." >&2
    exit 1
}
grep -qx "TeamIdentifier=$EXPECTED_TEAM" <<< "$SIGNATURE" || {
    echo "Identity validation failed: TeamIdentifier is not $EXPECTED_TEAM." >&2
    exit 1
}
grep -q '^Authority=Developer ID Application: Marton Paulo (TBN79KU9ML)$' <<< "$SIGNATURE" || {
    echo "Identity validation failed: expected Developer ID Application authority is absent." >&2
    exit 1
}
grep -q 'flags=.*runtime' <<< "$SIGNATURE" || {
    echo "Identity validation failed: Hardened Runtime is absent." >&2
    exit 1
}
if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q .; then
    echo "Identity validation failed: application entitlements changed from the stable empty set." >&2
    exit 1
fi

ACTUAL_REQUIREMENT=$(codesign -dr - "$APP" 2>&1 | sed -n 's/^designated => //p')
[ "$ACTUAL_REQUIREMENT" = "$EXPECTED_REQUIREMENT" ] || {
    echo "Identity validation failed: designated requirement changed." >&2
    echo "expected: $EXPECTED_REQUIREMENT" >&2
    echo "actual:   $ACTUAL_REQUIREMENT" >&2
    exit 1
}

CERT_DIR=$(mktemp -d)
trap 'find "$CERT_DIR" -type f -delete; rmdir "$CERT_DIR"' EXIT
codesign -d --extract-certificates="$CERT_DIR/leaf" "$APP" 2>/dev/null
cmp -s "$EXPECTED_CERT" "$CERT_DIR/leaf0" || {
    echo "Identity validation failed: release certificate differs from the stable WindowHop certificate." >&2
    exit 1
}

while IFS= read -r executable; do
    file "$executable" | grep -q 'Mach-O' || continue
    codesign --verify --strict "$executable"
    NESTED_SIGNATURE=$(codesign -dvvv "$executable" 2>&1)
    grep -qx "TeamIdentifier=$EXPECTED_TEAM" <<< "$NESTED_SIGNATURE" || {
        echo "Identity validation failed: nested code uses another team: $executable" >&2
        exit 1
    }
done < <(find "$APP/Contents" -type f -perm -111 -print)

echo "release identity: ok ($EXPECTED_IDENTIFIER, team $EXPECTED_TEAM, stable certificate and requirement)"
