#!/usr/bin/env python3
"""Fails when a rendered release-notes page has broken inline markup (#150).

    scripts/release_notes_html_check.py <staged-site-dir>

Reads every page under `<dir>/release-notes/` and reports, per page, an inline tag that
closes out of order or never closes, and a backtick outside <code> and <kbd> (a code
span the renderer did not understand leaves one). Exit 1 when any page has a problem.
"""

import html.parser
import pathlib
import sys

VOID = {"meta", "link", "br", "img", "hr", "input"}
LITERAL = {"code", "kbd", "script", "style"}


class Checker(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.stack, self.problems = [], []

    def handle_starttag(self, tag, attrs):
        if tag not in VOID:
            self.stack.append(tag)

    def handle_startendtag(self, tag, attrs):
        pass

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        if not self.stack or self.stack[-1] != tag:
            self.problems.append(f"</{tag}> closes out of order (open: {'/'.join(self.stack) or 'none'})")
            if tag in self.stack:
                del self.stack[self.stack.index(tag):]
        else:
            self.stack.pop()

    def handle_data(self, data):
        if "`" in data and not LITERAL & set(self.stack):
            self.problems.append(f"stray backtick in: {data.strip()[:60]}")


def page_problems(source):
    checker = Checker()
    checker.feed(source)
    checker.close()
    return checker.problems + [f"<{tag}> never closes" for tag in checker.stack]


def main(directory):
    failed = False
    for page in sorted((pathlib.Path(directory) / "release-notes").rglob("*.html")):
        for problem in page_problems(page.read_text(encoding="utf-8")):
            failed = True
            print(f"{page}: {problem}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
