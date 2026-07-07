#!/bin/bash
# Prepends a release entry to appcast.xml (creating it if missing).
# Usage: scripts/make-appcast.sh <version> <build-number> <zip-path> <signature-attrs>
#   signature-attrs is sign_update's output: sparkle:edSignature="..." length="..."
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$1"
BUILD_NUMBER="$2"
ZIP_PATH="$3"
SIGNATURE_ATTRS="$4"
URL="https://github.com/martonpaulo/windowhop/releases/download/v$VERSION/$(basename "$ZIP_PATH")"
DATE=$(LC_ALL=en_US.UTF-8 date -u "+%a, %d %b %Y %H:%M:%S +0000")

# BSD awk rejects newlines in -v values, so the item travels via a temp file
ITEM_FILE=$(mktemp)
trap 'rm -f "$ITEM_FILE"' EXIT
cat > "$ITEM_FILE" <<EOF
    <item>
      <title>$VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url="$URL" $SIGNATURE_ATTRS type="application/octet-stream"/>
    </item>
EOF

if [ ! -f appcast.xml ]; then
    cat > appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>WindowHop</title>
    <link>https://github.com/martonpaulo/windowhop</link>
    <description>Most recent updates to WindowHop</description>
    <language>en</language>
  </channel>
</rss>
EOF
fi

if grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" appcast.xml; then
    echo "appcast.xml already contains $VERSION; leaving unchanged"
    exit 0
fi

# insert the new item right after <language> (newest first)
awk -v itemfile="$ITEM_FILE" '
    { print }
    /<language>en<\/language>/ {
        while ((getline line < itemfile) > 0) print line
        close(itemfile)
    }
' appcast.xml > appcast.xml.new
mv appcast.xml.new appcast.xml
echo "appcast.xml updated with $VERSION (build $BUILD_NUMBER)"
