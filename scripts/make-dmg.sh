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
# create-dmg signs the DMG with the first available identity, or skips with a
# warning when none exists — both fine (the app inside carries its own signature)
(cd artifacts && npx --yes "create-dmg@$CREATE_DMG_VERSION" ../build/WindowHop.app .)
mv "artifacts/WindowHop $VERSION.dmg" "$DMG"
hdiutil verify "$DMG" -quiet && echo "hdiutil verify: ok"
echo "created $DMG"
