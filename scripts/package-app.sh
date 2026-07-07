#!/bin/bash
# Builds the Release binary and assembles a runnable WindowHop.app with the
# Sparkle framework embedded.
#
# Signing:
#   - With DEVELOPER_ID_IDENTITY set: Developer ID + hardened runtime (release path).
#   - Otherwise: ad-hoc signing — free to build and run locally, no paid account.
#
# Usage: scripts/package-app.sh [version] [build-number]
# Output: build/WindowHop.app and artifacts/WindowHop-<version>.zip
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
BUILD_NUMBER="${2:-1}"
IDENTITY="${DEVELOPER_ID_IDENTITY:--}"

swift build -c release

APP=build/WindowHop.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/WindowHop "$APP/Contents/MacOS/WindowHop"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# ditto preserves the framework's symlink structure; cp -R would break it
ditto .build/release/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

# sign nested code first (Sparkle's helpers), then the framework, then the app
SIGN_FLAGS=(--force --sign "$IDENTITY")
if [ "$IDENTITY" != "-" ]; then
    SIGN_FLAGS+=(--timestamp)
    case "$IDENTITY" in
        *"Developer ID"*)
            # hardened runtime needs a team identifier for library validation;
            # the stable self-signed identity has none, so it signs without it
            SIGN_FLAGS+=(--options runtime) ;;
    esac
fi
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"

mkdir -p artifacts
ZIP="artifacts/WindowHop-$VERSION.zip"
rm -f "$ZIP"
# ditto -c -k preserves symlinks and signatures, as Sparkle requires
ditto -c -k --keepParent "$APP" "$ZIP"

echo "built $APP (version $VERSION, build $BUILD_NUMBER, identity: $IDENTITY)"
echo "zipped $ZIP"
