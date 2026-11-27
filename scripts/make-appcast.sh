#!/usr/bin/env bash
# Canonical Sparkle appcast script for the owner's macOS apps. Copy it unchanged to
# scripts/make-appcast.sh in each app; bench-setup alignment reports a drifted copy.
#
# Adds one release entry, newest first, to appcast.xml at the repository root, creating the feed
# when it does not exist. The feed title and the GitHub repository come from CFBundleName and
# SUFeedURL, and the minimum macOS from LSMinimumSystemVersion, all in Support/Info.plist.
#
# An entry for this version that already exists is left alone. When it advertises the same build
# number, download URL, signature and length, the run is a no-op; when any of them differs, the run
# fails and prints that entry, because the feed then describes a different build and an operator
# has to decide which one is true. Published entries are never rewritten, and their release-notes
# links are never compared.
#
# The update window's notes link defaults to the GitHub release page. An app that publishes its notes
# on its own site passes --release-notes-url with a {version} placeholder, for example
# https://<host>/release-notes/{version}/update/, and --full-release-notes-url for the page that
# lists every version ("Version History"), so no workflow edits the feed afterwards.
#
# Writes only appcast.xml; progress goes to stderr and stdout stays empty.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/cli.sh"
cd "$(dirname "$0")/.."

usage() {
  cat <<'USAGE'
usage: scripts/make-appcast.sh --version <X.Y.Z> --build-number <N> --archive <path.zip> --signature <attributes>
  --version <X.Y.Z>          short version of the release
  --build-number <N>         build number of the release
  --archive <path.zip>       the archive; only its file name is used, in the download URL
  --signature <attributes>   sign-update.sh output: sparkle:edSignature="..." length="..."
  --release-notes-url <template>
                             https:// notes link, {version} replaced by the version
                             (default: the GitHub release page)
  --full-release-notes-url <url>
                             https:// page listing every version's notes (default: none)
  --help                     show this help
USAGE
}


version=''
build_number=''
archive=''
signature=''
notes_template=''
full_notes_url=''
while [[ $# -gt 0 ]]; do
  case $1 in
    --version) need_value "$@"; version=$2; shift 2 ;;
    --build-number) need_value "$@"; build_number=$2; shift 2 ;;
    --archive) need_value "$@"; archive=$2; shift 2 ;;
    --signature) need_value "$@"; signature=$2; shift 2 ;;
    --release-notes-url) need_value "$@"; notes_template=$2; shift 2 ;;
    --full-release-notes-url) need_value "$@"; full_notes_url=$2; shift 2 ;;
    --help) usage; exit 0 ;;
    *) fail_usage "unknown option $1" ;;
  esac
done
for required in version build_number archive signature; do
  [[ -n ${!required} ]] || fail_usage "--${required//_/-} is required"
done
signature=${signature#"${signature%%[![:space:]]*}"}
signature=${signature%"${signature##*[![:space:]]}"}
signature_shape='^sparkle:edSignature="[A-Za-z0-9+/]+=*" length="[0-9]+"$'
[[ $signature =~ $signature_shape ]] \
  || fail_usage "--signature must be sparkle:edSignature=\"...\" length=\"...\", as sign-update.sh prints it"
if [[ -n $notes_template && ( $notes_template != https://* || $notes_template != *'{version}'* ) ]]; then
  fail_usage '--release-notes-url must be an https:// URL containing {version}'
fi
if [[ -n $full_notes_url && $full_notes_url != https://* ]]; then
  fail_usage '--full-release-notes-url must be an https:// URL'
fi

python3 - "$version" "$build_number" "$archive" "$signature" "$notes_template" "$full_notes_url" <<'PY'
import os
import plistlib
import re
import sys
import tempfile
import time
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

version, build_number, archive, signature, notes_template, full_notes_url = sys.argv[1:7]
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
FEED = "appcast.xml"
PLIST = "Support/Info.plist"


def die(message):
    sys.stderr.write("error: %s\n" % message)
    sys.exit(1)


def attribute(value):
    return '"%s"' % escape(value, {'"': "&quot;"})


if not os.path.isfile(PLIST):
    die("%s not found; run this from an app repository" % PLIST)
with open(PLIST, "rb") as handle:
    info = plistlib.load(handle)
for key in ("CFBundleName", "LSMinimumSystemVersion", "SUFeedURL"):
    if not isinstance(info.get(key), str) or not info[key]:
        die("%s has no %s" % (PLIST, key))
feed_url = re.fullmatch(
    r"https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/[^/]+/appcast\.xml", info["SUFeedURL"]
)
if not feed_url:
    die("SUFeedURL is %s; expected https://raw.githubusercontent.com/<owner>/<repo>/<branch>/appcast.xml"
        % info["SUFeedURL"])
name = info["CFBundleName"]
repository = "https://github.com/%s/%s" % feed_url.groups()
url = "%s/releases/download/v%s/%s" % (repository, version, os.path.basename(archive))
notes_url = (notes_template or "%s/releases/tag/v{version}" % repository).replace("{version}", version)
full_notes = (
    "      <sparkle:fullReleaseNotesLink>%s</sparkle:fullReleaseNotesLink>\n" % escape(full_notes_url)
    if full_notes_url else ""
)
ed_signature, length = re.fullmatch(r'sparkle:edSignature="([^"]+)" length="([0-9]+)"', signature).groups()

if os.path.exists(FEED):
    with open(FEED, encoding="utf-8") as handle:
        text = handle.read()
else:
    text = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<rss version="2.0" xmlns:sparkle="%s">\n'
        "  <channel>\n"
        "    <title>%s</title>\n"
        "    <link>%s</link>\n"
        "    <description>Most recent updates to %s</description>\n"
        "    <language>en</language>\n"
        "  </channel>\n"
        "</rss>\n" % (SPARKLE, escape(name), escape(repository), escape(name))
    )
try:
    ET.fromstring(text.encode("utf-8"))
except ET.ParseError as error:
    die("%s is not well-formed XML: %s" % (FEED, error))

# Each item on its own: a pattern that spans from the first <item> to this version's text would
# swallow every newer entry above it.
items = []
for block in re.finditer(r"[ \t]*<item>.*?</item>", text, re.S):
    element = ET.fromstring(block.group(0).strip().replace("<item>", '<item xmlns:sparkle="%s">' % SPARKLE, 1))
    items.append((block, element))
matches = [
    (block, element) for block, element in items
    if (element.findtext("{%s}shortVersionString" % SPARKLE) or "").strip() == version
]
if len(matches) > 1:
    die("%s advertises %s %d times; resolve it by hand" % (FEED, version, len(matches)))

if matches:
    block, element = matches[0]
    enclosure = element.find("enclosure")
    enclosure_value = (lambda key: enclosure.get(key) if enclosure is not None else None)
    existing = [
        ("build number", element.findtext("{%s}version" % SPARKLE), build_number),
        ("download URL", enclosure_value("url"), url),
        ("signature", enclosure_value("{%s}edSignature" % SPARKLE), ed_signature),
        ("length", enclosure_value("length"), length),
    ]
    for field, published, wanted in existing:
        if (published or "").strip() != wanted:
            sys.stderr.write(
                "error: %s already advertises %s with a different %s: %s there, %s now.\n"
                "Existing entry:\n%s\n" % (FEED, version, field, published, wanted, block.group(0))
            )
            sys.exit(1)
    sys.stderr.write("%s already advertises this exact %s build; nothing to do.\n" % (FEED, version))
    sys.exit(0)

DAYS = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
MONTHS = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
now = time.gmtime()
published = "%s, %02d %s %d %02d:%02d:%02d +0000" % (
    DAYS[now.tm_wday], now.tm_mday, MONTHS[now.tm_mon - 1], now.tm_year, now.tm_hour, now.tm_min, now.tm_sec
)
item = (
    "    <item>\n"
    "      <title>%s</title>\n"
    "      <pubDate>%s</pubDate>\n"
    "      <sparkle:releaseNotesLink>%s</sparkle:releaseNotesLink>\n"
    "%s"
    "      <sparkle:version>%s</sparkle:version>\n"
    "      <sparkle:shortVersionString>%s</sparkle:shortVersionString>\n"
    "      <sparkle:minimumSystemVersion>%s</sparkle:minimumSystemVersion>\n"
    "      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>\n"
    '      <enclosure url=%s sparkle:edSignature=%s length=%s type="application/octet-stream"/>\n'
    "    </item>\n" % (
        escape(version), published, escape(notes_url), full_notes, escape(build_number),
        escape(version), escape(info["LSMinimumSystemVersion"]),
        attribute(url), attribute(ed_signature), attribute(length),
    )
)
if items:
    position = items[0][0].start()
else:
    channel_end = text.find("</channel>")
    if channel_end < 0:
        die("%s has no </channel> to add the entry to" % FEED)
    position = text.rfind("\n", 0, channel_end) + 1
text = text[:position] + item + text[position:]
ET.fromstring(text.encode("utf-8"))

handle = tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=".", prefix=".appcast.", delete=False)
with handle:
    handle.write(text)
os.replace(handle.name, FEED)
sys.stderr.write("%s now advertises %s %s (build %s).\n" % (FEED, name, version, build_number))
PY
