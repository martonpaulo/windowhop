#!/usr/bin/env python3
"""The DRY gate (#722): each value, block of code, cross-language rule and written rule has one owner.

    dry_check.py [--root DIR] [--data FILE] [--init | --shrink | --list] [magic|duplicates|twins|documents|retired]...

Five checks, each reading its section of `dry-check.json` at the repository root (rules and schema:
bench-project-standards `references/dry-checks.md`). A check whose section is absent is skipped, and says so.

- magic: a number, duration, URL, system path, port, colour or repeated phrase with no name, in Python,
  shell, Go or JavaScript. Ratchet per file and class (`magicValues.counts`).
- duplicates: a block of 4 or more code lines that appears 3 or more times. Ratchet per area, the
  first `depth` folders of the block's first copy (`duplicates.counts`). A code file over 50 lines
  with a byte-identical twin fails at two copies, unless every copy is a `duplicates.identical`
  row with its reason (#1237).
- twins: a rule two languages hold has one owner and one golden file both sides' tests read
  (`twins`, one row per rule).
- documents: a page over its byte budget, and the same rule sentence written in two documents.
  Ratchet per file (`documents.repeated`).
- retired: a renamed thing's old name, written again. Each `retired.terms` row names the term, the name
  to use and the globs where it may stay; ratchet per file and term (`retired.counts`), so a file with no
  row allows none (#1713).

A count above its row fails and names each line. A count below its row fails too, so a ratchet only
goes down: `--shrink` lowers the rows and never raises one. `--init` records today's counts once, for
a section with no counts yet. `--list` prints every finding, with no verdict.

Exit 0 when every check holds, 1 on a finding, 2 on a usage or data error. Python's standard library
and Git only. Adapted from Panoram's tools/magic_values.py, clients/macos/scripts/duplicates.py,
tools/twins.py and tools/doc_rules.py (the owner's own code).

shortcut: Go, shell and JavaScript are read by small lexers, not parsers, so a number in a heredoc or
a generated table counts as code; a real parser would need each language's toolchain in every gate.
"""
from __future__ import annotations

import ast
import collections
import fnmatch
import json
import pathlib
import re
import subprocess
import sys

DATA_FILE = "dry-check.json"
CHECKS = ("magic", "duplicates", "twins", "documents", "retired")
SECTION = {"magic": "magicValues", "duplicates": "duplicates", "twins": "twins", "documents": "documents", "retired": "retired"}
EXIT_FINDING, EXIT_USAGE = 1, 2
SHEBANG_BYTES = 200  # the first line of a file is read this far to find its interpreter

SUFFIXES = {
    ".go": "go", ".py": "python", ".sh": "shell", ".bash": "shell",
    ".js": "javascript", ".mjs": "javascript", ".cjs": "javascript", ".ts": "javascript",
    ".jsx": "javascript", ".tsx": "javascript", ".swift": "swift",
}
SHEBANG = (("python", "python"), ("bash", "shell"), ("/sh", "shell"), ("env sh", "shell"), ("node", "javascript"))
# Tests write their own values; third-party and generated code is not ours to name.
TEST_FILE = re.compile(
    r"((^|/)(tests?|Tests|__tests__)/|(^|/)test_[^/]*\.(py|sh)$|_test\.(py|go|sh)$|\.test\.[a-z]+$|-test\.sh$)"
)
NOT_OURS = re.compile(r"(^|/)(third_party|vendor|testdata|fixtures|node_modules)/")
GENERATED = (".pb.go", "_gen.go", ".pb.swift", ".min.js", ".d.ts")
# A file that owns values: its literals are the names the rest of the code reads.
OWNER_FILE = re.compile(r"(^|/)(defaults?(_[a-z]+)?\.(go|py|sh|js|mjs|ts)|defaults\.env\.sh)$")


def language(root: pathlib.Path, path: str) -> str | None:
    """The language of a tracked file, by suffix, or by its `#!` line when it has no suffix."""
    suffix = pathlib.PurePosixPath(path).suffix
    if suffix:
        return SUFFIXES.get(suffix)
    try:
        with open(root / path, "rb") as handle:
            first = handle.readline(SHEBANG_BYTES).decode("utf-8", "replace")
    except OSError:
        return None
    if not first.startswith("#!"):
        return None
    return next((name for needle, name in SHEBANG if needle in first), None)


class GitFailed(Exception):
    """`git ls-files` failed in a Git work tree; a walk would read its ignored files (#1050)."""


def tracked(root: pathlib.Path) -> list[str]:
    """Every file of the repository: by Git, or by walking a plain copy with no `.git`, such as a fixture."""
    try:
        out = subprocess.run(
            ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            cwd=root, check=True, capture_output=True, text=True,
        ).stdout.split("\0")
    except (OSError, subprocess.CalledProcessError) as error:
        if any((folder / ".git").exists() for folder in (root, *root.parents)):  # inside a work tree: never walk
            raise GitFailed((getattr(error, "stderr", None) or str(error)).strip()) from error
        out = [p.relative_to(root).as_posix() for p in root.rglob("*") if ".git" not in p.relative_to(root).parts]
    return sorted(p for p in out if p and (root / p).is_file() and not (root / p).is_symlink())


def read(root: pathlib.Path, path: str) -> str:
    return (root / path).read_text(encoding="utf-8", errors="replace")


def inside(path: str, folders: list[str]) -> bool:
    return not folders or any(f in (".", "") or path == f or path.startswith(f.rstrip("/") + "/") for f in folders)


def matches(path: str, globs: list[str]) -> bool:
    return any(fnmatch.fnmatchcase(path, glob) for glob in globs)


def ratchet(found: collections.Counter, counts: dict, accepted: dict, what: str, lines: dict) -> list[str]:
    """One line per row whose count differs from today's: above names each line, below asks for a shrink."""
    problems = []
    for key in sorted(set(found) | set(counts) | set(accepted)):
        limit = counts.get(key, 0) + accepted.get(key, 0)
        have = found.get(key, 0)
        label = " ".join(key) if isinstance(key, tuple) else key
        if have > limit:
            problems.append(f"{label}: {have} {what}, {limit} allowed; give each one owner (references/dry-checks.md):")
            problems += [f"  {line}" for line in lines.get(key, [])]
        elif have < limit:
            problems.append(f"{label}: {have} {what}, the ratchet says {limit}; run --shrink")
    return problems


# ---------- magic: values with no name ----------

Finding = collections.namedtuple("Finding", "path line kind value")
PLAIN_NUMBERS = {0, 1, 2, 8, 10, 16, 32, 64, 100}  # counting, halving, a byte's bits, a base, a percent
URL = re.compile(r"\b(?:https?|wss?)://[^\s\"'`]+")
PATH = re.compile(r"^(?:/(?:etc|opt|usr|var|home|Users|Library|Applications|run|srv|tmp)/|~/)")
PORT = re.compile(r"(?:\blocalhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0)?:\d{4,5}\b")
# A hex colour holds a letter: `#123` and `#1068` are issue numbers. A colour function may nest one
# call, as in `rgb(var(--x))` (#1068).
COLOUR = re.compile(r"^#(?=[0-9]*[a-fA-F])(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"
                    r"|^(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch|color|color-mix)\((?:[^()]|\([^()]*\))*\)$")
SENTENCE = re.compile(r"^[A-Z][a-z]+(?: [^\s]+){2,}[.!?…]?$")
REPEATED_MINIMUM = 12  # characters of a repeated phrase
REPEATED_TIMES = 3  # times it must repeat
VALUE_SHOWN = 60
BEFORE_TOKEN = 24  # characters read back for a Go log call before a sentence


def classify_string(path, line, text):
    """The classes of one string literal outside a constant."""
    for kind, pattern in (("url", URL.search), ("path", PATH.match), ("port", PORT.search), ("colour", COLOUR.match)):
        if pattern(text):
            return [Finding(path, line, kind, text[:VALUE_SHOWN])]
    return []


def number(token):
    """The value of a decimal literal; None for a hex, binary or octal one, which is a mask or a mode."""
    if token[:2].lower() in ("0x", "0b", "0o"):
        return None
    try:
        return float(token.replace("_", "").rstrip("n"))
    except ValueError:
        return None


GO_TOKEN = re.compile(
    r"""//[^\n]*|/\*.*?\*/|`[^`]*`|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'"""
    r"""|\b0[xXbBoO][0-9a-fA-F_]+\b|\b\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?\b|\b[A-Za-z_]\w*\b|[()\[\]{}=]|\n""",
    re.S,
)
GO_LOG = re.compile(r"\b(?:Msg|Msgf|Errorf|New|Str|Err|Int|Bool|Fatalf|Printf|Fprintf|Sprintf|Errorln|Warnf|Infof)\s*\($")


def go_findings(path, source):
    found, strings = [], []
    line, depth_const, in_const_line, previous = 1, 0, False, ""
    for match in GO_TOKEN.finditer(source):
        token = match.group()
        before = source[max(0, match.start() - BEFORE_TOKEN): match.start()]
        if token == "\n":
            line, in_const_line = line + 1, False
            continue
        if token[:2] in ("//", "/*"):
            line += token.count("\n")
            continue
        if token == "const":
            in_const_line = True
        elif previous == "const" and token == "(":
            depth_const, in_const_line = 1, False
        elif depth_const and token == "(":
            depth_const += 1
        elif depth_const and token == ")":
            depth_const -= 1
        named = depth_const > 0 or in_const_line
        if token[0] in '"`':
            is_tag = token[0] == "`" and re.match(r"`\w+:\"", token)
            text = token[1:-1]
            if not named and not is_tag:
                found += classify_string(path, line, text)
                strings.append((line, text))
                if SENTENCE.match(text) and not GO_LOG.search(before):
                    found.append(Finding(path, line, "sentence", text[:VALUE_SHOWN]))
            line += token.count("\n")
        elif token[0].isdigit() and not named:
            value = number(token)
            if value is not None and value not in PLAIN_NUMBERS and previous != "[":
                kind = "duration" if re.match(r"\s*\*\s*time\.", source[match.end(): match.end() + 10]) else "number"
                found.append(Finding(path, line, kind, token))
        previous = token
    return found, strings


DURATION_ARGUMENTS = ("timeout", "delay", "interval")


class PythonReader(ast.NodeVisitor):
    def __init__(self, path):
        self.path, self.found, self.strings, self.named, self.counted = path, [], [], 0, set()

    def visit_Assign(self, node):
        constant = all(isinstance(t, ast.Name) and t.id.lstrip("_").isupper() for t in node.targets)
        self.named += constant
        self.generic_visit(node)
        self.named -= constant

    def visit_AnnAssign(self, node):
        constant = isinstance(node.target, ast.Name) and node.target.id.lstrip("_").isupper()
        self.named += constant
        self.generic_visit(node)
        self.named -= constant

    def visit_Expr(self, node):
        if not (isinstance(node.value, ast.Constant) and isinstance(node.value.value, str)):  # a docstring
            self.generic_visit(node)

    def visit_Call(self, node):
        name = getattr(node.func, "attr", getattr(node.func, "id", ""))
        values = [k.value for k in node.keywords if k.arg in DURATION_ARGUMENTS]
        if name == "sleep":
            values += node.args
        for value in values:
            if not self.named and isinstance(value, ast.Constant) and isinstance(value.value, (int, float)):
                self.found.append(Finding(self.path, value.lineno, "duration", repr(value.value)))
                self.counted.add(id(value))
        self.generic_visit(node)

    def visit_Constant(self, node):
        if self.named or id(node) in self.counted:
            return
        value = node.value
        if isinstance(value, bool) or value is None:
            return
        if isinstance(value, (int, float)):
            if abs(value) not in PLAIN_NUMBERS:
                self.found.append(Finding(self.path, node.lineno, "number", repr(value)))
        elif isinstance(value, str):
            self.found += classify_string(self.path, node.lineno, value)
            self.strings.append((node.lineno, value))


def python_findings(path, source):
    reader = PythonReader(path)
    try:
        reader.visit(ast.parse(source))
    except SyntaxError:
        return [Finding(path, 1, "unreadable", "")], []
    return reader.found, reader.strings


SHELL_DURATION = re.compile(r"\b(?:sleep|timeout)\s+(\d+(?:\.\d+)?)")
SHELL_FLAG = re.compile(r"(?:^|\s)--?[a-zA-Z][\w-]*[= ](\d{2,})\b")
SHELL_CONSTANT = re.compile(r"^\s*(?:readonly\s+|export\s+|local\s+|declare\s+-\w+\s+)?[A-Z_][A-Z0-9_]*=")
SHELL_WORD = re.compile(
    r"""["']([^"']+)["']|(?<![\w.])((?:https?://|wss?://|/(?:etc|opt|usr|var|home|Users|Library|Applications|run|srv)/|~/)\S+)"""
)


def shell_findings(path, source):
    found, strings = [], []
    for line_number, raw in enumerate(source.splitlines(), 1):
        line = re.sub(r"(^|\s)#.*$", "", raw)
        if not line.strip() or SHELL_CONSTANT.match(line):
            continue
        duration = SHELL_DURATION.search(line)
        if duration and float(duration.group(1)) not in PLAIN_NUMBERS:
            found.append(Finding(path, line_number, "duration", duration.group(1)))
        flag = SHELL_FLAG.search(line)
        if flag and not duration:
            found.append(Finding(path, line_number, "number", flag.group(1)))
        for match in SHELL_WORD.finditer(line):
            word = match.group(1) or match.group(2)
            found += classify_string(path, line_number, word)
            strings.append((line_number, word))
    return found, strings


JS_TOKEN = re.compile(
    r"""//[^\n]*|/\*.*?\*/|`(?:\\.|[^`\\])*`|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'"""
    r"""|\b0[xXbBoO][0-9a-fA-F_]+n?\b|\b\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?n?\b|[A-Za-z_$][\w$]*|[()\[\]{};=]|\n""",
    re.S,
)
# A `/` after one of these starts a regular expression literal, not a division.
JS_REGEX_AFTER = set("(,=:[!&|?{};+-*%<>~^") | {"", "return", "typeof", "case", "of", "in"}
JS_CONSTANT = re.compile(r"^[A-Z][A-Z0-9_]*$")


def blank_js_regexes(source: str) -> str:
    """The source with every regular expression literal's body blanked, so its digits are not numbers."""
    out, i, previous = [], 0, ""
    while i < len(source):
        char = source[i]
        if source.startswith("//", i) or source.startswith("/*", i):
            end = source.find("\n", i) if source[i + 1] == "/" else source.find("*/", i + 2) + 2
            end = len(source) if end <= i else end
            out.append(source[i:end])
            i = end
            continue
        if char in "\"'`":
            j = i + 1
            while j < len(source) and source[j] != char and not (char != "`" and source[j] == "\n"):
                j += 2 if source[j] == "\\" else 1
            out.append(source[i:j + 1])
            i, previous = j + 1, "x"
            continue
        if char == "/" and previous in JS_REGEX_AFTER:
            j, in_class = i + 1, False
            while j < len(source) and source[j] != "\n" and (in_class or source[j] != "/"):
                in_class = (in_class or source[j] == "[") and source[j] != "]"
                j += 2 if source[j] == "\\" else 1
            out.append("/" + " " * (j - i - 1))
            i, previous = j, "x"
            continue
        out.append(char)
        if char.isalnum() or char in "_$":
            word = re.match(r"[\w$]+", source[i:]).group()
            out.append(word[1:])
            i += len(word)
            previous = word
            continue
        if not char.isspace():
            previous = char
        i += 1
    return "".join(out)


def javascript_findings(path, source):
    """A literal outside an UPPER_CASE `const`, `let` or `var` statement is a value with no name."""
    found, strings = [], []
    line, depth, named_depth, declaring, previous = 1, 0, None, False, ""
    for match in JS_TOKEN.finditer(blank_js_regexes(source)):
        token = match.group()
        if token == "\n" or token == ";":
            if named_depth is not None and depth <= named_depth:
                named_depth = None
            line += token == "\n"
            continue
        if token[:2] in ("//", "/*"):
            line += token.count("\n")
            continue
        if token in ("const", "let", "var"):
            declaring = True
        elif declaring:
            if JS_CONSTANT.match(token) and named_depth is None:
                named_depth = depth
            declaring = False
        if token in "([{":
            depth += 1
        elif token in ")]}":
            depth -= 1
        named = named_depth is not None
        if token[0] in "\"'`":
            text = token[1:-1]
            if not named:
                found += classify_string(path, line, text)
                strings.append((line, text))
            line += token.count("\n")
        elif token[0].isdigit() and not named:
            value = number(token)
            if value is not None and value not in PLAIN_NUMBERS and previous != "[":
                found.append(Finding(path, line, "number", token))
        previous = token
    return found, strings


READERS = {"go": go_findings, "python": python_findings, "shell": shell_findings, "javascript": javascript_findings}


def counted(path: str) -> bool:
    return not (TEST_FILE.search(path) or NOT_OURS.search(path) or OWNER_FILE.search(path) or path.endswith(GENERATED))


def magic_findings(sources: dict[str, tuple[str, str]]) -> list[Finding]:
    """Every finding of `{path: (language, source)}`; a phrase repeats when three or more uses share it."""
    found, uses = [], collections.defaultdict(list)
    for path, (lang, source) in sources.items():
        new, strings = READERS[lang](path, source)
        found += new
        for line, text in strings:
            if len(text) >= REPEATED_MINIMUM and " " in text.strip() and not URL.search(text):
                uses[(lang, text)].append((path, line))
    for (_, text), where in uses.items():
        if len(where) >= REPEATED_TIMES:
            found += [Finding(path, line, "repeated", text[:VALUE_SHOWN]) for path, line in where]
    return sorted(found, key=lambda f: (f.path, f.line, f.kind))


def magic_sources(root, paths, section):
    folders, exclude = section.get("folders", []), section.get("exclude", [])
    sources = {}
    for path in paths:
        lang = language(root, path)
        if lang in READERS and inside(path, folders) and counted(path) and not matches(path, exclude):
            sources[path] = (lang, read(root, path))
    return sources


def magic_counts(found):
    return collections.Counter((f.path, f.kind) for f in found)


def magic_check(root, paths, section):
    found = magic_findings(magic_sources(root, paths, section))
    counts = {(p, k): n for p, kinds in section.get("counts", {}).items() for k, n in kinds.items()}
    accepted, problems = {}, []
    for path, kinds in section.get("accepted", {}).items():
        for kind, row in kinds.items():
            if not str(row.get("reason", "")).strip():
                problems.append(f"{path} {kind}: an accepted row with no reason")
            accepted[(path, kind)] = int(row.get("count", 0))
    lines = collections.defaultdict(list)
    for f in found:
        lines[(f.path, f.kind)].append(f"{f.path}:{f.line}: {f.kind} {f.value}")
    problems += ratchet(magic_counts(found), counts, accepted, "magic values", lines)
    return problems, found, f"{len(found)} values"


def magic_record(found, section, shrink):
    accepted = {(p, k): int(r.get("count", 0)) for p, kinds in section.get("accepted", {}).items() for k, r in kinds.items()}
    have, counts = magic_counts(found), {}
    old = section.get("counts", {})
    keys = {(p, k) for p, kinds in old.items() for k in kinds} if shrink else set(have)
    for path, kind in keys:
        left = max(have.get((path, kind), 0) - accepted.get((path, kind), 0), 0)
        if shrink:
            left = min(left, old[path][kind])
        if left:
            counts.setdefault(path, {})[kind] = left
    return {**section, "counts": {p: dict(sorted(k.items())) for p, k in sorted(counts.items())}}


# ---------- duplicates: repeated blocks of code ----------

WINDOW = 4  # lines in a block
REPEATS = 3  # times a block must repeat
IDENTICAL_LINES = 50  # a whole copied file: one owner and an import, never two copies (#1237)
COMMENT = {"python": "#", "shell": "#", "javascript": "//", "go": "//", "swift": "//"}
STRING_ANY = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|`(?:\\.|[^`\\])*`')
NUMBER_ANY = re.compile(r"(?<![A-Za-z0-9_$])\d+(?:\.\d+)?")
WORD = re.compile(r"(?P<before>[.$-]?)(?P<word>[A-Za-z_][\w]*)(?P<call>\s*\()?")
SHELL_COMMAND_START = re.compile(r"(?:^|[|;&(`]|\$\(|\bthen\b|\bdo\b|\belse\b)\s*$")
# An import, a test's signature, a constant, a switch arm: each names or maps a value and shares no code.
NOT_A_BLOCK = re.compile(
    r"^(import\b|from \S+ import\b|export \{|package \w|source \S|\. \S|#!|"
    r"(async\s+)?def test\w*\(|(it|test|describe)\s*\(|func Test\w*\(|@Test\b|(@\w+\s+)*func test\w*\(|test_\w+\s*\(\)\s*\{|"
    r"(export\s+)?(const|let|var|readonly|declare\s+-\w+)?\s*[A-Z_][A-Z0-9_]*\s*=|case\b|default:)"
)
KEYWORDS = frozenset(
    "and as assert async await break case catch class const continue def default defer del do done elif "
    "else enum esac export extends false fi finally for from func function go if import in is lambda let local "
    "new nil none not null of or pass raise readonly return self static struct switch then this throw true try "
    "type typeof until var void while with yield".split()
)


def normalise(line: str, lang: str) -> str:
    """The line's shape: no comment, literals blanked, names as `v`, called names and members kept.
    Empty when it names nothing a copy could share."""
    text = line.strip()
    if not text or NOT_A_BLOCK.match(text):
        return ""
    text = STRING_ANY.sub('""', text)
    marker = COMMENT[lang]
    text = re.split(r"(?:^|\s)#", text, maxsplit=1)[0] if marker == "#" else re.split(r"(?<!:)//", text, maxsplit=1)[0]
    text = NUMBER_ANY.sub("0", text)
    kept = []

    def word(match):
        before, name, call = match.group("before"), match.group("word"), match.group("call") or ""
        if name.lower() in KEYWORDS:
            return match.group(0)
        command = lang == "shell" and (before == "-" or SHELL_COMMAND_START.search(text[: match.start()]))
        if call or name[0].isupper() or command:
            kept.append(name)
            return before + name + call.strip()
        return before + ("m" if before == "." else "v")

    text = " ".join(WORD.sub(word, text).split())
    return text if kept and not text.startswith(("/*", "*")) else ""


def significant(text: str, lang: str):
    return [(n, norm) for n, raw in enumerate(text.splitlines(), 1) if (norm := normalise(raw, lang))]


def groups(files: dict[str, tuple[str, str]]):
    """The repeated blocks of `{path: (language, text)}` as (length, [(path, first, last)]), biggest first."""
    lines = {path: significant(text, lang) for path, (lang, text) in files.items()}
    windows, seen = {}, {}
    for path, rows in lines.items():
        for i in range(len(rows) - WINDOW + 1):
            key = tuple(norm for _, norm in rows[i:i + WINDOW])
            # A window that overlaps or touches the last one with the same lines in this file is one
            # region (a table, a run of the same call), not a second copy.
            last = seen.get((key, path))
            seen[key, path] = i
            if last is None or i - last > WINDOW:
                windows.setdefault(key, []).append((path, i))
    repeated = {frozenset(spots) for spots in windows.values() if len(spots) >= REPEATS}

    def shifted(spots, by):
        return frozenset((path, i + by) for path, i in spots)

    found = []
    for spots in repeated:
        if shifted(spots, -1) in repeated:
            continue  # the middle of a longer run, reported from its start
        length = WINDOW
        while shifted(spots, length - WINDOW + 1) in repeated:
            length += 1
        copies = sorted((path, lines[path][i][0], lines[path][i + length - 1][0]) for path, i in spots)
        found.append((length, copies))
    found.sort(key=lambda group: (-group[0] * len(group[1]), -group[0], group[1]))
    return found


def area(path: str, depth: int) -> str:
    parts = pathlib.PurePosixPath(path).parent.parts[:depth]
    return "/".join(parts) or "."


def duplicate_files(root, paths, section):
    exclude = section.get("exclude", [])
    files = {}
    for path in paths:
        lang = language(root, path)
        if lang in COMMENT and not NOT_OURS.search(path) and not path.endswith(GENERATED) and not matches(path, exclude):
            files[path] = (lang, read(root, path))
    return files


def identical_problems(files, allowed):
    """Byte-identical code files over IDENTICAL_LINES lines, two copies or more, not every copy allowed."""
    same = collections.defaultdict(list)
    for path, (_, text) in files.items():
        if text.count("\n") > IDENTICAL_LINES:
            same[text].append(path)
    problems, seen = [], set()
    for copies in sorted(sorted(group) for group in same.values() if len(group) > 1):
        seen.update(copies)
        if not all(str(allowed.get(path) or "").strip() for path in copies):
            problems.append(f"identical files, {len(copies)} copies: {', '.join(copies)}; keep one and import it,"
                            " or give every copy a `duplicates.identical` row with its reason")
    for path in sorted(allowed):
        if not str(allowed[path] or "").strip():
            problems.append(f"identical row {path} has no reason")
        elif path not in seen:
            problems.append(f"identical row {path} names no identical copy; remove the row")
    return problems


def duplicate_counts(found, depth):
    return collections.Counter(area(copies[0][0], depth) for _, copies in found)


def duplicates_check(root, paths, section):
    depth = int(section.get("depth", 1))
    files = duplicate_files(root, paths, section)
    found = groups(files)
    lines = collections.defaultdict(list)
    for length, copies in found:
        where = ", ".join(f"{p}:{a}-{b}" for p, a, b in copies)
        lines[area(copies[0][0], depth)].append(f"{length} lines x {len(copies)}: {where}")
    problems = ratchet(duplicate_counts(found, depth), section.get("counts", {}), {}, "repeated blocks", lines)
    problems += identical_problems(files, section.get("identical", {}))
    return problems, found, f"{len(found)} repeated blocks"


def duplicates_record(found, section, shrink):
    have, old = duplicate_counts(found, int(section.get("depth", 1))), section.get("counts", {})
    counts = {a: min(have.get(a, 0), n) for a, n in old.items()} if shrink else dict(have)
    return {**section, "counts": {a: n for a, n in sorted(counts.items()) if n}}


# ---------- twins: one rule in two languages ----------

TWIN_FIELDS = ("rule", "owner", "other", "pattern", "golden")
# A rule's other side may live in a language the magic and duplicates checks do not read; twins read
# it too, so a React Native or Android project can name its Java or Kotlin side (#1078).
TWIN_SUFFIXES = (".java", ".kt")


def code_files(root, relative, paths):
    """The code files at or under a path, tests left out."""
    prefix = relative.rstrip("/") + "/"
    return [p for p in paths if (p == relative or p.startswith(prefix)) and not TEST_FILE.search(p)
            and (language(root, p) or p.endswith(TWIN_SUFFIXES))]


def holds(root, pattern, relative, paths, texts):
    for path in code_files(root, relative, paths):
        if pattern.search(texts.setdefault(path, read(root, path))):
            return True
    return False


def twin_problems(root, row, paths, texts):
    name = row.get("rule") or "<no rule>"
    missing = [field for field in TWIN_FIELDS if field not in row or (field != "golden" and not row[field])]
    if missing:
        return [f"{name}: lacks {', '.join(missing)}; a rule two languages hold needs one owner"]
    problems = []
    if row["golden"] and not (root / row["golden"]).is_file():
        problems.append(f"{name}: its golden {row['golden']} is gone")
    for side in ("owner", "other"):
        if not (root / row[side]).exists():
            problems.append(f"{name}: its {side} {row[side]} is gone")
    if problems:
        return problems
    try:
        pattern = re.compile(row["pattern"])
    except re.error as error:
        return [f"{name}: the pattern does not compile: {error}"]
    if not holds(root, pattern, row["owner"], paths, texts):
        problems.append(f"{name}: the pattern has no match in its owner {row['owner']}, so the row is stale")
    twin = holds(root, pattern, row["other"], paths, texts)
    if row.get("open"):
        if not twin:
            problems.append(f"{name}: open on #{row['open']}, but {row['other']} no longer holds it; close the row")
    elif twin and not row["golden"]:
        problems.append(f"{name}: in both {row['owner']} and {row['other']} with no golden both sides' tests read")
    return problems


def twins_check(root, paths, section):
    rows = section.get("rules", []) if isinstance(section, dict) else section
    texts = {}
    problems = [p for row in rows for p in twin_problems(root, row, paths, texts)]
    open_rows = sum(1 for row in rows if row.get("open"))
    return problems, rows, f"{len(rows)} rules, {open_rows} open"


# ---------- documents: page budgets and a rule written twice ----------

SAME_RULE = 60  # characters: a shorter sentence («Read first.») may repeat
LIST_MARKER = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?")
SENTENCE_BREAK = re.compile(r"(?<=[.!?])\s+")
LINK = re.compile(r"!?\[([^\]]*)\]\([^)\s]*\)")  # a link counts by its text, not its target (#775)


def sentences(text: str):
    """(line, sentence) for each prose sentence outside frontmatter, code blocks, tables, headings
    and comments, each link reduced to its text."""
    units, unit, fence, comment = [], [], False, False
    lines = text.splitlines()
    front = 0
    if lines and lines[0].strip() == "---":  # YAML frontmatter is metadata, not a rule (#775)
        front = next((n for n, line in enumerate(lines[1:], 2) if line.strip() == "---"), 0)

    def close():
        if unit:
            units.append(list(unit))
            unit.clear()

    for number, line in enumerate(lines, 1):
        if number <= front:
            continue
        stripped = line.strip()
        if stripped.startswith(("```", "~~~")):
            fence = not fence
            close()
            continue
        if comment or stripped.startswith("<!--"):
            comment = "-->" not in stripped
            close()
            continue
        if fence or not stripped or stripped.startswith(("|", "#", "<", ">")) or line.startswith(("    ", "\t")) and not unit:
            close()
            continue
        if LIST_MARKER.match(line):
            close()
            stripped = LIST_MARKER.sub("", line).strip()
        unit.append((number, stripped))
    close()
    for unit in units:
        joined, starts = "", []
        for number, part in unit:
            starts.append((len(joined), number))
            joined += part + " "
        offset = 0
        for sentence in SENTENCE_BREAK.split(joined.strip()):
            at = joined.find(sentence, offset)
            offset = at + len(sentence)
            line = max(n for start, n in starts if start <= at)
            yield line, " ".join(LINK.sub(r"\1", sentence).split())


def documents_found(root, paths, section):
    files = [p for p in paths if matches(p, section.get("files", [])) and not matches(p, section.get("exclude", []))]
    minimum = int(section.get("minimum", SAME_RULE))
    owner, repeats = {}, []
    for path in files:
        for line, sentence in sentences(read(root, path)):
            if len(sentence) < minimum:
                continue
            first = owner.setdefault(sentence, (path, line))
            if first[0] != path:
                repeats.append((path, line, first, sentence))
    return files, repeats


def documents_check(root, paths, section):
    files, repeats = documents_found(root, paths, section)
    problems = []
    for path in files:
        for glob, limit in section.get("budgets", {}).items():
            if fnmatch.fnmatchcase(path, glob):
                size = (root / path).stat().st_size
                if size > limit:
                    problems.append(f"{path}: {size} bytes, over its {limit}-byte budget; split it or move detail out")
                break
    lines = collections.defaultdict(list)
    for path, line, (first, first_line), sentence in repeats:
        lines[path].append(f"{path}:{line}: the same rule as {first}:{first_line}; keep it in one, link it: «{sentence[:VALUE_SHOWN]}…»")
    found = collections.Counter(path for path, *_ in repeats)
    problems += ratchet(found, section.get("repeated", {}), {}, "rules written in another document", lines)
    return problems, repeats, f"{len(files)} documents, {len(repeats)} repeated rules"


def documents_record(found, section, shrink):
    have, old = collections.Counter(path for path, *_ in found), section.get("repeated", {})
    counts = {p: min(have.get(p, 0), n) for p, n in old.items()} if shrink else dict(have)
    return {**section, "repeated": {p: n for p, n in sorted(counts.items()) if n}}


# ---------- retired: a renamed thing never comes back under its old name (#1713) ----------


class DataError(Exception):
    """A section the check cannot read: exit 2, never a finding."""


def retired_terms(section):
    """Each `terms` row with its compiled pattern: the exact term on a word boundary, case-sensitive, its
    words separated by any whitespace, so a line break inside it still counts (#1828)."""
    rows = []
    for row in section.get("terms", []):
        if not isinstance(row, dict):
            raise DataError(f"a retired row is an object with term, use and keep: {row!r}")
        term, use = str(row.get("term") or "").strip(), str(row.get("use") or "").strip()
        if not term or not use:
            raise DataError(f"a retired row needs its term and the name to use instead: {row}")
        keep = row.get("keep", [])
        if not isinstance(keep, list) or not all(isinstance(glob, str) for glob in keep):
            raise DataError(f"a retired row's keep is a list of globs: {row}")
        words = r"\s+".join(re.escape(word) for word in term.split())
        rows.append((row, re.compile(r"(?<![\w-])" + words + r"(?![\w-])")))
    return rows


def retired_found(root, paths, section):
    """(path, line, row) for each use of a retired term outside its `keep` globs and the data file."""
    found = []
    rows = retired_terms(section)
    for path in paths:
        if path == DATA_FILE:
            continue
        wanted = [(row, pattern) for row, pattern in rows if not matches(path, row.get("keep", []))]
        if not wanted:
            continue
        text = read(root, path)
        for row, pattern in wanted:
            found += [(path, text.count("\n", 0, match.start()) + 1, row) for match in pattern.finditer(text)]
    return found


def retired_counts(found):
    return collections.Counter((path, row["term"]) for path, _, row in found)


def retired_check(root, paths, section):
    found = retired_found(root, paths, section)
    counts = {(p, t): n for p, terms in section.get("counts", {}).items() for t, n in terms.items()}
    lines = collections.defaultdict(list)
    for path, number, row in found:
        issue = f" (#{row['issue']})" if row.get("issue") else ""
        lines[(path, row["term"])].append(f"{path}:{number}: «{row['term']}» is retired: write «{row['use']}»{issue}")
    return ratchet(retired_counts(found), counts, {}, "uses of a retired term", lines), found, f"{len(found)} retired uses"


def retired_record(found, section, shrink):
    have, old = retired_counts(found), section.get("counts", {})
    keys = {(p, t) for p, terms in old.items() for t in terms} if shrink else set(have)
    counts = {}
    for path, term in keys:
        left = min(have.get((path, term), 0), old[path][term]) if shrink else have[(path, term)]
        if left:
            counts.setdefault(path, {})[term] = left
    return {**section, "counts": {p: dict(sorted(t.items())) for p, t in sorted(counts.items())}}


RUN = {"magic": magic_check, "duplicates": duplicates_check, "twins": twins_check, "documents": documents_check,
       "retired": retired_check}
RECORD = {"magic": (magic_record, "counts"), "duplicates": (duplicates_record, "counts"), "documents": (documents_record, "repeated"),
          "retired": (retired_record, "counts")}


def describe(check, item):
    if check == "magic":
        return f"{item.path}:{item.line}: {item.kind} {item.value}"
    if check == "duplicates":
        length, copies = item
        return f"{length} lines x {len(copies)}: " + ", ".join(f"{p}:{a}-{b}" for p, a, b in copies)
    if check == "documents":
        path, line, (first, first_line), sentence = item
        return f"{path}:{line}: as {first}:{first_line}: {sentence[:VALUE_SHOWN]}"
    if check == "retired":
        path, line, row = item
        return f"{path}:{line}: {row['term']}"
    return f"{item.get('rule')}: {item.get('owner')} / {item.get('other')}"


def git_root() -> pathlib.Path:
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True, capture_output=True, text=True).stdout
        return pathlib.Path(out.strip())
    except (OSError, subprocess.CalledProcessError):
        return pathlib.Path.cwd()


def main(argv: list[str]) -> int:
    root, data_path, mode, chosen = None, None, "check", []
    args = iter(argv)
    for arg in args:
        if arg in ("--root", "--data"):
            value = next(args, None)
            if value is None:
                print(f"dry-check: {arg} needs a value", file=sys.stderr)
                return EXIT_USAGE
            root, data_path = (pathlib.Path(value), data_path) if arg == "--root" else (root, pathlib.Path(value))
        elif arg in ("--init", "--shrink", "--list"):
            mode = arg[2:]
        elif arg in CHECKS:
            chosen.append(arg)
        else:
            print(f"dry-check: unknown argument {arg}; see the usage at the top of this file", file=sys.stderr)
            return EXIT_USAGE
    root = (root or git_root()).resolve()
    data_path = data_path if data_path and data_path.is_absolute() else root / (data_path or DATA_FILE)
    try:
        data = json.loads(data_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        print(f"dry-check: cannot read {data_path}: {error}", file=sys.stderr)
        return EXIT_USAGE
    try:
        paths = tracked(root)
    except GitFailed as error:
        print(f"dry-check: git ls-files failed in {root}: {error}", file=sys.stderr)
        return EXIT_USAGE
    status = 0
    for check in chosen or CHECKS:
        name = SECTION[check]
        if name not in data:
            print(f"dry-check: {check} skipped, no `{name}` section in {data_path.name}")
            continue
        section = data[name]
        try:
            problems, found, summary = RUN[check](root, paths, section)
        except DataError as error:
            print(f"dry-check: {check}: {error}", file=sys.stderr)
            status = max(status, EXIT_USAGE)
            continue
        if mode == "list":
            for item in found:
                print(f"{check}: {describe(check, item)}")
            continue
        if mode in ("init", "shrink") and check in RECORD:
            record, key = RECORD[check]
            if mode == "init" and section.get(key):
                print(f"dry-check: {check} already has {key}; --init records today's count once, use --shrink", file=sys.stderr)
                status = max(status, EXIT_USAGE)
                continue
            data[name] = record(found, section, shrink=mode == "shrink")
            print(f"dry-check: {check} recorded, {summary}")
            continue
        for problem in problems:
            print(f"{check}: {problem}")
        if problems:
            status = max(status, EXIT_FINDING)
        else:
            print(f"dry-check: {check} ok, {summary}")
    if mode in ("init", "shrink"):
        data_path.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
