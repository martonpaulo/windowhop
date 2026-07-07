#!/bin/bash
# Creates the beginner-facing WindowHop DMG with sindresorhus/create-dmg
# (pinned): the standard polished drag-to-Applications layout, written
# programmatically — works headless on CI, no Finder scripting.
# Usage: scripts/make-dmg.sh <version>   (expects build/WindowHop.app to exist)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
CREATE_DMG_VERSION=8.0.0
DMG="artifacts/WindowHop-$VERSION.dmg"

[ -d build/WindowHop.app ] || { echo "build/WindowHop.app missing; run scripts/package-app.sh first"; exit 1; }

mkdir -p artifacts
rm -f "$DMG" "artifacts/WindowHop $VERSION.dmg"
# create-dmg only auto-detects Apple-issued identities and hard-fails otherwise;
# point it at the stable WindowHop identity when that's what the keychain has
IDENTITY_ARGS=()
if security find-identity -v -p codesigning 2>/dev/null | grep -q '"WindowHop Code Signing"'; then
    IDENTITY_ARGS=("--identity=WindowHop Code Signing")
fi
# ${arr[@]+...} keeps macOS bash 3.2 happy about empty arrays under set -u
(cd artifacts && npx --yes "create-dmg@$CREATE_DMG_VERSION" \
    ${IDENTITY_ARGS[@]+"${IDENTITY_ARGS[@]}"} ../build/WindowHop.app .)
mv "artifacts/WindowHop $VERSION.dmg" "$DMG"
hdiutil verify "$DMG" -quiet && echo "hdiutil verify: ok"
echo "created $DMG"
