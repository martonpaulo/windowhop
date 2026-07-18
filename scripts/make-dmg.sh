#!/bin/bash
# Creates the WindowHop installer DMG: drag-to-Applications layout with
# background artwork, fixed icon positions, a volume icon, and (locally) a
# matching icon on the .dmg file itself. Built with appdmg (pinned), which
# writes the Finder layout (.DS_Store) programmatically — works headless on
# CI, no Finder scripting.
# Usage: scripts/make-dmg.sh <version>   (expects build/WindowHop.app to exist)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
APPDMG_VERSION=0.6.6
DMG="artifacts/WindowHop-$VERSION.dmg"

[ -d build/WindowHop.app ] || { echo "build/WindowHop.app missing; run scripts/package-app.sh first"; exit 1; }

mkdir -p artifacts
rm -f "$DMG"

# icon centers must stay in sync with the background artwork
# (scripts/render-dmg-background.swift): window 660x420, icons at y 220
cat > artifacts/dmg-spec.json <<'JSON'
{
  "title": "WindowHop",
  "icon": "../Support/AppIcon.icns",
  "background": "../Support/dmg-background.tiff",
  "icon-size": 128,
  "window": { "size": { "width": 660, "height": 420 } },
  "contents": [
    { "x": 180, "y": 220, "type": "file", "path": "../build/WindowHop.app" },
    { "x": 480, "y": 220, "type": "link", "path": "/Applications" }
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
    cp Support/AppIcon.icns artifacts/dmg-file-icon.icns
    sips -i artifacts/dmg-file-icon.icns >/dev/null
    DeRez -only icns artifacts/dmg-file-icon.icns > artifacts/dmg-icon.rsrc
    Rez -append artifacts/dmg-icon.rsrc -o "$DMG"
    SetFile -a C "$DMG"
    rm -f artifacts/dmg-file-icon.icns artifacts/dmg-icon.rsrc
fi

# sign with the stable WindowHop identity when the keychain has it (CI and
# release machines); unsigned DMGs remain valid for local inspection
if security find-identity -v -p codesigning 2>/dev/null | grep -q '"WindowHop Code Signing"'; then
    codesign --force --sign "WindowHop Code Signing" "$DMG"
    echo "signed with WindowHop Code Signing"
fi

hdiutil verify "$DMG" -quiet && echo "hdiutil verify: ok"
echo "created $DMG"
