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

# An entry for this version already exists. That is an idempotent no-op only
# when it advertises exactly what is being published; a mismatch means the feed
# describes a different build and must be resolved by an operator, not
# silently accepted as success.
if grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" appcast.xml; then
    EXISTING_ITEM=$(awk -v version="$VERSION" '
        /<item>/ { buffer = ""; inside = 1 }
        inside { buffer = buffer $0 "\n" }
        inside && $0 ~ "<sparkle:shortVersionString>" version "</sparkle:shortVersionString>" { match_found = 1 }
        /<\/item>/ { if (inside && match_found) { printf "%s", buffer; exit } ; inside = 0; match_found = 0 }
    ' appcast.xml)
    MISMATCH=""
    printf '%s' "$EXISTING_ITEM" | grep -q "<sparkle:version>$BUILD_NUMBER</sparkle:version>" \
        || MISMATCH="build number"
    printf '%s' "$EXISTING_ITEM" | grep -qF "url=\"$URL\"" \
        || MISMATCH="${MISMATCH:-enclosure URL}"
    for attribute in $SIGNATURE_ATTRS; do
        printf '%s' "$EXISTING_ITEM" | grep -qF "$attribute" \
            || MISMATCH="${MISMATCH:-signature or length}"
    done
    if [ -n "$MISMATCH" ]; then
        echo "appcast.xml already advertises $VERSION with a different $MISMATCH." >&2
        echo "Existing entry:" >&2
        printf '%s\n' "$EXISTING_ITEM" >&2
        exit 1
    fi
    echo "appcast.xml already advertises this exact $VERSION build; leaving unchanged"
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
mv -f appcast.xml.new appcast.xml
echo "appcast.xml updated with $VERSION (build $BUILD_NUMBER)"
