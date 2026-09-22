#!/usr/bin/env bash
# Canonical release-identity check for the owner's macOS apps. Copy it unchanged to
# scripts/verify-release-identity.sh in each app; project-setup alignment reports a drifted copy.
#
# Rejects a signed app whose effective macOS identity would differ from the released one. macOS
# keys the Accessibility grant, the Keychain and UserDefaults to that identity, so a change here
# silently costs every user their permissions and data on the next update. Run it after signing
# and again on the app inside the DMG.
#
# The expected identity comes from the repository, never from this file:
#   - identifier and executable: CFBundleIdentifier and CFBundleExecutable in Support/Info.plist;
#   - certificate: Support/ReleaseCertificate.cer, the leaf0 that
#       codesign -d --extract-certificates=leaf <a signed release build>
#     writes; its CN is the signing authority and its OU the team;
#   - requirement: Support/ExpectedDesignatedRequirement.txt, the text after `designated => ` in
#       codesign -dr - <a signed release build>
#
# Checks, in order: arm64 only; a strict deep verification; the identifier, team, authority and
# hardened runtime; the stable empty entitlement set; the designated requirement; the leaf
# certificate byte for byte; and every nested Mach-O verified and signed by the same team.
#
# Prints one `release identity: ok` line on stdout and everything else on stderr.
set -euo pipefail
cd "$(dirname "$0")/.."

PLIST_BUDDY=${PLIST_BUDDY:-/usr/libexec/PlistBuddy}
PLIST=Support/Info.plist
CERTIFICATE=Support/ReleaseCertificate.cer
REQUIREMENT=Support/ExpectedDesignatedRequirement.txt

usage() {
  cat <<'USAGE'
usage: scripts/verify-release-identity.sh [--app <App.app>] [--team <TEAMID>]
  --app <App.app>    the signed app to check (default build/<Name>.app)
  --team <TEAMID>    the expected team; must equal the certificate's (default: the certificate's OU)
  --help             show this help
To record the fixtures from a signed release build:
  codesign -d --extract-certificates=leaf <App.app>   then commit leaf0 as Support/ReleaseCertificate.cer
  codesign -dr - <App.app>                            then commit the text after `designated => `
                                                      as Support/ExpectedDesignatedRequirement.txt
USAGE
}

fail_usage() { echo "error: $1" >&2; usage >&2; exit 2; }
need_value() { [[ $# -ge 2 && -n $2 && $2 != --* ]] || fail_usage "$1 needs a value"; }
fail() { echo "Identity validation failed: $1" >&2; exit 1; }

app=''
team=''
while [[ $# -gt 0 ]]; do
  case $1 in
    --app) need_value "$@"; app=$2; shift 2 ;;
    --team) need_value "$@"; team=$2; shift 2 ;;
    --help) usage; exit 0 ;;
    *) fail_usage "unknown option $1" ;;
  esac
done
team_shape='^[A-Z0-9]{10}$'
[[ -z $team || $team =~ $team_shape ]] || fail_usage "--team must be ten capital letters or digits, not $team"

[[ -f $PLIST ]] || fail "$PLIST not found; run this from an app repository"
read_key() { "$PLIST_BUDDY" -c "Print :$1" "$PLIST" 2>/dev/null || fail "$PLIST has no $1"; }
name=$(read_key CFBundleName)
identifier=$(read_key CFBundleIdentifier)
executable=$(read_key CFBundleExecutable)
app=${app:-build/$name.app}

[[ -d $app ]] || fail "app not found: $app"
[[ -f $app/Contents/MacOS/$executable ]] || fail "main executable not found: $app/Contents/MacOS/$executable"
[[ -f $CERTIFICATE ]] || fail "$CERTIFICATE not found; see --help to record it"
[[ -s $REQUIREMENT ]] || fail "$REQUIREMENT is missing or empty; see --help to record it"
expected_requirement=$(tr -d '\n' <"$REQUIREMENT")

# One CN= and one OU= line, the same under LibreSSL and OpenSSL with this -nameopt.
subject=$(openssl x509 -inform DER -in "$CERTIFICATE" -noout -subject -nameopt sep_multiline,utf8,-esc_msb) \
  || fail "$CERTIFICATE is not a DER certificate"
authority=''
certificate_team=''
while IFS= read -r line; do
  line=${line#"${line%%[![:space:]]*}"}
  case $line in
    CN=*) authority=${line#CN=} ;;
    OU=*) certificate_team=${line#OU=} ;;
  esac
done <<<"$subject"
[[ $authority == 'Developer ID Application: '* ]] \
  || fail "$CERTIFICATE is not a Developer ID Application certificate (CN is '$authority')"
[[ -n $certificate_team ]] || fail "$CERTIFICATE names no team (no OU)"
if [[ -n $team && $team != "$certificate_team" ]]; then
  fail "--team is $team, but $CERTIFICATE belongs to team $certificate_team"
fi
team=$certificate_team

# Apple silicon only: the main executable carries exactly one arm64 slice.
archs=$(lipo -archs "$app/Contents/MacOS/$executable") || fail "lipo could not read the main executable"
[[ $archs == arm64 ]] || fail "the main executable must be arm64 only, found: $archs"

codesign --verify --deep --strict --verbose=2 "$app" >&2 || fail "the deep strict verification failed"

signature=$(codesign -dvvv "$app" 2>&1) || fail "codesign could not display the signature"
grep -Fqx "Identifier=$identifier" <<<"$signature" || fail "the signing identifier is not $identifier"
grep -Fqx "TeamIdentifier=$team" <<<"$signature" || fail "the TeamIdentifier is not $team"
grep -Fqx "Authority=$authority" <<<"$signature" || fail "the authority $authority is absent"
runtime=0
while IFS= read -r line; do
  [[ $line == *flags=*runtime* ]] && runtime=1
done <<<"$signature"
(( runtime )) || fail "the hardened runtime is absent"

entitlements=$(codesign -d --entitlements - "$app" 2>/dev/null) || fail "codesign could not read the entitlements"
[[ -z ${entitlements//[[:space:]]/} ]] || fail "the entitlements changed from the stable empty set"

requirement_output=$(codesign -dr - "$app" 2>/dev/null) || fail "codesign could not read the designated requirement"
actual_requirement=''
while IFS= read -r line; do
  case $line in 'designated => '*) actual_requirement=${line#'designated => '} ;; esac
done <<<"$requirement_output"
if [[ $actual_requirement != "$expected_requirement" ]]; then
  echo "expected: $expected_requirement" >&2
  echo "actual:   $actual_requirement" >&2
  fail "the designated requirement changed"
fi

certificates=$(mktemp -d)
trap 'rm -rf "$certificates"' EXIT
codesign -d --extract-certificates="$certificates/leaf" "$app" 2>/dev/null \
  || fail "codesign could not extract the certificates"
cmp -s "$CERTIFICATE" "$certificates/leaf0" || fail "the leaf certificate differs from $CERTIFICATE"

while IFS= read -r nested; do
  description=$(file "$nested") || fail "file could not read $nested"
  [[ $description == *Mach-O* ]] || continue
  codesign --verify --strict "$nested" >&2 || fail "nested code fails verification: $nested"
  nested_signature=$(codesign -dvvv "$nested" 2>&1) || fail "codesign could not display $nested"
  grep -Fqx "TeamIdentifier=$team" <<<"$nested_signature" || fail "nested code uses another team: $nested"
done < <(find "$app/Contents" -type f -perm -111 -print)

echo "release identity: ok ($identifier, team $team, stable certificate and requirement)"
