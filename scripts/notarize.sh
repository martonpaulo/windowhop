#!/usr/bin/env bash
# Canonical notarization script for the owner's macOS apps. Copy it unchanged to
# scripts/notarize.sh in each app; project-setup alignment reports a drifted copy.
#
# Submits one artifact to the Apple notary service, waits, prints the notary log
# on any result other than Accepted, and staples a disk image or installer
# package in place. A ZIP cannot be stapled: staple the .app it was made from.
#
# Credentials, chosen by environment and never printed:
#   CI:    NOTARY_API_KEY_PATH, NOTARY_API_KEY_ID, NOTARY_API_ISSUER_ID
#   Mac:   the Keychain profile NOTARY_PROFILE, default skd-notary
#
# Usage: scripts/notarize.sh --artifact <artifact.dmg|artifact.pkg|artifact.zip>
# The artifact is resolved against the caller's directory before the cd into the repository.
# A bare path still works with a warning until every app passes --artifact (#370).
set -euo pipefail

usage() {
  cat <<USAGE
usage: scripts/notarize.sh --artifact <artifact.dmg|artifact.pkg|artifact.zip>
  --artifact <path>   the disk image, installer package or ZIP to notarize
  --help              show this help
Credentials, chosen by environment and never printed:
  CI:    NOTARY_API_KEY_PATH, NOTARY_API_KEY_ID, NOTARY_API_ISSUER_ID
  Mac:   the Keychain profile NOTARY_PROFILE, default skd-notary
USAGE
}

fail_usage() { echo "error: $1" >&2; usage >&2; exit 2; }
need_value() { [[ $# -ge 2 && -n $2 && $2 != --* ]] || fail_usage "$1 needs a value"; }

artifact=''
positional=''
while [[ $# -gt 0 ]]; do
  case $1 in
    --artifact)
      need_value "$@"
      [[ -z $artifact ]] || fail_usage 'give --artifact once'
      artifact=$2
      shift 2
      ;;
    --help) usage; exit 0 ;;
    -*) fail_usage "unknown option $1" ;;
    *) [[ -z $positional ]] || fail_usage 'give one artifact'; positional=$1; shift ;;
  esac
done
if [[ -n $positional ]]; then
  [[ -z $artifact ]] || fail_usage 'give the artifact once, with --artifact'
  echo "warning: scripts/notarize.sh <path> is deprecated and will be removed; call scripts/notarize.sh --artifact $positional" >&2
  artifact=$positional
fi
[[ -n $artifact ]] || fail_usage '--artifact is required'
[[ -f $artifact ]] || fail_usage "artifact $artifact not found"
# Resolved before the cd, so a relative path means what it meant to the caller.
artifact=$(cd "$(dirname "$artifact")" && pwd)/$(basename "$artifact")
cd "$(dirname "$0")/.."

if [[ -n ${NOTARY_API_KEY_PATH:-} ]]; then
  : "${NOTARY_API_KEY_ID:?set NOTARY_API_KEY_ID with NOTARY_API_KEY_PATH}"
  : "${NOTARY_API_ISSUER_ID:?set NOTARY_API_ISSUER_ID with NOTARY_API_KEY_PATH}"
  [[ -f $NOTARY_API_KEY_PATH ]] || { echo "error: NOTARY_API_KEY_PATH is not a file" >&2; exit 1; }
  auth=(--key "$NOTARY_API_KEY_PATH" --key-id "$NOTARY_API_KEY_ID" --issuer "$NOTARY_API_ISSUER_ID")
  echo "Notarizing $(basename "$artifact") with API key $NOTARY_API_KEY_ID."
else
  profile=${NOTARY_PROFILE:-skd-notary}
  auth=(--keychain-profile "$profile")
  echo "Notarizing $(basename "$artifact") with Keychain profile $profile."
fi

result=$(xcrun notarytool submit "$artifact" "${auth[@]}" --wait --output-format json)
status=$(plutil -extract status raw -o - - <<<"$result" 2>/dev/null || echo unknown)
id=$(plutil -extract id raw -o - - <<<"$result" 2>/dev/null || echo unknown)
echo "Submission $id: $status"

if [[ $status != Accepted ]]; then
  [[ $id != unknown ]] && xcrun notarytool log "$id" "${auth[@]}" >&2 || true
  exit 1
fi

case $artifact in
  *.dmg | *.pkg)
    xcrun stapler staple "$artifact"
    xcrun stapler validate "$artifact"
    ;;
  *.zip)
    echo "ZIP accepted; staple the .app inside it and rebuild the ZIP."
    ;;
esac
