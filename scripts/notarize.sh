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
# Usage: scripts/notarize.sh <artifact.dmg|artifact.pkg|artifact.zip>
set -euo pipefail

if [[ $# -ne 1 || ! -f $1 ]]; then
  echo "usage: $0 <artifact.dmg|artifact.pkg|artifact.zip>" >&2
  exit 2
fi
artifact=$1

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
