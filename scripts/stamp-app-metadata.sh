#!/bin/bash
# Writes the packaged build's public metadata into an app bundle's Info.plist:
# the version, the build number and the release date. package-app.sh is the
# only caller, and this script is the only writer of AppReleaseDate; the key is
# never typed into Support/Info.plist (validate.sh enforces that).
#
# The release date is an ISO 8601 calendar date, YYYY-MM-DD. package-app.sh
# passes the packaged commit's committer date (`git log -1 --format=%cs`), so
# rebuilding the same commit stamps the same date.
#
# Usage: scripts/stamp-app-metadata.sh <Info.plist> <version> <build> <release-date>
set -euo pipefail

if [ "$#" -ne 4 ]; then
    echo "usage: $0 <Info.plist> <version> <build> <release-date>" >&2
    exit 2
fi
PLIST=$1
VERSION=$2
BUILD_NUMBER=$3
RELEASE_DATE=$4

if [ ! -f "$PLIST" ]; then
    echo "error: no Info.plist at $PLIST" >&2
    exit 1
fi
if [ -z "$VERSION" ] || [ -z "$BUILD_NUMBER" ]; then
    echo "error: the version and the build number must not be empty" >&2
    exit 1
fi
if ! [[ "$RELEASE_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "error: release date '$RELEASE_DATE' is not YYYY-MM-DD" >&2
    exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
if /usr/libexec/PlistBuddy -c "Print :AppReleaseDate" "$PLIST" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :AppReleaseDate $RELEASE_DATE" "$PLIST"
else
    /usr/libexec/PlistBuddy -c "Add :AppReleaseDate string $RELEASE_DATE" "$PLIST"
fi
