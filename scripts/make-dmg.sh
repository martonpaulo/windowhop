#!/usr/bin/env bash
# Canonical installer-DMG script for the owner's macOS apps. Copy it unchanged to
# scripts/make-dmg.sh in each app; project-setup alignment reports a drifted copy.
#
# Builds a drag-to-Applications disk image with appdmg (pinned), which writes the Finder layout
# without scripting Finder, so it works headless. The spec is written with absolute paths into a
# work directory that is kept, because it records what was built. When the Command Line Tools'
# Rez and SetFile are present, the .dmg file also gets the installer icon as a resource fork.
# The DMG is signed only when DEVELOPER_ID_IDENTITY is set, and always verified.
#
# Needs build/<Name>.app from scripts/package-app.sh, Support/AppInstallerIcon.icns and
# Support/<Name>InstallerBackground.tiff. The geometry flags must match the background artwork.
#
# Prints the DMG path on stdout and everything else on stderr.
set -euo pipefail
cd "$(dirname "$0")/.."

PLIST_BUDDY=${PLIST_BUDDY:-/usr/libexec/PlistBuddy}
PLIST=Support/Info.plist
APPDMG_VERSION=0.6.6

usage() {
  cat <<USAGE
usage: scripts/make-dmg.sh [options]
  --version <X.Y.Z>                 version in the title and file name (default from Support/Info.plist)
  --app <App.app>                   bundle to ship (default build/<Name>.app)
  --output <path.dmg>               disk image to create (default artifacts/<Name>-<version>.dmg)
  --work-dir <dir>                  where the spec is kept (default artifacts/dmg-<version>)
  --window-size <WxH>               Finder window size (default 680x400)
  --icon-size <N>                   icon size in points (default 112)
  --app-position <x,y>              center of the app icon (default 180,225)
  --applications-position <x,y>     center of the Applications link (default 500,225)
  --force                           replace an existing disk image and work directory
  --help                            show this help
USAGE
}

fail_usage() { echo "error: $1" >&2; usage >&2; exit 2; }
need_value() { [[ $# -ge 2 && -n $2 && $2 != --* ]] || fail_usage "$1 needs a value"; }
need_match() { # $1 option, $2 value, $3 pattern, $4 shape
  [[ $2 =~ $3 ]] || fail_usage "$1 must look like $4, not $2"
}

version=''
app=''
dmg=''
work_dir=''
window_size=680x400
icon_size=112
app_position=180,225
applications_position=500,225
force=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --version) need_value "$@"; version=$2; shift 2 ;;
    --app) need_value "$@"; app=$2; shift 2 ;;
    --output) need_value "$@"; dmg=$2; shift 2 ;;
    --work-dir) need_value "$@"; work_dir=$2; shift 2 ;;
    --window-size) need_value "$@"; need_match "$1" "$2" '^[0-9]+x[0-9]+$' WxH; window_size=$2; shift 2 ;;
    --icon-size) need_value "$@"; need_match "$1" "$2" '^[0-9]+$' N; icon_size=$2; shift 2 ;;
    --app-position) need_value "$@"; need_match "$1" "$2" '^[0-9]+,[0-9]+$' x,y; app_position=$2; shift 2 ;;
    --applications-position)
      need_value "$@"; need_match "$1" "$2" '^[0-9]+,[0-9]+$' x,y; applications_position=$2; shift 2 ;;
    --force) force=1; shift ;;
    --help) usage; exit 0 ;;
    *) fail_usage "unknown option $1" ;;
  esac
done

[[ -f $PLIST ]] || { echo "error: $PLIST not found; run this from an app repository" >&2; exit 1; }
read_key() { # $1 key, $2 plist
  "$PLIST_BUDDY" -c "Print :$1" "$2" 2>/dev/null || { echo "error: $2 has no $1" >&2; exit 1; }
}
name=$(read_key CFBundleName "$PLIST")
[[ -n $version ]] || version=$(read_key CFBundleShortVersionString "$PLIST")
app=${app:-build/$name.app}
dmg=${dmg:-artifacts/$name-$version.dmg}
work_dir=${work_dir:-artifacts/dmg-$version}
icon=Support/AppInstallerIcon.icns
background=Support/${name}InstallerBackground.tiff

[[ -d $app ]] || { echo "error: $app not found; run scripts/package-app.sh first" >&2; exit 1; }
for asset in "$icon" "$background"; do
  [[ -f $asset ]] || { echo "error: $asset not found; the installer needs it" >&2; exit 1; }
done
for existing in "$dmg" "$work_dir"; do
  if [[ -e $existing ]]; then
    (( force )) || { echo "error: $existing already exists; pass --force to replace it" >&2; exit 1; }
    rm -rf "$existing"
  fi
done

absolute() { printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd)" "$(basename "$1")"; }
json() { # a JSON string literal
  local text=${1//\\/\\\\}
  text=${text//\"/\\\"}
  printf '"%s"' "$text"
}
mkdir -p "$(dirname "$dmg")" "$work_dir"
spec=$work_dir/dmg-spec.json
cat >"$spec" <<JSON
{
  "title": $(json "$name $version"),
  "icon": $(json "$(absolute "$icon")"),
  "background": $(json "$(absolute "$background")"),
  "icon-size": $icon_size,
  "window": { "size": { "width": ${window_size%x*}, "height": ${window_size#*x} } },
  "contents": [
    { "x": ${app_position%,*}, "y": ${app_position#*,}, "type": "file", "path": $(json "$(absolute "$app")") },
    { "x": ${applications_position%,*}, "y": ${applications_position#*,}, "type": "link", "path": "/Applications" }
  ]
}
JSON
echo "Creating $dmg from $spec." >&2
npx --yes "appdmg@$APPDMG_VERSION" "$spec" "$dmg" >&2

# The file's own icon is a resource fork: it survives a local copy, while a download strips it and
# leaves the volume icon as the one people see after mounting.
if xcrun --find Rez >/dev/null 2>&1 && command -v SetFile >/dev/null 2>&1; then
  cp "$icon" "$work_dir/dmg-file-icon.icns"
  sips -i "$work_dir/dmg-file-icon.icns" >/dev/null
  DeRez -only icns "$work_dir/dmg-file-icon.icns" >"$work_dir/dmg-icon.rsrc"
  Rez -append "$work_dir/dmg-icon.rsrc" -o "$dmg" >&2
  SetFile -a C "$dmg" >&2
fi

if [[ -n ${DEVELOPER_ID_IDENTITY:-} ]]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID_IDENTITY" "$dmg" >&2
fi
hdiutil verify -quiet "$dmg" >&2
echo "Created $name $version installer." >&2
printf '%s\n' "$dmg"
