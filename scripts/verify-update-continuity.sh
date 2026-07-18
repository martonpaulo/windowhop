#!/bin/bash
# Compares two signed release apps before an update test. TCC continuity depends
# on the effective signing requirement staying stable; the actual permission
# grant is then exercised manually through the release checklist.
set -euo pipefail
cd "$(dirname "$0")/.."

[ "$#" -eq 2 ] || {
    echo "usage: scripts/verify-update-continuity.sh <previous.app> <candidate.app>" >&2
    exit 2
}
PREVIOUS=$1
CANDIDATE=$2

scripts/verify-release-identity.sh "$PREVIOUS"
scripts/verify-release-identity.sh "$CANDIDATE"

requirement() {
    codesign -dr - "$1" 2>&1 | sed -n 's/^designated => //p'
}
identifier() {
    codesign -dvvv "$1" 2>&1 | sed -n 's/^Identifier=//p'
}
team() {
    codesign -dvvv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p'
}

[ "$(requirement "$PREVIOUS")" = "$(requirement "$CANDIDATE")" ] || {
    echo "Update continuity failed: designated requirements differ." >&2
    exit 1
}
[ "$(identifier "$PREVIOUS")" = "$(identifier "$CANDIDATE")" ] || {
    echo "Update continuity failed: signing identifiers differ." >&2
    exit 1
}
[ "$(team "$PREVIOUS")" = "$(team "$CANDIDATE")" ] || {
    echo "Update continuity failed: TeamIdentifiers differ." >&2
    exit 1
}

echo "update identity continuity: ok"
