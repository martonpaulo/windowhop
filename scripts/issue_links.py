#!/usr/bin/env python3
"""Every issue and pull request reference in Markdown prose is a link (#734).

    issue_links.py [ROOT] [--repo OWNER/NAME]

Reads every `*.md` file under ROOT (default `.`); dot folders, `node_modules`, `vendor`,
`third_party`, `.build` and symbolic links are left out. A bare reference is `#N`, `PR #N` or
`owner/repo#N`; `[#N](https://github.com/OWNER/NAME/issues/N)` is the link form, and so is `[#N]` when the file
defines `[#N]: <url>` (#822). Left as written: fenced blocks, code spans (a quoted commit subject
sits in one), links, autolinks, URLs, HTML comments, reference definitions and quoted lines (`>`). It never asks GitHub whether a number exists: the author checks
that before linking.

Prints, per hit, `<file>:<line>: bare reference <text>; link it as [<text>](<url>)` and exits 1 on
any, 2 on a usage error. The repository of a `#N` is `--repo`, else the `origin` remote's; without
`--repo`, an `origin` that cannot be read as a GitHub repository is a usage error, never a
placeholder in the link (#1220). Python's
standard library and Git only. Adapted from Panoram's tools/issue_links.py (the owner's own code).

Exit: 0 every reference is linked, 1 a bare reference, 2 a usage error.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

GITHUB = "https://github.com"
GIT_TIMEOUT = 10  # seconds for `git remote get-url`
SKIP_DIRS = {"node_modules", "vendor", "third_party", ".build"}
PROTECTED = re.compile(
    r"(`+).+?\1"  # code span
    r"|!?\[(?:[^\[\]]|\[[^\]]*\])*\]\([^)]*\)"  # inline link or image
    r"|\[[^\]]*\]\[[^\]]*\]"  # reference link
    r"|<https?://[^>]+>"  # autolink
    r"|https?://[^\s)>\]]+"  # bare URL
    r"|<!--.*?-->"  # HTML comment
)
REFERENCE = re.compile(
    r"(?<![\w/&#.-])(?:(?P<repo>[A-Za-z0-9-]+/[A-Za-z0-9._-]+)#|(?:PRs? )?#)(?P<n>\d{1,5})(?!\w)"
)
SHORTCUT = re.compile(r"\[([^\[\]]+)\]")
DEFINITION = re.compile(r"^ {0,3}\[([^\[\]]+)\]:\s*\S")
FENCE = re.compile(r"(`{3,}|~{3,})")
REMOTE = re.compile(r"github\.com[:/](?P<repo>[^/\s]+/[^/\s]+?)(?:\.git)?/?$")


def bare(text: str) -> list[tuple[int, str]]:
    """(line, reference) for each bare reference in one Markdown file's text."""
    hits, fence = [], None
    lines = text.split("\n")
    labels = {found.group(1).lower() for line in lines if (found := DEFINITION.match(line))}
    for number, line in enumerate(lines, 1):
        stripped = line.lstrip()
        opening = FENCE.match(stripped)
        if fence:
            if opening and stripped.startswith(fence) and stripped.strip() == fence[0] * len(stripped.strip()):
                fence = None
            continue
        if opening:
            fence = opening.group(1)
            continue
        if stripped.startswith(">") or DEFINITION.match(line):
            continue
        hits.extend((number, ref) for ref in references(line, labels))
    return hits


def references(line: str, labels: frozenset[str] | set[str] = frozenset()) -> list[str]:
    """The bare references of one prose line, outside its protected spans; a `[label]` the file
    defines is a link."""
    chunks, last = [], 0
    for span in PROTECTED.finditer(line):
        chunks.append(line[last:span.start()])
        last = span.end()
    chunks.append(line[last:])
    chunks = [SHORTCUT.sub(lambda m: " " if m.group(1).lower() in labels else m.group(0), chunk)
              for chunk in chunks]
    return [found.group(0) for chunk in chunks for found in REFERENCE.finditer(chunk)]


def suggestion(text: str, repo: str) -> str:
    """The link form of a bare reference: a pull request's when the text says PR."""
    found = REFERENCE.fullmatch(text)
    kind = "pull" if text.startswith("PR") else "issues"
    return f"[{text}]({GITHUB}/{found.group('repo') or repo}/{kind}/{found.group('n')})"


class OriginUnreadable(Exception):
    """The `origin` remote is missing or names no GitHub repository (#1220)."""


def origin(root: Path) -> str:
    try:
        url = subprocess.run(["git", "-C", str(root), "remote", "get-url", "origin"],
                             capture_output=True, text=True, timeout=GIT_TIMEOUT).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        url = ""
    found = REMOTE.search(url)
    if not found:
        raise OriginUnreadable(f"{root}: no GitHub `origin` remote to name the repository of a bare #N; pass --repo OWNER/NAME")
    return found.group("repo")


def problems(root: Path, repo: str) -> list[str]:
    found = []
    for folder, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not d.startswith("."))
        for name in sorted(files):
            path = Path(folder, name)
            if not name.endswith(".md") or path.is_symlink():
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except (OSError, UnicodeError):
                continue
            relative = path.relative_to(root).as_posix()
            for number, ref in bare(text):
                found.append(f"{relative}:{number}: bare reference {ref}; link it as {suggestion(ref, repo)}")
    return found


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("root", nargs="?", default=".")
    parser.add_argument("--repo", help="OWNER/NAME of a bare #N; default: the origin remote's")
    args = parser.parse_args(argv)
    root = Path(args.root)
    if not root.is_dir():
        parser.print_usage(sys.stderr)
        return 2
    try:
        repo = args.repo or origin(root)
    except OriginUnreadable as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    found = problems(root, repo)
    for problem in found:
        print(problem)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
