#!/usr/bin/env bash
# Canonical Sparkle signing script for the owner's macOS apps. Copy it unchanged to
# scripts/sign-update.sh in each app; project-setup alignment reports a drifted copy.
#
# Signs a release archive with Sparkle's sign_update, taken from the Sparkle version SwiftPM
# resolved into .build/artifacts, and prints the appcast attributes make-appcast.sh expects:
#   sparkle:edSignature="..." length="..."
# Without options sign_update reads the key from the login Keychain. Everything after -- goes to
# sign_update unchanged, so CI passes the key on standard input:
#   printf '%s\n' "$SPARKLE_PRIVATE_KEY" | scripts/sign-update.sh --archive <zip> -- --ed-key-file -
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  cat <<'USAGE'
usage: scripts/sign-update.sh --archive <path.zip> [-- <sign_update options>]
  --archive <path.zip>   the release archive to sign
  --help                 show this help
Options after -- are passed to sign_update unchanged, for example -- --ed-key-file -
USAGE
}

fail_usage() { echo "error: $1" >&2; usage >&2; exit 2; }

archive=''
passthrough=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --archive)
      [[ $# -ge 2 && -n $2 && $2 != --* ]] || fail_usage '--archive needs a value'
      archive=$2; shift 2 ;;
    --help) usage; exit 0 ;;
    --) shift; passthrough=("$@"); break ;;
    *) fail_usage "unknown option $1" ;;
  esac
done
[[ -n $archive ]] || fail_usage '--archive is required'
[[ -f $archive ]] || { echo "error: $archive not found" >&2; exit 1; }

# A find that fails inside a pipeline under pipefail exits silently, so check the directory first.
[[ -d .build/artifacts ]] || { echo "error: .build/artifacts not found; run 'swift build' first" >&2; exit 1; }
# The path, not the name: Sparkle also ships bin/old_dsa_scripts/sign_update, which is not the tool.
sign_update=$(find .build/artifacts -path '*/bin/sign_update' -type f -print -quit)
[[ -n $sign_update ]] || { echo "error: sign_update not found under .build/artifacts; run 'swift build' first" >&2; exit 1; }

"$sign_update" ${passthrough[@]+"${passthrough[@]}"} "$archive" \
  || { echo "error: sign_update failed for $archive" >&2; exit 1; }
