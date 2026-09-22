#!/usr/bin/env bash
# Canonical packaging script for the owner's macOS apps. Copy it unchanged to
# scripts/package-app.sh in each app; project-setup alignment reports a drifted copy.
#
# Builds the release binary, assembles <Name>.app with Sparkle.framework embedded, checks that the
# packaged bundle identifier is the one in Support/Info.plist, signs nested code, then the
# framework, then the app, and archives the bundle with the only Sparkle-safe ZIP tool, ditto.
# Every app value comes from Support/Info.plist; nothing here names a product.
#
# Signing: the default identity "-" is ad-hoc, free to build and run locally. A Developer ID
# identity (DEVELOPER_ID_IDENTITY or --identity) always adds --timestamp --options runtime, which
# notarization requires; --hardened adds them to an ad-hoc build too.
#
# Prints the app path and the archive path on stdout, one per line, and everything else on stderr.
set -euo pipefail
cd "$(dirname "$0")/.."

PLIST_BUDDY=${PLIST_BUDDY:-/usr/libexec/PlistBuddy}
PLIST=Support/Info.plist

usage() {
  cat <<USAGE
usage: scripts/package-app.sh [options]
  --output <App.app>      bundle to create (default build/<Name>.app)
  --archive <path.zip>    archive to create (default artifacts/<Name>-<version>.zip)
  --identity <id>         codesign identity (default \$DEVELOPER_ID_IDENTITY, else "-" ad-hoc)
  --version <X.Y.Z>       short version to stamp (requires --build-number)
  --build-number <N>      build number to stamp (requires --version)
  --arch <arch>           build architecture (default arm64)
  --hardened              hardened runtime and timestamp, even for an ad-hoc identity
  --force                 replace an existing bundle or archive
  --help                  show this help
USAGE
}

fail_usage() { echo "error: $1" >&2; usage >&2; exit 2; }
need_value() { [[ $# -ge 2 && -n $2 && $2 != --* ]] || fail_usage "$1 needs a value"; }

app=''
archive=''
identity=${DEVELOPER_ID_IDENTITY:--}
version=''
build_number=''
arch=arm64
hardened=0
force=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --output) need_value "$@"; app=$2; shift 2 ;;
    --archive) need_value "$@"; archive=$2; shift 2 ;;
    --identity) need_value "$@"; identity=$2; shift 2 ;;
    --version) need_value "$@"; version=$2; shift 2 ;;
    --build-number) need_value "$@"; build_number=$2; shift 2 ;;
    --arch) need_value "$@"; arch=$2; shift 2 ;;
    --hardened) hardened=1; shift ;;
    --force) force=1; shift ;;
    --help) usage; exit 0 ;;
    *) fail_usage "unknown option $1" ;;
  esac
done
if [[ -n $version && -z $build_number || -z $version && -n $build_number ]]; then
  fail_usage '--version and --build-number must be given together'
fi

[[ -f $PLIST ]] || { echo "error: $PLIST not found; run this from an app repository" >&2; exit 1; }
read_key() { # $1 key, $2 plist
  "$PLIST_BUDDY" -c "Print :$1" "$2" 2>/dev/null || { echo "error: $2 has no $1" >&2; exit 1; }
}
name=$(read_key CFBundleName "$PLIST")
executable=$(read_key CFBundleExecutable "$PLIST")
bundle_id=$(read_key CFBundleIdentifier "$PLIST")
[[ -n $version ]] || version=$(read_key CFBundleShortVersionString "$PLIST")
[[ -n $build_number ]] || build_number=$(read_key CFBundleVersion "$PLIST")
app=${app:-build/$name.app}
archive=${archive:-artifacts/$name-$version.zip}

for existing in "$app" "$archive"; do
  if [[ -e $existing ]]; then
    (( force )) || { echo "error: $existing already exists; pass --force to replace it" >&2; exit 1; }
    rm -rf "$existing"
  fi
done

echo "Building $executable $version ($build_number) for $arch." >&2
swift build -c release --arch "$arch" --product "$executable" >&2
bin_path=$(swift build -c release --arch "$arch" --product "$executable" --show-bin-path)

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin_path/$executable" "$app/Contents/MacOS/$executable"
cp "$PLIST" "$app/Contents/Info.plist"
if [[ -f Support/AppIcon.icns ]]; then
  cp Support/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
fi
for lproj in Support/*.lproj; do
  if [[ -d $lproj ]]; then
    ditto "$lproj" "$app/Contents/Resources/$(basename "$lproj")"
  fi
done
if [[ -d Support/Assets.xcassets ]]; then
  minimum=$(read_key LSMinimumSystemVersion "$PLIST")
  xcrun actool --compile "$app/Contents/Resources" --platform macosx \
    --minimum-deployment-target "$minimum" --app-icon AppIcon \
    --output-partial-info-plist /dev/null Support/Assets.xcassets >&2
fi

# ditto keeps the framework's symlinks; cp -R flattens them and breaks Sparkle's signature.
sparkle=$bin_path/Sparkle.framework
[[ -d $sparkle ]] || { echo "error: Sparkle.framework not found at $sparkle" >&2; exit 1; }
framework=$app/Contents/Frameworks/Sparkle.framework
ditto "$sparkle" "$framework"

"$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
"$PLIST_BUDDY" -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"

# Keychain items and UserDefaults are keyed by the bundle identifier, so a second one silently
# orphans the user's data. Check it before anything is signed or archived.
packaged_id=$(read_key CFBundleIdentifier "$app/Contents/Info.plist")
if [[ $packaged_id != "$bundle_id" ]]; then
  echo "error: the packaged bundle identifier is $packaged_id, but $PLIST says $bundle_id" >&2
  exit 1
fi

sign=(codesign --force --sign "$identity")
if (( hardened )) || [[ $identity != - ]]; then
  sign+=(--timestamp --options runtime)
fi
# Nested code first, then the framework, then the app. The version directories are discovered,
# because the letter is Sparkle's to choose.
for version_dir in "$framework"/Versions/*; do
  if [[ -L $version_dir || ! -d $version_dir ]]; then
    continue
  fi
  for nested in "$version_dir"/XPCServices/*.xpc "$version_dir/Autoupdate" "$version_dir/Updater.app"; do
    if [[ -e $nested ]]; then
      "${sign[@]}" "$nested" >&2
    fi
  done
done
"${sign[@]}" "$framework" >&2
"${sign[@]}" "$app" >&2
codesign --verify --deep --strict "$app" >&2

mkdir -p "$(dirname "$archive")"
ditto -c -k --keepParent "$app" "$archive" >&2
echo "Packaged $name $version ($build_number), identity $identity." >&2
printf '%s\n%s\n' "$app" "$archive"
