#!/bin/bash
# Repository validation: invariants that must hold for every commit and release.
# Run from the repository root. Exits non-zero with an explanation on violation.
#
# Strict mode, but every check reports instead of aborting: a check runs as an `if`
# condition, and a substitution that may legitimately find nothing (a missing plist key,
# a grep with no match, `head` closing a pipe early) ends in `|| true`, so the empty value
# reaches the check that explains it and the remaining checks still run.
set -euo pipefail
cd "$(dirname "$0")/.."

failures=0
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
pass() { echo "  ok: $1"; }

TRACKED=$(git ls-files)

# --- product identity -------------------------------------------------------
if grep -rn "com\.martonpss\|com\.lwouis\|lwouis\.alt-tab" $TRACKED 2>/dev/null | grep -v "^UPSTREAM.md\|^docs/"; then
    fail "obsolete bundle identifier found in tracked files"
else
    pass "no obsolete bundle identifiers"
fi
# The identifier before #43 survives only where the one-time settings copy reads
# its domain; CHANGELOG.md keeps the history as it was released.
if grep -n "com\.perso\." $TRACKED 2>/dev/null \
    | grep -v "^CHANGELOG.md:\|^Sources/WindowHopKit/LegacyDomainMigration.swift:"; then
    fail "the pre-#43 bundle identifier appears outside LegacyDomainMigration.swift"
else
    pass "the pre-#43 bundle identifier appears only in the settings migration"
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Support/Info.plist)" = "com.martonpaulo.windowhop" ]; then
    pass "bundle identifier is com.martonpaulo.windowhop"
else
    fail "Support/Info.plist bundle identifier is not com.martonpaulo.windowhop"
fi
# Code reads the identifier at runtime (Bundle.main.bundleIdentifier, #98); only
# Support/ and the identity checks in scripts/ carry the value.
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Support/Info.plist || true)
if grep -rnF "$BUNDLE_ID" Sources/ Tests/ 2>/dev/null; then
    fail "bundle identifier literal found in Sources/ or Tests/; read Bundle.main.bundleIdentifier"
else
    pass "no bundle identifier literal in Sources/ or Tests/"
fi

# --- no private API, no capture outside the preview subsystem ----------------
if grep -rn "_silgen_name\|SLPSPostEvent\|_SLPSSetFront\|CGSSetSymbolicHotKey\|_AXUIElementGetWindow\|_AXUIElementCreateWithRemoteToken" Sources/ 2>/dev/null | grep -v "^\S*:[0-9]*: *///" | grep -v "^\S*:[0-9]*: *//"; then
    fail "private API reference found in Sources/"
else
    pass "no private APIs"
fi
# legacy capture APIs are banned everywhere; ScreenCaptureKit is sanctioned only
# inside the session-scoped preview subsystem
if grep -rn "CGWindowListCreateImage\|CGDisplayStream" Sources/ 2>/dev/null; then
    fail "legacy screen-capture API found in Sources/"
else
    pass "no legacy screen capture"
fi
if grep -rln "ScreenCaptureKit\|SCShareableContent\|SCScreenshotManager" Sources/ 2>/dev/null \
    | grep -v "Sources/WindowHopCore/Engine/PreviewProvider.swift"; then
    fail "ScreenCaptureKit used outside Engine/PreviewProvider.swift"
else
    pass "ScreenCaptureKit confined to the preview provider"
fi
# a test suite named without a path leaks a plist into ~/Library/Preferences that no
# teardown can remove; TestDefaults puts every test suite under $TMPDIR (#129)
if grep -rn "UserDefaults(suiteName\|windowhop-tests-" Tests/ 2>/dev/null \
    | grep -v "^Tests/WindowHopTestSupport/TestDefaults.swift:"; then
    fail "a test makes a UserDefaults suite outside TestDefaults"
else
    pass "test UserDefaults suites confined to TestDefaults"
fi
# WindowHopKit holds the pure rules: value-type frameworks only (AGENTS.md, Kit import
# contract), and no AX, workspace or capture reference even through a transitive import
KIT_IMPORTS='^(Foundation|CoreGraphics|Observation|Synchronization)$'
if grep -rhE "^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]" Sources/WindowHopKit/ 2>/dev/null \
    | sed -E 's/^.*import[[:space:]]+(class |struct |enum |protocol |func |var |let |typealias )?//; s/[.[:space:]].*$//' \
    | sort -u | grep -vE "$KIT_IMPORTS"; then
    fail "WindowHopKit imports a framework outside its allowlist"
else
    pass "WindowHopKit imports only its allowlisted frameworks"
fi
if grep -rn "AXUIElement\|AXObserver\|NSWorkspace\|ScreenCaptureKit" Sources/WindowHopKit/ 2>/dev/null \
    | grep -v "^\S*:[0-9]*: *//"; then
    fail "WindowHopKit references AX, NSWorkspace or ScreenCaptureKit"
else
    pass "WindowHopKit has no AX, workspace or capture references"
fi
if grep -rn "AppCenter\|analytics\|telemetry" Sources/ --include="*.swift" 2>/dev/null | grep -iv "no telemetry\|telemetry, no\|no analytics"; then
    fail "telemetry reference found in Sources/"
else
    pass "no telemetry"
fi

# --- String Catalog (#99) -----------------------------------------------------
# English only: one catalog, one compiled table. Whether the catalog matches the
# sources needs a compiler build, so `make strings-check` owns that check (CI runs it
# in the build job); here the committed table must be the catalog's compiled form.
LPROJS=$(find Support -maxdepth 1 -name '*.lproj' | sort | tr '\n' ' ' || true)
if [ "$LPROJS" = "Support/en.lproj " ] \
    && [ "$(ls Support/en.lproj)" = "Localizable.strings" ] \
    && [ "$(find Support -name '*.xcstrings' | tr '\n' ' ')" = "Support/Localizable.xcstrings " ]; then
    pass "one English String Catalog and one compiled table"
else
    fail "Support/ must hold only Localizable.xcstrings and en.lproj/Localizable.strings (found: $LPROJS)"
fi
STRINGS_TMP=$(mktemp -d)
if xcrun xcstringstool compile Support/Localizable.xcstrings --output-directory "$STRINGS_TMP" >/dev/null 2>&1 \
    && cmp -s "$STRINGS_TMP/en.lproj/Localizable.strings" Support/en.lproj/Localizable.strings; then
    pass "Support/en.lproj/Localizable.strings is the compiled catalog"
else
    fail "Support/en.lproj/Localizable.strings differs from the compiled catalog; run make strings"
fi
rm -rf "$STRINGS_TMP"

# --- updater configuration ---------------------------------------------------
for key in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks; do
    if /usr/libexec/PlistBuddy -c "Print :$key" Support/Info.plist >/dev/null 2>&1; then
        pass "Info.plist has $key"
    else
        fail "Info.plist missing $key"
    fi
done
FEED=$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' Support/Info.plist 2>/dev/null || true)
case "$FEED" in
    https://*) pass "appcast feed is HTTPS" ;;
    *) fail "appcast feed is not HTTPS: $FEED" ;;
esac

# the release date is stamped at packaging time (scripts/stamp-app-metadata.sh),
# never typed into the source Info.plist
if /usr/libexec/PlistBuddy -c 'Print :AppReleaseDate' Support/Info.plist >/dev/null 2>&1; then
    fail "Support/Info.plist must not contain AppReleaseDate; packaging stamps it"
else
    pass "release date is left to packaging"
fi

# "Report an Issue…" prefills these bug-report inputs by id (WindowHopKit/ProjectLinks.swift);
# renaming one would silently drop the prefill
for field_id in windowhop-version macos-version; do
    if grep -qE "^[[:space:]]*id: $field_id[[:space:]]*$" .github/ISSUE_TEMPLATE/bug_report.yml; then
        pass "bug report form declares id: $field_id"
    else
        fail "bug_report.yml no longer declares id: $field_id, which ProjectLinks.issueReport prefills"
    fi
done

# --- appcast/release metadata consistency ------------------------------------
if [ -f appcast.xml ]; then
    if grep -q "sparkle:edSignature=" appcast.xml && grep -q "https://github.com/martonpaulo/windowhop/releases/download/" appcast.xml; then
        pass "appcast entries are signed and point at GitHub Releases"
    else
        fail "appcast.xml missing edSignature or GitHub release URLs"
    fi
    # The macOS floor has one owner, LSMinimumSystemVersion, and make-appcast.sh
    # copies it into every new entry. The newest entry may therefore never
    # advertise a floor above it. It may sit below it between raising the floor
    # and the next release, because that entry describes the previous build;
    # older entries keep their own floor so older systems keep their last release.
    BUNDLE_FLOOR=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Support/Info.plist || true)
    NEWEST_FLOOR=$(grep -o '<sparkle:minimumSystemVersion>[^<]*' appcast.xml | head -1 | cut -d'>' -f2 || true)
    # prints -1, 0 or 1 comparing dotted versions numerically
    FLOOR_ORDER=$(awk -v a="$NEWEST_FLOOR" -v b="$BUNDLE_FLOOR" 'BEGIN {
        n = split(a, x, "."); m = split(b, y, ".")
        for (i = 1; i <= (n > m ? n : m); i++) {
            if (x[i] + 0 < y[i] + 0) { print -1; exit }
            if (x[i] + 0 > y[i] + 0) { print 1; exit }
        }
        print 0 }')
    if [ -z "$NEWEST_FLOOR" ]; then
        fail "newest appcast entry has no minimumSystemVersion"
    elif [ "$FLOOR_ORDER" = "1" ]; then
        fail "newest appcast floor ($NEWEST_FLOOR) is above LSMinimumSystemVersion ($BUNDLE_FLOOR)"
    else
        pass "newest appcast floor ($NEWEST_FLOOR) is consistent with LSMinimumSystemVersion ($BUNDLE_FLOOR)"
    fi
fi

# --- documentation/release synchronization ----------------------------------
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist || true)
# The README no longer advertises a download (the GitHub About carries the site), so the
# document that must track the shipped version is the changelog: its newest entry is the
# release being described. The file follows Keep a Changelog: `## [X.Y.Z] - date`
# headings, with one `## [Unreleased]` section above every version.
CHANGELOG_VERSION=$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | head -1 | tr -d '#[] ' || true)
if [ "$CHANGELOG_VERSION" = "$VERSION" ]; then
    pass "CHANGELOG's newest entry matches version $VERSION"
else
    fail "CHANGELOG's newest entry ($CHANGELOG_VERSION) does not match version $VERSION"
fi
UNRELEASED_COUNT=$(grep -c '^## \[Unreleased\]' CHANGELOG.md || true)
UNRELEASED_LINE=$(grep -n '^## \[Unreleased\]' CHANGELOG.md | head -1 | cut -d: -f1 || true)
FIRST_VERSION_LINE=$(grep -nE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | head -1 | cut -d: -f1 || true)
if [ "$UNRELEASED_COUNT" = "1" ] && [ "${UNRELEASED_LINE:-0}" -lt "${FIRST_VERSION_LINE:-0}" ]; then
    pass "CHANGELOG has one [Unreleased] section above every version"
else
    fail "CHANGELOG needs exactly one '## [Unreleased]' heading before every version heading"
fi

MARKDOWN_FILES=$(git ls-files '*.md')
while IFS= read -r markdown; do
    [ -n "$markdown" ] || continue
    while IFS= read -r target; do
        case "$target" in
            https://*|http://*|mailto:*|'#'*|'') continue ;;
        esac
        if [ -e "$(dirname "$markdown")/$target" ]; then
            :
        else
            fail "$markdown references missing local file: $target"
        fi
    done < <(grep -oE '\]\([^)]+\)' "$markdown" 2>/dev/null | sed 's/^](//; s/)$//')
done <<< "$MARKDOWN_FILES"

# A screenshot is in use when Markdown links it or the site names it, as a src
# or as a srcset candidate (the hero's narrower widths appear nowhere else).
while IFS= read -r screenshot; do
    [ -n "$screenshot" ] || continue
    site_path=${screenshot#site/}
    if grep -qF "($screenshot)" $MARKDOWN_FILES \
        || grep -qF -e "\"/$site_path\"" -e "/$site_path " -e "\"$site_path\"" -e "$site_path " \
            site/index.html site/help/index.html site/alttab-alternative/index.html; then
        :
    else
        fail "unreferenced screenshot is tracked: $screenshot"
    fi
done < <(find site/screenshots -type f -print 2>/dev/null | sort || true)

if [ "$failures" -eq 0 ]; then
    pass "Markdown local links and tracked screenshots are synchronized"
fi

# --- GitHub Pages site -------------------------------------------------------
# scripts/validate-site.sh is skill-deck's canonical copy (CNAME host pattern, canonical
# URL, og:url, noindex, robots.txt, sitemap.xml) and stays byte-identical. WindowHop's own
# site rules live here, in a subshell that stops at its first violation.
if scripts/validate-site.sh; then
    pass "GitHub Pages site (canonical checks)"
else
    fail "GitHub Pages site failed the canonical checks"
fi

windowhop_site_checks() (
    set -euo pipefail
    required=(
      site/index.html
      site/help/index.html
      site/alttab-alternative/index.html
      site/styles/main.css
      site/scripts/main.js
      site/scripts/demo.js
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
    # Every published page, and the ones search engines index (all but the 404).
    pages=(site/index.html site/help/index.html site/alttab-alternative/index.html site/404.html)
    indexed=(site/index.html site/help/index.html site/alttab-alternative/index.html)
    if grep -n 'href="#"' "${pages[@]}"; then
      echo "website has a link without a destination (href=\"#\")" >&2
      exit 1
    fi

    VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)
    # The download is the DMG itself (#35). Releases also publish an Installer.zip that
    # wraps it; the site does not link that one.
    DOWNLOAD_URL="https://github.com/martonpaulo/windowhop/releases/latest/download/WindowHop-$VERSION.dmg"
    downloads=$(grep -hoE 'href="[^"]*/releases/[^"]*/download/[^"]*"' "${pages[@]}" || true)
    test -n "$downloads" || { echo "website has no download link" >&2; exit 1; }
    while IFS= read -r href; do
      test "$href" = "href=\"$DOWNLOAD_URL\"" || {
        echo "website download link does not match version $VERSION: $href" >&2
        exit 1
      }
    done <<< "$downloads"
    # Structured data names the same file as the buttons.
    grep -Fq "\"downloadUrl\": \"$DOWNLOAD_URL\"" site/index.html || {
      echo "website JSON-LD downloadUrl is not $DOWNLOAD_URL" >&2
      exit 1
    }
    # The deploy fills this element with the download total (scripts/render-download-count.sh);
    # the committed page keeps it empty and hidden so a failed count shows nothing.
    grep -Fq '<p class="hero-stats" id="hero-stats" hidden></p>' site/index.html || {
      echo "website is missing the empty, hidden hero-stats element" >&2
      exit 1
    }
    grep -Fq '<p class="download-count" id="download-count" hidden></p>' site/index.html || {
      echo "website is missing the empty, hidden download-count element" >&2
      exit 1
    }
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

    for marker in 'id="features"' 'id="download"' 'id="install"' 'id="help"' "href=\"$DOWNLOAD_URL\"" \
                  'prefers-color-scheme: dark' 'prefers-reduced-motion: reduce' \
                  'Developed by Marton Paulo' \
                  'Download WindowHop <span data-site-version>' 'a[href^="http"]::after' \
                  'id="alttab-alternative"' 'id="demo"' '"@type": "FAQPage"'; do
      grep -R -Fq "$marker" "${indexed[@]}" site/styles/main.css || {
        echo "website is missing required marker: $marker" >&2
        exit 1
      }
    done
    # About (#123) and the site keep the AltTab credit as text; a bare "AltTab on GitHub"
    # link read as WindowHop's own repository.
    if grep -Fq 'AltTab on GitHub' "${pages[@]}"; then
      echo "website links \"AltTab on GitHub\" on its own; keep the credit as text" >&2
      exit 1
    fi

    # Each indexed page names its own URL in the canonical link and og:url, and the
    # sitemap lists it. The URL follows the file: site/help/index.html is /help/.
    host=$(tr -d '[:space:]' < site/CNAME)
    for page in "${indexed[@]}"; do
      path=${page#site/}; path=${path%index.html}
      url="https://$host/$path"
      grep -Fq "<link rel=\"canonical\" href=\"$url\">" "$page" || { echo "$page: canonical is not $url" >&2; exit 1; }
      grep -Fq "<meta property=\"og:url\" content=\"$url\">" "$page" || { echo "$page: og:url is not $url" >&2; exit 1; }
      grep -Fq "<loc>$url</loc>" site/sitemap.xml || { echo "site/sitemap.xml does not list $url" >&2; exit 1; }
      ! grep -qi 'noindex' "$page" || { echo "$page must not contain noindex" >&2; exit 1; }
    done

    # Search and share previews read different tags; they must say the same thing, on
    # every indexed page, and no two pages share a title.
    titles=""
    for page in "${indexed[@]}"; do
      title=$(grep -oE '<title>[^<]*</title>' "$page" | sed -E 's/<\/?title>//g')
      description=$(grep -oE '<meta name="description" content="[^"]*"' "$page" | sed -E 's/.*content="//; s/"$//')
      test -n "$title" && test -n "$description" || {
        echo "$page is missing its <title> or meta description" >&2
        exit 1
      }
      for tag in 'property="og:title"' 'name="twitter:title"'; do
        grep -Fq "<meta $tag content=\"$title\">" "$page" || {
          echo "$page: $tag does not equal the <title>" >&2
          exit 1
        }
      done
      for tag in 'property="og:description"' 'name="twitter:description"'; do
        grep -Fq "<meta $tag content=\"$description\">" "$page" || {
          echo "$page: $tag does not equal the meta description" >&2
          exit 1
        }
      done
      titles+="$title"$'\n'
    done
    [ -z "$(printf '%s' "$titles" | sort | uniq -d)" ] || { echo "two website pages share a <title>" >&2; exit 1; }
    description=$(grep -oE '<meta name="description" content="[^"]*"' site/index.html | sed -E 's/.*content="//; s/"$//')
    grep -Fq "\"description\": \"$description\"" site/index.html || {
      echo "site/index.html: the JSON-LD description does not equal the meta description" >&2
      exit 1
    }

    # Favicons (issue #93): every declared `sizes` describes the file it names, and the home
    # page declares one larger than 48 px, which Google Search asks for. The files come
    # from `scripts/make-icon.swift --favicon site` (part of `make icon`).
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

    # Header and footer are copied into every page (the site has no build step), so
    # the copies must stay identical: the footer byte for byte, the header by label.
    footer_of() { sed -n '/<footer class="site-footer">/,/<\/footer>/p' "$1"; }
    for page in "${pages[@]}"; do
      [ "$(footer_of site/index.html)" = "$(footer_of "$page")" ] || {
          echo "$page footer differs from site/index.html" >&2
          exit 1
      }
    done

    # Every page shows the same header destinations, in the same order.
    nav_labels() { sed -n '/<nav aria-label="Page sections">/,/<\/nav>/p' "$1" | grep -oE '>[^<]+</a>'; }
    for page in "${pages[@]}"; do
      [ "$(nav_labels site/index.html)" = "$(nav_labels "$page")" ] || {
          echo "$page header navigation differs from site/index.html" >&2
          exit 1
      }
    done

    # Every link that leaves the site opens in a new tab (target="_blank", the
    # owner's rule) and carries rel="noopener". Its arrow is drawn once,
    # by the a[href^="http"]::after rule in main.css (a marker above), so the markup
    # never repeats it.
    while IFS= read -r line; do
        case "$line" in *'rel="noopener"'*) ;; *)
            echo "external link without rel=\"noopener\": $line" >&2; exit 1 ;;
        esac
        case "$line" in *'target="_blank"'*) ;; *)
            echo "external link that does not open in a new tab: $line" >&2; exit 1 ;;
        esac
    done < <(grep -hoE '<a [^>]*href="https?://[^"]+"[^>]*>.*</a>' "${pages[@]}" || true)

    # Every local path a page names: src and href values, plus each candidate of a
    # srcset or imagesrcset list with its width descriptor dropped. A path that starts
    # with / is from the site root; any other is relative to the page; a directory
    # path means its index.html; a #fragment is ignored.
    local_references() {
      grep -oE '(src|href)="[^"]+"' "$1" | sed -E 's/^(src|href)="//; s/"$//'
      grep -oE '(srcset|imagesrcset)="[^"]+"' "$1" \
        | sed -E 's/^(srcset|imagesrcset)="//; s/"$//' | tr ',' '\n' | awk '{print $1}'
    }
    for page in "${pages[@]}"; do
      while IFS= read -r reference; do
        reference=${reference%%#*}
        reference=${reference%%\?*}
        case "$reference" in
          http:*|https:*|'') continue ;;
          /*) file="site$reference" ;;
          *) file="$(dirname "$page")/$reference" ;;
        esac
        case "$file" in */) file="${file}index.html" ;; esac
        test -f "$file" || {
          echo "$page references missing local file: $file" >&2
          exit 1
        }
      done < <(local_references "$page")
    done

    # /assets/ is cached by browsers for a year (a Cloudflare rule on the custom
    # domain), so the icon's address carries its content version: a new icon must be
    # a new address, or visitors keep the old one.
    icon_version=$(md5 -q site/assets/app-icon.png 2>/dev/null || md5sum site/assets/app-icon.png | cut -d' ' -f1)
    icon_version=${icon_version:0:8}
    if grep -ho '/assets/app-icon.png[^"]*"' "${pages[@]}" | grep -vqF "/assets/app-icon.png?v=$icon_version\""; then
      echo "an app-icon.png reference lacks ?v=$icon_version (the icon's current content version)" >&2
      exit 1
    fi

    # Every published screenshot is used, and each one exists in a light and a dark
    # version: the pages show the one that matches the visitor's appearance.
    for shot in site/screenshots/*.webp; do
      name=$(basename "$shot")
      case "$name" in
        *-light*) twin=${name/-light/-dark} ;;
        *-dark*) twin=${name/-dark/-light} ;;
        *) echo "screenshot without a light or dark twin: $shot" >&2; exit 1 ;;
      esac
      test -f "site/screenshots/$twin" || { echo "$shot has no $twin" >&2; exit 1; }
    done

    if grep -RinE 'codex-clipboard|annotation|red arrow|private repository' "${pages[@]}" site/styles site/scripts; then
      echo "website contains development-only or sensitive wording" >&2
      exit 1
    fi
)
if windowhop_site_checks; then
    pass "GitHub Pages site (WindowHop checks)"
else
    fail "GitHub Pages site failed the WindowHop checks"
fi

# --- release notes pages (#128) ------------------------------------------------
# Sparkle's update window shows the site's notes page for each version, written at
# deploy time from CHANGELOG.md. The script must render the current changelog, and
# every appcast item with a changelog entry must link its page, not GitHub's.
notes_dir=$(mktemp -d)
if python3 scripts/render-release-notes.py "$notes_dir" >/dev/null \
    && [ -f "$notes_dir/release-notes/$CHANGELOG_VERSION/index.html" ] \
    && [ -f "$notes_dir/release-notes/index.html" ]; then
    pass "release notes render from CHANGELOG ($CHANGELOG_VERSION included)"
else
    fail "scripts/render-release-notes.py did not render the notes for $CHANGELOG_VERSION"
fi
rm -rf "$notes_dir"
if grep -q "releaseNotesLink>https://github.com/" appcast.xml; then
    fail "appcast.xml links a GitHub release page; link https://windowhop.martonpaulo.com/release-notes/X.Y.Z/"
else
    pass "appcast release notes link the site's pages"
fi
grep -q "render-release-notes.py" .github/workflows/deploy.yml \
    || fail "deploy.yml does not render the release notes"

# --- canonical release scripts ------------------------------------------------
# These are byte-identical copies of skill-deck's project-release assets, whose
# own suites own their behavior (the conventions check reports a drifted copy).
# Here each one must parse and answer --help (notarize.sh has no --help), so a
# broken copy is caught before a tag.
script_failures=$failures
for script in package-app.sh make-dmg.sh make-appcast.sh publish-release.sh notarize.sh \
    verify-release-identity.sh verify-dmg-branding.sh sign-update.sh make-keys.sh; do
    if ! bash -n "scripts/$script"; then
        fail "scripts/$script does not parse"
    elif [ "$script" != notarize.sh ] && ! "scripts/$script" --help >/dev/null 2>&1; then
        fail "scripts/$script --help fails"
    fi
done
if [ "$failures" -eq "$script_failures" ]; then
    pass "canonical release scripts parse and answer --help"
fi

# --- release-script fixtures -------------------------------------------------
# These run the real scripts in isolation, publish-release.sh against a fake
# `gh`: no network, no token, no signing material, no real release.
for fixture in tests/scripts/publish-release-tests.sh tests/scripts/release-notes-tests.sh \
    tests/scripts/stamp-app-metadata-tests.sh tests/scripts/verify-update-continuity-tests.sh; do
    if output=$("$fixture" 2>&1); then
        pass "$(printf '%s' "$output" | tail -1)"
    else
        printf '%s\n' "$output"
        fail "$(basename "$fixture") reported failures"
    fi
done

# --- secrets must never be committed -----------------------------------------
if git ls-files | grep -iE "private.?key|\.p12$|\.pem$"; then
    fail "potential secret file tracked in git"
else
    pass "no secret-looking files tracked"
fi

echo ""
if [ "$failures" -gt 0 ]; then
    echo "validation FAILED with $failures problem(s)"
    exit 1
fi
echo "validation passed"
