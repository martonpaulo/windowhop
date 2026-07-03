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

# --- appcast/release metadata consistency ------------------------------------
if [ -f appcast.xml ]; then
    if grep -q "sparkle:edSignature=" appcast.xml && grep -q "https://github.com/martonpaulo/windowhop/releases/download/" appcast.xml; then
        pass "appcast entries are signed and point at GitHub Releases"
    else
        fail "appcast.xml missing edSignature or GitHub release URLs"
    fi
fi

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
