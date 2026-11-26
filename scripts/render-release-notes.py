#!/usr/bin/env python3
"""Writes WindowHop's release notes into a staged copy of the site.

    scripts/render-release-notes.py <staged-site-dir>

Every `## [X.Y.Z] - YYYY-MM-DD` entry of CHANGELOG.md becomes
`<dir>/release-notes/X.Y.Z/index.html` (a site page, with the site's header and
footer), and all of them together become `<dir>/release-notes/index.html`. Each
version also gets `<dir>/release-notes/X.Y.Z/update/index.html` for Sparkle's update
window: the same version section (date, version, changes) in the site's style and
nothing else, no header, footer or page title (#128). The appcast's
`sparkle:releaseNotesLink` points at that page and `sparkle:fullReleaseNotesLink` at
the full list; WindowHop grows the window to the page's height (UpdateAlertSizer).

The deploy workflow runs this on its staged copy, like render-download-count.sh:
nothing it writes is committed. The pages carry `noindex`; the changelog is not a
search landing page. Only the Markdown the changelog uses is understood: `###`
headings, `- ` bullets with indented continuation lines, paragraphs, **bold**,
`code` and [links](url). A code span follows CommonMark: it opens with a run of
backticks and closes with a run of the same length, so ``` `` ` `` ``` is one span
holding a backtick (#171). A span that holds only a key or a key chord (`⌘⇧Tab`,
`` ` ``) becomes one keycap per key, as the site's pages show keys.
"""

import datetime
import html
import pathlib
import re
import sys

ENTRY = re.compile(r"^## \[(\d+\.\d+\.\d+)\] - (\d{4}-\d{2}-\d{2})\s*$")


MODIFIERS = "⌘⌥⇧⌃"
NAMED_KEYS = ("Tab", "Return", "Space", "Esc", "Escape", "Delete", "Enter")
CHORD = re.compile(rf"([{MODIFIERS}]*)({'|'.join(NAMED_KEYS)}|[←→↑↓]|\S)")


def code_spans(text):
    """Splits text into ("text", s) and ("code", s) parts, as CommonMark reads code spans:
    a run of N backticks opens a span that only a run of exactly N backticks closes, and
    one space is stripped from each end when both ends have one. A run with no closer
    stays literal text."""
    parts, plain, i = [], "", 0
    while i < len(text):
        if text[i] != "`":
            plain += text[i]
            i += 1
            continue
        run = len(text[i:]) - len(text[i:].lstrip("`"))
        closer = re.compile(rf"(?<!`)`{{{run}}}(?!`)").search(text, i + run)
        if not closer:
            plain += text[i:i + run]
            i += run
            continue
        content = text[i + run:closer.start()]
        if len(content) > 1 and content[0] == content[-1] == " " and content.strip():
            content = content[1:-1]
        if plain:
            parts.append(("text", plain))
            plain = ""
        parts.append(("code", content))
        i = closer.end()
    if plain:
        parts.append(("text", plain))
    return parts


def keys(content):
    """The keys of a code span that is a key chord, in order, or None for any other code."""
    match = CHORD.fullmatch(content)
    if not match:
        return None
    return list(match.group(1)) + [match.group(2)]


def code_html(content):
    chord = keys(content)
    if chord:
        return "".join(f"<kbd>{html.escape(key, quote=False)}</kbd>" for key in chord)
    # an option such as --cask is kept whole (styles: code .flag), not split at its hyphens
    escaped = html.escape(content, quote=False)
    return "<code>" + re.sub(r"(?<![\w-])(--[a-z]+)", r'<span class="flag">\1</span>', escaped) + "</code>"


def text_html(text):
    """Escapes text, then turns **bold** and [links](url) into HTML."""
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    return re.sub(
        r"\[([^\]]+)\]\((https?://[^)\s]+)\)",
        lambda m: f'<a target="_blank" href="{html.escape(m.group(2))}" rel="noopener">{m.group(1)}</a>',
        text,
    )


def inline(text):
    """The changelog's inline Markdown as HTML. Code spans are cut out first and stand in
    as placeholders, so a `*` or `[` inside one is never read as bold or a link."""
    spans, plain = [], ""
    for kind, value in code_spans(text):
        if kind == "code":
            plain += f"\x00{len(spans)}\x00"
            spans.append(code_html(value))
        else:
            plain += value.replace("\x00", "")
    return re.sub("\x00(\\d+)\x00", lambda m: spans[int(m.group(1))], text_html(plain))


def entries(changelog):
    """Yields (version, date, body lines) for every released entry, newest first."""
    current = None
    for line in changelog.splitlines():
        match = ENTRY.match(line)
        if match:
            if current:
                yield current
            current = (match.group(1), match.group(2), [])
        elif line.startswith("## ") or re.match(r"^\[[^\]]+\]: ", line):
            if current:
                yield current
            current = None
        elif current:
            current[2].append(line)
    if current:
        yield current


def groups(lines):
    """[(type, [item markdown])] in changelog order: Added, Changed, Fixed…"""
    out = []
    for line in lines:
        if line.startswith("### "):
            out.append((line[4:].strip(), []))
        elif line.startswith("- ") and out:
            out[-1][1].append(line[2:].strip())
        elif line.startswith("  ") and out and out[-1][1] and line.strip():
            out[-1][1][-1] += " " + line.strip()
    return out


def groups_html(lines):
    """Each change type as a small heading and a plain list, in the text column."""
    return "\n".join(
        f"""      <h3 class="notes-type">{html.escape(kind)}</h3>
      <ul class="notes-list">{"".join(f"<li>{inline(item)}</li>" for item in items)}</ul>"""
        for kind, items in groups(lines))


def long_date(iso):
    day = datetime.date.fromisoformat(iso)
    return f"{day.day} {day:%B %Y}"


def chrome(site):
    """The site's header and footer, taken from the 404 page so they have one source."""
    text = (site / "404.html").read_text()
    header = re.search(r'  <header class="site-header".*?</header>\n', text, re.S).group(0)
    header = header.replace('<a href="/release-notes/">', '<a href="/release-notes/" aria-current="page">')
    footer = re.search(r'  <footer class="site-footer">.*?</footer>\n', text, re.S).group(0)
    return header, footer


def page(title, description, content, header="", footer="", body_class="notes-page"):
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="light dark">
  <meta name="robots" content="noindex">
  <title>{html.escape(title)}</title>
  <meta name="description" content="{html.escape(description)}">
  <link rel="icon" href="/favicon.ico" sizes="16x16 32x32 48x48">
  <link rel="stylesheet" href="/styles/main.css">
  <script>document.documentElement.classList.add("js");</script>
  <script src="/scripts/main.js" defer></script>
</head>
<body class="{body_class}">
{'  <a class="skip-link" href="#main">Skip to content</a>' + chr(10) if header else ''}{header}  <main id="main">
{content}
  </main>
{footer}</body>
</html>
"""


def version_section(version, date, lines, link):
    """One release as a site section: the date as eyebrow, the version as heading."""
    title = f'<a href="/release-notes/{version}/">WindowHop {version}</a>' if link else f"WindowHop {version}"
    return f"""    <section class="section" id="v{version}" aria-labelledby="title-{version}">
      <p class="eyebrow"><time datetime="{date}">{long_date(date)}</time></p>
      <h2 id="title-{version}">{title}</h2>
{groups_html(lines)}
    </section>"""


def page_hero(eyebrow, title, lead):
    return f"""    <section class="page-hero" aria-labelledby="notes-title">
      <p class="eyebrow">{eyebrow}</p>
      <h1 id="notes-title">{title}</h1>
      <p class="hero-summary">{lead}</p>
    </section>"""


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: render-release-notes.py <staged-site-dir>")
    root = pathlib.Path(__file__).resolve().parent.parent
    site = pathlib.Path(sys.argv[1])
    released = list(entries((root / "CHANGELOG.md").read_text()))
    header, footer = chrome(root / "site")
    if not released:
        sys.exit("render-release-notes: CHANGELOG.md has no released entry")

    for version, date, lines in released:
        target = site / "release-notes" / version
        target.mkdir(parents=True, exist_ok=True)

        (target / "index.html").write_text(page(
            f"WindowHop {version} release notes",
            f"What changed in WindowHop {version}, released on {long_date(date)}.",
            page_hero(
                "Release notes", f"WindowHop {version}",
                f'Released on {long_date(date)}. <a href="/release-notes/">All release notes</a>.')
            + "\n" + version_section(version, date, lines, link=False),
            header, footer, body_class="notes-page",
        ))
        (target / "update").mkdir(exist_ok=True)
        (target / "update" / "index.html").write_text(page(
            f"What’s new in WindowHop {version}",
            f"The changes in WindowHop {version}.",
            version_section(version, date, lines, link=False),
            body_class="notes-page is-update",
        ))

    listing = "\n".join(version_section(v, d, l, link=True) for v, d, l in released)
    (site / "release-notes" / "index.html").write_text(page(
        "WindowHop release notes",
        "What changed in every WindowHop release.",
        page_hero(
            "Releases", "Release notes.",
            "What changed in each version of WindowHop. The app shows the same notes when it updates.")
        + "\n" + listing,
        header, footer,
    ))
    print(f"release notes: {len(released)} versions, newest {released[0][0]}")


if __name__ == "__main__":
    main()
