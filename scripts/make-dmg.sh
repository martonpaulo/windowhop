#!/bin/bash
# Creates the beginner-facing WindowHop DMG: drag-to-install layout with a
# branded background, large icons, and an Applications shortcut. Build-time
# native tooling only (hdiutil + Finder scripting for the .DS_Store layout).
# Usage: scripts/make-dmg.sh <version>   (expects build/WindowHop.app to exist)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
VOLUME_NAME="WindowHop"
STAGING=build/dmg-staging
RW_DMG=build/WindowHop-rw.dmg
DMG="artifacts/WindowHop-$VERSION.dmg"
MOUNT_POINT="/Volumes/$VOLUME_NAME"

[ -d build/WindowHop.app ] || { echo "build/WindowHop.app missing; run scripts/package-app.sh first"; exit 1; }

# background artwork (1x + 2x combined into one Retina-aware TIFF)
swift scripts/make-dmg-background.swift build/dmg-bg >/dev/null
tiffutil -cathidpicheck build/dmg-bg/background.png build/dmg-bg/background@2x.png \
    -out build/dmg-bg/background.tiff 2>/dev/null

rm -rf "$STAGING" "$RW_DMG" "$DMG"
mkdir -p "$STAGING/.background" artifacts
ditto build/WindowHop.app "$STAGING/WindowHop.app"
ln -s /Applications "$STAGING/Applications"
cp build/dmg-bg/background.tiff "$STAGING/.background/background.tiff"

# writable image first so Finder can persist the icon layout into .DS_Store
hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING" -ov -format UDRW -quiet "$RW_DMG"
hdiutil attach "$RW_DMG" -mountpoint "$MOUNT_POINT" -noautoopen -quiet

# Finder scripting needs a GUI session; on headless CI the DMG still works,
# just without the custom icon layout
osascript <<EOF || echo "warning: Finder layout scripting unavailable; using default layout"
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 140, 860, 590}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "WindowHop.app" of container window to {165, 210}
        set position of item "Applications" of container window to {495, 210}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF
sync
hdiutil detach "$MOUNT_POINT" -quiet

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" -quiet
rm -f "$RW_DMG"
rm -rf "$STAGING"
hdiutil verify "$DMG" -quiet && echo "hdiutil verify: ok"
echo "created $DMG"
