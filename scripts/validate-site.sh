#!/usr/bin/env bash
# Canonical site check for the owner's product sites. Copy it unchanged to scripts/validate-site.sh;
# bench-setup alignment reports a drifted copy. It checks every page of the site as one set before
# the GitHub Pages deploy (#314, #352) and prints one OK line on stdout; every failure goes to stderr.
#
# Site: CNAME is a *.martonpaulo.com host; index.html, .nojekyll, robots.txt and sitemap.xml exist;
# robots.txt names the sitemap and does not disallow the whole site.
#
# Pages are every *.html under the site folder, found on disk, so a new page cannot skip the check.
# A page's URL follows its file: help/index.html is /help/, privacy.html is /privacy.html. A page
# whose robots or googlebot meta says noindex is non-indexed; 404.html must be one, index.html never.
#   - Every indexed page: canonical and og:url equal its URL, sitemap.xml lists it, it has a title
#     and a description, og:title and og:description equal them, twitter:title and
#     twitter:description equal them when present, and no two indexed pages share a title.
#   - sitemap.xml lists only indexed pages, or paths under a --generated prefix.
#   - Every page: each external <a> has target="_blank" and rel="noopener"; each local src, href
#     and srcset candidate resolves to a file (/x from the site root, anything else from the page's
#     folder); a local href's #fragment names an id, or a legacy <a name>, in the page it reaches,
#     the same page for a bare #fragment (#499); the header's link labels and the footer's links equal index.html's; every JSON-LD
#     block parses; each [data-copy] command holds an [aria-live] status for its «Copied» (#2161).
#   - Breadcrumb: index.html and 404.html have none. Every other page has one
#     <nav aria-label="Breadcrumb"><ol>, whose first crumb is the product (og:site_name) linking to
#     the home page and whose last crumb is the current page, not a link, with aria-current="page";
#     and one BreadcrumbList JSON-LD node matching it item for item.
#   - Screenshots in the visitor's appearance: an image (.webp, .png, .jpg, .jpeg, .avif) whose name
#     has -light or -dark as a hyphen-delimited part needs its twin with that part swapped (#351).
#   - Shared site library (#448, #449): when .site-library.json exists, every file it lists (the
#     library's styles and scripts, accent.css and every generated page) has the SHA-256 it records,
#     so a hand edit of a copied or generated file fails; rebuild with site.mjs instead. Every page
#     of such a site also carries the appearance pre-paint script, an inline <script> in <head>
#     before the first stylesheet that reads localStorage in try/catch and sets data-theme, and
#     every page but an update page carries the System / Light / Dark control in its header, a
#     named role="radiogroup" whose radios are system, light and dark (#420).
#   - Update pages: release-notes/<version>/update/index.html is the version section alone, for
#     Sparkle's update window (render-release-notes.sh). It is exempt from header and footer parity
#     and from the breadcrumb, and from nothing else (#385).
#
# Asset versions: scripts/version-site-assets.sh --check passes on site/, and a deploy.yml runs
# scripts/version-site-assets.sh --site on its staged copy (#358).
#
# An app's own site checks, which read its own data, live in its scripts/validate.sh after the call
# to this script, never in an edited copy.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/cli.sh"
cd "$(dirname "$0")/.."

usage() {
  cat <<'USAGE'
usage: scripts/validate-site.sh [--site <dir>] [--generated <path>...]
  --site <dir>        the folder to check, relative to the repository root or absolute (default: site)
  --generated <path>  a site path prefix, such as release-notes/, that only the deploy writes; a page
                      may link below it and the sitemap may list it before it exists; repeatable
  --help              show this help
USAGE
}

fail() { echo "validate-site: $1" >&2; exit 1; }

DOCS=site
generated=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --site) need_value "$@"; DOCS=${2%/}; shift 2 ;;
    --generated) need_value "$@"; generated+=("$2"); shift 2 ;;
    --help) usage; exit 0 ;;
    *) fail_usage "unknown option $1" ;;
  esac
done

[ -d "$DOCS" ] || fail "missing $DOCS/"
[ -f "$DOCS/CNAME" ] || fail "missing $DOCS/CNAME"
HOST=$(tr -d '[:space:]' < "$DOCS/CNAME")
[[ "$HOST" =~ ^[a-z0-9-]+\.martonpaulo\.com$ ]] || fail "CNAME host '$HOST' is not a martonpaulo.com subdomain"
URL="https://$HOST/"
[ -f "$DOCS/index.html" ] || fail "missing $DOCS/index.html"
[ -f "$DOCS/.nojekyll" ] || fail "missing $DOCS/.nojekyll"
[ -f "$DOCS/robots.txt" ] || fail "missing $DOCS/robots.txt"
[ -f "$DOCS/sitemap.xml" ] || fail "missing $DOCS/sitemap.xml"
grep -qF "Sitemap: ${URL}sitemap.xml" "$DOCS/robots.txt" || fail "robots.txt must reference ${URL}sitemap.xml"
grep -q 'Disallow: /$' "$DOCS/robots.txt" && fail "robots.txt must not disallow the whole site"

# Bash 3.2 treats an empty "${generated[@]}" as unbound under set -u; this form expands to nothing.
summary=$(python3 - "$DOCS" "$HOST" ${generated[@]+"${generated[@]}"} <<'PY'
import html
import json
import os
import posixpath
import re
import sys
from html.parser import HTMLParser
from urllib.parse import unquote, urljoin, urlsplit

docs, host = sys.argv[1], sys.argv[2]
generated = [g.lstrip("/") for g in sys.argv[3:]]
base = "https://%s/" % host
failures = []


def fail(page, message):
    failures.append("validate-site: %s: %s" % (page, message))


def collapse(text):
    return " ".join((text or "").split())


def check_site_library():
    manifest_path = os.path.join(docs, ".site-library.json")
    if not os.path.exists(manifest_path):
        return
    import hashlib
    try:
        with open(manifest_path, encoding="utf-8") as handle:
            files = json.load(handle)["files"]
    except (OSError, ValueError, KeyError, TypeError) as exc:
        fail(".site-library.json", "unreadable: %s" % exc)
        return
    for rel, digest in sorted(files.items()):
        path = os.path.join(docs, rel)
        if not os.path.isfile(path):
            fail(rel, "listed in .site-library.json but missing; rebuild with site.mjs")
            continue
        with open(path, "rb") as handle:
            actual = hashlib.sha256(handle.read()).hexdigest()
        if actual != digest:
            fail(rel, "differs from what site.mjs wrote (.site-library.json); edit site-source/ and rebuild")


check_site_library()
library_site = os.path.exists(os.path.join(docs, ".site-library.json"))


class Page(HTMLParser):
    """Collects what the checks read from one page, in document order."""

    def __init__(self):
        HTMLParser.__init__(self, convert_charrefs=True)
        self.title = None
        self.metas = {}
        self.canonical = None
        self.anchors = []  # dicts: href, target, rel, text, label, header, footer
        self.refs = []  # (attribute, value)
        self.ids = set()  # every id, and every legacy <a name>, a #fragment can reach
        self.jsonld = []
        self.header_links = None
        self.footer_links = None
        self.crumb_navs = []  # each a list of <ol>, each a list of <li> dicts
        self.pre_paint = []  # text of each inline <script> in <head> before the first stylesheet
        self.theme_switches = []  # each the radio values of a role="radiogroup" with a name, in the header
        self.copies = []  # each [data-copy] element: {"text": [...], "live": bool}
        self._copy = None
        self._copy_tag = None
        self._copy_depth = 0
        self._title = None
        self._in_head = False
        self._stylesheet_seen = False
        self._inline = None
        self._group = None
        self._group_tag = None
        self._group_depth = 0
        self._anchor = None
        self._script = None
        self._header_depth = 0
        self._footer_depth = 0
        self._nav = None
        self._nav_depth = 0
        self._li = None

    def handle_starttag(self, tag, attrs):
        a = {}
        for key, value in attrs:
            a.setdefault(key, "" if value is None else value)
        if a.get("id"):
            self.ids.add(a["id"])
        if self._copy is not None:
            if tag == self._copy_tag:
                self._copy_depth += 1
            if "aria-live" in a:
                self._copy["live"] = True
        elif "data-copy" in a:
            self._copy = {"text": [], "live": False}
            self._copy_tag = tag
            self._copy_depth = 1
            self.copies.append(self._copy)
        if tag == "a" and a.get("name"):
            self.ids.add(a["name"])
        if tag == "title" and self.title is None:
            self._title = []
        elif tag == "meta":
            key = (a.get("name") or a.get("property") or "").lower()
            if key and key not in self.metas:
                self.metas[key] = a.get("content", "")
        elif tag == "link" and "canonical" in a.get("rel", "").lower().split() and self.canonical is None:
            self.canonical = a.get("href", "")
        elif tag == "script" and a.get("type", "").lower() == "application/ld+json":
            self._script = []
        elif tag == "script" and "src" not in a and self._in_head and not self._stylesheet_seen:
            self._inline = []
        if tag == "head":
            self._in_head = True
        elif tag == "body":
            self._in_head = False
        if tag == "link" and "stylesheet" in a.get("rel", "").lower().split():
            self._stylesheet_seen = True
        if self._group is not None:
            if tag == self._group_tag:
                self._group_depth += 1
            elif tag == "input" and a.get("type", "").lower() == "radio":
                self._group.append(a.get("value", ""))
        elif (self._header_depth and a.get("role", "").lower() == "radiogroup"
                and collapse(a.get("aria-label") or a.get("aria-labelledby"))):
            self._group = []
            self._group_tag = tag
            self._group_depth = 1
            self.theme_switches.append(self._group)
        for attribute in ("src", "href"):
            if attribute in a:
                self.refs.append((attribute, a[attribute]))
        for attribute in ("srcset", "imagesrcset"):
            for candidate in a.get(attribute, "").split(","):
                parts = candidate.split()
                if parts:
                    self.refs.append((attribute, parts[0]))
        if tag == "header":
            if self._header_depth or self.header_links is None:
                self._header_depth += 1
                if self.header_links is None:
                    self.header_links = []
        elif tag == "footer":
            if self._footer_depth or self.footer_links is None:
                self._footer_depth += 1
                if self.footer_links is None:
                    self.footer_links = []
        elif tag == "nav":
            if self._nav is not None:
                self._nav_depth += 1
            elif collapse(a.get("aria-label")).lower() == "breadcrumb":
                self._nav = []
                self._nav_depth = 1
                self.crumb_navs.append(self._nav)
        elif tag == "ol" and self._nav is not None:
            self._nav.append([])
        elif tag == "li" and self._nav is not None and self._nav:
            self._li = {"text": [], "links": [], "current": a.get("aria-current")}
            self._nav[-1].append(self._li)
        elif tag == "a":
            self._anchor = {
                "href": a.get("href"),
                "target": a.get("target", ""),
                "rel": a.get("rel", ""),
                "aria": a.get("aria-label", ""),
                "alt": [],
                "text": [],
                "header": bool(self._header_depth),
                "footer": bool(self._footer_depth),
            }
            self.anchors.append(self._anchor)
            if self._li is not None:
                self._li["links"].append(self._anchor)
        elif tag == "img" and self._anchor is not None and a.get("alt"):
            self._anchor["alt"].append(a["alt"])

    def handle_endtag(self, tag):
        if self._copy is not None and tag == self._copy_tag:
            self._copy_depth -= 1
            if not self._copy_depth:
                self._copy = None
        if self._group is not None and tag == self._group_tag:
            self._group_depth -= 1
            if not self._group_depth:
                self._group = None
        if tag == "title" and self._title is not None:
            self.title = collapse("".join(self._title))
            self._title = None
        elif tag == "script" and self._script is not None:
            self.jsonld.append("".join(self._script))
            self._script = None
        elif tag == "script" and self._inline is not None:
            self.pre_paint.append("".join(self._inline))
            self._inline = None
        elif tag == "head":
            self._in_head = False
        elif tag == "a" and self._anchor is not None:
            anchor = self._anchor
            text = collapse("".join(anchor["text"]))
            anchor["label"] = text or collapse(anchor["aria"]) or collapse(" ".join(anchor["alt"]))
            if anchor["header"]:
                self.header_links.append(anchor["label"])
            if anchor["footer"]:
                self.footer_links.append((anchor["href"], anchor["label"]))
            self._anchor = None
        elif tag == "header" and self._header_depth:
            self._header_depth -= 1
        elif tag == "footer" and self._footer_depth:
            self._footer_depth -= 1
        elif tag == "li" and self._li is not None:
            self._li = None
        elif tag == "nav" and self._nav is not None:
            self._nav_depth -= 1
            if not self._nav_depth:
                self._nav = None

    def handle_data(self, data):
        if self._copy is not None:
            self._copy["text"].append(data)
        if self._title is not None:
            self._title.append(data)
        if self._script is not None:
            self._script.append(data)
        if self._inline is not None:
            self._inline.append(data)
        if self._anchor is not None:
            self._anchor["text"].append(data)
        if self._li is not None:
            self._li["text"].append(data)


def page_url(rel):
    path = rel[: -len("index.html")] if rel == "index.html" or rel.endswith("/index.html") else rel
    return base + path


def under_generated(site_path):
    return any(site_path.startswith(prefix) for prefix in generated)


def resolve_local(rel, value):
    """Return the site path a local reference names, or None when it leaves the site."""
    path = unquote(value.split("#", 1)[0].split("?", 1)[0])
    if not path:
        return None, ""
    if path.startswith("/"):
        joined = path.lstrip("/")
    else:
        joined = posixpath.join(posixpath.dirname(rel), path)
    trailing = path.endswith("/")
    normal = posixpath.normpath(joined) if joined else "."
    if normal == ".":
        normal = ""
    if normal.startswith(".."):
        return None, path
    if trailing or normal == "":
        normal = posixpath.join(normal, "index.html")
    return normal, path


def breadcrumb_nodes(value):
    nodes = []
    items = value if isinstance(value, list) else [value]
    for item in items:
        if not isinstance(item, dict):
            continue
        kind = item.get("@type")
        kinds = kind if isinstance(kind, list) else [kind]
        if "BreadcrumbList" in kinds:
            nodes.append(item)
        if "@graph" in item:
            nodes.extend(breadcrumb_nodes(item["@graph"]))
    return nodes


# Pages, sorted, found on disk.
rels = []
for root, dirs, files in os.walk(docs):
    dirs.sort()
    for name in sorted(files):
        if name.endswith(".html"):
            rels.append(posixpath.relpath(posixpath.join(root, name), docs).replace(os.sep, "/"))
rels.sort()

pages = {}
for rel in rels:
    parser = Page()
    with open(os.path.join(docs, rel), encoding="utf-8") as handle:
        parser.feed(handle.read())
    parser.close()
    pages[rel] = parser


def noindex(page):
    return any("noindex" in page.metas.get(key, "").lower() for key in ("robots", "googlebot"))


home = pages["index.html"]
indexed = [rel for rel in rels if not noindex(pages[rel])]
indexed_urls = {page_url(rel): rel for rel in indexed}

with open(os.path.join(docs, "sitemap.xml"), encoding="utf-8") as handle:
    locs = [html.unescape(loc) for loc in re.findall(r"<loc>\s*(.*?)\s*</loc>", handle.read(), re.S)]

if noindex(home):
    fail("index.html", "must not contain noindex")
if "404.html" in pages and not noindex(pages["404.html"]):
    fail("404.html", 'must carry <meta name="robots" content="noindex">')

titles = {}
for rel in indexed:
    page, url = pages[rel], page_url(rel)
    if collapse(page.canonical) != url:
        fail(rel, "canonical must be %s" % url)
    if collapse(page.metas.get("og:url")) != url:
        fail(rel, "og:url must be %s" % url)
    if url not in locs:
        fail(rel, "sitemap.xml must list %s" % url)
    title = page.title or ""
    description = collapse(page.metas.get("description"))
    if not title:
        fail(rel, "has no <title>")
    if not description:
        fail(rel, "has no meta description")
    for key, want in (("og:title", title), ("og:description", description)):
        if collapse(page.metas.get(key)) != want:
            fail(rel, "%s must equal the page's %s" % (key, key.split(":")[1]))
    for key, want in (("twitter:title", title), ("twitter:description", description)):
        if key in page.metas and collapse(page.metas[key]) != want:
            fail(rel, "%s must equal the page's %s" % (key, key.split(":")[1]))
    if title:
        if title in titles:
            fail(rel, 'two pages share the title "%s" (%s)' % (title, titles[title]))
        else:
            titles[title] = rel

for loc in locs:
    if loc in indexed_urls:
        continue
    if loc.startswith(base) and under_generated(loc[len(base):]):
        continue
    fail("sitemap.xml", "sitemap.xml lists %s, which is not an indexed page" % loc)

for root, dirs, files in os.walk(docs):
    for filename in files:
        stem, extension = os.path.splitext(filename)
        if extension.lower() not in (".webp", ".png", ".jpg", ".jpeg", ".avif"):
            continue
        parts = stem.split("-")
        for index, part in enumerate(parts):
            if part not in ("light", "dark"):
                continue
            swapped = parts[:index] + ["dark" if part == "light" else "light"] + parts[index + 1:]
            twin = "-".join(swapped) + extension
            if not os.path.isfile(os.path.join(root, twin)):
                folder = os.path.relpath(root, docs)
                here = filename if folder == "." else "%s/%s" % (folder, filename)
                there = twin if folder == "." else "%s/%s" % (folder, twin)
                fail(here, "has no %s" % there)

site_name = collapse(home.metas.get("og:site_name"))
scheme = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")



def missing_fragment(rel, value, reached):
    """Fail when a link's #fragment names no id or legacy <a name> in the page it reaches (#499)."""
    fragment = unquote(value.split("#", 1)[1])
    # An empty fragment and #top scroll to the top by the HTML standard; :~: is a text fragment.
    if not fragment or fragment.lower() == "top" or fragment.startswith(":~:") or reached not in pages:
        return
    if fragment not in pages[reached].ids:
        fail(rel, 'link %s points to a missing id "%s" in %s' % (value, fragment, reached))


update_page = re.compile(r"^release-notes/[^/]+/update/index\.html$")

for rel in rels:
    page, url = pages[rel], page_url(rel)
    chromeless = bool(update_page.match(rel))

    for anchor in page.anchors:
        href = collapse(anchor["href"])
        parts = urlsplit(href)
        if parts.scheme in ("http", "https") and (parts.hostname or "") != host:
            if anchor["target"] != "_blank":
                fail(rel, 'external link without target="_blank": %s' % href)
            if "noopener" not in anchor["rel"].lower().split():
                fail(rel, 'external link without rel="noopener": %s' % href)

    for copy in page.copies:
        if not copy["live"]:
            fail(rel, 'data-copy command without an [aria-live] status for its "Copied": %s'
                 % collapse("".join(copy["text"])))

    for attribute, value in page.refs:
        value = value.strip()
        if not value.split("#", 1)[0].split("?", 1)[0] or scheme.match(value):
            continue
        target, shown = resolve_local(rel, value)
        if target is not None and under_generated(target):
            continue
        full = os.path.join(docs, target) if target is not None else None
        if full is not None and os.path.isdir(full):
            full = os.path.join(full, "index.html")
        if full is None or not os.path.isfile(full):
            fail(rel, "references missing local file %s" % (target if target is not None else shown))
            continue
        if attribute == "href" and "#" in value:
            missing_fragment(rel, value, posixpath.relpath(full, docs).replace(os.sep, "/"))

    for anchor in page.anchors:
        value = collapse(anchor["href"])
        if value.startswith("#"):
            missing_fragment(rel, value, rel)

    if rel != "index.html" and not chromeless:
        if page.header_links != home.header_links:
            fail(rel, "header links differ from index.html: %s, not %s" % (page.header_links, home.header_links))
        if page.footer_links != home.footer_links:
            fail(rel, "footer links differ from index.html: %s, not %s" % (page.footer_links, home.footer_links))

    if library_site:
        if not any("localStorage" in text and "data-theme" in text and "try" in text for text in page.pre_paint):
            fail(rel, "appearance: needs the inline pre-paint script in <head>, before the stylesheets, "
                      "that applies the stored choice (localStorage in try/catch); rebuild with site.mjs")
        if not chromeless and not any(sorted(values) == ["dark", "light", "system"] for values in page.theme_switches):
            fail(rel, 'appearance: the header needs the System / Light / Dark control, a named '
                      'role="radiogroup" with radio values system, light and dark; rebuild with site.mjs')

    nodes = []
    for block in page.jsonld:
        try:
            nodes.extend(breadcrumb_nodes(json.loads(block)))
        except ValueError as error:
            fail(rel, "invalid JSON-LD: %s" % error)

    if chromeless:
        continue

    if rel in ("index.html", "404.html"):
        if page.crumb_navs:
            fail(rel, "breadcrumb must not appear on this page")
        if nodes:
            fail(rel, "BreadcrumbList must not appear on this page")
        continue

    if len(page.crumb_navs) != 1:
        fail(rel, 'breadcrumb: needs exactly one <nav aria-label="Breadcrumb">, found %d' % len(page.crumb_navs))
        continue
    lists = page.crumb_navs[0]
    if len(lists) != 1 or len(lists[0]) < 2:
        fail(rel, "breadcrumb: needs one <ol> with at least two <li>")
        continue
    crumbs = lists[0]
    for crumb in crumbs:
        crumb["label"] = collapse("".join(crumb["text"]))
    problem = None
    for index, crumb in enumerate(crumbs[:-1], 1):
        if len(crumb["links"]) != 1 or not collapse(crumb["links"][0]["href"]):
            problem = "crumb %d must contain exactly one <a href>" % index
            break
    last = crumbs[-1]
    if problem is None and last["links"]:
        problem = "the last crumb is the current page and must not be a link"
    if problem is None and last["current"] != "page":
        problem = 'the last crumb needs aria-current="page"'
    name = collapse(page.metas.get("og:site_name")) or site_name
    if problem is None and not name:
        problem = "the product name is unknown: the page has no og:site_name"
    if problem is None and crumbs[0]["label"] != name:
        problem = 'the first crumb must be the product name "%s", not "%s"' % (name, crumbs[0]["label"])
    if problem is None and urljoin(url, collapse(crumbs[0]["links"][0]["href"])) != base:
        problem = "the first crumb must link to %s" % base
    if problem:
        fail(rel, "breadcrumb: " + problem)
        continue

    if len(nodes) != 1:
        fail(rel, "BreadcrumbList: needs exactly one node, found %d" % len(nodes))
        continue
    elements = nodes[0].get("itemListElement")
    elements = elements if isinstance(elements, list) else []
    def position(element):
        value = element.get("position") if isinstance(element, dict) else None
        return int(value) if isinstance(value, int) or (isinstance(value, str) and value.isdigit()) else 0
    elements = sorted(elements, key=position)
    if [position(e) for e in elements] != list(range(1, len(crumbs) + 1)):
        fail(rel, "BreadcrumbList: positions must run 1 to %d, one per visible crumb" % len(crumbs))
        continue
    for index, (element, crumb) in enumerate(zip(elements, crumbs), 1):
        item = element.get("item")
        if isinstance(item, dict):
            item = item.get("@id")
        if collapse(element.get("name")) != crumb["label"]:
            fail(rel, 'BreadcrumbList: item %d name "%s" differs from the visible "%s"' % (index, collapse(element.get("name")), crumb["label"]))
            break
        want = url if index == len(crumbs) else urljoin(url, collapse(crumb["links"][0]["href"]))
        if (item is not None or index < len(crumbs)) and item != want:
            fail(rel, "BreadcrumbList: item %d must be %s, not %s" % (index, want, item))
            break

if failures:
    sys.stderr.write("\n".join(failures) + "\n")
    sys.exit(1)
print("validate-site: OK (%s, %d pages)" % (base, len(rels)))
PY
)

# Asset versions (#358): the tracked site/ can be versioned, and the deploy versions its staged copy.
if [[ -d site ]]; then
  scripts/version-site-assets.sh --check || fail "a local asset address cannot be versioned"
fi
if [[ -f .github/workflows/deploy.yml ]]; then
  grep -Eq '^[^#]*scripts/version-site-assets[.]sh --site' .github/workflows/deploy.yml \
    || fail "deploy.yml must run scripts/version-site-assets.sh --site on its staged copy"
fi
echo "$summary"
