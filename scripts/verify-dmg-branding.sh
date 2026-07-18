#!/bin/bash
# Verifies the portable DMG contents plus the local Finder custom-icon metadata.
set -euo pipefail
cd "$(dirname "$0")/.."

DMG=${1:?usage: scripts/verify-dmg-branding.sh <installer.dmg>}
[ -f "$DMG" ] || { echo "DMG branding validation failed: missing $DMG" >&2; exit 1; }
hdiutil verify "$DMG" -quiet
GetFileInfo -a "$DMG" | grep -q C || {
    echo "DMG branding validation failed: Finder custom-icon flag is absent." >&2
    exit 1
}
DeRez -only icns "$DMG" | grep -F "data 'icns'" >/dev/null || {
    echo "DMG branding validation failed: custom Finder icon resource is absent." >&2
    exit 1
}

MOUNT=$(mktemp -d)
cleanup() {
    hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true
    rmdir "$MOUNT" >/dev/null 2>&1 || true
}
trap cleanup EXIT
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null
cmp Support/AppInstallerIcon.icns "$MOUNT/.VolumeIcon.icns" || {
    echo "DMG branding validation failed: mounted-volume icon differs." >&2
    exit 1
}
[ -f "$MOUNT/.DS_Store" ] || {
    echo "DMG branding validation failed: Finder layout is absent." >&2
    exit 1
}
[ -f "$MOUNT/.background/WindowHopInstallerBackground.tiff" ] || {
    echo "DMG branding validation failed: installer artwork is absent." >&2
    exit 1
}
[ -d "$MOUNT/WindowHop.app" ] && [ -L "$MOUNT/Applications" ] || {
    echo "DMG branding validation failed: draggable app or Applications alias is absent." >&2
    exit 1
}

echo "DMG branding: ok (Finder icon, volume icon, background, layout, app and alias)"
