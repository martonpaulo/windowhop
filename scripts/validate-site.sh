#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

required=(
  docs/index.html
  docs/styles/main.css
  docs/scripts/main.js
  docs/assets/app-icon.png
  docs/favicon.ico
  docs/apple-touch-icon.png
  docs/social-card.jpg
  docs/.nojekyll
  docs/CNAME
  docs/robots.txt
  docs/sitemap.xml
  docs/404.html
)
for path in "${required[@]}"; do
  test -f "$path" || { echo "missing GitHub Pages file: $path" >&2; exit 1; }
done

grep -Fxq "windowhop.martonpaulo.com" docs/CNAME || {
  echo "docs/CNAME does not name the published host" >&2
  exit 1
}

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
              'Developed by Marton Paulo' 'AltTab on GitHub' \
              'Download WindowHop <span data-site-version>' 'class="external-icon"'; do
  grep -R -Fq "$marker" docs/index.html docs/styles/main.css || {
    echo "website is missing required marker: $marker" >&2
    exit 1
  }
done

# The 404 page is part of the site, not a bare fallback: same header, same
# footer, same design, and it links back to the one page that exists.
for marker in 'class="site-header"' 'class="site-footer"' '/styles/main.css' 'href="/"'; do
    grep -Fq "$marker" docs/404.html || {
        echo "docs/404.html is missing required marker: $marker" >&2
        exit 1
    }
done

# Every link that leaves the site carries the external-link arrow and
# rel="noopener"; a link to another page of this site carries neither.
while IFS= read -r line; do
    case "$line" in *'rel="noopener"'*) ;; *)
        echo "external link without rel=\"noopener\": $line" >&2; exit 1 ;;
    esac
    case "$line" in *'class="external-icon"'*) ;; *)
        echo "external link without the external-link icon: $line" >&2; exit 1 ;;
    esac
done < <(grep -hoE '<a [^>]*(href="https?://[^"]+"|data-link="(github|issues|license|altTab|download|releases|releaseNotes)")[^>]*>.*</a>' \
    docs/index.html docs/404.html || true)

# Every local path the page names: src and href values, plus each candidate of a
# srcset or imagesrcset list with its width descriptor dropped.
local_references() {
  grep -oE '(src|href)="[^"]+"' docs/index.html | sed -E 's/^(src|href)="//; s/"$//'
  grep -oE '(srcset|imagesrcset)="[^"]+"' docs/index.html \
    | sed -E 's/^(srcset|imagesrcset)="//; s/"$//' | tr ',' '\n' | awk '{print $1}'
}

while IFS= read -r reference; do
  case "$reference" in
    http:*|https:*|'#'*|'') continue ;;
  esac
  test -f "docs/$reference" || {
    echo "website references missing local file: docs/$reference" >&2
    exit 1
  }
done < <(local_references | grep -vE '^styles/main\.css$|^scripts/main\.js$' || true)

if grep -RinE 'codex-clipboard|annotation|red arrow|private repository' docs/index.html docs/styles docs/scripts; then
  echo "website contains development-only or sensitive wording" >&2
  exit 1
fi

echo "website validation passed"
