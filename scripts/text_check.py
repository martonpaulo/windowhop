#!/usr/bin/env python3
"""Check a repository's tracked text the way Skill Deck checks its own (#797).

    text_check.py [ROOT]

Three rules, each over the files Git tracks under ROOT (default `.`), or every file when ROOT is not
a Git repository; dot folders, `node_modules`, `vendor`, `third_party` and `.build` are left out:

- `invisible`: no text file carries an invisible or bidirectional-control character, because a
  reviewer cannot see what a tool or an agent reads. An emoji joined by a zero-width joiner to an
  emoji or a symbol (U+1F642 U+200D U+2194) passes, and so do a subdivision flag's tag characters
  (U+1F3F4 then tags).
- `links`: every relative Markdown link resolves, and its `#anchor` names a heading GitHub
  generates. Repeated headings take `-1`, `-2`; a `#` line inside a fence is no heading; a `#L12`
  line anchor and an absolute or external link are not checked.
- `contents`: a Markdown file under `docs/` (not `docs/research/`, whose dated notes are read once)
  longer than 100 lines and with two or more `##` sections starts with a Contents list (a
  `## Contents` heading, or a line that is exactly `Contents:`) linking every `##` section.

Prints `<file>:<line>: <rule>: <problem>` per hit, then exits 1 on any, 0 on none, 2 on a usage
error. Python's standard library and Git only. Copy it unchanged to `scripts/text_check.py` and run
it in the project's gate; the `text-check` rule of `check_repository_conventions.py` reads the copy.
"""
from __future__ import annotations

import re
import subprocess
import sys
import unicodedata
from pathlib import Path
from urllib.parse import unquote, urlsplit

SKIP_DIRS = {"node_modules", "vendor", "third_party", ".build"}
TEXT_SUFFIXES = {
    ".md", ".sh", ".py", ".yaml", ".yml", ".json", ".tsv", ".toml", ".txt", ".js", ".mjs", ".ts",
    ".tsx", ".jsx", ".css", ".html", ".swift", ".go", ".rs", ".rb", ".plist", ".xml", ".strings",
}
INVISIBLE = {
    0x00AD: "soft hyphen",
    0x180E: "Mongolian vowel separator",
    0x200B: "zero-width space",
    0x200C: "zero-width non-joiner",
    0x200D: "zero-width joiner",
    0x200E: "left-to-right mark",
    0x200F: "right-to-left mark",
    0x2060: "word joiner",
    0xFEFF: "byte order mark",
    **{code: "bidirectional control" for code in (*range(0x202A, 0x202F), *range(0x2066, 0x206A))},
    **{code: "tag character" for code in range(0xE0000, 0xE0080)},
}
CONTENTS_THRESHOLD = 100
FENCE = re.compile(r"^\s*(?:```|~~~)")
INLINE_LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
REFERENCE_LINK = re.compile(r"^\s*\[[^\]]+\]:\s*(\S+)")
# An inline code span: a run of backticks closed by a run of the same length (CommonMark 6.1).
CODE_SPAN = re.compile(r"(?<!`)(`+)(?!`).+?(?<!`)\1(?!`)")


def tracked_files(root: Path) -> list[Path]:
    """The files Git tracks under root, or every file when root is not a work tree."""
    try:
        listed = subprocess.run(["git", "-C", str(root), "ls-files", "-z"], capture_output=True, check=False)
    except OSError:
        listed = None
    if listed is not None and listed.returncode == 0:
        names = [name for name in listed.stdout.decode("utf-8", "replace").split("\0") if name]
    else:
        names = [path.relative_to(root).as_posix() for path in root.rglob("*") if path.is_file()]
    kept = []
    for name in sorted(names):
        parts = name.split("/")
        if any(part.startswith(".") or part in SKIP_DIRS for part in parts[:-1]):
            continue
        path = root / name
        if path.is_file() and not path.is_symlink():
            kept.append(path)
    return kept


# Emoji ranges: the pictographs, the dingbats and miscellaneous symbols, and the emoji presentation selector.
EMOJI_PLANE = 0x1F000
DINGBATS = range(0x2600, 0x27C0)
EMOJI_SELECTOR = 0xFE0F
# Symbols a ZWJ sequence may join to, such as U+2194 or U+2695: So and Sm in this block.
SYMBOL_BLOCK = range(0x2000, 0x2C00)
SYMBOL_CATEGORIES = ("So", "Sm")
JOINER = 0x200D
BLACK_FLAG = 0x1F3F4
TAGS = range(0xE0020, 0xE0080)


def _is_emoji(char: str) -> bool:
    code = ord(char)
    return code >= EMOJI_PLANE or code in DINGBATS or code == EMOJI_SELECTOR


def _is_symbol(char: str) -> bool:
    """A character an emoji ZWJ sequence may join to: an emoji, or a symbol of `SYMBOL_BLOCK`."""
    return _is_emoji(char) or (ord(char) in SYMBOL_BLOCK and unicodedata.category(char) in SYMBOL_CATEGORIES)


def _in_flag_tags(line: str, index: int) -> bool:
    """Whether the tag character at `index` belongs to a subdivision flag: the black flag, then tags only."""
    start = index
    while start > 0 and ord(line[start - 1]) in TAGS:
        start -= 1
    return start > 0 and ord(line[start - 1]) == BLACK_FLAG


def check_invisible(label: str, text: str) -> list[str]:
    problems = []
    for number, line in enumerate(text.splitlines(), 1):
        for index, char in enumerate(line):
            name = INVISIBLE.get(ord(char))
            if name is None:
                continue
            if ord(char) == JOINER and 0 < index < len(line) - 1 and _is_emoji(line[index - 1]) and _is_symbol(line[index + 1]):
                continue
            if ord(char) in TAGS and _in_flag_tags(line, index):
                continue
            problems.append(f"{label}:{number}: invisible: U+{ord(char):04X} ({name}); write it as an escape if intended")
    return problems


def headings(text: str) -> list[tuple[int, str, str]]:
    """Each heading's level, text and the anchor GitHub generates for it, in document order."""
    found: list[tuple[int, str, str]] = []
    seen: dict[str, int] = {}
    fenced = False
    for line in text.splitlines():
        if FENCE.match(line):
            fenced = not fenced
            continue
        if fenced or not re.match(r"^#{1,6}\s", line):
            continue
        level = len(line) - len(line.lstrip("#"))
        title = line.lstrip("#").strip()
        raw = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", title)
        raw = re.sub(r"[`*]", "", raw)
        # Trim before removing characters: a heading that opens with an emoji keeps a leading hyphen.
        slug = re.sub(r"[^\w\- ]+", "", raw.strip().lower()).replace(" ", "-")
        if not slug:
            continue
        count = seen.get(slug, 0)
        seen[slug] = count + 1
        found.append((level, title, slug if count == 0 else f"{slug}-{count}"))
    return found


def _destinations(text: str) -> list[tuple[int, str]]:
    found: list[tuple[int, str]] = []
    fenced = False
    for number, line in enumerate(text.splitlines(), 1):
        if FENCE.match(line):
            fenced = not fenced
            continue
        if fenced:
            continue
        line = CODE_SPAN.sub("", line)
        found.extend((number, match.group(1).strip()) for match in INLINE_LINK.finditer(line))
        reference = REFERENCE_LINK.match(line)
        if reference:
            found.append((number, reference.group(1).strip()))
    return found


def check_links(path: Path, label: str, text: str, anchors: dict[Path, set[str]]) -> list[str]:
    problems = []
    for number, raw in _destinations(text):
        destination = raw[1 : raw.index(">")] if raw.startswith("<") and ">" in raw else raw.split(maxsplit=1)[0]
        parsed = urlsplit(destination)
        if not destination or parsed.scheme or parsed.netloc or destination.startswith("/"):
            continue
        fragment = unquote(parsed.fragment)
        target = path if not parsed.path else path.parent / unquote(parsed.path)
        if not target.exists():
            problems.append(f"{label}:{number}: links: target does not exist: {raw}")
            continue
        if not fragment or target.suffix != ".md" or re.fullmatch(r"L\d+(?:-L\d+)?", fragment):
            continue
        resolved = target.resolve()
        if resolved not in anchors:
            try:
                anchors[resolved] = {anchor for _, _, anchor in headings(resolved.read_text(encoding="utf-8"))}
            except (OSError, UnicodeError):
                continue
        if fragment.lower() not in anchors[resolved]:
            problems.append(f"{label}:{number}: links: anchor names no heading: {raw}")
    return problems


def _contents_block(lines: list[str]) -> list[str] | None:
    fenced = False
    for index, line in enumerate(lines):
        if FENCE.match(line):
            fenced = not fenced
            continue
        if fenced:
            continue
        if line.strip() == "## Contents":
            block = []
            for following in lines[index + 1 :]:
                if re.match(r"^##\s", following):
                    break
                block.append(following)
            return block
        if line.strip() == "Contents:":
            block = []
            for following in lines[index + 1 :]:
                if re.match(r"^##\s", following) or (block and not following.strip()):
                    break
                if following.strip():
                    block.append(following)
            return block
        if re.match(r"^##\s", line):
            return None
    return None


def check_contents(label: str, text: str) -> list[str]:
    lines = text.splitlines()
    if len(lines) <= CONTENTS_THRESHOLD:
        return []
    sections = [(title, anchor) for level, title, anchor in headings(text) if level == 2 and title != "Contents"]
    if len(sections) < 2:
        return []
    block = _contents_block(lines)
    if block is None:
        return [f"{label}:1: contents: {len(lines)} lines and no Contents list before the first section"]
    linked = {unquote(target).lower() for target in re.findall(r"\]\(#([^)\s]+)\)", "\n".join(block))}
    return [f"{label}:1: contents: the Contents list misses '{title}' (#{anchor})"
            for title, anchor in sections if anchor not in linked]


def check(root: Path) -> list[str]:
    problems: list[str] = []
    anchors: dict[Path, set[str]] = {}
    for path in tracked_files(root):
        if path.suffix not in TEXT_SUFFIXES:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            continue
        label = path.relative_to(root).as_posix()
        problems.extend(check_invisible(label, text))
        if path.suffix == ".md":
            problems.extend(check_links(path, label, text, anchors))
            if label.startswith("docs/") and not label.startswith("docs/research/"):
                problems.extend(check_contents(label, text))
    return problems


def main(argv: list[str]) -> int:
    if len(argv) > 1 or (argv and argv[0].startswith("-")):
        print("usage: text_check.py [ROOT]", file=sys.stderr)
        return 2
    root = Path(argv[0] if argv else ".")
    if not root.is_dir():
        print(f"text_check.py: not a directory: {root}", file=sys.stderr)
        return 2
    problems = check(root.resolve())
    for problem in problems:
        print(problem)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
