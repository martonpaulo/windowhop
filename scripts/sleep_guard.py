#!/usr/bin/env python3
"""No test proves «nothing happened», or waits for work, by sleeping (#740).

    sleep_guard.py [ROOT]

A sleep in a test (`time.Sleep(`, `time.sleep(`, `sleep(`, `Task.sleep(`, `Thread.sleep(`,
`usleep(`, `waitForTimeout(`, a shell `sleep 1`) needs a `timing-independent:` note on its line or
the line above, saying why the time cannot change the result: a poll with a deadline, a fake that
stands for slow work. A check that nothing arrived waits on a signal instead; a known one not fixed
yet carries `timing-dependent (#N):`, naming the open issue that removes it.

An assertion on elapsed wall-clock time (`assertLess(elapsed, 2)`, `time.monotonic() - start`,
`time.Since(`, `Date.now() -`, a comparison with a `*_MS` or `*_SECONDS` budget constant, #1858)
is a measurement, not a test: a loaded machine fails it (#1712). It
needs the same note, or the file holds a measurement switch, an environment variable named
`<PREFIX>_PERF_TESTS` the bound runs only under (Panoram's `PANORAM_PERF_TESTS`).

A test file is `*_test.go`, `test_*.py`, `*_test.py`, `*.test.*`, `*.spec.*`, `*Tests.swift`,
`*Test.swift`, or a code file in a `tests`, `Tests`, `test` or `__tests__` folder. Dot folders,
`node_modules`, `vendor`, `third_party` and `.build` are left out, and so are the forks the
repository's `upstreams.json` records (each source's `localPaths`, #900). Prints one line per finding
and exits 1 on any, 2 on a usage error. Python's standard library only. Adapted from Panoram's
tools/sleep_guard.py (the owner's own code), which reads Go only.

A project's own rules live in `sleep_guard.json` beside this script, so the script itself is copied
unchanged (#1992):

    {"rules": [{"pattern": "testing\\.Benchmark\\(", "unless": "PANORAM_PERF_TESTS",
                "says": "testing.Benchmark in a test is a measurement; skip it unless PANORAM_PERF_TESTS=1"}],
     "skip": ["fake*_test.go"]}

A rule's `pattern` is a regex a test line must not hold unless its file names `unless`; a `skip` glob
leaves out a test file, matched against its name, or its repository path when it holds a `/`.

shortcut: a regex per line, not a parser, so a sleep inside a string counts (a fake's code usually
is one) and a trailing comment that names a sleep counts too; a parser would need each language's
toolchain in every gate.
"""
from __future__ import annotations

import fnmatch
import json
import os
import re
import sys
from pathlib import Path

NOTE = "timing-independent:"
DEBT = re.compile(r"timing-dependent \(#\d+\):")
CODE = {".go", ".py", ".sh", ".bash", ".zsh", ".swift", ".js", ".mjs", ".cjs", ".ts", ".tsx", ".jsx",
        ".rb", ".kt", ".java", ".rs"}
TEST_NAME = re.compile(r"(_test\.go|^test_.*\.py|_test\.py|\.(test|spec)\.[^.]+|Tests?\.swift)$")
TEST_DIRS = {"tests", "Tests", "test", "__tests__"}
SKIP_DIRS = {"node_modules", "vendor", "third_party", ".build"}
SLEEP = re.compile(
    r"(\b(time\.Sleep|sleep|usleep|waitForTimeout)\s*\("
    r"|(^|[\s;&|({`])sleep\s+[\d$.])"
)
ASSERT = re.compile(r"\b(assert\w*|expect|XCTAssert\w*|require\.\w+)\b")
ELAPSED = re.compile(
    r"(\belapsed\w*\b|time\.Since\(|\b(monotonic|perf_counter|time|now|Now)\(\)\s*-\s*[A-Za-z_])"
    # a time budget held in a constant: `assert.ok(firstCard <= WARM_FIRST_CARD_MS)` (#1858)
    r"|[<>]=?\s*[A-Z][A-Z0-9_]*_(MS|SECONDS)\b"
)
SWITCH = re.compile(r"\b[A-Z][A-Z0-9]*_PERF_TESTS\b")
COMMENT = ("#", "//", "/*")
OWN = Path(__file__).with_name("sleep_guard.json")  # the project's own rules (#1992)


def own_rules(path: Path = OWN) -> tuple[list[tuple[re.Pattern, str, str]], list[str]]:
    """The project's rules, as (pattern, the token that exempts a file, message), and its skip globs."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return [], []
    rules = [(re.compile(rule["pattern"]), rule.get("unless", ""), rule["says"]) for rule in data.get("rules", [])]
    return rules, list(data.get("skip", []))


def top(root: Path) -> Path:
    """The repository holding `root`, whose `upstreams.json` and paths the forks and skips name: the
    nearest folder with a `.git` entry, read with no `git` call, so a leaked `GIT_DIR` cannot redirect it."""
    return next((folder for folder in (root, *root.parents) if (folder / ".git").exists()), root)


def forks(repository: Path) -> set[Path]:
    """The folders and files `upstreams.json` records as copied code (#900)."""
    try:
        data = json.loads((repository / "upstreams.json").read_text(encoding="utf-8"))
        return {repository / local.rstrip("/") for source in data["sources"] for local in source["localPaths"]}
    except (OSError, ValueError, KeyError, TypeError):
        return set()


def skipped(path: Path, repository: Path, globs: list[str]) -> bool:
    where = path.relative_to(repository).as_posix()
    return any(fnmatch.fnmatch(where if "/" in glob else path.name, glob) for glob in globs)


def is_test(path: Path, root: Path) -> bool:
    if path.suffix not in CODE:
        return False
    return bool(TEST_NAME.search(path.name)) or any(
        part in TEST_DIRS for part in path.relative_to(root).parts[:-1]
    )


def problems(root: Path, own: Path = OWN) -> list[str]:
    root = Path(root).resolve()
    repository = top(root)
    copied = forks(repository)
    rules, globs = own_rules(own)
    found = []
    for folder, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")
                         and Path(folder, d) not in copied)
        for name in sorted(files):
            path = Path(folder, name)
            if not is_test(path, root) or path in copied or skipped(path, repository, globs):
                continue
            try:
                lines = path.read_text(encoding="utf-8").split("\n")
            except (OSError, UnicodeError):
                continue
            text = "\n".join(lines)
            switched = bool(SWITCH.search(text))
            for index, line in enumerate(lines):
                if line.lstrip().startswith(COMMENT):
                    continue
                for pattern, unless, says in rules:
                    if pattern.search(line) and not (unless and unless in text):
                        found.append(f"{path.relative_to(root).as_posix()}:{index + 1}: {says}")
                sleep = SLEEP.search(line)
                bound = not switched and ASSERT.search(line) and ELAPSED.search(line)
                if not (sleep or bound):
                    continue
                near = line + (lines[index - 1] if index else "")
                if NOTE in near or DEBT.search(near):
                    continue
                where = f"{path.relative_to(root).as_posix()}:{index + 1}:"
                if sleep:
                    found.append(
                        f"{where} a sleep in a test without a «{NOTE}» note; wait on the condition, "
                        "or name the open issue with «timing-dependent (#N):» (#740)"
                    )
                else:
                    found.append(
                        f"{where} an elapsed-time bound in a test without a «{NOTE}» note; it is a "
                        "measurement: say why load cannot fail it, or run it only under a "
                        "<PREFIX>_PERF_TESTS switch (#1712)"
                    )
    return found


def main(argv: list[str]) -> int:
    if len(argv) > 1 or (argv and not Path(argv[0]).is_dir()):
        print("usage: sleep_guard.py [ROOT]", file=sys.stderr)
        return 2
    found = problems(Path(argv[0] if argv else "."))
    for problem in found:
        print(problem)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
