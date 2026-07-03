#!/bin/bash
# Creates a distributable DMG with WindowHop.app and an Applications shortcut.
# Usage: scripts/make-dmg.sh <version>   (expects build/WindowHop.app to exist)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
STAGING=build/dmg-staging
DMG="artifacts/WindowHop-$VERSION.dmg"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING" artifacts
ditto build/WindowHop.app "$STAGING/WindowHop.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "WindowHop $VERSION" -srcfolder "$STAGING" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGING"
echo "created $DMG"
