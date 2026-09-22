#!/usr/bin/env bash
# Canonical Sparkle key script for the owner's macOS apps. Copy it unchanged to
# scripts/make-keys.sh in each app; project-setup alignment reports a drifted copy.
#
# One-time setup per machine: makes sure the login Keychain holds a Sparkle EdDSA key, using
# Sparkle's generate_keys from .build/artifacts, and records its public half as SUPublicEDKey in
# Support/Info.plist. The private key never leaves the Keychain and is never committed.
#
# A committed SUPublicEDKey that differs from the Keychain's is refused unless --force is given:
# every installed copy checks updates against the committed key, so replacing it by accident
# breaks every later update. Rotating a key on purpose also needs Sparkle's rotation procedure.
#
# Prints the public key alone on stdout and everything else on stderr.
set -euo pipefail
cd "$(dirname "$0")/.."

PLIST_BUDDY=${PLIST_BUDDY:-/usr/libexec/PlistBuddy}
PLIST=Support/Info.plist

usage() {
  cat <<'USAGE'
usage: scripts/make-keys.sh [--force]
  --force   replace a committed SUPublicEDKey that differs from the Keychain's key
  --help    show this help
USAGE
}

force=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --force) force=1; shift ;;
    --help) usage; exit 0 ;;
    *) echo "error: unknown option $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ -f $PLIST ]] || { echo "error: $PLIST not found; run this from an app repository" >&2; exit 1; }

find_generate_keys() {
  [[ -d .build/artifacts ]] || return 0
  find .build/artifacts -path '*/bin/generate_keys' -type f -print -quit
}
generate_keys=$(find_generate_keys)
if [[ -z $generate_keys ]]; then
  echo "generate_keys not found under .build/artifacts; running swift build once." >&2
  swift build >&2 || { echo "error: swift build failed" >&2; exit 1; }
  generate_keys=$(find_generate_keys)
fi
[[ -n $generate_keys ]] || { echo "error: generate_keys not found under .build/artifacts" >&2; exit 1; }

# Creates a key only when the Keychain has none; its own message says which happened.
"$generate_keys" >&2 || true
public_key=$("$generate_keys" -p) || { echo "error: generate_keys -p failed" >&2; exit 1; }
public_key=${public_key//[[:space:]]/}
key_shape='^[A-Za-z0-9+/]{43}=$'
[[ $public_key =~ $key_shape ]] \
  || { echo "error: generate_keys -p printed '$public_key', which is not an Ed25519 public key" >&2; exit 1; }

if committed=$("$PLIST_BUDDY" -c 'Print :SUPublicEDKey' "$PLIST" 2>/dev/null); then
  if [[ $committed == "$public_key" ]]; then
    echo "SUPublicEDKey in $PLIST already matches the Keychain's key." >&2
  elif (( force )); then
    "$PLIST_BUDDY" -c "Set :SUPublicEDKey $public_key" "$PLIST"
    echo "SUPublicEDKey in $PLIST replaced: $committed -> $public_key" >&2
  else
    echo "error: $PLIST has SUPublicEDKey $committed, but the Keychain's key is $public_key." >&2
    echo "Every installed copy trusts the committed key; pass --force only to rotate it on purpose." >&2
    exit 1
  fi
else
  "$PLIST_BUDDY" -c "Add :SUPublicEDKey string $public_key" "$PLIST"
  echo "SUPublicEDKey added to $PLIST." >&2
fi
echo "The private key stays in the login Keychain. Never commit it." >&2
printf '%s\n' "$public_key"
