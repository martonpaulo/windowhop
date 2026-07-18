#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

required=(
  docs/index.html
  docs/styles/main.css
  docs/scripts/main.js
  docs/assets/app-icon.png
  docs/assets/favicon.png
  docs/assets/social-preview.png
  docs/.nojekyll
)
for path in "${required[@]}"; do
  test -f "$path" || { echo "missing GitHub Pages file: $path" >&2; exit 1; }
done

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)
grep -Fq "version: \"$VERSION\"" docs/scripts/main.js || {
  echo "website version does not match Support/Info.plist: $VERSION" >&2
  exit 1
}
grep -Fq "WindowHop-$VERSION-Installer.zip" docs/scripts/main.js || {
  echo "website installer URL does not match version $VERSION" >&2
  exit 1
}

for marker in 'id="features"' 'id="download"' 'data-link="download"' \
              'prefers-color-scheme: dark' 'prefers-reduced-motion: reduce' \
              'Developed by Marton Paulo' 'AltTab on GitHub'; do
  grep -R -Fq "$marker" docs/index.html docs/styles/main.css || {
    echo "website is missing required marker: $marker" >&2
    exit 1
  }
done

while IFS= read -r reference; do
  case "$reference" in
    http:*|https:*|'#'*|'') continue ;;
  esac
  test -f "docs/$reference" || {
    echo "website references missing local file: docs/$reference" >&2
    exit 1
  }
done < <(grep -oE '(src|href)="[^"]+"' docs/index.html \
  | sed -E 's/^(src|href)="//; s/"$//' \
  | grep -vE '^styles/main\.css$|^scripts/main\.js$' || true)

if grep -RinE 'codex-clipboard|annotation|red arrow|private repository' docs/index.html docs/styles docs/scripts; then
  echo "website contains development-only or sensitive wording" >&2
  exit 1
fi

echo "website validation passed"
