#!/usr/bin/env python3
"""Writes WindowHop's release notes into a staged copy of the site.

    scripts/render-release-notes.py <staged-site-dir>

Every `## [X.Y.Z] - YYYY-MM-DD` entry of CHANGELOG.md becomes
`<dir>/release-notes/X.Y.Z/index.html`, and all of them together become
`<dir>/release-notes/index.html`. The appcast's `sparkle:releaseNotesLink` points
at the version's page, so Sparkle's update window shows the notes on their own,
in the site's look, instead of the whole GitHub release page (#128).

The deploy workflow runs this on its staged copy, like render-download-count.sh:
nothing it writes is committed. The pages carry `noindex`; the changelog is not a
search landing page. Only the Markdown the changelog uses is understood: `###`
headings, `- ` bullets with indented continuation lines, paragraphs, **bold**,
`code` and [links](url).
"""

import datetime
import hashlib
import html
import pathlib
import re
import sys

ENTRY = re.compile(r"^## \[(\d+\.\d+\.\d+)\] - (\d{4}-\d{2}-\d{2})\s*$")


def inline(text):
    """Escapes text, then turns the changelog's inline Markdown into HTML."""
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
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


def body_html(lines, level):
    """Renders one entry's sections: headings at `level`, bullet lists and paragraphs."""
    out, items, paragraph = [], [], []

    def flush_paragraph():
        if paragraph:
            out.append(f"<p>{inline(' '.join(paragraph))}</p>")
            paragraph.clear()

    def flush_items():
        if items:
            out.append("<ul>" + "".join(f"<li>{inline(i)}</li>" for i in items) + "</ul>")
            items.clear()

    for line in lines:
        if line.startswith("### "):
            flush_paragraph()
            flush_items()
            out.append(f"<h{level}>{inline(line[4:].strip())}</h{level}>")
        elif line.startswith("- "):
            flush_paragraph()
            items.append(line[2:].strip())
        elif line.startswith("  ") and items and line.strip():
            items[-1] += " " + line.strip()
        elif line.strip():
            flush_items()
            paragraph.append(line.strip())
        else:
            flush_paragraph()
            flush_items()
    flush_paragraph()
    flush_items()
    return "\n".join(out)


def long_date(iso):
    day = datetime.date.fromisoformat(iso)
    return f"{day.day} {day:%B %Y}"


def page(title, description, content):
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
</head>
<body class="notes-page">
  <main class="notes">
{content}
  </main>
</body>
</html>
"""


def icon_url(root):
    """The icon's address with a content version: /assets/ is cached for a year."""
    digest = hashlib.md5((root / "site" / "assets" / "app-icon.png").read_bytes()).hexdigest()[:8]
    return f"/assets/app-icon.png?v={digest}"


ICON = "/assets/app-icon.png"


def entry_html(version, date, lines, heading="h1", link=False):
    title = f'<a href="/release-notes/{version}/">WindowHop {version}</a>' if link else f"WindowHop {version}"
    return f"""    <article class="notes-entry">
      <header class="notes-header">
        <img src="{ICON}" width="56" height="56" alt="">
        <div>
          <{heading}>{title}</{heading}>
          <p class="notes-date"><time datetime="{date}">{long_date(date)}</time></p>
        </div>
      </header>
{body_html(lines, 3 if heading == "h2" else 2)}
    </article>"""


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: render-release-notes.py <staged-site-dir>")
    root = pathlib.Path(__file__).resolve().parent.parent
    site = pathlib.Path(sys.argv[1])
    global ICON
    ICON = icon_url(root)
    released = list(entries((root / "CHANGELOG.md").read_text()))
    if not released:
        sys.exit("render-release-notes: CHANGELOG.md has no released entry")

    for version, date, lines in released:
        target = site / "release-notes" / version
        target.mkdir(parents=True, exist_ok=True)
        # no download button: in Sparkle's window, Install Update is the action
        footer = """    <footer class="notes-footer">
      <a class="text-link" href="/release-notes/">All release notes</a>
    </footer>"""
        (target / "index.html").write_text(page(
            f"WindowHop {version} release notes",
            f"What changed in WindowHop {version}, released on {long_date(date)}.",
            entry_html(version, date, lines) + "\n" + footer,
        ))

    listing = "\n".join(entry_html(v, d, l, heading="h2", link=True) for v, d, l in released)
    (site / "release-notes" / "index.html").write_text(page(
        "WindowHop release notes",
        "What changed in every WindowHop release.",
        f'    <h1 class="notes-title">Release notes</h1>\n{listing}',
    ))
    print(f"release notes: {len(released)} versions, newest {released[0][0]}")


if __name__ == "__main__":
    main()
