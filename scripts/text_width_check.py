#!/usr/bin/env python3
"""Refuse a width cap on text in a web page's styles and markup (workbench#2124).

On the owner's web pages text fills its column: the page's one column width (a `.container` or a
`--page-width` token) is the only width text gets, never a reading measure of its own
(interface standard rule 17). This check reads the stylesheets and pages under each PATH and
prints one line per cap:

- any width property (`width`, `max-width`, `inline-size`, `max-inline-size`) whose value holds a
  `ch` length or a `--measure` token, on any selector;
- any custom property named `--measure...`, or one whose value is a `ch` length, but `--width-subtitle`;
- a `max-width` or `max-inline-size` other than `none`, `100%` or `var(--page-width)` on a text
  selector, a pseudo-element such as `::before` excepted: its last part is a text element (`p`, `h1` to `h6`, `li`, `blockquote`...) or a
  class named for text (`lead`, `summary`, `copy`, `prose`, `description`...), unless the same class
  also names a control (`button`, `icon`, `badge`...);
- in markup, a `style` attribute with such a cap, and the Tailwind classes `max-w-prose`,
  `max-w-[..ch]`, `prose` without `max-w-none`, and any `max-w-*` but `max-w-none`/`max-w-full` on a
  text element.

The one exception (owner, 2026-11-26): the centred subtitle under the page's main title, the element
with the class `hero-summary`, may take a `max-width` or `max-inline-size` in a rule that centres it
(`margin` or `margin-inline` with `auto`). Nothing else may.

The sibling rule (owner, 2026-11-26): the page reserves the scrollbar's space, so a short page and a
long page rendered at the same width keep the same content left edge. When the paths hold any style
(a stylesheet or a `<style>` block), one rule for `html` or `:root` must declare
`scrollbar-gutter: stable`, else one line `PATH: no html { scrollbar-gutter: stable }` fails.

Stylesheets are `.css`, `.scss` and `.less`; pages are `.html`, `.htm`, `.astro`, `.vue`, `.svelte`,
`.jsx` and `.tsx`, whose `<style>` blocks are read as CSS. A folder is read through `git ls-files`
when Git tracks files in it, else every file in it, so a built folder such as `dist/` is read whole;
`node_modules`, `vendor` and `.git` are skipped. Each failure prints
`PATH:LINE: <selector> { <property>: <value> }: <reason>`; the exit code is 1 then, else 0.

    python3 text_width_check.py PATH [PATH ...]
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

STYLE_SUFFIXES = {".css", ".scss", ".less"}
PAGE_SUFFIXES = {".html", ".htm", ".astro", ".vue", ".svelte", ".jsx", ".tsx"}
SKIPPED_PARTS = {"node_modules", "vendor", ".git"}
WIDTH_PROPS = {"width", "max-width", "inline-size", "max-inline-size"}
CAP_PROPS = {"max-width", "max-inline-size"}
NOT_A_CAP = {"none", "100%", "auto", "fit-content", "min-content", "max-content", "inherit", "initial",
             "unset", "revert", "revert-layer", "var(--page-width)"}
TEXT_TAGS = {"p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "ul", "ol", "dl", "dt", "dd", "blockquote",
             "figcaption", "caption", "summary", "small", "span", "strong", "em", "label", "legend", "q",
             "cite", "address", "pre"}
TEXT_WORDS = {"lead", "lede", "summary", "subtitle", "tagline", "intro", "prose", "text", "copy",
              "description", "desc", "blurb", "body", "note", "notice", "caption", "paragraph", "para",
              "excerpt", "message", "title", "heading", "headline", "kicker", "eyebrow", "subhead", "measure"}
CONTROL_WORDS = {"button", "btn", "icon", "img", "image", "logo", "avatar", "dot", "badge", "chip",
                 "toggle", "switch", "input", "thumb", "swatch", "glyph", "bar", "spinner", "media"}
SUBTITLE_CLASS = "hero-summary"
SUBTITLE_WIDTH = "--width-subtitle"
CH_LENGTH = re.compile(r"(?<![\w-])-?\d*\.?\d+ch\b")
MEASURE_VAR = re.compile(r"var\(\s*--measure")
LAST_COMPOUND = re.compile(r"[^\s>+~]+$")
STYLE_BLOCK = re.compile(r"(<style\b[^>]*>)(.*?)</style>", re.S | re.I)
TAG = re.compile(r"<([a-zA-Z][\w-]*)\b([^<>]*?)/?>", re.S)
ATTR = re.compile(r"""\b(class|className|style)\s*=\s*(?:"([^"]*)"|'([^']*)'|\{\s*["'`]([^"'`]*)["'`]\s*\})""", re.S)
TAILWIND_CAP = re.compile(r"^(?:[\w-]+:)*max-w-(.+)$")
GUTTER_SELECTORS = {"html", ":root"}
GUTTER_RULE = ("the page reserves the scrollbar's space, so short and long pages share one left edge "
               "(interface standard rule 17, workbench#2124)")
RULE = "text fills its column, with no width cap of its own (interface standard rule 17, workbench#2124)"


def strip_comments(css: str) -> str:
    """Block comments, and the `//` line comments of SCSS and Less, blanked to spaces with their
    newlines kept, so line numbers stay right."""
    blank = lambda m: re.sub(r"[^\n]", " ", m.group())  # noqa: E731
    css = re.sub(r"/\*.*?\*/", blank, css, flags=re.S)
    return re.sub(r"(?m)(?:^|(?<=[\s;{}]))//.*$", blank, css)


def rules(css: str):
    """(line, selectors, declarations) for each block, nested blocks too; an at-rule is transparent.

    shortcut: a brace scanner, not a CSS parser; a brace inside a string or url() would confuse it,
    read the styles with a real parser once a site needs that."""
    css = strip_comments(css)
    stack: list[list[str]] = []
    start = 0
    body: list[tuple[int, str]] = []
    bodies: list[list[tuple[int, str]]] = []
    found = []
    for index, char in enumerate(css):
        if char == "{":
            prelude = css[start:index]
            head, _, selector = prelude.rpartition(";")
            if head.strip():
                body.append((css.count("\n", 0, start), head))
            selector = selector.strip()
            parent = next((s for s in reversed(stack) if s), [])
            if selector.startswith("@") or not selector:
                selectors: list[str] = []
            else:
                parts = [s.strip() for s in selector.split(",") if s.strip()]
                if parent:
                    parts = [(p.replace("&", q) if "&" in p else f"{q} {p}") for q in parent for p in parts]
                selectors = parts
            stack.append(selectors)
            bodies.append(body)
            body = []
            line = css.count("\n", 0, index) + 1
            found.append((line, selectors, body))
            start = index + 1
        elif char == "}":
            tail = css[start:index]
            if tail.strip():
                body.append((css.count("\n", 0, start), tail))
            if stack:
                stack.pop()
                body = bodies.pop()
            start = index + 1
    for line, selectors, chunks in found:
        declarations = []
        for offset, chunk in chunks:
            row = offset
            for piece in chunk.split(";"):
                prop, colon, value = piece.partition(":")
                if colon and prop.strip():
                    lead = piece[: len(piece) - len(piece.lstrip())]
                    declarations.append((row + lead.count("\n") + 1, prop.strip().lower(), " ".join(value.split())))
                row += piece.count("\n")
        yield line, selectors, declarations


def compound_parts(selector: str) -> tuple[str, list[str]]:
    """The element name and class names of a selector's last compound, pseudo-classes removed."""
    match = LAST_COMPOUND.search(re.sub(r":[\w-]+(\((?:[^()]|\([^()]*\))*\))?", "", selector).strip())
    last = match.group() if match else ""
    tag = re.match(r"^[a-zA-Z][\w-]*", last)
    return (tag.group().lower() if tag else ""), re.findall(r"\.([\w-]+)", last)


def is_text(selector: str) -> bool:
    """A selector for text; a pseudo-element (`::before`) is decoration, never text."""
    if re.search(r"::?(?:before|after|marker|placeholder|backdrop)\b", selector):
        return False
    tag, classes = compound_parts(selector)
    # A plural names the same thing: `.notes` is text as `.note` is, `.icons` a control as `.icon` is.
    words = [{w for part in re.split(r"[-_]", name.lower()) for w in (part, part.removesuffix("s"))}
             for name in classes]
    if any(word & CONTROL_WORDS for word in words):
        return False
    return tag in TEXT_TAGS or any(word & TEXT_WORDS for word in words)


def is_subtitle(selector: str) -> bool:
    return compound_parts(selector)[1] == [SUBTITLE_CLASS]


def is_cap(prop: str, value: str) -> bool:
    """A `max-width` or `max-inline-size` that narrows; a fixed `width` counts only in `ch`."""
    return prop in CAP_PROPS and value.replace("!important", "").strip().lower() not in NOT_A_CAP


def declaration_problems(selectors: list[str], declarations, centred: bool) -> list[tuple[int, str]]:
    found = []
    shown = ", ".join(selectors) or "(top level)"
    for line, prop, value in declarations:
        if prop.startswith("--"):
            if prop.startswith("--measure") or (CH_LENGTH.search(value) and prop != SUBTITLE_WIDTH):
                found.append((line, f"{shown} {{ {prop}: {value} }}: a reading-measure token; {RULE}"))
            continue
        if prop not in WIDTH_PROPS:
            continue
        subtitle = selectors and all(is_subtitle(s) for s in selectors) and prop in CAP_PROPS
        if subtitle and (centred or not is_cap(prop, value)):
            continue
        if subtitle:
            found.append((line, f"{shown} {{ {prop}: {value} }}: the subtitle keeps a width only in a rule that "
                                f"centres it (margin auto); {RULE}"))
        elif CH_LENGTH.search(value) or MEASURE_VAR.search(value):
            found.append((line, f"{shown} {{ {prop}: {value} }}: a width in ch or a measure token; {RULE}"))
        elif any(is_text(s) for s in selectors) and is_cap(prop, value):
            found.append((line, f"{shown} {{ {prop}: {value} }}: a width cap on text; {RULE}"))
    return found


def css_problems(css: str, line_offset: int = 0) -> list[tuple[int, str]]:
    found = []
    for _, selectors, declarations in rules(css):
        centred = any(prop in ("margin", "margin-inline", "margin-left", "margin-right") and "auto" in value
                      for _, prop, value in declarations)
        found += [(line + line_offset, text) for line, text in declaration_problems(selectors, declarations, centred)]
    return found


def reserves_gutter(css: str) -> bool:
    """True when a rule for `html` or `:root` declares `scrollbar-gutter: stable`."""
    return any(prop == "scrollbar-gutter" and "stable" in value.lower()
               and any(s.strip().lower() in GUTTER_SELECTORS for s in selectors)
               for _, selectors, declarations in rules(css) for _, prop, value in declarations)


def markup_problems(text: str) -> list[tuple[int, str]]:
    found = []
    for block in STYLE_BLOCK.finditer(text):
        offset = text.count("\n", 0, block.start(2))
        found += css_problems(block.group(2), offset)
    for tag in TAG.finditer(text):
        name = tag.group(1)
        line = text.count("\n", 0, tag.start()) + 1
        classes: list[str] = []
        style = ""
        for attr in ATTR.finditer(tag.group(2)):
            value = next(v for v in attr.groups()[1:] if v is not None)
            if attr.group(1) == "style":
                style = value
            else:
                classes += value.split()
        selector = name.lower() + "".join(f".{c}" for c in classes if re.fullmatch(r"[\w-]+", c))
        if style:
            declarations = [(line, p.strip().lower(), " ".join(v.split()))
                            for p, _, v in (d.partition(":") for d in style.split(";")) if p.strip()]
            centred = any(p.startswith("margin") and "auto" in v for _, p, v in declarations)
            found += declaration_problems([selector], declarations, centred)
        caps = [m.group(1) for m in map(TAILWIND_CAP.match, classes) if m]
        bare = {re.sub(r"^(?:[\w-]+:)*", "", c) for c in classes}
        for cap in caps:
            if cap == "prose" or CH_LENGTH.search(cap.strip("[]")):
                found.append((line, f"<{name} class=\"max-w-{cap}\">: a reading measure; {RULE}"))
            elif cap not in ("none", "full") and is_text(selector):
                found.append((line, f"<{name} class=\"max-w-{cap}\">: a width cap on text; {RULE}"))
        if "prose" in bare and "max-w-none" not in bare:
            found.append((line, f"<{name} class=\"prose\">: the typography plugin caps text at 65ch; add max-w-none; {RULE}"))
    return found


def files(path: Path) -> list[Path]:
    if path.is_file():
        return [path]
    listed = subprocess.run(["git", "-C", str(path), "ls-files", "-z", "--", "."], capture_output=True, check=False)
    names = [n for n in listed.stdout.decode("utf-8", "replace").split("\0") if n] if listed.returncode == 0 else []
    candidates = [path / name for name in names] if names else sorted(p for p in path.rglob("*") if p.is_file())
    return [p for p in candidates if not SKIPPED_PARTS & set(p.relative_to(path).parts)]


def problems(paths: list[Path]) -> list[str]:
    found: list[str] = []
    styled = gutter = False
    for root in paths:
        for path in files(root):
            suffix = path.suffix.lower()
            if suffix not in STYLE_SUFFIXES | PAGE_SUFFIXES or not path.is_file():
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            listed = css_problems(text) if suffix in STYLE_SUFFIXES else markup_problems(text)
            found += [f"{path}:{line}: {message}" for line, message in listed]
            styles = [text] if suffix in STYLE_SUFFIXES else [m.group(2) for m in STYLE_BLOCK.finditer(text)]
            styled = styled or bool(styles)
            gutter = gutter or any(reserves_gutter(css) for css in styles)
    if styled and not gutter:
        found.append(f"{', '.join(map(str, paths))}: no html {{ scrollbar-gutter: stable }}: {GUTTER_RULE}")
    return found


def main(argv: list[str]) -> int:
    if not argv or any(arg.startswith("-") for arg in argv):
        print(__doc__.strip().splitlines()[-1].strip(), file=sys.stderr)
        return 2
    missing = [arg for arg in argv if not Path(arg).exists()]
    if missing:
        print(f"text_width_check: no such path: {', '.join(missing)}", file=sys.stderr)
        return 2
    found = problems([Path(arg) for arg in argv])
    for line in found:
        print(line)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
