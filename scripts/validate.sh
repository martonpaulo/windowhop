#!/bin/bash
# Repository validation: invariants that must hold for every commit and release.
# Run from the repository root. Exits non-zero with an explanation on violation.
set -uo pipefail
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
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Support/Info.plist)" = "com.perso.windowhop" ]; then
    pass "bundle identifier is com.perso.windowhop"
else
    fail "Support/Info.plist bundle identifier is not com.perso.windowhop"
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
if grep -rn "AppCenter\|analytics\|telemetry" Sources/ --include="*.swift" 2>/dev/null | grep -iv "no telemetry\|telemetry, no\|no analytics"; then
    fail "telemetry reference found in Sources/"
else
    pass "no telemetry"
fi

# --- updater configuration ---------------------------------------------------
for key in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks; do
    if /usr/libexec/PlistBuddy -c "Print :$key" Support/Info.plist >/dev/null 2>&1; then
        pass "Info.plist has $key"
    else
        fail "Info.plist missing $key"
    fi
done
FEED=$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' Support/Info.plist)
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

# "Report an Issue…" prefills these bug-report inputs by id (Core/ProjectLinks.swift);
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
    BUNDLE_FLOOR=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Support/Info.plist)
    NEWEST_FLOOR=$(grep -o '<sparkle:minimumSystemVersion>[^<]*' appcast.xml | head -1 | cut -d'>' -f2)
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
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)
# The README no longer advertises a download (the GitHub About carries the site), so the
# document that must track the shipped version is the changelog: its newest entry is the
# release being described. The file follows Keep a Changelog: `## [X.Y.Z] - date`
# headings, with one `## [Unreleased]` section above every version.
CHANGELOG_VERSION=$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | head -1 | tr -d '#[] ')
if [ "$CHANGELOG_VERSION" = "$VERSION" ]; then
    pass "CHANGELOG's newest entry matches version $VERSION"
else
    fail "CHANGELOG's newest entry ($CHANGELOG_VERSION) does not match version $VERSION"
fi
UNRELEASED_COUNT=$(grep -c '^## \[Unreleased\]' CHANGELOG.md || true)
UNRELEASED_LINE=$(grep -n '^## \[Unreleased\]' CHANGELOG.md | head -1 | cut -d: -f1)
FIRST_VERSION_LINE=$(grep -nE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | head -1 | cut -d: -f1)
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
        || grep -qF -e "\"$site_path\"" -e "$site_path " site/index.html; then
        :
    else
        fail "unreferenced screenshot is tracked: $screenshot"
    fi
done < <(find site/screenshots -type f -print | sort)

if [ "$failures" -eq 0 ]; then
    pass "Markdown local links and tracked screenshots are synchronized"
fi

if scripts/validate-site.sh; then
    pass "GitHub Pages static site"
else
    fail "GitHub Pages static site validation failed"
fi

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
# These run the real scripts in isolation: no network, no token, no signing
# material, no real release.
for fixture in tests/scripts/release-notes-tests.sh tests/scripts/stamp-app-metadata-tests.sh; do
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
