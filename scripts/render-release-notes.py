#!/usr/bin/env python3
"""Writes WindowHop's release notes into a staged copy of the site.

    scripts/render-release-notes.py <staged-site-dir>

Every `## [X.Y.Z] - YYYY-MM-DD` entry of CHANGELOG.md becomes
`<dir>/release-notes/X.Y.Z/index.html` (a site page, with the site's header and
footer), and all of them together become `<dir>/release-notes/index.html`. Each
version also gets `<dir>/release-notes/X.Y.Z/update/index.html`: one line per
change (its type and its bold headline) and a link to the full notes, short
enough for Sparkle's update window without scrolling. The appcast's
`sparkle:releaseNotesLink` points at that page and `sparkle:fullReleaseNotesLink`
at the full list (#128).

The deploy workflow runs this on its staged copy, like render-download-count.sh:
nothing it writes is committed. The pages carry `noindex`; the changelog is not a
search landing page. Only the Markdown the changelog uses is understood: `###`
headings, `- ` bullets with indented continuation lines, paragraphs, **bold**,
`code` and [links](url).
"""

import datetime
import html
import pathlib
import re
import sys

ENTRY = re.compile(r"^## \[(\d+\.\d+\.\d+)\] - (\d{4}-\d{2}-\d{2})\s*$")


def inline(text):
    """Escapes text, then turns the changelog's inline Markdown into HTML."""
    text = html.escape(text, quote=False)
    # an option such as --cask is kept whole (styles: code .flag), not split at its hyphens
    text = re.sub(
        r"`([^`]+)`",
        lambda m: "<code>" + re.sub(r"(?<![\w-])(--[a-z]+)", r'<span class="flag">\1</span>', m.group(1)) + "</code>",
        text,
    )
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    return re.sub(
        r"\[([^\]]+)\]\((https?://[^)\s]+)\)",
        lambda m: f'<a target="_blank" href="{html.escape(m.group(2))}" rel="noopener">{m.group(1)}</a>',
        text,
    )


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


def headlines(lines):
    """(section, headline) per bullet: the bold lead-in, or the first sentence."""
    section, out, items = "", [], []
    for line in lines:
        if line.startswith("### "):
            section = line[4:].strip()
        elif line.startswith("- "):
            items.append([section, line[2:].strip()])
        elif line.startswith("  ") and items and line.strip():
            items[-1][1] += " " + line.strip()
    for section, text in items:
        bold = re.match(r"\*\*([^*]+)\*\*", text)
        title = bold.group(1) if bold else re.split(r"(?<=\.)\s", text)[0]
        out.append((section, title.rstrip(":.")))
    return out


def compact_html(version, lines):
    rows = "\n".join(
        f'      <li><span class="notes-tag">{html.escape(section)}</span>{inline(title)}</li>'
        for section, title in headlines(lines))
    return f"""    <ul class="notes-compact">
{rows}
    </ul>
    <p class="notes-more"><a target="_blank" href="https://windowhop.martonpaulo.com/release-notes/{version}/" rel="noopener">Full release notes</a></p>"""


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
{'  <a class="skip-link" href="#main">Skip to content</a>' + chr(10) if header else ''}{header}  <main id="main"{' class="notes"' if "is-compact" in body_class else ""}>
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
            f"The changes in WindowHop {version}, in short.",
            compact_html(version, lines),
            body_class="notes-page is-compact",
        ))

    listing = "\n".join(version_section(v, d, l, link=True) for v, d, l in released)
    (site / "release-notes" / "index.html").write_text(page(
        "WindowHop release notes",
        "What changed in every WindowHop release.",
        page_hero(
            "Releases", "Release notes.",
            "What changed in each version of WindowHop. The app shows the same notes, in short, when it updates.")
        + "\n" + listing,
        header, footer,
    ))
    print(f"release notes: {len(released)} versions, newest {released[0][0]}")


if __name__ == "__main__":
    main()
