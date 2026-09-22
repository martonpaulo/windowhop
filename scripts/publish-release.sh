#!/usr/bin/env bash
# Canonical publication script for the owner's macOS apps. Copy it unchanged to
# scripts/publish-release.sh in each app; project-setup alignment reports a drifted copy. It is the
# only script in the set that publishes anything, and it runs only from the release workflow.
#
# The update feed may only advertise files that already exist, so this is the verified step before
# any appcast change: it stages every artifact in a draft, checks the complete set against the local
# files by name, byte count and SHA-256, publishes, and checks again against the public release.
#
#   - A public release is never rewritten. When it already holds exactly these artifacts the run is
#     a read-only no-op; anything else, an asset it did not produce included, is an operator
#     conflict.
#   - A draft left by an earlier run is completed, never duplicated.
#   - Only "release not found" means there is no release yet. Any other lookup failure, and any
#     failure to read whether the release is a draft, stops the run: reading an authentication
#     error as "no release" would publish a second release over a live one.
#   - The tag must already exist on the remote (--verify-tag), so nothing untagged is published.
#
# The release title is "<CFBundleName> <tag without its leading v>". stdout stays empty.
set -euo pipefail
cd "$(dirname "$0")/.."

PLIST_BUDDY=${PLIST_BUDDY:-/usr/libexec/PlistBuddy}
PLIST=Support/Info.plist

usage() {
  cat <<'USAGE'
usage: scripts/publish-release.sh --tag <vX.Y.Z> --notes-file <file> --artifact <path> [--artifact <path>...]
  --tag <vX.Y.Z>        the release tag, which must already exist on the remote
  --notes-file <file>   release notes, not empty
  --artifact <path>     a file to publish; repeat for each one
  --help                show this help
USAGE
}

fail_usage() { echo "error: $1" >&2; usage >&2; exit 2; }
need_value() { [[ $# -ge 2 && -n $2 && $2 != --* ]] || fail_usage "$1 needs a value"; }
die() { echo "error: $1" >&2; exit 1; }

tag=''
notes=''
artifacts=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --tag) need_value "$@"; tag=$2; shift 2 ;;
    --notes-file) need_value "$@"; notes=$2; shift 2 ;;
    --artifact) need_value "$@"; artifacts+=("$2"); shift 2 ;;
    --help) usage; exit 0 ;;
    *) fail_usage "unknown option $1" ;;
  esac
done
[[ -n $tag ]] || fail_usage '--tag is required'
[[ -n $notes ]] || fail_usage '--notes-file is required'
# Checked before any expansion: bash before 4.4 treats an empty "${artifacts[@]}" as unbound.
(( ${#artifacts[@]} > 0 )) || fail_usage 'give at least one --artifact'

[[ -f $PLIST ]] || die "$PLIST not found; run this from an app repository"
name=$("$PLIST_BUDDY" -c 'Print :CFBundleName' "$PLIST" 2>/dev/null) || die "$PLIST has no CFBundleName"
[[ -s $notes ]] || die "release notes $notes are missing or empty"
for artifact in "${artifacts[@]}"; do
  [[ -f $artifact ]] || die "artifact $artifact not found"
done

errors=$(mktemp)
trap 'rm -f "$errors"' EXIT

# Prints "name<TAB>size<TAB>digest" for every asset; the digest is empty when GitHub reports none. Returns 0 when the release was read, 1 when it does not
# exist, and 2 when the lookup itself failed; the caller never reads 2 as "no release yet".
release_assets() {
  local output status=0
  output=$(gh release view "$tag" --json assets 2>"$errors") || status=$?
  if (( status != 0 )); then
    [[ $(cat "$errors") == 'release not found' ]] && return 1
    printf 'error: could not read release %s: %s\n' "$tag" "$(cat "$errors")" >&2
    return 2
  fi
  printf '%s' "$output" | python3 -c '
import json, sys
for asset in json.load(sys.stdin)["assets"]:
    print("%s\t%s\t%s" % (asset["name"], asset["size"], asset.get("digest") or ""))
' || { printf 'error: could not parse the assets of release %s\n' "$tag" >&2; return 2; }
}

# Like release_assets, for a release that must exist by now.
require_release_assets() {
  local output status=0
  output=$(release_assets) || status=$?
  case $status in
    0) printf '%s' "$output" ;;
    1) die "release $tag disappeared while it was being published" ;;
    *) exit 1 ;;
  esac
}

# Prints true or false. Any other answer stops the run: a failed read is never taken as "public".
release_draft_state() {
  local answer status=0
  answer=$(gh release view "$tag" --json isDraft --jq .isDraft 2>"$errors") || status=$?
  if (( status != 0 )) || [[ $answer != true && $answer != false ]]; then
    die "could not read whether release $tag is a draft: $(cat "$errors")$answer"
  fi
  printf '%s' "$answer"
}

is_local() { # $1 asset name
  local artifact
  for artifact in "${artifacts[@]}"; do
    [[ $(basename "$artifact") == "$1" ]] && return 0
  done
  return 1
}

sha256() { # $1 file -> "sha256:<hex>", the same on macOS and Linux, where shasum and sha256sum differ
  python3 -c 'import hashlib, sys; print("sha256:" + hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"
}

# The release must hold exactly the local artifacts: every one, at its local byte count and SHA-256,
# and nothing else. A same-size file with other bytes is caught by the digest.
verify_assets() { # $1 "name<TAB>size<TAB>digest" lines
  local artifact asset size published digest published_digest
  for artifact in "${artifacts[@]}"; do
    asset=$(basename "$artifact")
    size=$(wc -c <"$artifact" | tr -d '[:space:]')
    published=$(printf '%s\n' "$1" | awk -F'\t' -v n="$asset" '$1 == n { print $2 }')
    [[ -n $published ]] || die "release $tag is missing asset $asset"
    [[ $published == "$size" ]] \
      || die "asset $asset is $published bytes on release $tag but $size bytes locally"
    published_digest=$(printf '%s\n' "$1" | awk -F'\t' -v n="$asset" '$1 == n { print $3 }')
    [[ -n $published_digest ]] || die "release $tag reports no SHA-256 for $asset, so it cannot be verified"
    digest=$(sha256 "$artifact")
    [[ $published_digest == "$digest" ]] \
      || die "asset $asset is $published_digest on release $tag but $digest locally"
  done
  while IFS=$'\t' read -r asset size _; do
    [[ -z $asset ]] || is_local "$asset" \
      || die "release $tag also carries $asset, which this run did not produce; resolve it by hand"
  done <<<"$1"
}

lookup=0
existing=$(release_assets) || lookup=$?
(( lookup != 2 )) || exit 1
if (( lookup == 0 )); then
  draft=$(release_draft_state)
  if [[ $draft == true ]]; then
    echo "Release $tag exists as a draft; completing it." >&2
  else
    verify_assets "$existing"
    echo "Release $tag is already public with exactly these artifacts; nothing to do." >&2
    exit 0
  fi
else
  echo "Creating draft release $tag." >&2
  gh release create "$tag" --draft --verify-tag --title "$name ${tag#v}" --notes-file "$notes" >&2
fi

# --clobber is safe only here: the release is still a draft, so nothing it replaces was public.
for artifact in "${artifacts[@]}"; do
  echo "Uploading $(basename "$artifact")." >&2
  gh release upload "$tag" "$artifact" --clobber >&2
done

assets=$(require_release_assets)
verify_assets "$assets"
echo "Draft $tag holds exactly these artifacts; publishing." >&2
gh release edit "$tag" --draft=false >&2

draft=$(release_draft_state)
[[ $draft == false ]] || die "release $tag is still a draft after publishing"
assets=$(require_release_assets)
verify_assets "$assets"
echo "Release $tag is public with every artifact verified." >&2
