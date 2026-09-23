#!/usr/bin/env python3
"""Gives every local stylesheet, script and image address a content version.

    scripts/version-site-assets.py <staged-site-dir>

In each HTML file of the staged copy, `/styles/…`, `/scripts/…`, `/assets/…` and
`/screenshots/…` addresses (in src, href and srcset) get `?v=<first 8 hex of the
file's md5>`. A changed file therefore has a new address, so a browser never pairs
new HTML with a cached old stylesheet or script: that pairing once replaced the
Homebrew command with "Copy". The CDN also caches /assets/ for a year.

The deploy workflow runs this last on its staged copy, like the other render
scripts, so no hash is ever committed or maintained by hand.
"""

import hashlib
import pathlib
import re
import sys

VERSIONED = re.compile(r"(/(?:styles|scripts|assets|screenshots)/[^\s\"'?#,]+)(\?v=[0-9a-f]+)?")


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: version-site-assets.py <staged-site-dir>")
    site = pathlib.Path(sys.argv[1])
    digests = {}

    def version(match):
        path = match.group(1)
        file = site / path.lstrip("/")
        if not file.is_file():
            return match.group(0)
        if path not in digests:
            digests[path] = hashlib.md5(file.read_bytes()).hexdigest()[:8]
        return f"{path}?v={digests[path]}"

    def attribute(match):
        return match.group(1) + VERSIONED.sub(version, match.group(2)) + match.group(3)

    pages = sorted(site.rglob("*.html"))
    for page in pages:
        text = page.read_text()
        text = re.sub(r'((?:src|href|srcset|imagesrcset)=")([^"]*)(")', attribute, text)
        page.write_text(text)
    print(f"asset versions: {len(digests)} files across {len(pages)} pages")


if __name__ == "__main__":
    main()
