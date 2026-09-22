#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

required=(
  site/index.html
  site/styles/main.css
  site/scripts/main.js
  site/assets/app-icon.png
  site/favicon.ico
  site/favicon-192.png
  site/apple-touch-icon.png
  site/social-card.jpg
  site/.nojekyll
  site/CNAME
  site/robots.txt
  site/sitemap.xml
  site/404.html
)
for path in "${required[@]}"; do
  test -f "$path" || { echo "missing GitHub Pages file: $path" >&2; exit 1; }
done

grep -Fxq "windowhop.martonpaulo.com" site/CNAME || {
  echo "site/CNAME does not name the published host" >&2
  exit 1
}

# Link destinations and the displayed version live in the HTML, so the page works
# without scripts; Support/Info.plist is the one source they must match.
pages=(site/index.html site/404.html)
if grep -n 'href="#"' "${pages[@]}"; then
  echo "website has a link without a destination (href=\"#\")" >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)
DOWNLOAD_URL="https://github.com/martonpaulo/windowhop/releases/latest/download/WindowHop-$VERSION-Installer.zip"
downloads=$(grep -hoE 'href="[^"]*/releases/[^"]*/download/[^"]*"' "${pages[@]}" || true)
test -n "$downloads" || { echo "website has no download link" >&2; exit 1; }
while IFS= read -r href; do
  test "$href" = "href=\"$DOWNLOAD_URL\"" || {
    echo "website download link does not match version $VERSION: $href" >&2
    exit 1
  }
done <<< "$downloads"
notes=$(grep -hoE 'href="[^"]*/releases/tag/[^"]*"' "${pages[@]}" || true)
test -n "$notes" || { echo "website has no release-notes link" >&2; exit 1; }
while IFS= read -r href; do
  case "$href" in *"/tag/v$VERSION\"") ;; *)
    echo "website release-notes link does not match version $VERSION: $href" >&2; exit 1 ;;
  esac
done <<< "$notes"
while IFS= read -r span; do
  test "$span" = "<span data-site-version>$VERSION</span>" || {
    echo "website version does not match Support/Info.plist ($VERSION): $span" >&2
    exit 1
  }
done < <(grep -hoE '<span data-site-version>[^<]*</span>' "${pages[@]}")

for marker in 'id="features"' 'id="download"' "href=\"$DOWNLOAD_URL\"" \
              'prefers-color-scheme: dark' 'prefers-reduced-motion: reduce' \
              'Developed by Marton Paulo' 'AltTab on GitHub' \
              'Download WindowHop <span data-site-version>' 'class="external-icon"' \
              'id="alttab-alternative"'; do
  grep -R -Fq "$marker" site/index.html site/styles/main.css || {
    echo "website is missing required marker: $marker" >&2
    exit 1
  }
done

# Search and share previews read different tags; they must say the same thing.
title=$(grep -oE '<title>[^<]*</title>' site/index.html | sed -E 's/<\/?title>//g')
description=$(grep -oE '<meta name="description" content="[^"]*"' site/index.html | sed -E 's/.*content="//; s/"$//')
test -n "$title" && test -n "$description" || {
  echo "site/index.html is missing its <title> or meta description" >&2
  exit 1
}
for tag in 'property="og:title"' 'name="twitter:title"'; do
  grep -Fq "<meta $tag content=\"$title\">" site/index.html || {
    echo "site/index.html: $tag does not equal the <title>" >&2
    exit 1
  }
done
for tag in 'property="og:description"' 'name="twitter:description"'; do
  grep -Fq "<meta $tag content=\"$description\">" site/index.html || {
    echo "site/index.html: $tag does not equal the meta description" >&2
    exit 1
  }
done
grep -Fq "\"description\": \"$description\"" site/index.html || {
  echo "site/index.html: the JSON-LD description does not equal the meta description" >&2
  exit 1
}

# Favicons (issue #93): every declared `sizes` describes the file it names, and the home
# page declares one larger than 48 px, which Google Search asks for. The files come
# from `swift scripts/make-icon.swift --favicon site`.
icon_sizes() {
  case "$1" in
    *.ico) python3 -c '
import struct, sys
data = open(sys.argv[1], "rb").read()
reserved, kind, count = struct.unpack("<HHH", data[:6])
assert reserved == 0 and kind == 1, "not an ICO file"
sizes = []
for i in range(count):
    w, h = data[6 + 16 * i], data[7 + 16 * i]
    sizes.append(f"{w or 256}x{h or 256}")
print(" ".join(sorted(sizes, key=lambda s: int(s.split("x")[0]))))' "$1" ;;
    *.png) sips -g pixelWidth -g pixelHeight "$1" \
             | awk '/pixelWidth/ { w = $2 } /pixelHeight/ { h = $2 } END { print w "x" h }' ;;
    *) echo "unsupported" ;;
  esac
}
largest_icon=0
while IFS= read -r link; do
  page=${link%%:*}; tag=${link#*:}
  href=$(sed -nE 's/.*href="([^"]*)".*/\1/p' <<< "$tag")
  declared=$(sed -nE 's/.*sizes="([^"]*)".*/\1/p' <<< "$tag")
  file="site/${href#/}"
  test -f "$file" || { echo "$page declares a missing icon: $href" >&2; exit 1; }
  actual=$(icon_sizes "$file")
  test "$declared" = "$actual" || {
    echo "$page: icon $href declares sizes=\"$declared\" but the file has $actual" >&2
    exit 1
  }
  if test "$page" = site/index.html; then
    for size in $actual; do
      test "${size%%x*}" -gt "$largest_icon" && largest_icon=${size%%x*}
    done
  fi
done < <(grep -oE '<link rel="icon"[^>]*>' "${pages[@]}")
test "$largest_icon" -gt 48 || {
  echo "site/index.html declares no favicon larger than 48 px" >&2
  exit 1
}

# The 404 page is part of the site, not a bare fallback: same header, same
# footer, same design, and it links back to the one page that exists.
for marker in 'class="site-header"' 'class="site-footer"' '/styles/main.css' 'href="/"'; do
    grep -Fq "$marker" site/404.html || {
        echo "site/404.html is missing required marker: $marker" >&2
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
done < <(grep -hoE '<a [^>]*href="https?://[^"]+"[^>]*>.*</a>' \
    site/index.html site/404.html || true)

# Every local path the page names: src and href values, plus each candidate of a
# srcset or imagesrcset list with its width descriptor dropped.
local_references() {
  grep -oE '(src|href)="[^"]+"' site/index.html | sed -E 's/^(src|href)="//; s/"$//'
  grep -oE '(srcset|imagesrcset)="[^"]+"' site/index.html \
    | sed -E 's/^(srcset|imagesrcset)="//; s/"$//' | tr ',' '\n' | awk '{print $1}'
}

while IFS= read -r reference; do
  case "$reference" in
    http:*|https:*|'#'*|'') continue ;;
  esac
  test -f "site/$reference" || {
    echo "website references missing local file: site/$reference" >&2
    exit 1
  }
done < <(local_references | grep -vE '^styles/main\.css$|^scripts/main\.js$' || true)

if grep -RinE 'codex-clipboard|annotation|red arrow|private repository' site/index.html site/styles site/scripts; then
  echo "website contains development-only or sensitive wording" >&2
  exit 1
fi

echo "website validation passed"
