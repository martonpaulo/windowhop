#!/usr/bin/env python3
"""Fixtures for the release-notes renderer's inline Markdown and the text-width check (#171).

They run the real scripts' functions on fixed strings, so the real CHANGELOG.md and
stylesheet never shape the result. The last line is the summary validate.sh prints.
"""

import importlib.util
import pathlib
import sys

sys.dont_write_bytecode = True
SCRIPTS = pathlib.Path(__file__).resolve().parent.parent.parent / "scripts"


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), SCRIPTS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


notes = load("render-release-notes")
width = load("text_width_check")
html_check = load("release_notes_html_check")
passed = failed = 0


def check(name, actual, expected):
    global passed, failed
    if actual == expected:
        passed += 1
    else:
        failed += 1
        print(f"FAIL: {name}\n  expected: {expected}\n  actual:   {actual}", file=sys.stderr)


# --- code spans and keys -------------------------------------------------------------------
# The 2.4.0 «Added» entry, as CHANGELOG.md writes it: the backtick key inside double backticks.
check("2.4.0 entry reads as one sentence with its key as a keycap",
      notes.inline("**`` ` `` moves back in the switcher**: while the switcher is open, `` ` `` "
                   "selects the previous window, as in the macOS app switcher."),
      "<strong><kbd>`</kbd> moves back in the switcher</strong>: while the switcher is open, "
      "<kbd>`</kbd> selects the previous window, as in the macOS app switcher.")
check("a key chord becomes one keycap per key", notes.inline("press `⌘⇧Tab` now"),
      "press <kbd>⌘</kbd><kbd>⇧</kbd><kbd>Tab</kbd> now")
check("a modifier and an arrow", notes.inline("`⌥←`"), "<kbd>⌥</kbd><kbd>←</kbd>")
check("ordinary code stays one code span, its option whole",
      notes.inline("`brew install --cask martonpaulo/tap/windowhop`"),
      '<code>brew install <span class="flag">--cask</span> martonpaulo/tap/windowhop</code>')
check("a word is code, not a key", notes.inline("`Preferences`"), "<code>Preferences</code>")
check("a double-backtick span may hold a backtick run", notes.inline("``a ` b``"), "<code>a ` b</code>")
check("a single backtick run closes only a single run", notes.inline("`a``b`"), "<code>a``b</code>")
check("a backtick with no closer stays text", notes.inline("a ` alone"), "a ` alone")
check("markup inside code is not bold or a link", notes.inline("`**x** [y](https://e.com)`"),
      "<code>**x** [y](https://e.com)</code>")
check("code is escaped", notes.inline("`WindowHop-<version>.dmg`"), "<code>WindowHop-&lt;version&gt;.dmg</code>")
check("no stray backtick in any rendered 2.4.0 line",
      "`" in notes.inline("**`` ` `` moves back**").replace("<kbd>`</kbd>", ""), False)

# --- rendered page check (#150) ----------------------------------------------------------------
# The garbled markup the old renderer wrote for the 2.4.0 entry fails; the fixed output passes.
check("the old renderer's 2.4.0 output fails the page check",
      len(html_check.page_problems("<li><strong>`<code> </code> `<code> moves back</strong>: x </code>"
                                   "<code> </code> `` selects</li>")) > 0, True)
check("the fixed 2.4.0 output passes the page check",
      html_check.page_problems("<li><strong><kbd>`</kbd> moves back</strong>: <kbd>`</kbd> selects</li>"), [])
check("a stray backtick outside code fails", len(html_check.page_problems("<p>a ` b</p>")), 1)

# --- text width ------------------------------------------------------------------------------
good = (".container { width: var(--page-width); } img { max-width: 100%; } .x { max-width: none; }"
        ".mini-window { max-width: 10rem; } @media (max-width: 640px) { .a { width: 1rem; } }"
        "/* .old { max-width: 80ch; } */")
check("column-keeping widths, drawings, media queries and comments pass", width.css_problems(good), [])
for bad in (".section p { max-width: var(--measure-prose); }", ":root { --measure: 68ch; }",
            "h1 { max-width: 16ch; }", ".hero-copy { max-width: 51.25rem; }", ".lead { width: 60ch; }",
            ".notes { max-inline-size: 40rem; }"):
    check(f"a text width cap fails: {bad}", len(width.css_problems(bad)), 1)
check("the reserved scrollbar space passes", width.reserves_gutter("html { scrollbar-gutter: stable; }"), True)
check("a page without it fails", width.reserves_gutter("body { margin: 0; }"), False)

print(f"site text: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
