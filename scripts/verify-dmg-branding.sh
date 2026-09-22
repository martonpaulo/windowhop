#!/usr/bin/env bash
# Canonical installer-DMG check for the owner's macOS apps. Copy it unchanged to
# scripts/verify-dmg-branding.sh in each app; project-setup alignment reports a drifted copy.
#
# Verifies what make-dmg.sh promises: the image passes hdiutil verify; the .dmg file carries the
# Finder custom-icon flag and its icns resource; and, mounted read-only, the volume has the
# installer icon from Support/AppInstallerIcon.icns, a Finder layout, the background
# <Name>InstallerBackground.tiff, the app and the Applications link. The image is always detached
# again, whatever fails.
#
# Prints one `DMG branding: ok` line on stdout and everything else on stderr.
set -euo pipefail
cd "$(dirname "$0")/.."

PLIST_BUDDY=${PLIST_BUDDY:-/usr/libexec/PlistBuddy}
PLIST=Support/Info.plist
ICON=Support/AppInstallerIcon.icns

usage() {
  cat <<'USAGE'
usage: scripts/verify-dmg-branding.sh --dmg <path.dmg>
  --dmg <path.dmg>   the installer disk image to check
  --help             show this help
USAGE
}

fail_usage() { echo "error: $1" >&2; usage >&2; exit 2; }
fail() { echo "DMG branding validation failed: $1" >&2; exit 1; }

dmg=''
while [[ $# -gt 0 ]]; do
  case $1 in
    --dmg)
      [[ $# -ge 2 && -n $2 && $2 != --* ]] || fail_usage '--dmg needs a value'
      dmg=$2; shift 2 ;;
    --help) usage; exit 0 ;;
    *) fail_usage "unknown option $1" ;;
  esac
done
# No default: one taken from the plist version could check a stale image.
[[ -n $dmg ]] || fail_usage '--dmg is required'

[[ -f $PLIST ]] || fail "$PLIST not found; run this from an app repository"
name=$("$PLIST_BUDDY" -c 'Print :CFBundleName' "$PLIST" 2>/dev/null) || fail "$PLIST has no CFBundleName"
[[ -f $dmg ]] || fail "$dmg not found"
[[ -f $ICON ]] || fail "$ICON not found"

hdiutil verify -quiet "$dmg" >&2 || fail "hdiutil verify failed"
attributes=$(GetFileInfo -a "$dmg") || fail "GetFileInfo could not read the Finder attributes"
[[ $attributes == *C* ]] || fail "the Finder custom-icon flag is absent"
resources=$(DeRez -only icns "$dmg") || fail "DeRez could not read the resource fork"
grep -Fq "data 'icns'" <<<"$resources" || fail "the custom Finder icon resource is absent"

mount=$(mktemp -d)
cleanup() {
  hdiutil detach "$mount" -quiet >/dev/null 2>&1 || true
  rmdir "$mount" >/dev/null 2>&1 || true
}
trap cleanup EXIT
hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mount" >/dev/null || fail "hdiutil could not attach $dmg"
cmp -s "$ICON" "$mount/.VolumeIcon.icns" || fail "the volume icon differs from $ICON"
[[ -f $mount/.DS_Store ]] || fail "the Finder layout (.DS_Store) is absent"
[[ -f $mount/.background/${name}InstallerBackground.tiff ]] \
  || fail "the installer background .background/${name}InstallerBackground.tiff is absent"
[[ -d $mount/$name.app ]] || fail "$name.app is absent from the volume"
[[ -L $mount/Applications ]] || fail "the Applications link is absent from the volume"

echo "DMG branding: ok (Finder icon, volume icon, background, layout, app and alias)"
