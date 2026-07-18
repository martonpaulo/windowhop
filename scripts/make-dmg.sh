#!/bin/bash
# Creates the WindowHop installer DMG: drag-to-Applications layout with
# background artwork, fixed icon positions, a volume icon, and (locally) a
# matching icon on the .dmg file itself. Built with appdmg (pinned), which
# writes the Finder layout (.DS_Store) programmatically — works headless on
# CI, no Finder scripting.
# Usage: scripts/make-dmg.sh <version>   (expects build/WindowHop.app to exist)
set -euo pipefail
cd "$(dirname "$0")/.."

DEFAULT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)
VERSION="${1:-$DEFAULT_VERSION}"
APPDMG_VERSION=0.6.6
DMG="artifacts/WindowHop-$VERSION.dmg"

[ -d build/WindowHop.app ] || { echo "build/WindowHop.app missing; run scripts/package-app.sh first"; exit 1; }

mkdir -p artifacts
rm -f "$DMG"

# icon centers must stay in sync with the background artwork
# (scripts/render-dmg-background.swift): window 680x400, icons at y 225
cat > artifacts/dmg-spec.json <<JSON
{
  "title": "WindowHop $VERSION",
  "icon": "../Support/AppInstallerIcon.icns",
  "background": "../Support/WindowHopInstallerBackground.tiff",
  "icon-size": 112,
  "window": { "size": { "width": 680, "height": 400 } },
  "contents": [
    { "x": 180, "y": 225, "type": "file", "path": "../build/WindowHop.app" },
    { "x": 500, "y": 225, "type": "link", "path": "/Applications" }
  ]
}
JSON
npx --yes "appdmg@$APPDMG_VERSION" artifacts/dmg-spec.json "$DMG"
rm -f artifacts/dmg-spec.json

# give the .dmg file itself the WindowHop icon (resource fork; survives local
# copies — download services strip xattrs, so the VOLUME icon is the one every
# user sees after mounting)
if xcrun --find Rez >/dev/null 2>&1 && command -v SetFile >/dev/null 2>&1; then
    # sips -i gives the icns a resource fork holding itself, which DeRez can
    # then extract (flat icns files have none)
    cp Support/AppInstallerIcon.icns artifacts/dmg-file-icon.icns
    sips -i artifacts/dmg-file-icon.icns >/dev/null
    DeRez -only icns artifacts/dmg-file-icon.icns > artifacts/dmg-icon.rsrc
    Rez -append artifacts/dmg-icon.rsrc -o "$DMG"
    SetFile -a C "$DMG"
    rm -f artifacts/dmg-file-icon.icns artifacts/dmg-icon.rsrc
fi

# Official CI passes its validated Developer ID identity explicitly. Local
# builds remain unsigned unless the caller intentionally provides an identity.
if [ -n "${DEVELOPER_ID_IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$DEVELOPER_ID_IDENTITY" "$DMG"
    echo "signed with $DEVELOPER_ID_IDENTITY"
fi

hdiutil verify "$DMG" -quiet && echo "hdiutil verify: ok"
echo "created $DMG"
