#!/bin/bash
# Builds the Release binary and assembles a runnable, ad-hoc-signed WindowHop.app.
# Usage: scripts/package-app.sh
# Output: build/WindowHop.app and artifacts/WindowHop-release.zip
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/WindowHop.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/WindowHop "$APP/Contents/MacOS/WindowHop"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# ad-hoc signature: free to build and run locally; no paid developer account required
codesign --force --sign - "$APP"

mkdir -p artifacts
rm -f artifacts/WindowHop-release.zip
ditto -c -k --keepParent "$APP" artifacts/WindowHop-release.zip

echo "built $APP"
echo "zipped artifacts/WindowHop-release.zip"
