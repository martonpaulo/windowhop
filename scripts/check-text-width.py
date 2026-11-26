#!/usr/bin/env python3
"""Fails when a site stylesheet gives text a width cap of its own (#171).

    scripts/check-text-width.py <file.css>...

Text on the site fills its column, the page width `.container` and `main` set. So no
declaration holds a length in `ch` (a reading measure), and `max-width` or
`max-inline-size` is only `100%` or `none`, which keep a box inside its column, or a
size on one of the drawings in DRAWINGS, which are not text. Comments are ignored.
"""

import re
import sys

# The demo's and the mocks' drawn shapes: small windows and lines, never running text.
DRAWINGS = {".mini-window", ".mock-lines i", ".demo-panel"}
RULE = re.compile(r"([^{}]+)\{([^{}]*)\}")
CAP = ("max-width", "max-inline-size")


def problems(css, path="css"):
    """Every text width cap in `css`, as `path: selector { property: value }` lines."""
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    found = []
    for prelude, body in RULE.findall(css):
        selector = " ".join(prelude.split())
        if selector.startswith("@"):
            continue  # an at-rule's prelude, such as `@media (max-width: 640px)`
        for declaration in body.split(";"):
            if ":" not in declaration:
                continue
            prop, value = (part.strip() for part in declaration.split(":", 1))
            if re.search(r"(?<![\w-])[\d.]+ch\b", value):
                found.append(f"{path}: {selector} {{ {prop}: {value} }}: a length in ch caps text")
            elif prop in CAP and value not in ("100%", "none") and selector not in DRAWINGS:
                found.append(f"{path}: {selector} {{ {prop}: {value} }}: text never takes a width cap")
    return found


def main():
    found = []
    for path in sys.argv[1:]:
        with open(path, encoding="utf-8") as handle:
            found += problems(handle.read(), path)
    for line in found:
        print(line, file=sys.stderr)
    sys.exit(1 if found else 0)


if __name__ == "__main__":
    main()
