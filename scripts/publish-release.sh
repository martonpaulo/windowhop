#!/bin/bash
# Publishes one GitHub release, artifacts first.
#
# The updater feed may only advertise files that already exist, so this script
# is the verified predecessor of any appcast change: it stages every artifact in
# a draft, verifies the complete set against the local files, publishes, and
# verifies again against the public release. It never overwrites an asset that
# is already public and never reports success for a partial publication.
#
# Usage: scripts/publish-release.sh <tag> <notes-file> <artifact>...
# Idempotent: re-running against a complete, matching public release is a
# read-only no-op.
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="$1"
NOTES_FILE="$2"
shift 2
ARTIFACTS=("$@")

die() { echo "$1" >&2; exit 1; }

[ ${#ARTIFACTS[@]} -gt 0 ] || die "No artifacts given."
[ -s "$NOTES_FILE" ] || die "Release notes file $NOTES_FILE is missing or empty."
for artifact in "${ARTIFACTS[@]}"; do
    [ -f "$artifact" ] || die "Artifact $artifact does not exist."
done

local_size() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1"; }

# Prints "name<TAB>size" for every asset of the release.
# Exit 0 = release read; 1 = release does not exist; 2 = the lookup itself
# failed. The three are kept apart because an auth or network error must never
# be read as "no release yet" — `die` inside a command substitution would only
# end the subshell and leave the caller creating a duplicate release.
release_assets() {
    local output status
    output=$(gh release view "$TAG" --json assets 2>&1) && status=0 || status=$?
    if [ $status -ne 0 ]; then
        case "$output" in
            *"release not found"*|*"Not Found"*|*"not found"*) return 1 ;;
            *) printf 'Could not read release %s: %s\n' "$TAG" "$output" >&2; return 2 ;;
        esac
    fi
    printf '%s' "$output" | python3 -c '
import json, sys
for asset in json.load(sys.stdin)["assets"]:
    print("%s\t%s" % (asset["name"], asset["size"]))
'
}

# Same call, but any lookup failure other than "does not exist" is fatal.
require_release_assets() {
    local output status
    output=$(release_assets) && status=0 || status=$?
    [ $status -eq 2 ] && exit 1
    [ $status -eq 0 ] || die "Release $TAG disappeared while publishing it."
    printf '%s' "$output"
}

release_is_draft() {
    [ "$(gh release view "$TAG" --json isDraft --jq .isDraft)" = "true" ]
}

# Every local artifact must be present with exactly its local byte count.
verify_assets() {
    local assets="$1" artifact name size published
    for artifact in "${ARTIFACTS[@]}"; do
        name=$(basename "$artifact")
        size=$(local_size "$artifact")
        published=$(printf '%s\n' "$assets" | awk -F'\t' -v n="$name" '$1 == n { print $2 }')
        [ -n "$published" ] || die "Release $TAG is missing asset $name."
        [ "$published" = "$size" ] \
            || die "Asset $name is $published bytes on the release but $size bytes locally."
    done
}

EXISTING=$(release_assets) && LOOKUP=0 || LOOKUP=$?
[ "$LOOKUP" -eq 2 ] && exit 1
if [ "$LOOKUP" -eq 0 ]; then
    if release_is_draft; then
        echo "release $TAG exists as a draft; completing it"
    else
        # A public release is never rewritten. Either it is already exactly what
        # this run would publish, or an operator has to resolve the conflict.
        verify_assets "$EXISTING"
        echo "release $TAG is already published with the expected assets; nothing to do"
        exit 0
    fi
else
    echo "creating draft release $TAG"
    gh release create "$TAG" --draft --title "WindowHop ${TAG#v}" --notes-file "$NOTES_FILE"
fi

# --clobber is safe here: the release is still a draft, so nothing it replaces
# was ever advertised or downloadable.
for artifact in "${ARTIFACTS[@]}"; do
    echo "uploading $(basename "$artifact")"
    gh release upload "$TAG" "$artifact" --clobber
done

verify_assets "$(require_release_assets)"
echo "draft $TAG holds the complete artifact set; publishing"
gh release edit "$TAG" --draft=false

release_is_draft && die "Release $TAG is still a draft after publishing."
verify_assets "$(require_release_assets)"
echo "release $TAG is public with every artifact verified"
