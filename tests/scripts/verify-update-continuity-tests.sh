#!/bin/bash
# Executable fixtures for scripts/verify-update-continuity.sh, including its
# --identifier-transition mode (#43). The apps are throwaway directories and a
# fake `codesign` and `lipo` answer for them from files inside each one: no
# signing identity, no real release, no network.
set -uo pipefail
cd "$(dirname "$0")/../.."
REPO_ROOT=$PWD

PASSED=0
FAILED=0
check() {
    if [ "$2" = "$3" ]; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
        echo "FAIL: $1" >&2
        echo "  expected: $3" >&2
        echo "  actual:   $2" >&2
    fi
}

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/bin"

cat >"$SANDBOX/bin/codesign" <<'FAKE'
#!/bin/bash
# Answers from <app>/fake/{identifier,team,authority,requirement}; the app is the last argument.
app=${!#}
fake=$app/fake
case $1 in
    --verify) exit 0 ;;
    -dvvv)
        {
            echo "Executable=$app/Contents/MacOS/WindowHop"
            echo "Identifier=$(cat "$fake/identifier")"
            echo "CodeDirectory v=20500 size=1 flags=0x10000(runtime) hashes=1+0 location=embedded"
            echo "Authority=$(cat "$fake/authority")"
            echo "TeamIdentifier=$(cat "$fake/team")"
        } >&2
        ;;
    -dr) echo "designated => $(cat "$fake/requirement")" ;;
    -d)
        case $2 in
            --entitlements) ;;
            --extract-certificates=*) cp "$fake/leaf" "${2#--extract-certificates=}0" ;;
            *) exit 1 ;;
        esac
        ;;
    *) exit 1 ;;
esac
FAKE
printf '#!/bin/bash\necho arm64\n' >"$SANDBOX/bin/lipo"
chmod +x "$SANDBOX/bin/codesign" "$SANDBOX/bin/lipo"
export PATH="$SANDBOX/bin:$PATH"

NEW_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Support/Info.plist)
OLD_ID=com.example.previous
REQUIREMENT=$(tr -d '\n' <Support/ExpectedDesignatedRequirement.txt)
REST=${REQUIREMENT#"identifier \"$NEW_ID\" "}
AUTHORITY=$(openssl x509 -inform DER -in Support/ReleaseCertificate.cer -noout -subject \
    -nameopt sep_multiline,utf8,-esc_msb | sed -n 's/^ *CN=//p')
TEAM=$(openssl x509 -inform DER -in Support/ReleaseCertificate.cer -noout -subject \
    -nameopt sep_multiline,utf8,-esc_msb | sed -n 's/^ *OU=//p')

# make_app <name> <identifier> <requirement>
make_app() {
    local app="$SANDBOX/$1/WindowHop.app"
    mkdir -p "$app/Contents/MacOS" "$app/fake"
    printf '#!/bin/sh\n' >"$app/Contents/MacOS/WindowHop"
    chmod +x "$app/Contents/MacOS/WindowHop"
    printf '%s' "$2" >"$app/fake/identifier"
    printf '%s' "$3" >"$app/fake/requirement"
    printf '%s' "$AUTHORITY" >"$app/fake/authority"
    printf '%s' "$TEAM" >"$app/fake/team"
    cp Support/ReleaseCertificate.cer "$app/fake/leaf"
    echo "$app"
}
continuity() { "$REPO_ROOT/scripts/verify-update-continuity.sh" "$@" >/dev/null 2>&1; echo $?; }

CURRENT=$(make_app current "$NEW_ID" "$REQUIREMENT")
CURRENT_TOO=$(make_app current-too "$NEW_ID" "$REQUIREMENT")
LEGACY=$(make_app legacy "$OLD_ID" "identifier \"$OLD_ID\" $REST")
DRIFTED=$(make_app drifted "$OLD_ID" "identifier \"$OLD_ID\" $REST and info[CFBundleVersion] exists")

# --- the normal gate --------------------------------------------------------------
check "same identity passes" "$(continuity "$CURRENT_TOO" "$CURRENT")" "0"
check "an identifier change fails without the transition" "$(continuity "$LEGACY" "$CURRENT")" "1"

# --- the one-time transition ---------------------------------------------------------
check "old -> new passes in transition mode" \
    "$(continuity --identifier-transition "$OLD_ID" "$NEW_ID" "$LEGACY" "$CURRENT")" "0"
check "a requirement that differs beyond the identifier fails" \
    "$(continuity --identifier-transition "$OLD_ID" "$NEW_ID" "$DRIFTED" "$CURRENT")" "1"
check "a previous app not signed as <old> fails" \
    "$(continuity --identifier-transition "$OLD_ID" "$NEW_ID" "$CURRENT_TOO" "$CURRENT")" "1"
check "a candidate still signed as <old> fails" \
    "$(continuity --identifier-transition "$OLD_ID" "$NEW_ID" "$LEGACY" "$LEGACY")" "1"
check "<new> must be the Info.plist identifier" \
    "$(continuity --identifier-transition "$OLD_ID" com.example.other "$LEGACY" "$CURRENT")" "2"
check "<old> and <new> must differ" \
    "$(continuity --identifier-transition "$NEW_ID" "$NEW_ID" "$CURRENT_TOO" "$CURRENT")" "2"
check "a malformed identifier is refused" \
    "$(continuity --identifier-transition 'com.*' "$NEW_ID" "$LEGACY" "$CURRENT")" "2"

# --- usage errors -----------------------------------------------------------------
check "one app is a usage error" "$(continuity "$CURRENT")" "2"
check "a transition without apps is a usage error" \
    "$(continuity --identifier-transition "$OLD_ID" "$NEW_ID")" "2"

if [ "$FAILED" -gt 0 ]; then
    echo "verify-update-continuity: $FAILED failed, $PASSED passed" >&2
    exit 1
fi
echo "verify-update-continuity: all $PASSED checks passed"
