#!/bin/bash
# Compares two signed release apps before an update test. TCC continuity depends
# on the effective signing requirement staying stable; the actual permission
# grant is then exercised manually through the release checklist.
#
# --identifier-transition <old> <new> is for the one release that moves the
# bundle identifier (#43), where continuity is deliberately broken in exactly
# one place. The previous app must be signed as <old>, the candidate as <new>
# (the identifier in Support/Info.plist), and their designated requirements may
# differ only in the `identifier "…"` clause: the team, the leaf certificate
# and every other clause must still match. Users still grant Accessibility
# again after that update, because TCC keys the grant to the identifier.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
    echo "usage: scripts/verify-update-continuity.sh [--identifier-transition <old> <new>]" \
        "<previous.app> <candidate.app>" >&2
    exit 2
}
fail() {
    echo "Update continuity failed: $1" >&2
    exit 1
}

OLD_ID=''
NEW_ID=''
if [ "${1:-}" = --identifier-transition ]; then
    [ "$#" -eq 5 ] || usage
    OLD_ID=$2
    NEW_ID=$3
    shift 3
    identifier_shape='^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$'
    [[ $OLD_ID =~ $identifier_shape && $NEW_ID =~ $identifier_shape ]] || usage
    [ "$OLD_ID" != "$NEW_ID" ] || usage
    plist_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Support/Info.plist)
    [ "$NEW_ID" = "$plist_id" ] || {
        echo "error: <new> must be the identifier in Support/Info.plist ($plist_id)" >&2
        exit 2
    }
fi
[ "$#" -eq 2 ] || usage
[ -d "$1" ] || fail "app not found: $1"
[ -d "$2" ] || fail "app not found: $2"
PREVIOUS=$(cd "$1" && pwd)
CANDIDATE=$(cd "$2" && pwd)

requirement() {
    codesign -dr - "$1" 2>&1 | sed -n 's/^designated => //p'
}
identifier() {
    codesign -dvvv "$1" 2>&1 | sed -n 's/^Identifier=//p'
}
team() {
    codesign -dvvv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p'
}

scripts/verify-release-identity.sh --app "$CANDIDATE"

if [ -z "$OLD_ID" ]; then
    scripts/verify-release-identity.sh --app "$PREVIOUS"
    [ "$(requirement "$PREVIOUS")" = "$(requirement "$CANDIDATE")" ] \
        || fail "designated requirements differ."
    [ "$(identifier "$PREVIOUS")" = "$(identifier "$CANDIDATE")" ] \
        || fail "signing identifiers differ."
else
    # The previous app gets the full release-identity contract as it stood under
    # <old>: a throwaway copy of the fixtures with only the identifier swapped.
    expected=$(tr -d '\n' <Support/ExpectedDesignatedRequirement.txt)
    [[ $expected == "identifier \"$NEW_ID\" "* ]] \
        || fail "Support/ExpectedDesignatedRequirement.txt does not start with identifier \"$NEW_ID\""
    fixtures=$(mktemp -d)
    trap 'rm -rf "$fixtures"' EXIT
    mkdir -p "$fixtures/scripts" "$fixtures/Support"
    cp scripts/verify-release-identity.sh "$fixtures/scripts/"
    cp Support/Info.plist Support/ReleaseCertificate.cer "$fixtures/Support/"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $OLD_ID" "$fixtures/Support/Info.plist"
    printf '%s\n' "identifier \"$OLD_ID\" ${expected#"identifier \"$NEW_ID\" "}" \
        >"$fixtures/Support/ExpectedDesignatedRequirement.txt"
    "$fixtures/scripts/verify-release-identity.sh" --app "$PREVIOUS"

    previous_requirement=$(requirement "$PREVIOUS")
    [[ $previous_requirement == "identifier \"$OLD_ID\" "* ]] \
        || fail "the previous requirement does not start with identifier \"$OLD_ID\"."
    [ "identifier \"$NEW_ID\" ${previous_requirement#"identifier \"$OLD_ID\" "}" \
        = "$(requirement "$CANDIDATE")" ] \
        || fail "designated requirements differ beyond the identifier clause."
    [ "$(identifier "$PREVIOUS")" = "$OLD_ID" ] || fail "the previous app is not signed as $OLD_ID."
    [ "$(identifier "$CANDIDATE")" = "$NEW_ID" ] || fail "the candidate is not signed as $NEW_ID."
fi
[ "$(team "$PREVIOUS")" = "$(team "$CANDIDATE")" ] || fail "TeamIdentifiers differ."

if [ -z "$OLD_ID" ]; then
    echo "update identity continuity: ok"
else
    echo "update identity continuity: ok (identifier transition $OLD_ID -> $NEW_ID)"
fi
