#!/usr/bin/env bash
# Renders design/social-card/social-card.html to site/social-card.jpg (1200x630, JPEG q92, 4:4:4).
# Run on a Mac: the card is drawn with the system font. Needs Node and ImageMagick.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
npx --yes playwright@1.63.0 screenshot --viewport-size="1200,630" \
  "file://$PWD/design/social-card/social-card.html" "$tmp/card.png" >/dev/null
magick "$tmp/card.png" -strip -quality 92 -sampling-factor 4:4:4 -interlace Plane site/social-card.jpg
