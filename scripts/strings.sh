#!/usr/bin/env bash
# Regenerate, or check, the English String Catalog and its compiled table.
#
#   Support/Localizable.xcstrings          every user-visible string (generated)
#   Support/en.lproj/Localizable.strings   its compiled form, which the canonical
#                                          scripts/package-app.sh copies into the app
#                                          (it compiles no catalog: martonpaulo/skill-deck#333)
#
# The Swift sources are the authority: each key is the English text written in
# `String(localized:)`, a SwiftUI literal or another localizable API. The keys come from
# the compiler (`-emit-localized-strings`), not from `xcstringstool extract`: extract
# misses keys chosen by a ternary and writes `%arg` where the runtime key is `%@` or
# `%lld` (probe recorded on #99). Every entry receives an explicit English value equal to
# its key, because xcstringstool compiles no table for entries without one.
#
# Never edit the two generated files by hand; change the source and run `make strings`.
#
# Usage: scripts/strings.sh           regenerate both files
#        scripts/strings.sh --check   fail when either file differs from the sources
set -euo pipefail

mode=write
case "${1:-}" in
  "") ;;
  --check) mode=check ;;
  *) echo "usage: $0 [--check]" >&2; exit 64 ;;
esac

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

catalog=Support/Localizable.xcstrings
table=Support/en.lproj/Localizable.strings
# A separate scratch path: the extra compiler flags would otherwise invalidate the
# normal .build products on every run.
scratch=.build/strings
work="$(mktemp -d "${TMPDIR:-/tmp}/windowhop-strings.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# 1. Keys, from the compiler. The compiler writes a file's stringsdata only when it
#    compiles that file, so removing this project's module products forces a full
#    recompile of our sources (dependencies stay built).
if [[ -d $scratch ]]; then
  find "$scratch" -type d -name 'WindowHop*.build' -prune -exec rm -rf {} +
fi
mkdir -p "$work/stringsdata"
if ! swift build --scratch-path "$scratch" \
    -Xswiftc -emit-localized-strings \
    -Xswiftc -emit-localized-strings-path -Xswiftc "$work/stringsdata" \
    > "$work/build.log" 2>&1; then
  cat "$work/build.log" >&2
  echo "strings: the build failed" >&2
  exit 1
fi
shopt -s nullglob
stringsdata=("$work"/stringsdata/*.stringsdata)
if [[ ${#stringsdata[@]} -eq 0 ]]; then
  echo "strings: the compiler wrote no stringsdata" >&2
  exit 1
fi

# 2. The catalog, rebuilt from an empty one so a removed string leaves no stale entry.
#    xcstringstool reads the table name from the file name, so it must stay Localizable.
mkdir -p "$work/catalog"
printf '{"sourceLanguage":"en","strings":{},"version":"1.0"}\n' > "$work/catalog/Localizable.xcstrings"
xcrun xcstringstool sync "$work/catalog/Localizable.xcstrings" --stringsdata "${stringsdata[@]}"
python3 - "$work/catalog/Localizable.xcstrings" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    catalog = json.load(f)
for key, entry in catalog["strings"].items():
    entry.pop("extractionState", None)
    entry["localizations"] = {"en": {"stringUnit": {"state": "translated", "value": key}}}
with open(path, "w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2, separators=(",", " : "), sort_keys=True)
    f.write("\n")
PY

# 3. The compiled table.
xcrun xcstringstool compile "$work/catalog/Localizable.xcstrings" --output-directory "$work/compiled"

generated_catalog="$work/catalog/Localizable.xcstrings"
generated_table="$work/compiled/en.lproj/Localizable.strings"
if [[ ! -f $generated_table ]]; then
  echo "strings: xcstringstool compiled no en.lproj/Localizable.strings" >&2
  exit 1
fi

if [[ $mode == write ]]; then
  mkdir -p "$(dirname "$table")"
  cp "$generated_catalog" "$catalog"
  cp "$generated_table" "$table"
  echo "strings: $(xcrun xcstringstool print "$catalog" | wc -l | tr -d ' ') keys in $catalog and $table"
  exit 0
fi

stale=0
for pair in "$catalog:$generated_catalog" "$table:$generated_table"; do
  committed="${pair%%:*}"
  generated="${pair#*:}"
  if ! cmp -s "$committed" "$generated"; then
    echo "strings: $committed is out of date with the sources" >&2
    diff -u "$committed" "$generated" >&2 || true
    stale=1
  fi
done
if [[ $stale -ne 0 ]]; then
  echo "strings: run 'make strings' and commit the result" >&2
  exit 1
fi
echo "strings: $catalog and $table match the sources"
